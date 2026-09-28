import Examples.Enterprise.Agent.Payment.AgentPayment
import CedarPooSpec.SchemaJson

namespace CedarPooSpec.AgentPaymentValidatedExport

open CedarPooSpec.AgentPaymentExample

def manifest : Except String Lean.Json := do
  let mut rows : List Lean.Json := []
  for (name, root, account, origin, requested, _) in cases do
    for ((layerRoot, req), index) in (checks root account origin requested).zipIdx do
      let receipt ← CedarPooSpec.PolicyJson.authorizationCase
        s!"{name}-layer-{index}" layerRoot.toLower paymentModel layerRoot req paymentEntities
      rows := rows ++ [receipt]
  CedarPooSpec.SchemaJson.validatedManifest paymentSchema rows

end CedarPooSpec.AgentPaymentValidatedExport
