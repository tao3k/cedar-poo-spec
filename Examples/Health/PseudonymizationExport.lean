import CedarPooSpec.PolicyJson
import CedarPooSpec.SchemaJson
import Examples.Health.Pseudonymization

/-! Export each composed root with the same source and target entities used by
the Lean decision proof. Rust Cedar validates the schema and replays the cases. -/

namespace CedarPooSpec.PseudonymizationExport

open CedarPooSpec.PseudonymizationExample

def manifest : Except String Lean.Json := do
  let rows ← cases.mapM fun (name, root, req, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name root model root req entities
  CedarPooSpec.SchemaJson.validatedManifest schema rows

end CedarPooSpec.PseudonymizationExport
