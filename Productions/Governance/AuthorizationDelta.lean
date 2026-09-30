import CedarPooSpec.AuthorizationDeltaJson
import Examples.Governance.TicketSharing

/-!
The same ticket-sharing C4 graph first narrows access through device posture,
then grants access to another ticket. Cedar SymCC analyzes both revisions over
every request type declared by the example schema.
-/

namespace CedarPooSpec.TicketSharingDelta

open CedarPooSpec.TicketSharingExample
open CedarPooSpec.AuthorizationDelta

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
  let .ok narrowJson := CedarPooSpec.AuthorizationDeltaJson.report narrowed
    | throw (IO.userError "could not render posture report")
  let .ok expandedJson := CedarPooSpec.AuthorizationDeltaJson.report expanded
    | throw (IO.userError "could not render grant counterexample")
  let .ok manifest := CedarPooSpec.AuthorizationDeltaJson.witnessCases expanded
    expandedModel "Revoked" "Expanded"
    | throw (IO.userError "could not render Cedar witness cases")
  return Lean.Json.mkObj [("posture", narrowJson), ("new_grant", expandedJson),
    ("manifest", manifest)]

end CedarPooSpec.TicketSharingDelta

def main : IO Unit := do
  IO.println (← CedarPooSpec.TicketSharingDelta.run).compress
