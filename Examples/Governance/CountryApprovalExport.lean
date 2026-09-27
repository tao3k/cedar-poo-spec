import Examples.Governance.CountryApproval

namespace CedarPooSpec.CountryApprovalExport

open CedarPooSpec.CountryApprovalExample

def manifest : Except String Lean.Json := do
  let exported ← cases.mapM fun (name, root, req, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name root.toLower model
      root req entities
  return Lean.Json.mkObj [("cases", Lean.toJson exported)]

end CedarPooSpec.CountryApprovalExport
