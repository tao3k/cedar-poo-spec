import Examples.Enterprise.PurchaseApproval

namespace CedarPooSpec.PurchaseApprovalExport

open CedarPooSpec.PurchaseApprovalExample

def manifest : Except String Lean.Json := do
  let exported ← cases.mapM fun (name, root, req, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name root.toLower model
      root req entities
  return Lean.Json.mkObj [("cases", Lean.toJson exported)]

end CedarPooSpec.PurchaseApprovalExport

def main : IO Unit :=
  match CedarPooSpec.PurchaseApprovalExport.manifest with
  | .ok json => IO.println json.compress
  | .error message => throw (IO.userError message)
