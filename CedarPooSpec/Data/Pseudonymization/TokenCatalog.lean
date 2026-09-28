/-!
Metadata for token compatibility and HMAC key-domain separation. A catalog
check does not inspect cryptographic key material or authenticate a declared
transformation. Those facts belong to the producer and Host.
-/

namespace CedarPooSpec.Data.Pseudonymization

structure TokenLineage where
  tenant : String
  keyDomain : String
  tokenKeyVersion : String
  transformVersion : String
  wrappingVersion : String

structure TokenProfile where
  mode : String
  scope : String
  lineage : TokenLineage

/-- HMAC tokens in distinct scopes need distinct key lineage to avoid a
    passive cross-scope join. Wrapping-key rotation alone is insufficient. -/
def hmacKeyReuseAcrossScopes (left right : TokenProfile) : Bool :=
  left.mode == "hmac-sha256" && right.mode == "hmac-sha256" &&
  left.scope != right.scope &&
  left.lineage.keyDomain == right.lineage.keyDomain &&
  left.lineage.tokenKeyVersion == right.lineage.tokenKeyVersion &&
  left.lineage.transformVersion == right.lineage.transformVersion

def hmacCatalogSeparated (catalog : List TokenProfile) : Bool :=
  catalog.all fun left =>
    catalog.all fun right => !hmacKeyReuseAcrossScopes left right

end CedarPooSpec.Data.Pseudonymization
