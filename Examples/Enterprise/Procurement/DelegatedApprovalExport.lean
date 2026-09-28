import Examples.Enterprise.Procurement.DelegatedApproval

namespace CedarPooSpec.DelegatedApprovalExport

open CedarPooSpec.DelegatedApprovalExample

def manifest : Except String Lean.Json := do
  let exported ← delegatedCases.mapM fun (name, root, req, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name root.toLower delegatedModel
      root req delegatedEntities
  return Lean.Json.mkObj [("cases", Lean.toJson exported)]

end CedarPooSpec.DelegatedApprovalExport
