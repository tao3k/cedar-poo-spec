import Examples.Enterprise.Agent.Department.DepartmentSynthesis

namespace CedarPooSpec.DepartmentSynthesisValidatedExport

open CedarPooSpec.DepartmentSynthesisExample

/-- Export the exact context supplied at each pre-admission boundary. -/
def manifest : Except String Lean.Json := do
  let mut rows : List Lean.Json := []
  for (name, root, state, attempts, _) in cases do
    for ((req, _), index) in (replay root state attempts).1.zipIdx do
      let row ← CedarPooSpec.PolicyJson.authorizationCase
        s!"{name}-step-{index}" root model root req entities
      rows := rows ++ [row]
  CedarPooSpec.SchemaJson.validatedManifest schema rows

end CedarPooSpec.DepartmentSynthesisValidatedExport
