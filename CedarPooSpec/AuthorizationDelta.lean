import CedarPooSpec.Revision
import Cedar.SymCC
import Cedar.Validation.EnvironmentValidator

/-!
Authorization changes are analyzed using Cedar's symbolic compiler. C4 owns
the revision; Cedar owns the meaning of Allow and the symbolic query.
-/

namespace CedarPooSpec.AuthorizationDelta

open Cedar.Spec Cedar.Validation CedarPooSpec.PolicyModules

inductive Error where
  | compilation (error : PolicyModules.Error)
  | schema (message : String)
  | noEnvironments
  | beforeInvalid (error : ValidationError)
  | afterInvalid (error : ValidationError)
  | beforeTypecheck (error : ValidationError)
  | afterTypecheck (error : ValidationError)
  | solver (message : String)
  | invalidWitness
  deriving Repr

/-- A concrete request and entity store that the new revision allows and the
    old revision denies, replayed against the original Cedar policies. -/
structure Expansion where
  typeEnv : TypeEnv
  witness : Cedar.Spec.Env
  beforeResponse : Response
  afterResponse : Response
  deriving Repr

/-- One query is run for every request type declared by the Cedar schema. -/
structure Report where
  changedPolicyIds : List PolicyID
  environmentsChecked : Nat
  expansions : List Expansion
  deriving Repr

def Report.noExpansion (report : Report) : Bool := report.expansions.isEmpty

/-- Check `Allow(new) → Allow(old)` in each schema environment. A solver error,
    unknown result, or failed witness replay never becomes a no-expansion result.
    The symbolic implication and its proof are owned by upstream Cedar. -/
def analyze (revision : Revision) (schema : Schema) : IO (Except Error Report) := do
  if let .error error := schema.validateWellFormed then
    return .error (.schema (toString error))
  let environments := schema.environments
  if environments.isEmpty then
    return .error .noEnvironments
  let before := revision.beforePolicies
  let after := revision.afterPolicies
  if let .error error := Cedar.Validation.validate before schema then
    return .error (.beforeInvalid error)
  if let .error error := Cedar.Validation.validate after schema then
    return .error (.afterInvalid error)
  let mut expansions : List Expansion := []
  for typeEnv in environments do
    let typedBefore ← match Cedar.SymCC.wellTypedPolicies before typeEnv with
      | .ok policies => pure policies
      | .error error => return .error (.beforeTypecheck error)
    let typedAfter ← match Cedar.SymCC.wellTypedPolicies after typeEnv with
      | .ok policies => pure policies
      | .error error => return .error (.afterTypecheck error)
    let answer : Except Error (Option Cedar.Spec.Env) ← try
      let solver ← Cedar.SymCC.Solver.cvc5
      let result ← Cedar.SymCC.SolverM.run solver
        (Cedar.SymCC.implies? typedAfter typedBefore
          (Cedar.SymCC.SymEnv.ofTypeEnv typeEnv))
      pure (.ok result)
    catch error =>
      pure (.error (.solver error.toString))
    match answer with
    | .error error => return .error error
    | .ok none => pure ()
    | .ok (some witness) =>
      if let .error _ := Cedar.Validation.validateRequest schema witness.request then
        return .error .invalidWitness
      if let .error _ := Cedar.Validation.validateEntities schema witness.entities then
        return .error .invalidWitness
      let beforeResponse := Cedar.Spec.isAuthorized witness.request witness.entities before
      let afterResponse := Cedar.Spec.isAuthorized witness.request witness.entities after
      if beforeResponse.decision != .deny || afterResponse.decision != .allow then
        return .error .invalidWitness
      expansions := expansions ++ [⟨typeEnv, witness, beforeResponse, afterResponse⟩]
  return .ok {
    changedPolicyIds := revision.changedPolicyIds
    environmentsChecked := environments.length
    expansions
  }

/-- Compile both POO roots before asking Cedar for their authorization delta. -/
def analyzeModel (model : Model) (beforeRoot afterRoot : String) (schema : Schema) :
    IO (Except Error Report) := do
  match model.compileRevision beforeRoot afterRoot with
  | .error error => return .error (.compilation error)
  | .ok revision => analyze revision schema

end CedarPooSpec.AuthorizationDelta
