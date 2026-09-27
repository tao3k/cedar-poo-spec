import Examples.Enterprise.Exchange.Signing.SigningBoundary

namespace CedarPooSpec.ExchangeSigningExport

open CedarPooSpec.ExchangeSigningExample

def manifest : Except String Lean.Json := do
  let mut rows : List Lean.Json := []
  for (name, root, wallet, facts, _) in cases do
    let receipt ← CedarPooSpec.PolicyJson.authorizationCase
      name root.toLower model root (request wallet facts) entities
    rows := rows ++ [receipt]
  return Lean.Json.mkObj [("cases", Lean.toJson rows)]

end CedarPooSpec.ExchangeSigningExport
