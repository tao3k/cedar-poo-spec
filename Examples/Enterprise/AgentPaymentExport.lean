import Examples.Enterprise.AgentPayment

namespace CedarPooSpec.AgentPaymentExport

open CedarPooSpec.AgentPaymentExample

def manifest : Except String Lean.Json := do
  let mut rows : List Lean.Json := []
  for (name, root, account, origin, requested, _) in cases do
    for ((layerRoot, req), index) in (checks root account origin requested).zipIdx do
      let receipt ← CedarPooSpec.PolicyJson.authorizationCase
        s!"{name}-layer-{index}" layerRoot.toLower paymentModel layerRoot req paymentEntities
      rows := rows ++ [receipt]
  return Lean.Json.mkObj [("cases", Lean.toJson rows)]

end CedarPooSpec.AgentPaymentExport

def main : IO Unit :=
  match CedarPooSpec.AgentPaymentExport.manifest with
  | .ok json => IO.println json.compress
  | .error message => throw (IO.userError message)
