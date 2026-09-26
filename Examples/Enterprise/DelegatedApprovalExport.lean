import Examples.Enterprise.DelegatedApproval

namespace CedarPooSpec.DelegatedApprovalExport

open CedarPooSpec.DelegatedApprovalExample

def manifest : Except String Lean.Json := do
  let exported ← delegatedCases.mapM fun (name, root, req, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name root.toLower delegatedModel
      root req delegatedEntities
  return Lean.Json.mkObj [("cases", Lean.toJson exported)]

end CedarPooSpec.DelegatedApprovalExport

def main : IO Unit :=
  match CedarPooSpec.DelegatedApprovalExport.manifest with
  | .ok json => IO.println json.compress
  | .error message => throw (IO.userError message)
