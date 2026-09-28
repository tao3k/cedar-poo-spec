import CedarPooSpec.PolicyJson
import Examples.Governance.AttestedDataAccess

/-! Export attested-data POO revisions and Lean-computed authorization receipts. -/

namespace CedarPooSpec.AttestedDataAccessExport

open CedarPooSpec.AttestedDataAccessExample

private def case (name root : String) (req : Cedar.Spec.Request) :
    Except String Lean.Json :=
  PolicyJson.authorizationCase name s!"attested-{root.toLower}" model root req entities

def rows : Except String (List Lean.Json) := do
  let stable ← unchangedCases.mapM fun (name, req, _) => do
    let before ← case s!"{name}-baseline" "Governed" req
    let after ← case s!"{name}-updated" "GovernedV2" req
    return [before, after]
  let staleBefore ← case "stale-attestation-baseline" "Governed"
    (request customerDataset { attestationFresh := false })
  let staleAfter ← case "stale-attestation-updated" "GovernedV2"
    (request customerDataset { attestationFresh := false })
  let inherited ← case "pre-integration-broad-permit" "DataOwner"
    (request financeDataset {})
  return stable.flatten ++ [staleBefore, staleAfter, inherited]

def manifest : Except String Lean.Json := do
  return Lean.Json.mkObj [("cases", Lean.toJson (← rows))]

end CedarPooSpec.AttestedDataAccessExport
