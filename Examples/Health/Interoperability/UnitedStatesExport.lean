import Examples.Health.Interoperability.UnitedStatesAdmission

/-! Export the finite payer-exchange decisions to official Cedar Rust. -/

namespace CedarPooSpec.UnitedStatesPayerExample.ValidatedExport

open CedarPooSpec.UnitedStatesPayerExample

def manifest : Except String Lean.Json := do
  let rows ← cases.mapM fun (name, root, req, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name root model root req entities
  let projected ← Admission.projectedCases.mapM fun (name, req, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name "Governed" model "Governed" req entities
  CedarPooSpec.SchemaJson.validatedManifest schema (rows ++ projected)

end CedarPooSpec.UnitedStatesPayerExample.ValidatedExport
