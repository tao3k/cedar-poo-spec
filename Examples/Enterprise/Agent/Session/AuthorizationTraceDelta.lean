import CedarPooSpec.AuthorizationDeltaTrace
import CedarPooSpec.PolicyJson
import Examples.Enterprise.Agent.Session.BoundedSession

/-!
One proposed agent action sequence is replayed from the same initial session
under two C4 roots. A denied action leaves its side's Host ledger unchanged,
so later requests may have different context even for the same proposal.
-/

namespace CedarPooSpec.BoundedSessionTraceDelta

open CedarPooSpec.AuthorizationDelta
open CedarPooSpec.BoundedSessionExample

private def observe (state : Session) (attempt : Attempt) : Cedar.Spec.Env :=
  ⟨request state attempt, entities⟩

private def compare (attempts : List Attempt) :
    Except Error (TraceImpact Session) :=
  compareTrace schema model "Base" "Integrated" ({} : Session)
    attempts observe advance

private def receiptCases (name : String) (impact : TraceImpact Session) :
    Except String (List Lean.Json) := do
  let indexed := impact.steps.zipIdx
  let before ← indexed.mapM fun (step, index) =>
    CedarPooSpec.PolicyJson.authorizationCase s!"{name}-before-{index}" "Base"
      model "Base" step.beforeEnv.request step.beforeEnv.entities
  let after ← indexed.mapM fun (step, index) =>
    CedarPooSpec.PolicyJson.authorizationCase s!"{name}-after-{index}" "Integrated"
      model "Integrated" step.afterEnv.request step.afterEnv.entities
  return before ++ after

def run : IO Lean.Json := do
  let .ok sensitive := compare [readSecret, sendExternal]
    | throw (IO.userError "sensitive-read trace comparison failed")
  if sensitive.steps.map TraceStep.beforeAllowed != [true, true] ||
      sensitive.steps.map TraceStep.afterAllowed != [true, false] ||
      !sensitive.lost || sensitive.gained ||
      !sensitive.beforeFinal.sensitiveSeen ||
      !sensitive.afterFinal.sensitiveSeen ||
      sensitive.beforeFinal.usedExports != 1 ||
      sensitive.afterFinal.usedExports != 0 ||
      !(sensitive.changes.map (·.id)).contains historyVeto.id then
    throw (IO.userError "sensitive-read trace lost its C4/history delta")
  let .ok budget := compare [readPublic, sendExternal, sendExternal, sendExternal]
    | throw (IO.userError "budget trace comparison failed")
  if budget.steps.map TraceStep.beforeAllowed != [true, true, true, true] ||
      budget.steps.map TraceStep.afterAllowed != [true, true, false, false] ||
      budget.beforeFinal.usedExports != 3 ||
      budget.afterFinal.usedExports != 1 ||
      !(budget.changes.map (·.id)).contains budgetVeto.id then
    throw (IO.userError "budget trace did not preserve separate Host states")
  let some last := budget.steps.getLast?
    | throw (IO.userError "budget trace has no final proposal")
  if last.beforeEnv.request.context == last.afterEnv.request.context then
    throw (IO.userError "later requests did not reflect divergent ledgers")
  let changedProposal := compareTrace schema model "Base" "Integrated"
      ({} : Session) [readPublic, sendExternal, sendExternal, sendExternal]
      (fun state attempt =>
        observe state (if state.usedExports > 1 then sendInternal else attempt))
      advance
  match changedProposal with
  | .error .operationChanged => pure ()
  | _ => throw (IO.userError "state-dependent operation substitution was admitted")
  let .ok sensitiveCases := receiptCases "sensitive" sensitive
    | throw (IO.userError "cannot export sensitive Cedar replay")
  let .ok budgetCases := receiptCases "budget" budget
    | throw (IO.userError "cannot export budget Cedar replay")
  return Lean.Json.mkObj [
    ("sensitive_before", Lean.toJson (sensitive.steps.map TraceStep.beforeAllowed)),
    ("sensitive_after", Lean.toJson (sensitive.steps.map TraceStep.afterAllowed)),
    ("budget_before", Lean.toJson (budget.steps.map TraceStep.beforeAllowed)),
    ("budget_after", Lean.toJson (budget.steps.map TraceStep.afterAllowed)),
    ("sensitive_owner", Lean.toJson
      ((sensitive.changes.find? (·.id == historyVeto.id)).bind
        (fun change => change.afterOwner.map (·.lastEditedBy)))),
    ("different_later_context", Lean.toJson true),
    ("operation_substitution_rejected", Lean.toJson true),
    ("manifest", Lean.Json.mkObj [("cases", Lean.toJson (sensitiveCases ++ budgetCases))])]

end CedarPooSpec.BoundedSessionTraceDelta

def main : IO Unit := do
  IO.println (← CedarPooSpec.BoundedSessionTraceDelta.run).compress
