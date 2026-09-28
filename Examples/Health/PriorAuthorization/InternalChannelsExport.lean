import Examples.Health.PriorAuthorization.InternalChannels

namespace CedarPooSpec.PriorAuthorizationInternalChannelsExport

open CedarPooSpec.PriorAuthorizationInternalChannels

def manifest : Except String Lean.Json := do
  let rows ← cases.mapM fun (name, root, envelope, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name root model root
      (request envelope) entities
  CedarPooSpec.SchemaJson.validatedManifest schema rows

end CedarPooSpec.PriorAuthorizationInternalChannelsExport
