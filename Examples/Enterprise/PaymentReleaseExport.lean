import Examples.Enterprise.PaymentRelease

namespace CedarPooSpec.PaymentReleaseExport

open CedarPooSpec.PaymentReleaseExample

def manifest : Except String Lean.Json := do
  let mut rows : List Lean.Json := []
  for (name, root, preparer, releaser, resource, _) in operationCases do
    let first ← CedarPooSpec.PolicyJson.authorizationCase s!"{name}-prepare"
      root.toLower model root (request preparer prepare resource) entities
    let second ← CedarPooSpec.PolicyJson.authorizationCase s!"{name}-release"
      root.toLower model root (request releaser release resource) entities
    rows := rows ++ [first, second]
  for (name, root, principal, action, resource, _) in branchCases do
    let receipt ← CedarPooSpec.PolicyJson.authorizationCase name root.toLower
      model root (request principal action resource) entities
    rows := rows ++ [receipt]
  return Lean.Json.mkObj [("cases", Lean.toJson rows)]

end CedarPooSpec.PaymentReleaseExport
