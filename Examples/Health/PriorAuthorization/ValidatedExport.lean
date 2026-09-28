import Examples.Health.PriorAuthorization.PriorAuthorization

namespace CedarPooSpec.PriorAuthorizationValidatedExport

open CedarPooSpec.PriorAuthorizationExample

/-- Every request is captured immediately before its proposed admission. -/
def manifest : Except String Lean.Json := do
  let mut rows : List Lean.Json := []
  for (name, root, state, attempts, _) in cases do
    for ((req, _), index) in (replay root state attempts).1.zipIdx do
      let row ← CedarPooSpec.PolicyJson.authorizationCase
        s!"{name}-step-{index}" root model root req entities
      rows := rows ++ [row]
  CedarPooSpec.SchemaJson.validatedManifest schema rows

/-- Raw Cedar replay of a malformed request that schema validation rejects.
    It checks the final positive grant's fail-closed behavior as well. -/
def malformedManifest : Except String Lean.Json := do
  let row ← CedarPooSpec.PolicyJson.authorizationCase
    "missing-disclosure-fact" "Governed" model "Governed"
    missingDisclosureFact entities
  return Lean.Json.mkObj [("cases", Lean.toJson [row])]

end CedarPooSpec.PriorAuthorizationValidatedExport
