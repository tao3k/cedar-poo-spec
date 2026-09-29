import Examples.Cloud.DataProtection.GoogleSdpRelease

namespace CedarPooSpec.Cloud.DataProtection.GoogleSdpRelease

open CedarPooSpec.Cloud.Pipeline

def manifest : Except String Lean.Json := do
  let rows ← (choices.flatMap fun choice =>
    [(s!"{choice.name}-pipeline", choice.root,
        GoogleThreatCase.request GoogleThreatCase.candidate choice.pipeline),
      (s!"{choice.name}-transform", choice.root, transformRequest choice)]).mapM
      fun (name, root, request) =>
        CedarPooSpec.PolicyJson.authorizationCase name root model root
          request entities
  return Lean.Json.mkObj [("cases", Lean.toJson rows)]

end CedarPooSpec.Cloud.DataProtection.GoogleSdpRelease
