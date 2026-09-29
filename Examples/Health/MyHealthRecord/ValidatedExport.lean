import Examples.Health.MyHealthRecord.Lifecycle

/-! Export the same finite consumer-platform decisions to official Cedar. -/

namespace CedarPooSpec.MyHealthRecordExample.ValidatedExport

open CedarPooSpec.MyHealthRecordExample

def manifest : Except String Lean.Json := do
  let rows ← cases.mapM fun (name, root, req, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name root model root req entities
  CedarPooSpec.SchemaJson.validatedManifest schema rows

end CedarPooSpec.MyHealthRecordExample.ValidatedExport
