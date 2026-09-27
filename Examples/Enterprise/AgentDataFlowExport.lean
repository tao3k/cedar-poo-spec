import Examples.Enterprise.AgentDataFlow

namespace CedarPooSpec.AgentDataFlowExport

open CedarPooSpec.AgentDataFlowExample

def manifest : Except String Lean.Json := do
  let mut rows : List Lean.Json := []
  for (name, readRoot, publishRoot, source, repo, origin, approver, approved, _) in cases do
    for ((root, req), index) in
        (checks readRoot publishRoot source repo origin approver approved).zipIdx do
      let receipt ← CedarPooSpec.PolicyJson.authorizationCase
        s!"{name}-layer-{index}" root.toLower dataModel root req dataEntities
      rows := rows ++ [receipt]
  return Lean.Json.mkObj [("cases", Lean.toJson rows)]

end CedarPooSpec.AgentDataFlowExport

def main : IO Unit :=
  match CedarPooSpec.AgentDataFlowExport.manifest with
  | .ok json => IO.println json.compress
  | .error message => throw (IO.userError message)
