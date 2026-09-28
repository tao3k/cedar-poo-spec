import Examples.Health.Interoperability.UnitedStatesPayer

/-! Export the finite payer-exchange decisions to official Cedar Rust. -/

namespace CedarPooSpec.UnitedStatesPayerExample.ValidatedExport

open CedarPooSpec.UnitedStatesPayerExample

def manifest : Except String Lean.Json := do
  let rows ← cases.mapM fun (name, root, req, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name root model root req entities
  CedarPooSpec.SchemaJson.validatedManifest schema rows

end CedarPooSpec.UnitedStatesPayerExample.ValidatedExport
