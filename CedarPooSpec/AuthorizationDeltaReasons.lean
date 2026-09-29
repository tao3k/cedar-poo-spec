import CedarPooSpec.AuthorizationDeltaOperational
import CedarPooSpec.AuthorizationDeltaEvidence

/-!
Conservative determining-policy delta over one validated schema. Cedar owns
policy matching and authorization; POO supplies revision and edit provenance.
A matching difference is only a candidate until original Cedar responses
confirm a changed determining-policy set.
-/

namespace CedarPooSpec.AuthorizationDelta

open Cedar.Spec Cedar.Validation CedarPooSpec.PolicyModules

inductive ReasonError where
  | operational (error : OperationalError)
  | solver (message : String)
  | invalidWitness (policyId : PolicyID)
  deriving Repr

structure ReasonWitness where
  /-- The queried policy ID; several edits may contribute to this witness. -/
  policyId : PolicyID
  typeEnv : TypeEnv
  witness : Cedar.Spec.Env
  beforeResponse : Response
  afterResponse : Response
  deriving Repr

structure ReasonImpactReport where
  decision : OperationalImpactReport
  changes : List PolicyChange
  provenanceChanges : List PolicyChange
  proof : ProofFootprint
  reasonWitnesses : List ReasonWitness
  unresolvedPolicyIds : List PolicyID
  matchingQueries : Nat

def ReasonImpactReport.reasonStable (report : ReasonImpactReport) : Bool :=
  report.reasonWitnesses.isEmpty && report.unresolvedPolicyIds.isEmpty

/-- Cedar reasons and POO responsibility are separate review surfaces. -/
def ReasonImpactReport.provenanceStable (report : ReasonImpactReport) : Bool :=
  report.provenanceChanges.isEmpty

private def typed (policy : Policy) (typeEnv : TypeEnv) (before : Bool) :
    Except ReasonError Policy :=
  (Cedar.SymCC.wellTypedPolicy policy typeEnv).mapError fun error =>
    .operational (.delta (if before then .beforeTypecheck error else .afterTypecheck error))

private def matchingDifference? (before after : Option Policy) (typeEnv : TypeEnv) :
    IO (Except ReasonError (Option Cedar.Spec.Env)) := do
  let query : Except ReasonError (Cedar.SymCC.SolverM (Option Cedar.Spec.Env)) := do
    let symEnv := Cedar.SymCC.SymEnv.ofTypeEnv typeEnv
    match before, after with
    | some left, some right =>
        let left ← typed left typeEnv true
        let right ← typed right typeEnv false
        return Cedar.SymCC.matchesEquivalent? left right symEnv
    | some left, none =>
        return Cedar.SymCC.neverMatches? (← typed left typeEnv true) symEnv
    | none, some right =>
        return Cedar.SymCC.neverMatches? (← typed right typeEnv false) symEnv
    | none, none => return pure none
  let query ← match query with
    | .ok query => pure query
    | .error error => return .error error
  try
    let solver ← Cedar.SymCC.Solver.cvc5
    return .ok (← Cedar.SymCC.SolverM.run solver query)
  catch error =>
    return .error (.solver error.toString)

/-- A reason-stable result requires error-free policy evaluation, unchanged
    effects for shared IDs, and no matching difference for every changed ID.
    A found match difference without a changed Cedar reason is unresolved. -/
def analyzeReasons (revision : Revision) (schema : Schema) :
    IO (Except ReasonError ReasonImpactReport) := do
  let decision ← match ← analyzeOperationalImpact revision schema with
    | .ok decision => pure decision
    | .error error => return .error (.operational error)
  let before := revision.beforePolicies
  let after := revision.afterPolicies
  let mut reasonWitnesses := []
  let mut unresolvedPolicyIds := []
  let mut matchingQueries := 0
  for id in revision.changedPolicyIds do
    let left := before.find? (·.id == id)
    let right := after.find? (·.id == id)
    if left.isNone && right.isNone then
      unresolvedPolicyIds := unresolvedPolicyIds ++ [id]
      continue
    if let (some oldPolicy, some newPolicy) := (left, right) then
      if oldPolicy.effect != newPolicy.effect then
        unresolvedPolicyIds := unresolvedPolicyIds ++ [id]
        continue
    let mut found := false
    let mut masked := false
    for typeEnv in schema.environments do
      matchingQueries := matchingQueries + 1
      let possible ← match ← matchingDifference? left right typeEnv with
        | .ok possible => pure possible
        | .error error => return .error error
      if let some witness := possible then
        if !(Cedar.Validation.validateRequest schema witness.request).isOk ||
            !(Cedar.Validation.validateEntities schema witness.entities).isOk then
          return .error (.invalidWitness id)
        let beforeResponse := Cedar.Spec.isAuthorized witness.request witness.entities before
        let afterResponse := Cedar.Spec.isAuthorized witness.request witness.entities after
        if beforeResponse.determiningPolicies != afterResponse.determiningPolicies then
          reasonWitnesses := reasonWitnesses ++
            [⟨id, typeEnv, witness, beforeResponse, afterResponse⟩]
          found := true
        else
          masked := true
    if masked && !found then
      unresolvedPolicyIds := unresolvedPolicyIds ++ [id]
  return .ok {
    decision
    changes := Revision.policyChanges revision
    provenanceChanges := Revision.provenanceChanges revision
    proof := Revision.proofFootprint revision
    reasonWitnesses
    unresolvedPolicyIds
    matchingQueries }

structure ExplainedReasonImpactReport where
  beforeRoot : String
  afterRoot : String
  report : ReasonImpactReport
  potentiallyInvalidatedRoots : List String

def analyzeModelReasons (model : Model) (beforeRoot afterRoot : String)
    (schema : Schema) : IO (Except ReasonError ExplainedReasonImpactReport) := do
  let revision ← match model.compileRevision beforeRoot afterRoot with
    | .ok revision => pure revision
    | .error error => return .error (.operational (.delta (.compilation error)))
  let report ← analyzeReasons revision schema
  return report.map fun report =>
    { beforeRoot, afterRoot, report
      potentiallyInvalidatedRoots :=
        affectedRoots model (report.changes ++ report.provenanceChanges) }

end CedarPooSpec.AuthorizationDelta
