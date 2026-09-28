import Examples.Health.Interoperability.Admission

/-! Export the finite upload decisions to official Cedar Rust. -/

namespace CedarPooSpec.AustralianEMRExample.ValidatedExport

open CedarPooSpec.AustralianEMRExample

def manifest : Except String Lean.Json := do
  let rows ← cases.mapM fun (name, root, req, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name root model root req entities
  let projected ← Admission.projectedCases.mapM fun (name, req, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name "Governed" model "Governed" req entities
  CedarPooSpec.SchemaJson.validatedManifest schema (rows ++ projected)

end CedarPooSpec.AustralianEMRExample.ValidatedExport
