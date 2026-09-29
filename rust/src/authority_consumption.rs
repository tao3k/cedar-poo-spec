//! Process-local model of a Host-owned, effect-bound approval instance.
//! Durable storage and approval authentication belong to the deploying Host.

/// Stable identity of one approval instance in the Host's authority store.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct AuthorityId(pub String);

impl From<&str> for AuthorityId {
    fn from(value: &str) -> Self {
        Self(value.into())
    }
}

/// One exact-effect approval with a Host-owned use limit and consumed count.
#[derive(Clone, Debug)]
pub struct AuthorityGrant<Effect> {
    pub id: AuthorityId,
    pub effect: Effect,
    pub max_uses: u64,
    pub used: u64,
}

/// Process-local collection of approval instances.
#[derive(Clone, Debug, Default)]
pub struct AuthorityLedger<Effect> {
    pub grants: Vec<AuthorityGrant<Effect>>,
}

/// Reason an approval instance cannot authorize the proposed effect.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Error {
    Missing,
    Duplicate,
    EffectMismatch,
    Exhausted,
}

impl<Effect: PartialEq> AuthorityLedger<Effect> {
    /// The use limit comes from Host state, never from a prepared ticket.
    pub fn check(&self, id: &AuthorityId, effect: &Effect) -> Result<(), Error> {
        let mut matches = self.grants.iter().filter(|grant| &grant.id == id);
        let grant = matches.next().ok_or(Error::Missing)?;
        if matches.next().is_some() {
            return Err(Error::Duplicate);
        }
        if &grant.effect != effect {
            return Err(Error::EffectMismatch);
        }
        if grant.used >= grant.max_uses {
            return Err(Error::Exhausted);
        }
        Ok(())
    }

    /// Call under the same serialized transaction as budget and audit writes.
    pub fn consume(&mut self, id: &AuthorityId, effect: &Effect) -> Result<(), Error> {
        self.check(id, effect)?;
        let grant = self
            .grants
            .iter_mut()
            .find(|grant| &grant.id == id)
            .ok_or(Error::Missing)?;
        grant.used += 1;
        Ok(())
    }

    pub fn used(&self, id: &AuthorityId) -> Result<u64, Error> {
        let mut matches = self.grants.iter().filter(|grant| &grant.id == id);
        let grant = matches.next().ok_or(Error::Missing)?;
        if matches.next().is_some() {
            return Err(Error::Duplicate);
        }
        Ok(grant.used)
    }
}

#[cfg(test)]
#[path = "../tests/unit/authority_consumption.rs"]
mod tests;
