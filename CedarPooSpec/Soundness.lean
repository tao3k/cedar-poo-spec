import CedarPooSpec.Validation
import Cedar.Thm.Validation.Validator

/-! Transport Cedar's existing typechecker soundness through a proof object. -/

namespace CedarPooSpec.Soundness

open Cedar.Spec
open Cedar.Validation
open LeanPoo.Proof

/-- The proof object certifies that its stored result came from Cedar's
    typechecker; Cedar's own theorem supplies the semantic guarantee. -/
theorem certifiedPolicySound (snapshot : Validation.Snapshot)
    (certificate : Certificate snapshot.proofObject)
    (typed : TypedExpr)
    (accepted : snapshot.result = .ok typed)
    (request : Request) (entities : Entities)
    (wellFormed : Cedar.Thm.InstanceOfWellFormedEnvironment
      request entities snapshot.environment) :
    ∃ result : Bool,
      Cedar.Thm.EvaluatesTo snapshot.policy.toExpr request entities result := by
  have checkerResult :
      typecheckPolicy snapshot.policy snapshot.environment = .ok typed := by
    have certified := certificate Validation.typecheckObligation
      (by simp [Validation.Snapshot.proofObject])
    change snapshot.result =
      typecheckPolicy snapshot.policy snapshot.environment at certified
    rw [certified] at accepted
    exact accepted
  exact Cedar.Thm.typecheck_policy_is_sound wellFormed checkerResult

end CedarPooSpec.Soundness
