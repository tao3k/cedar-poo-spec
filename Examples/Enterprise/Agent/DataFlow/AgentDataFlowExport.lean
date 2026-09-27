import Examples.Enterprise.Agent.DataFlow.AgentDataFlow

namespace CedarPooSpec.AgentDataFlowExport

open CedarPooSpec.AgentDataFlowExample

def wellFormedRows : Except String (List Lean.Json) := do
  let mut rows : List Lean.Json := []
  for (name, readRoot, publishRoot, source, repo, origin, approver, approved, _) in cases do
    for ((root, req), index) in
        (checks readRoot publishRoot source repo origin approver approved).zipIdx do
      let receipt ← CedarPooSpec.PolicyJson.authorizationCase
        s!"{name}-layer-{index}" root.toLower dataModel root req dataEntities
      rows := rows ++ [receipt]
  return rows

def manifest : Except String Lean.Json := do
  let mut rows ← wellFormedRows
  for ((root, req), index) in malformedChecks.zipIdx do
    let receipt ← CedarPooSpec.PolicyJson.authorizationCase
      s!"malformed-review-layer-{index}" root.toLower dataModel root req dataEntities
    rows := rows ++ [receipt]
  return Lean.Json.mkObj [("cases", Lean.toJson rows)]

end CedarPooSpec.AgentDataFlowExport
