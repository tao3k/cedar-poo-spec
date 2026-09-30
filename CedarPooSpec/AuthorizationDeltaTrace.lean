import CedarPooSpec.AuthorizationDeltaEvidence

/-!
Compare a fixed finite sequence of proposed actions under two C4 policy
roots. Each side evolves its own Host-supplied state after an error-free Cedar
Allow. This is a trace replay over the supplied proposals and transition
function, not a proof about every future agent action or Host execution.
-/

namespace CedarPooSpec.AuthorizationDelta

open Cedar.Spec Cedar.Validation CedarPooSpec.PolicyModules

/-- The same proposal evaluated against the two states reached so far. -/
structure TraceStep where
  beforeEnv : Cedar.Spec.Env
  afterEnv : Cedar.Spec.Env
  beforeResponse : Response
  afterResponse : Response

def TraceStep.beforeAllowed (step : TraceStep) : Bool :=
  step.beforeResponse.decision == .allow

def TraceStep.afterAllowed (step : TraceStep) : Bool :=
  step.afterResponse.decision == .allow

/-- Exact Cedar input equality, including the request context and entities. -/
def TraceStep.sameInput (step : TraceStep) : Bool :=
  decide (step.beforeEnv = step.afterEnv)

def TraceStep.gained (step : TraceStep) : Bool :=
  !step.beforeAllowed && step.afterAllowed

def TraceStep.lost (step : TraceStep) : Bool :=
  step.beforeAllowed && !step.afterAllowed

/-- A decision difference at identical Cedar inputs isolates the policy revision. -/
def TraceStep.directDifference (step : TraceStep) : Bool :=
  step.sameInput && (step.gained || step.lost)

/-- At different inputs the trace alone cannot apportion the difference between
    the policy revision and the Host history that produced those inputs. -/
def TraceStep.divergentInputDifference (step : TraceStep) : Bool :=
  !step.sameInput && (step.gained || step.lost)

/-- Finite behavior plus the C4 policy revision that produced it. -/
structure TraceImpact (State : Type) where
  beforeRoot : String
  afterRoot : String
  steps : List TraceStep
  beforeFinal : State
  afterFinal : State
  changes : List PolicyChange
  proof : ProofFootprint
  potentiallyInvalidatedRoots : List String

def TraceImpact.gained (impact : TraceImpact State) : Bool :=
  impact.steps.any TraceStep.gained

def TraceImpact.lost (impact : TraceImpact State) : Bool :=
  impact.steps.any TraceStep.lost

/-- Replay one fixed proposal list under two POO roots. =observe= and =advance=
    are supplied by the Host model. Both sides use the same functions, but
    their states may diverge after an authorization difference. Every observed
    request and entity store is schema validated; an erroring Cedar response
    fails the comparison instead of being treated as an executable Allow. -/
def compareTrace (schema : Schema) (model : Model)
    (beforeRoot afterRoot : String) (initial : State) (proposals : List Action)
    (observe : State → Action → Cedar.Spec.Env)
    (advance : State → Action → State) : Except Error (TraceImpact State) := do
  if proposals.isEmpty then throw .operationChanged
  if let .error error := schema.validateWellFormed then
    throw (.schema (toString error))
  let revision ← model.compileRevision beforeRoot afterRoot |>.mapError Error.compilation
  if let .error error := Cedar.Validation.validate revision.beforePolicies schema then
    throw (.beforeInvalid error)
  if let .error error := Cedar.Validation.validate revision.afterPolicies schema then
    throw (.afterInvalid error)
  let mut beforeState := initial
  let mut afterState := initial
  let mut reversedSteps := []
  for proposal in proposals do
    let before := observe beforeState proposal
    let after := observe afterState proposal
    if before.request.principal != after.request.principal ||
        before.request.action != after.request.action ||
        before.request.resource != after.request.resource then
      throw .operationChanged
    if !(Cedar.Validation.validateRequest schema before.request).isOk then
      throw .beforeRequestInvalid
    if !(Cedar.Validation.validateRequest schema after.request).isOk then
      throw .afterRequestInvalid
    if !(Cedar.Validation.validateEntities schema before.entities).isOk then
      throw .beforeEntitiesInvalid
    if !(Cedar.Validation.validateEntities schema after.entities).isOk then
      throw .afterEntitiesInvalid
    let beforeResponse :=
      Cedar.Spec.isAuthorized before.request before.entities revision.beforePolicies
    let afterResponse :=
      Cedar.Spec.isAuthorized after.request after.entities revision.afterPolicies
    if !beforeResponse.erroringPolicies.isEmpty ||
        !afterResponse.erroringPolicies.isEmpty then
      throw .policyEvaluationError
    reversedSteps := ⟨before, after,
                       beforeResponse, afterResponse⟩ :: reversedSteps
    if beforeResponse.decision == .allow then
      beforeState := advance beforeState proposal
    if afterResponse.decision == .allow then
      afterState := advance afterState proposal
  let changes := CedarPooSpec.AuthorizationDelta.Revision.policyChanges revision
  return ⟨beforeRoot, afterRoot, reversedSteps.reverse,
    beforeState, afterState, changes,
    CedarPooSpec.AuthorizationDelta.Revision.proofFootprint revision,
    affectedRoots model changes⟩

/-- All lists of one exact length over the supplied alphabet. Alphabet entries
    are treated as distinct choices by position; callers should avoid duplicates. -/
def proposalSequencesOfLength (alphabet : List Action) : Nat → List (List Action)
  | 0 => [[]]
  | length + 1 =>
      (proposalSequencesOfLength alphabet length).flatMap fun proposalPrefix =>
        alphabet.map fun action => proposalPrefix ++ [action]

theorem proposalSequencesOfLength_count (alphabet : List Action) (length : Nat) :
    (proposalSequencesOfLength alphabet length).length = alphabet.length ^ length := by
  induction length with
  | zero => simp [proposalSequencesOfLength]
  | succ length ih =>
      simp [proposalSequencesOfLength, List.map_const', List.sum_replicate_nat,
        ih, Nat.pow_succ]

/-- Every nonempty proposal list through the specified finite horizon. -/
def proposalSequencesUpTo (alphabet : List Action) (horizon : Nat) :
    List (List Action) :=
  (List.range horizon).flatMap fun length =>
    proposalSequencesOfLength alphabet (length + 1)

/-- Replay every proposal list in a bounded alphabet/horizon. The explicit case
    cap rejects unexpectedly large scopes before constructing the lists. This
    is exhaustive only for the listed choices and the supplied Host model. -/
def compareBoundedTraces (schema : Schema) (model : Model)
    (beforeRoot afterRoot : String) (initial : State)
    (alphabet : List Action) (horizon maxSequences : Nat)
    (observe : State → Action → Cedar.Spec.Env)
    (advance : State → Action → State) :
    Except Error (List (List Action × TraceImpact State)) := do
  if alphabet.isEmpty || horizon == 0 || maxSequences == 0 ||
      horizon > maxSequences then
    throw .invalidBoundedScope
  let (_, count) := (List.range horizon).foldl (fun (power, total) _ =>
    let next := power * alphabet.length
    (next, total + next)) (1, 0)
  if count > maxSequences then throw .invalidBoundedScope
  (proposalSequencesUpTo alphabet horizon).mapM fun proposals => do
    let impact ← compareTrace schema model beforeRoot afterRoot initial
      proposals observe advance
    return (proposals, impact)

end CedarPooSpec.AuthorizationDelta
