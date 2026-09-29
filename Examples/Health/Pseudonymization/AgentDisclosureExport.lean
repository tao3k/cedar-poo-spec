import CedarPooSpec.PolicyJson
import CedarPooSpec.SchemaJson
import Examples.Health.Pseudonymization.AgentDisclosure

/-! The same synthetic requests and composed policy roots are replayed by
the official Cedar Rust validator and authorizer. -/

namespace CedarPooSpec.PseudonymizationExample.AgentDisclosureExport

open CedarPooSpec.PseudonymizationExample.AgentDisclosure

def manifest : Except String Lean.Json := do
  let rows ← AgentDisclosure.cases.mapM fun (name, root, state, effect, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name root
      publicationModel root (projectedRequest state effect) publicationEntities
  CedarPooSpec.SchemaJson.validatedManifest publicationSchema rows

end CedarPooSpec.PseudonymizationExample.AgentDisclosureExport
