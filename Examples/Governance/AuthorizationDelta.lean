import CedarPooSpec.AuthorizationDelta
import CedarPooSpec.PolicyJson
import Examples.Governance.TicketSharing

/-!
The same ticket-sharing C4 graph first narrows access through device posture,
then grants access to another ticket. Cedar SymCC analyzes both revisions over
every request type declared by the example schema.
-/

namespace CedarPooSpec.TicketSharingDelta

open CedarPooSpec.TicketSharingExample
open CedarPooSpec.AuthorizationDelta

private def renderExpansion (expansion : Expansion) : Except String Lean.Json := do
  let request ← CedarPooSpec.PolicyJson.request expansion.witness.request |>.mapError reprStr
  let entities ← CedarPooSpec.PolicyJson.entities expansion.witness.entities |>.mapError reprStr
  return Lean.Json.mkObj [
    ("request", request),
    ("entities", entities),
    ("before_decision", Lean.toJson expansion.beforeResponse.decision),
    ("after_decision", Lean.toJson expansion.afterResponse.decision),
    ("before_reasons", Lean.toJson expansion.beforeResponse.determiningPolicies.toList),
    ("after_reasons", Lean.toJson expansion.afterResponse.determiningPolicies.toList)]

private def renderReport (report : Report) : Except String Lean.Json := do
  let expansions ← report.expansions.mapM renderExpansion
  return Lean.Json.mkObj [
    ("status", Lean.toJson (if report.noExpansion then "no-expansion-in-schema" else "expanded")),
    ("changed_policy_ids", Lean.toJson report.changedPolicyIds),
    ("environments_checked", Lean.toJson report.environmentsChecked),
    ("counterexamples", Lean.toJson expansions)]

private def renderWitnessCases (report : Report) : Except String Lean.Json := do
  let cases ← report.expansions.zipIdx.mapM fun (expansion, index) => do
    let before ← CedarPooSpec.PolicyJson.authorizationCase s!"delta-before-{index}"
      "revoked" expandedModel "Revoked" expansion.witness.request expansion.witness.entities
    let after ← CedarPooSpec.PolicyJson.authorizationCase s!"delta-after-{index}"
      "expanded" expandedModel "Expanded" expansion.witness.request expansion.witness.entities
    return [before, after]
  return Lean.Json.mkObj [("cases", Lean.toJson cases.flatten)]

def run : IO Lean.Json := do
  let narrowed ← match ← analyzeModel model "Published" "Posture" schema with
    | .ok report => pure report
    | .error error => throw (IO.userError s!"posture analysis: {reprStr error}")
  if !narrowed.noExpansion then
    throw (IO.userError "posture revision unexpectedly expands authorization")
  let expanded ← match ← analyzeModel expandedModel "Revoked" "Expanded" schema with
    | .ok report => pure report
    | .error error => throw (IO.userError s!"grant analysis: {reprStr error}")
  if expanded.noExpansion then
    throw (IO.userError "new ticket grant has no expansion witness")
  let .ok narrowJson := renderReport narrowed
    | throw (IO.userError "could not render posture report")
  let .ok expandedJson := renderReport expanded
    | throw (IO.userError "could not render grant counterexample")
  let .ok manifest := renderWitnessCases expanded
    | throw (IO.userError "could not render Cedar witness cases")
  return Lean.Json.mkObj [("posture", narrowJson), ("new_grant", expandedJson),
    ("manifest", manifest)]

end CedarPooSpec.TicketSharingDelta

def main : IO Unit := do
  IO.println (← CedarPooSpec.TicketSharingDelta.run).compress
