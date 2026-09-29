import Examples.Cloud.Pipeline.DeploymentCase

namespace CedarPooSpec.Cloud.Pipeline.DeploymentCase

def manifest : Except String Lean.Json := do
  let rows ← (choices.flatMap fun choice =>
    [(s!"{choice.name}-promotion", choice.root,
        GoogleThreatCase.request GoogleThreatCase.candidate choice.pipeline),
      (s!"{choice.name}-deployment", choice.root, deployRequest choice)]).mapM
      fun (name, root, request) =>
        CedarPooSpec.PolicyJson.authorizationCase name root model root
          request entities
  return Lean.Json.mkObj [("cases", Lean.toJson rows)]

end CedarPooSpec.Cloud.Pipeline.DeploymentCase
