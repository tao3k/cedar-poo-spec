import CedarPooSpec.PolicyJson
import Examples.Governance.TicketSharing

/-! Machine-readable cases computed from the Lean POO/Cedar source objects. -/

namespace CedarPooSpec.TicketSharingExport

open CedarPooSpec.TicketSharingExample

theorem unsupportedScopeRejected :
    (match PolicyJson.policy
      { Cedar.Spec.Policy.allowAll with
        principalScope := .principalScope (.is userType) } with
     | .error (.unsupportedScope _) => true
     | _ => false) = true := by
  native_decide

theorem duplicateIdsRejected :
    (match PolicyJson.policySet [Cedar.Spec.Policy.allowAll,
      Cedar.Spec.Policy.allowAll] with
     | .error (.duplicatePolicyId _) => true
     | _ => false) = true := by
  native_decide

private def convert {α : Type} [Repr α] (result : Except α β) : Except String β :=
  result.mapError (fun error => reprStr error)

private def case (name : String) (policyModel : CedarPooSpec.PolicyModules.Model)
    (root : String) (req : Cedar.Spec.Request)
    (store : Cedar.Spec.Entities) : Except String Lean.Json := do
  let policies ← convert (policyModel.compile root)
  let exported ← convert (PolicyJson.compiled policyModel root)
  let exportedEntities ← convert (PolicyJson.entities store)
  let exportedRequest ← convert (PolicyJson.request req)
  let response := Cedar.Spec.isAuthorized req store policies
  return Lean.Json.mkObj [
    ("name", Lean.toJson name),
    ("policies", exported),
    ("entities", exportedEntities),
    ("request", exportedRequest),
    ("expected", Lean.toJson (match response.decision with
      | .allow => "allow"
      | .deny => "deny")),
    ("expected_errors", Lean.toJson response.erroringPolicies.toList.length)]

def manifest : Except String Lean.Json := do
  let baselineCases ← List.mapM (fun (name, root, req, store) =>
    case name model root req store) [
    ("published-alice", "Published", request alice ticketA false, entities),
    ("posture-untrusted", "Posture", request alice ticketA false, entities),
    ("posture-trusted", "Posture", request alice ticketA true, entities),
    ("posture-viewer", "Posture", request bob ticketA false, entities),
    ("posture-closed", "Posture", request alice ticketA true, closedEntities),
    ("revoked-bob", "Revoked", request bob ticketB true, entities),
    ("revoked-viewer", "Revoked", request bob ticketA false, entities)]
  let newGrant ← case "expanded-alice" expandedModel "Expanded"
    (request alice ticketB true) entities
  let stillRevoked ← case "expanded-bob" expandedModel "Expanded"
    (request bob ticketB true) entities
  return Lean.Json.mkObj [("cases", Lean.toJson (baselineCases ++ [newGrant, stillRevoked]))]

end CedarPooSpec.TicketSharingExport

def main : IO Unit :=
  match CedarPooSpec.TicketSharingExport.manifest with
  | .ok json => IO.println json.compress
  | .error message => throw (IO.userError message)
