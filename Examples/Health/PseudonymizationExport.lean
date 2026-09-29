import CedarPooSpec.PolicyJson
import CedarPooSpec.SchemaJson
import Examples.Health.Pseudonymization
import Examples.Health.Pseudonymization.Deployment
import Examples.Health.Pseudonymization.Lifecycle

/-! Export each composed root with the same source and target entities used by
the Lean decision proof. Rust Cedar validates the schema and replays the cases. -/

namespace CedarPooSpec.PseudonymizationExport

open CedarPooSpec.PseudonymizationExample

def manifest : Except String Lean.Json := do
  unless hmacCatalogSeparated datasets do
    throw "cross-scope HMAC key reuse in published dataset catalog"
  let rows ← cases.mapM fun (name, root, req, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name root model root req entities
  CedarPooSpec.SchemaJson.validatedManifest schema rows

def deployableRoots : List PseudonymizationExample.Deployment.Root :=
  [.hospitalSiv, .randomizedGcm, .oneWayHmac,
   .resultRelease, .agentIncident, .recovered]

/-- Deployment artifacts have a typed allowlist; the migration ancestor is
    available only to the authorization regression manifest above. -/
def deploymentManifest : Except String Lean.Json := do
  unless hmacCatalogSeparated datasets do
    throw "cross-scope HMAC key reuse in published dataset catalog"
  let roots ← deployableRoots.mapM fun root => do
    let publication ← (PseudonymizationExample.Deployment.publish root).mapError
      (fun _ => "deployable root failed Cedar publication")
    return Lean.Json.mkObj [
      ("root", Lean.toJson root.name), ("policies", publication.json)]
  return Lean.toJson roots

end CedarPooSpec.PseudonymizationExport
