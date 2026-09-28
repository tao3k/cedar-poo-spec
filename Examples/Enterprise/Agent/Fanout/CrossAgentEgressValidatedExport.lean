import Examples.Enterprise.Agent.Fanout.CrossAgentEgress

namespace CedarPooSpec.CrossAgentEgressValidatedExport

open CedarPooSpec.CrossAgentEgressExample

/-- Export each request with the exact ledger facts seen before admission. -/
def manifest : Except String Lean.Json := do
  let mut rows : List Lean.Json := []
  for (name, root, view, attempts, _) in cases do
    for ((req, _), index) in (replay root view {} attempts).1.zipIdx do
      let row ← CedarPooSpec.PolicyJson.authorizationCase
        s!"{name}-step-{index}" root model root req entities
      rows := rows ++ [row]
  CedarPooSpec.SchemaJson.validatedManifest schema rows

end CedarPooSpec.CrossAgentEgressValidatedExport
