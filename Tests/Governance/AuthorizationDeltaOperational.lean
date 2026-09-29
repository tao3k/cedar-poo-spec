import CedarPooSpec.AuthorizationDeltaOperational
import CedarPooSpec.PolicyJson
import Examples.Governance.TicketSharing

/-!
A validated policy can overflow on a well-typed input. Cedar skips that
policy and keeps the same Allow/Deny decision; an error-rejecting Host changes
its execution decision. The operational delta must expose that witness.
-/

namespace CedarPooSpec.AuthorizationDeltaOperationalTest

open Cedar.Spec Cedar.Validation Cedar.Data
open CedarPooSpec.PolicyModules CedarPooSpec.TicketSharingExample
open CedarPooSpec.AuthorizationDelta

def amountActionEntry : ActionSchemaEntry :=
  { actionEntry with context := Map.make [
      ("deviceTrusted", .required (.bool .anyBool)),
      ("amount", .required .int)] }

def amountSchema : Schema :=
  { schema with acts := Map.make [(readAction, amountActionEntry)] }

def underflowGuard : Policy :=
  { id := "underflow-guard"
    effect := .forbid
    principalScope := .principalScope .any
    actionScope := .actionScope (.eq readAction)
    resourceScope := .resourceScope .any
    condition := [{ kind := .when, body := (
      .binaryApp .less
        (.binaryApp .sub (.getAttr (.var .context) "amount") (.lit (.int 1)))
        (.binaryApp .sub (.getAttr (.var .context) "amount") (.lit (.int 1)))) }] }

def allowAll : Policy :=
  { id := "baseline-allow"
    effect := .permit
    principalScope := .principalScope .any
    actionScope := .actionScope (.eq readAction)
    resourceScope := .resourceScope .any
    condition := [{ kind := .when, body := .lit (.bool true) }] }

def errorModel : Model :=
  (({ modules := [] } : Model).mix "Baseline" [] [.extend allowAll] |>.toOption.get
    (by native_decide) |>.extend "UnderflowGuard" "Baseline" [.extend underflowGuard]).toOption.get
    (by native_decide)

def run : IO Lean.Json := do
  let qualified ← match ← analyzeOperationalModelImpact model "Published" "Posture" schema with
    | .ok result => pure result
    | .error error => throw (IO.userError s!"qualified posture delta: {reprStr error}")
  if qualified.impact.classification != "loss-only" ||
      qualified.policiesChecked != 5 || qualified.environmentsChecked != 1 then
    throw (IO.userError "error-free posture delta changed")
  let revision ← match errorModel.compileRevision "Baseline" "UnderflowGuard" with
    | .ok revision => pure revision
    | .error error => throw (IO.userError s!"revision: {reprStr error}")
  let ordinary ← match ← analyzeImpact revision amountSchema with
    | .ok result => pure result
    | .error error => throw (IO.userError s!"ordinary delta: {reprStr error}")
  let (errorPolicy, errorWitness) ← match ← analyzeOperationalImpact revision amountSchema with
    | .error (.afterError id witness) =>
        let before := Cedar.Spec.isAuthorized witness.request witness.entities
          revision.beforePolicies
        let after := Cedar.Spec.isAuthorized witness.request witness.entities
          revision.afterPolicies
        if before.decision != .allow || after.decision != .allow ||
            !before.erroringPolicies.isEmpty ||
            !after.erroringPolicies.contains id then
          throw (IO.userError "error witness did not preserve Cedar Allow")
        pure (id, witness)
    | .error error => throw (IO.userError s!"operational delta: {reprStr error}")
    | .ok _ => throw (IO.userError "operational delta missed policy error")
  if ordinary.classification != "equivalent-in-schema" then
    throw (IO.userError "decision delta unexpectedly changed")
  let .ok beforeCase := CedarPooSpec.PolicyJson.authorizationCase
      "error-delta-before" "Baseline" errorModel "Baseline"
      errorWitness.request errorWitness.entities
    | throw (IO.userError "could not export baseline witness")
  let .ok afterCase := CedarPooSpec.PolicyJson.authorizationCase
      "error-delta-after" "UnderflowGuard" errorModel "UnderflowGuard"
      errorWitness.request errorWitness.entities
    | throw (IO.userError "could not export revised witness")
  return Lean.Json.mkObj [
    ("qualified_decision_delta", Lean.toJson qualified.impact.classification),
    ("qualified_policies_checked", Lean.toJson qualified.policiesChecked),
    ("decision_delta", Lean.toJson ordinary.classification),
    ("operational_error_policy", Lean.toJson errorPolicy),
    ("manifest", Lean.Json.mkObj [("cases", Lean.toJson [beforeCase, afterCase])])]

end CedarPooSpec.AuthorizationDeltaOperationalTest

def main : IO Unit := do
  IO.println (← CedarPooSpec.AuthorizationDeltaOperationalTest.run).compress
