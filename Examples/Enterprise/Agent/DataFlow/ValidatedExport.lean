import CedarPooSpec.SchemaJson
import Examples.Enterprise.Agent.DataFlow.AgentDataFlowExport

namespace CedarPooSpec.AgentDataFlowValidatedExport

open CedarPooSpec.AgentDataFlowExample
open CedarPooSpec.AgentDelegationExample

/-- Replay identical allow and deny requests through both construction roots. -/
def dispatchComparisonRows : Except String (List Lean.Json) := do
  let requests := [
    ("allow", publishRequest publicDoc publicRepo admin reviewer true),
    ("deny", publishRequest internalDoc publicRepo admin reviewer true)]
  let mut rows : List Lean.Json := []
  for (label, req) in requests do
    for root in ["PublishGoverned", "PublishDispatched"] do
      let receipt ← CedarPooSpec.PolicyJson.authorizationCase
        s!"dispatch-{label}-{root.toLower}" root.toLower dataModel root req dataEntities
      rows := rows ++ [receipt]
  return rows

def manifest : Except String Lean.Json := do
  let rows ← CedarPooSpec.AgentDataFlowExport.wellFormedRows
  let comparisons ← dispatchComparisonRows
  CedarPooSpec.SchemaJson.validatedManifest
    dataSchema (rows ++ comparisons)

end CedarPooSpec.AgentDataFlowValidatedExport
