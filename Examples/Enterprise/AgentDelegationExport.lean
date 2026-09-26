import Examples.Enterprise.AgentDelegation

namespace CedarPooSpec.AgentDelegationExport

open CedarPooSpec.AgentDelegationExample

def manifest : Except String Lean.Json := do
  let mut rows : List Lean.Json := []
  for (name, roots, agent, tool, origin, depth, capability, _) in flowCases do
    for ((root, req), index) in (checks roots agent tool origin depth capability).zipIdx do
      let receipt ← CedarPooSpec.PolicyJson.authorizationCase
        s!"{name}-layer-{index}" root.toLower model root req entities
      rows := rows ++ [receipt]
  for ((root, req), index) in malformedChecks.zipIdx do
    let receipt ← CedarPooSpec.PolicyJson.authorizationCase
      s!"malformed-origin-layer-{index}" root.toLower model root req entities
    rows := rows ++ [receipt]
  return Lean.Json.mkObj [("cases", Lean.toJson rows)]

end CedarPooSpec.AgentDelegationExport

def main : IO Unit :=
  match CedarPooSpec.AgentDelegationExport.manifest with
  | .ok json => IO.println json.compress
  | .error message => throw (IO.userError message)
