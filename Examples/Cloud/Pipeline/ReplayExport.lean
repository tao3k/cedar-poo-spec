import Examples.Cloud.Pipeline.GoogleThreatCase

/-! Export the same stage decisions checked in Lean for Cedar Rust replay. -/

namespace CedarPooSpec.Cloud.Pipeline.GoogleThreatCase

def manifest : Except String Lean.Json := do
  let rows ← cases.mapM fun (name, root, resource, facts, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name root model root
      (request resource facts) entities
  return Lean.Json.mkObj [("cases", Lean.toJson rows)]

end CedarPooSpec.Cloud.Pipeline.GoogleThreatCase
