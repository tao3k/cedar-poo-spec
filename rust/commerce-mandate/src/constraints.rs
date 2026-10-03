//! Selected merchant-ID and exact single-SKU requirement constraints.
//! All checks consume verified root claims and authenticated merchant checkout content.
use crate::{
    contract::{CheckoutConstraintCoverage, MandateError},
    wire,
};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

const MAX_ENTRIES: usize = 16;
const MAX_REQUIREMENTS: usize = 8;
const MAX_UNITS: u64 = 1_000_000;
const MAX_SEARCH: usize = 4096;

pub(crate) struct ConstraintSet(Vec<Constraint>);
enum Constraint {
    Merchants(BTreeSet<String>),
    Items(Vec<Requirement>),
}
struct Requirement {
    acceptable: BTreeSet<String>,
    quantity: u64,
}

pub(crate) fn parse(value: &Value) -> Result<ConstraintSet, MandateError> {
    let entries = array(value)?;
    let mut constraints = Vec::new();
    let mut has_items = false;
    for entry in entries {
        match wire::text(entry, "type")? {
            "checkout.allowed_merchants" => {
                constraints.push(Constraint::Merchants(merchants(entry)?))
            }
            "checkout.line_items" => {
                constraints.push(Constraint::Items(requirements(entry)?));
                has_items = true;
            }
            _ => return Err(MandateError::Unsupported),
        }
    }
    // Empty constraints remain the explicit seed-wire subset. Nonempty input
    // must include line_items, as required by the pinned schema's contains rule.
    if !entries.is_empty() && !has_items {
        return Err(MandateError::Constraint);
    }
    Ok(ConstraintSet(constraints))
}
impl ConstraintSet {
    pub(crate) fn coverage(&self) -> CheckoutConstraintCoverage {
        if self.0.is_empty() {
            CheckoutConstraintCoverage::SeedBindingOnly
        } else {
            CheckoutConstraintCoverage::ItemConstraintsChecked
        }
    }
    pub(crate) fn evaluate(&self, checkout: &Value) -> Result<(), MandateError> {
        for constraint in &self.0 {
            match constraint {
                Constraint::Merchants(allowed) => {
                    let merchant = checkout.get("merchant").ok_or(MandateError::Claims)?;
                    if !allowed.contains(wire::text(merchant, "id")?) {
                        return Err(MandateError::Constraint);
                    }
                }
                Constraint::Items(requirements) => evaluate_items(requirements, checkout)?,
            }
        }
        Ok(())
    }
}
fn array(value: &Value) -> Result<&Vec<Value>, MandateError> {
    let array = value.as_array().ok_or(MandateError::Claims)?;
    if array.len() > MAX_ENTRIES {
        return Err(MandateError::Limit);
    }
    Ok(array)
}
fn quantity(value: &Value) -> Result<u64, MandateError> {
    let quantity = value
        .as_u64()
        .filter(|q| *q > 0)
        .ok_or(MandateError::Claims)?;
    if quantity > MAX_UNITS {
        return Err(MandateError::Limit);
    }
    Ok(quantity)
}
fn merchants(value: &Value) -> Result<BTreeSet<String>, MandateError> {
    wire::fields(value, &["type", "allowed"])?;
    let entries = array(value.get("allowed").ok_or(MandateError::Claims)?)?;
    if entries.is_empty() {
        return Err(MandateError::Constraint);
    }
    let mut ids = BTreeSet::new();
    for merchant in entries {
        wire::fields(merchant, &["id", "name", "website"])?;
        wire::text(merchant, "name")?;
        if merchant.get("website").is_some() {
            wire::text(merchant, "website")?;
        }
        if !ids.insert(wire::text(merchant, "id")?.to_owned()) {
            return Err(MandateError::Claims);
        }
    }
    Ok(ids)
}
fn requirements(value: &Value) -> Result<Vec<Requirement>, MandateError> {
    wire::fields(value, &["type", "items"])?;
    let entries = array(value.get("items").ok_or(MandateError::Claims)?)?;
    if entries.is_empty() {
        return Err(MandateError::Constraint);
    }
    if entries.len() > MAX_REQUIREMENTS {
        return Err(MandateError::Limit);
    }
    let mut ids = BTreeSet::new();
    let mut result = Vec::new();
    for entry in entries {
        wire::fields(entry, &["id", "quantity", "acceptable_items"])?;
        if !ids.insert(wire::text(entry, "id")?) {
            return Err(MandateError::Claims);
        }
        let alternatives = array(entry.get("acceptable_items").ok_or(MandateError::Claims)?)?;
        // An undisclosed set is not evidence that all products are allowed.
        if alternatives.is_empty() {
            return Err(MandateError::Constraint);
        }
        let mut acceptable = BTreeSet::new();
        for item in alternatives {
            wire::fields(item, &["id", "title"])?;
            wire::text(item, "title")?;
            if !acceptable.insert(wire::text(item, "id")?.to_owned()) {
                return Err(MandateError::Claims);
            }
        }
        result.push(Requirement {
            acceptable,
            quantity: quantity(entry.get("quantity").ok_or(MandateError::Claims)?)?,
        });
    }
    Ok(result)
}
fn cart(checkout: &Value) -> Result<Vec<(String, u64)>, MandateError> {
    let entries = array(checkout.get("line_items").ok_or(MandateError::Claims)?)?;
    let mut ids = BTreeSet::new();
    let mut products = BTreeMap::<String, u64>::new();
    for line in entries {
        wire::fields(line, &["id", "item", "quantity", "totals"])?;
        if !ids.insert(wire::text(line, "id")?) {
            return Err(MandateError::Claims);
        }
        let item = line.get("item").ok_or(MandateError::Claims)?;
        wire::fields(item, &["id", "title", "price", "image_url"])?;
        wire::text(item, "title")?;
        item.get("price")
            .and_then(Value::as_u64)
            .ok_or(MandateError::Claims)?;
        array(line.get("totals").ok_or(MandateError::Claims)?)?;
        let qty = quantity(line.get("quantity").ok_or(MandateError::Claims)?)?;
        let total = products
            .entry(wire::text(item, "id")?.to_owned())
            .or_default();
        *total = total.checked_add(qty).ok_or(MandateError::Limit)?;
        if *total > MAX_UNITS {
            return Err(MandateError::Limit);
        }
    }
    Ok(products.into_iter().collect())
}
fn evaluate_items(requirements: &[Requirement], checkout: &Value) -> Result<(), MandateError> {
    let mut cart = cart(checkout)?;
    let demand = requirements
        .iter()
        .try_fold(0u64, |sum, r| sum.checked_add(r.quantity))
        .ok_or(MandateError::Limit)?;
    let supply = cart
        .iter()
        .try_fold(0u64, |sum, (_, q)| sum.checked_add(*q))
        .ok_or(MandateError::Limit)?;
    if demand != supply || supply == 0 {
        return Err(MandateError::Constraint);
    }
    let mut budget = MAX_SEARCH;
    if assign(requirements, &mut cart, &mut budget)? {
        Ok(())
    } else {
        Err(MandateError::Constraint)
    }
}
fn assign(
    requirements: &[Requirement],
    cart: &mut [(String, u64)],
    budget: &mut usize,
) -> Result<bool, MandateError> {
    if *budget == 0 {
        return Err(MandateError::Limit);
    }
    *budget -= 1;
    let Some((requirement, remaining)) = requirements.split_first() else {
        return Ok(cart.iter().all(|(_, q)| *q == 0));
    };
    for index in 0..cart.len() {
        if cart[index].1 >= requirement.quantity && requirement.acceptable.contains(&cart[index].0)
        {
            cart[index].1 -= requirement.quantity;
            let matched = assign(remaining, cart, budget)?;
            cart[index].1 += requirement.quantity;
            if matched {
                return Ok(true);
            }
        }
    }
    Ok(false)
}
