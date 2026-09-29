import CedarPooSpec.AuthorizationDeltaReasons
import CedarPooSpec.PolicyJson
import Examples.Governance.TicketSharing

/-!
Two independent grants authorize the same ticket. Removing one changes the
Cedar reason set but not the Allow/Deny decision. A shared incident veto can
mask the reason change, which must remain unresolved rather than certified.
-/

namespace CedarPooSpec.AuthorizationDeltaReasonTest

open Cedar.Spec CedarPooSpec.PolicyModules CedarPooSpec.TicketSharingExample
open CedarPooSpec.AuthorizationDelta

def primary : Policy :=
  (policiesV1.find? (·.id == "alice-ticket-a")).get (by native_decide)

def fallback : Policy := { primary with id := "alice-ticket-a-fallback" }

def incidentVeto : Policy :=
  { primary with
    id := "incident-veto",
    effect := .forbid,
    condition := [{ kind := .when, body := .lit (.bool true) }] }

def sharedModel : Model :=
  let base := (({ modules := [] } : Model).mix "Shared" []
    [.extend primary, .extend fallback]).toOption.get (by native_decide)
  (base.extend "OneGrantRemoved" "Shared" [.remove primary.id]).toOption.get
    (by native_decide)

def maskedModel : Model :=
  let base := (({ modules := [] } : Model).mix "Masked" []
    [.extend primary, .extend fallback, .extend incidentVeto]).toOption.get
      (by native_decide)
  (base.extend "MaskedOneRemoved" "Masked" [.remove primary.id]).toOption.get
    (by native_decide)

/-- Reassign ownership of the same Cedar policy through a native overlay. -/
def ownerModel : Model :=
  (sharedModel.extend "OwnershipShift" "Shared" [.overlay primary]).toOption.get
    (by native_decide)

def run : IO Lean.Json := do
  let .ok changed ← analyzeModelReasons sharedModel "Shared" "OneGrantRemoved" schema
    | throw (IO.userError "reason delta failed")
  if changed.report.decision.impact.classification != "equivalent-in-schema" ||
      changed.report.reasonStable || changed.report.reasonWitnesses.length != 1 ||
      !changed.report.unresolvedPolicyIds.isEmpty then
    throw (IO.userError "same-decision reason change was missed")
  let some edit := changed.report.changes.head?
    | throw (IO.userError "POO edit source missing")
  if changed.report.changes.length != 1 || edit.id != primary.id ||
      edit.beforeOwner.map (·.lastEditedBy) != some "Shared" ||
      edit.afterOwner.isSome ||
      !changed.potentiallyInvalidatedRoots.contains "OneGrantRemoved" then
    throw (IO.userError "reason witness lost C4 edit provenance")
  let some witness := changed.report.reasonWitnesses.head?
    | throw (IO.userError "reason witness missing")
  if witness.beforeResponse.decision != .allow ||
      witness.afterResponse.decision != .allow ||
      !witness.beforeResponse.determiningPolicies.contains primary.id ||
      witness.afterResponse.determiningPolicies.contains primary.id ||
      !witness.afterResponse.determiningPolicies.contains fallback.id then
    throw (IO.userError "invalid reason-change witness")
  let .ok stable ← analyzeModelReasons sharedModel "Shared" "Shared" schema
    | throw (IO.userError "stable reason query failed")
  if !stable.report.reasonStable || stable.report.matchingQueries != 0 then
    throw (IO.userError "unchanged root was not reason-stable")
  let .ok ownerShift ← analyzeModelReasons ownerModel "Shared" "OwnershipShift" schema
    | throw (IO.userError "owner delta query failed")
  let some transfer := ownerShift.report.provenanceChanges.head?
    | throw (IO.userError "same-body owner transfer was missed")
  if ownerShift.report.decision.impact.classification != "equivalent-in-schema" ||
      !ownerShift.report.reasonStable || ownerShift.report.provenanceStable ||
      !ownerShift.report.changes.isEmpty ||
      !ownerShift.report.proof.freshPolicyIds.isEmpty ||
      !ownerShift.report.proof.authorizationDependencies.isEmpty ||
      ownerShift.report.provenanceChanges.length != 1 ||
      transfer.id != primary.id ||
      transfer.beforeOwner.map (·.lastEditedBy) != some "Shared" ||
      transfer.afterOwner.map (·.lastEditedBy) != some "OwnershipShift" ||
      !ownerShift.potentiallyInvalidatedRoots.contains "OwnershipShift" then
    throw (IO.userError "same-body owner transfer was misclassified")
  let .ok masked ← analyzeModelReasons maskedModel "Masked" "MaskedOneRemoved" schema
    | throw (IO.userError "masked reason query failed")
  if masked.report.decision.impact.classification != "equivalent-in-schema" ||
      masked.report.reasonStable ||
      masked.report.unresolvedPolicyIds != [primary.id] ||
      !masked.report.reasonWitnesses.isEmpty then
    throw (IO.userError "masked match was incorrectly certified")
  let .ok beforeCase := CedarPooSpec.PolicyJson.authorizationCase
      "reason-before" "Shared" sharedModel "Shared"
      witness.witness.request witness.witness.entities
    | throw (IO.userError "could not export before reason witness")
  let .ok afterCase := CedarPooSpec.PolicyJson.authorizationCase
      "reason-after" "OneGrantRemoved" sharedModel "OneGrantRemoved"
      witness.witness.request witness.witness.entities
    | throw (IO.userError "could not export after reason witness")
  return Lean.Json.mkObj [
    ("decision_delta", Lean.toJson changed.report.decision.impact.classification),
    ("reason_policy", Lean.toJson witness.policyId),
    ("reason_stable", Lean.toJson changed.report.reasonStable),
    ("before_owner", Lean.toJson (edit.beforeOwner.map (·.lastEditedBy))),
    ("invalidated_roots", Lean.toJson changed.potentiallyInvalidatedRoots),
    ("masked_unresolved", Lean.toJson masked.report.unresolvedPolicyIds),
    ("stable_same_root", Lean.toJson stable.report.reasonStable),
    ("owner_shift_reason_stable", Lean.toJson ownerShift.report.reasonStable),
    ("owner_shift_provenance_stable", Lean.toJson ownerShift.report.provenanceStable),
    ("owner_shift_changed_policy_ids", Lean.toJson (ownerShift.report.changes.map (·.id))),
    ("owner_shift_policy", Lean.toJson transfer.id),
    ("owner_shift_before_owner", Lean.toJson (transfer.beforeOwner.map (·.lastEditedBy))),
    ("owner_shift_after_owner", Lean.toJson (transfer.afterOwner.map (·.lastEditedBy))),
    ("manifest", Lean.Json.mkObj [("cases", Lean.toJson [beforeCase, afterCase])])]

end CedarPooSpec.AuthorizationDeltaReasonTest

def main : IO Unit := do
  IO.println (← CedarPooSpec.AuthorizationDeltaReasonTest.run).compress
