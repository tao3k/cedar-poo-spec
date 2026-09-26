import CedarPooSpec.PolicyJson
import Examples.Health.ClinicalBreakGlass

/-! Export clinical POO revisions and Lean-computed authorization receipts. -/

namespace CedarPooSpec.ClinicalBreakGlassExport

open CedarPooSpec.ClinicalBreakGlassExample

def manifest : Except String Lean.Json := do
  let integrated ← cases.mapM fun (name, req, _) =>
    PolicyJson.authorizationCase name "clinical-integrated" model
      "Integrated" req entities
  let before ← PolicyJson.authorizationCase "pre-integration-broad-permit"
    "clinical-emergency" model "Emergency" (request remoteRecord {}) entities
  let preference ← PolicyJson.authorizationCase "preference-released"
    "clinical-integrated" model "Integrated"
      (request restrictedRecord {}) unrestrictedEntities
  return Lean.Json.mkObj [("cases", Lean.toJson (before :: integrated ++ [preference]))]

end CedarPooSpec.ClinicalBreakGlassExport

def main : IO Unit :=
  match CedarPooSpec.ClinicalBreakGlassExport.manifest with
  | .ok json => IO.println json.compress
  | .error message => throw (IO.userError message)
