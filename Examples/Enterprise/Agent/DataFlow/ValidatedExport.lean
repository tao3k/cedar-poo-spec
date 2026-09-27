import CedarPooSpec.SchemaJson
import Examples.Enterprise.Agent.DataFlow.AgentDataFlowExport

namespace CedarPooSpec.AgentDataFlowValidatedExport

def manifest : Except String Lean.Json := do
  let rows ← CedarPooSpec.AgentDataFlowExport.wellFormedRows
  CedarPooSpec.SchemaJson.validatedManifest
    CedarPooSpec.AgentDataFlowExample.dataSchema rows

end CedarPooSpec.AgentDataFlowValidatedExport
