//! Borrowed token profiles corresponding to the public Lean pseudonymization
//! catalog. The deploying Host authenticates catalog values and key material.

/// Capabilities modeled by the public Lean pseudonymization layer.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Mode {
    AesSiv,
    AesGcm,
    HmacSha256,
}

impl Mode {
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::AesSiv => "aes-siv",
            Self::AesGcm => "aes-gcm",
            Self::HmacSha256 => "hmac-sha256",
        }
    }

    #[must_use]
    pub const fn reversible(self) -> bool {
        !matches!(self, Self::HmacSha256)
    }

    #[must_use]
    pub const fn linkable(self) -> bool {
        !matches!(self, Self::AesGcm)
    }
}

/// Declared key and transformation lineage; no key bytes are held here.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct TokenLineage<'a> {
    pub tenant: &'a str,
    pub key_domain: &'a str,
    pub token_key_version: &'a str,
    pub transform_version: &'a str,
    pub wrapping_version: &'a str,
}

/// One declared token recipe and its equality-join scope.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct TokenProfile<'a> {
    pub mode: Mode,
    pub scope: &'a str,
    pub lineage: TokenLineage<'a>,
}

impl TokenProfile<'_> {
    /// Equality joins require the same token method, scope, and data-key
    /// recipe. Wrapping-key rotation alone does not change token equality.
    #[must_use]
    pub fn same_recipe(&self, other: &Self) -> bool {
        self.mode == other.mode
            && self.scope == other.scope
            && self.lineage.key_domain == other.lineage.key_domain
            && self.lineage.token_key_version == other.lineage.token_key_version
            && self.lineage.transform_version == other.lineage.transform_version
    }

    /// HMAC profiles in distinct scopes cannot declare the same data-key
    /// recipe without enabling passive cross-scope correlation.
    #[must_use]
    pub fn hmac_key_reuse_across_scopes(&self, other: &Self) -> bool {
        self.mode == Mode::HmacSha256
            && other.mode == Mode::HmacSha256
            && self.scope != other.scope
            && self.lineage.key_domain == other.lineage.key_domain
            && self.lineage.token_key_version == other.lineage.token_key_version
            && self.lineage.transform_version == other.lineage.transform_version
    }
}

#[cfg(test)]
#[path = "../tests/unit/pseudonymization.rs"]
mod tests;
