import Examples.Enterprise.Vehicle.VLA.CommandBoundary

/-! Export the same named decisions and materialized policy revisions. -/

namespace CedarPooSpec.VlaCommandBoundaryExport

open CedarPooSpec.VlaCommandBoundaryExample

def manifest : Except String Lean.Json := do
  let mut rows : List Lean.Json := []
  for (name, root, action, segment, facts, _) in cases do
    let receipt ← CedarPooSpec.PolicyJson.authorizationCase
      name root.toLower model root (request action segment facts) entities
    rows := rows ++ [receipt]
  return Lean.Json.mkObj [("cases", Lean.toJson rows)]

end CedarPooSpec.VlaCommandBoundaryExport
