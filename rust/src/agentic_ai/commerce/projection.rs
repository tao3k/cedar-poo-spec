//! Exact field projection from locally verified signatures to Lean claims.
//!
//! The Host must keep the `Verified*` values in its trusted process and compare
//! these claims before setting Lean's `verified` flags. Serialized claims alone
//! carry no cryptographic authority, time validity, revocation state, or budget.

use crate::agentic_ai::commerce::signatures::{
    AgentId, AgentPublicKey, MandateId, MandatePayload, MerchantId, OfferId, OfferPayload,
    PrincipalId, ProductId, VerifiedMandate, VerifiedOffer,
};
use serde::{Deserialize, Serialize};

macro_rules! lean_string {
    ($name:ident) => {
        #[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
        #[serde(transparent)]
        pub struct $name(String);

        impl From<&str> for $name {
            fn from(value: &str) -> Self {
                Self(value.to_owned())
            }
        }

        impl From<String> for $name {
            fn from(value: String) -> Self {
                Self(value)
            }
        }
    };
}

lean_string!(EntityTypeName);
lean_string!(EntityId);
lean_string!(CheckoutCommitment);

/// Field shape of Lean's `EntityType { id, path }`.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct LeanEntityTypeClaims {
    pub id: EntityTypeName,
    pub path: Vec<String>,
}

/// Field shape of Lean's `EntityUID { ty, eid }`.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct LeanEntityUidClaims {
    pub ty: LeanEntityTypeClaims,
    pub eid: EntityId,
}

/// Every Lean `Mandate` field except the Host-owned `verified`.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct LeanMandateClaims {
    pub mandate_id: MandateId,
    pub principal: LeanEntityUidClaims,
    pub agent_id: AgentId,
    pub agent_public_key: AgentPublicKey,
    pub allowed_merchants: Vec<MerchantId>,
    pub allowed_products: Vec<ProductId>,
    pub asset: String,
    pub per_purchase_cap: u64,
    pub total_cap: u64,
    pub policy_epoch: u64,
    pub expires_at: u64,
}

/// Every Lean `PurchaseTerms` field under `MerchantOffer`.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct LeanPurchaseTermsClaims {
    pub merchant_id: MerchantId,
    pub product_id: ProductId,
    pub offer_id: OfferId,
    pub checkout_commitment: CheckoutCommitment,
    pub amount_minor: u64,
    pub asset: String,
}

/// Every Lean `MerchantOffer` field except the Host-owned `verified`.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct LeanOfferClaims {
    pub terms: LeanPurchaseTermsClaims,
    pub expires_at: u64,
}

/// Project every signed mandate field. Exhaustive destructuring makes an
/// added source field a compile error until this mapping is reviewed.
pub fn mandate_claims(verified: &VerifiedMandate) -> LeanMandateClaims {
    let MandatePayload {
        mandate_id,
        principal,
        agent_id,
        agent_public_key,
        allowed_merchants,
        allowed_products,
        asset,
        per_purchase_cap,
        total_cap,
        policy_epoch,
        expires_at,
    } = verified.payload();
    let PrincipalId {
        entity_type_id,
        entity_type_path,
        entity_id,
    } = principal;
    LeanMandateClaims {
        mandate_id: mandate_id.clone(),
        principal: LeanEntityUidClaims {
            ty: LeanEntityTypeClaims {
                id: entity_type_id.clone().into(),
                path: entity_type_path.clone(),
            },
            eid: entity_id.clone().into(),
        },
        agent_id: agent_id.clone(),
        agent_public_key: agent_public_key.clone(),
        allowed_merchants: allowed_merchants.clone(),
        allowed_products: allowed_products.clone(),
        asset: asset.clone(),
        per_purchase_cap: *per_purchase_cap,
        total_cap: *total_cap,
        policy_epoch: *policy_epoch,
        expires_at: *expires_at,
    }
}

/// Project every signed offer field, mapping its verified SHA-256 value to
/// Lean's opaque checkout commitment field.
pub fn offer_claims(verified: &VerifiedOffer) -> LeanOfferClaims {
    let OfferPayload {
        merchant_id,
        product_id,
        offer_id,
        checkout_sha256,
        amount_minor,
        asset,
        expires_at,
    } = verified.payload();
    LeanOfferClaims {
        terms: LeanPurchaseTermsClaims {
            merchant_id: merchant_id.clone(),
            product_id: product_id.clone(),
            offer_id: offer_id.clone(),
            checkout_commitment: checkout_sha256.clone().into(),
            amount_minor: *amount_minor,
            asset: asset.clone(),
        },
        expires_at: *expires_at,
    }
}

/// Check caller-provided Lean mandate claims against all signed fields.
pub fn mandate_matches(verified: &VerifiedMandate, target: &LeanMandateClaims) -> bool {
    &mandate_claims(verified) == target
}

/// Check caller-provided Lean offer claims against all signed fields.
pub fn offer_matches(verified: &VerifiedOffer, target: &LeanOfferClaims) -> bool {
    &offer_claims(verified) == target
}
