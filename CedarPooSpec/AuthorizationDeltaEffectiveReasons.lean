import CedarPooSpec.AuthorizationDeltaReasons

/-!
Experimental whole-response reason analysis. Cedar supplies the symbolic
compiler, authorizer, model extraction, and concrete replay. The membership
formula follows Cedar's determining-policy theorem, but this adapter does not
yet have a Lean proof connecting that formula to the symbolic compiler.
-/

namespace CedarPooSpec.AuthorizationDelta

open Cedar.Spec Cedar.Validation CedarPooSpec.PolicyModules

private def typedPolicies (policies : Policies) (typeEnv : TypeEnv)
    (before : Bool) : Except ReasonError Policies :=
  (Cedar.SymCC.wellTypedPolicies policies typeEnv).mapError fun error =>
    .operational (.delta (if before then .beforeTypecheck error else .afterTypecheck error))

/-- Symbolic membership of one policy ID in the final Cedar reason set.
    Permit IDs count only for Allow; forbid IDs count only for Deny. -/
private def reasonMember (policies : Policies) (id : PolicyID)
    (symEnv : Cedar.SymCC.SymEnv) : Cedar.SymCC.Result Cedar.SymCC.Term := do
  let some policy := policies.find? (·.id == id)
    | return false
  let authorized ← Cedar.SymCC.isAuthorized policies symEnv
  let evaluated ← Cedar.SymCC.compile policy.toExpr symEnv
  let matched := Cedar.SymCC.Factory.eq evaluated
    (Cedar.SymCC.Factory.someOf true)
  let effective := if policy.effect == .permit then authorized
    else Cedar.SymCC.Factory.not authorized
  return Cedar.SymCC.Factory.and matched effective

private def effectiveReasonDifference? (before after : Policies)
    (id : PolicyID) (symEnv : Cedar.SymCC.SymEnv) :
    IO (Except ReasonError (Option Cedar.Spec.Env)) := do
  let all := before ++ after
  let query := fun env => do
    let left ← reasonMember before id env
    let right ← reasonMember after id env
    let expressions := all.map Policy.toExpr
    return (Cedar.SymCC.enforce expressions env).elts ++
      [Cedar.SymCC.Factory.not (Cedar.SymCC.Factory.eq left right)]
  try
    let solver ← Cedar.SymCC.Solver.cvc5
    return .ok (← Cedar.SymCC.SolverM.run solver
      (Cedar.SymCC.sat? all query symEnv))
  catch error =>
    return .error (.solver error.toString)

structure EffectiveReasonReport where
  decision : OperationalImpactReport
  changes : List PolicyChange
  provenanceChanges : List PolicyChange
  proof : ProofFootprint
  reasonWitnesses : List ReasonWitness
  policyQueries : Nat

/-- An empty solver witness set; not a Lean proof of this new query. -/
def EffectiveReasonReport.solverReasonStable (report : EffectiveReasonReport) : Bool :=
  report.reasonWitnesses.isEmpty

def EffectiveReasonReport.provenanceStable (report : EffectiveReasonReport) : Bool :=
  report.provenanceChanges.isEmpty

/-- Query final reason membership for every ID in the union of policy sets.
    A counterexample is admitted only after original Cedar replay confirms
    that the queried ID changes membership. Solver failures are errors. -/
def analyzeEffectiveReasons (revision : Revision) (schema : Schema) :
    IO (Except ReasonError EffectiveReasonReport) := do
  let decision ← match ← analyzeOperationalImpact revision schema with
    | .ok result => pure result
    | .error error => return .error (.operational error)
  let before := revision.beforePolicies
  let after := revision.afterPolicies
  let ids := ((before.map Policy.id) ++ (after.map Policy.id)).eraseDups
  let mut witnesses := []
  let mut policyQueries := 0
  if before != after then
    for typeEnv in schema.environments do
      let typedBefore ← match typedPolicies before typeEnv true with
        | .ok policies => pure policies
        | .error error => return .error error
      let typedAfter ← match typedPolicies after typeEnv false with
        | .ok policies => pure policies
        | .error error => return .error error
      let symEnv := Cedar.SymCC.SymEnv.ofTypeEnv typeEnv
      for id in ids do
        policyQueries := policyQueries + 1
        let possible ← match ← effectiveReasonDifference? typedBefore typedAfter id symEnv with
          | .ok possible => pure possible
          | .error error => return .error error
        if let some witness := possible then
          if !(Cedar.Validation.validateRequest schema witness.request).isOk ||
              !(Cedar.Validation.validateEntities schema witness.entities).isOk then
            return .error (.invalidWitness id)
          let beforeResponse := Cedar.Spec.isAuthorized witness.request witness.entities before
          let afterResponse := Cedar.Spec.isAuthorized witness.request witness.entities after
          let left := beforeResponse.determiningPolicies.contains id
          let right := afterResponse.determiningPolicies.contains id
          if left == right then return .error (.invalidWitness id)
          witnesses := witnesses ++
            [⟨id, typeEnv, witness, beforeResponse, afterResponse⟩]
  return .ok {
    decision
    changes := Revision.policyChanges revision
    provenanceChanges := Revision.provenanceChanges revision
    proof := Revision.proofFootprint revision
    reasonWitnesses := witnesses
    policyQueries }

structure ExplainedEffectiveReasonReport where
  beforeRoot : String
  afterRoot : String
  report : EffectiveReasonReport
  potentiallyInvalidatedRoots : List String

def analyzeModelEffectiveReasons (model : Model) (beforeRoot afterRoot : String)
    (schema : Schema) : IO (Except ReasonError ExplainedEffectiveReasonReport) := do
  let revision ← match model.compileRevision beforeRoot afterRoot with
    | .ok revision => pure revision
    | .error error => return .error (.operational (.delta (.compilation error)))
  let report ← analyzeEffectiveReasons revision schema
  return report.map fun report =>
    { beforeRoot, afterRoot, report
      potentiallyInvalidatedRoots :=
        affectedRoots model (report.changes ++ report.provenanceChanges) }

end CedarPooSpec.AuthorizationDelta
