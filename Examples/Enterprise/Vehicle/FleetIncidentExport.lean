import Examples.Enterprise.Vehicle.FleetIncident

/-! Export Lean-computed fleet authorization receipts and Cedar revisions. -/

namespace CedarPooSpec.FleetIncidentExport

open CedarPooSpec.FleetIncidentExample

def manifest : Except String Lean.Json := do
  let mut rows : List Lean.Json := []
  for (name, root, batch, facts, _) in updateCases do
    for ((layerRoot, request), index) in (updateChecks root batch facts).zipIdx do
      let receipt ← CedarPooSpec.PolicyJson.authorizationCase
        s!"{name}-layer-{index}" layerRoot.toLower model layerRoot request entities
      rows := rows ++ [receipt]
  for (name, root, batch, facts, _) in commandCases do
    let receipt ← CedarPooSpec.PolicyJson.authorizationCase
      name root.toLower model root (commandRequest batch facts) entities
    rows := rows ++ [receipt]
  return Lean.Json.mkObj [("cases", Lean.toJson rows)]

end CedarPooSpec.FleetIncidentExport
