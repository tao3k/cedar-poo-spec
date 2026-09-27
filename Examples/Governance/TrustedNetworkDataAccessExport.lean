import Examples.Governance.TrustedNetworkDataAccess

namespace CedarPooSpec.TrustedNetworkDataAccessExport

open CedarPooSpec.TrustedNetworkDataAccessExample

def manifest : Except String Lean.Json := do
  let exported ← cases.mapM fun (name, root, req, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name root.toLower networkModel
      root req networkEntities
  return Lean.Json.mkObj [("cases", Lean.toJson exported)]

end CedarPooSpec.TrustedNetworkDataAccessExport
