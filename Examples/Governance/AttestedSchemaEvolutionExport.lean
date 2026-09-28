import CedarPooSpec.PolicyJson
import CedarPooSpec.SchemaJson
import Examples.Governance.AttestedDataAccess

/-! Recheck one compiled POO root against both versions of its entity schema. -/

namespace CedarPooSpec.AttestedSchemaEvolutionExport

open CedarPooSpec.AttestedDataAccessExample

private def manifest (candidate : Cedar.Validation.Schema) : Except String Lean.Json := do
  let mut rows : List Lean.Json := []
  for (name, req, _) in unchangedCases do
    let receipt ← CedarPooSpec.PolicyJson.authorizationCase
      name "attested-governedv2" model "GovernedV2" req entities
    rows := rows ++ [receipt]
  let stale ← CedarPooSpec.PolicyJson.authorizationCase
    "stale-attestation" "attested-governedv2" model "GovernedV2"
    (request customerDataset { attestationFresh := false }) entities
  CedarPooSpec.SchemaJson.validatedManifest candidate (rows ++ [stale])

def bundle : Except String Lean.Json := do
  return Lean.Json.mkObj [
    ("before", ← manifest schema),
    ("after", ← manifest schemaV2)]

end CedarPooSpec.AttestedSchemaEvolutionExport
