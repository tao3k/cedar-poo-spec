import CedarPooSpec

open Cedar.Spec
open CedarPooSpec

/-- A single upstream policy can drive both independent adapters. -/
def examplePolicy : Policy := default

def exampleEvaluation : Evaluation.Snapshot :=
  Evaluation.Snapshot.evaluate examplePolicy.toExpr default Cedar.Data.Map.empty

def exampleValidation : Validation.Snapshot :=
  Validation.Snapshot.typecheck examplePolicy default

example : LeanPoo.Proof.Certificate
    (Composition.alignedProofObject exampleEvaluation exampleValidation) := by
  apply Composition.alignedCertificate
  · rfl
  · rfl
  · rfl

example (typed : Cedar.Validation.TypedExpr)
    (accepted : exampleValidation.result = .ok typed)
    (request : Request) (entities : Entities)
    (wellFormed : Cedar.Thm.InstanceOfWellFormedEnvironment
      request entities exampleValidation.environment) :
    ∃ result : Bool,
      Cedar.Thm.EvaluatesTo exampleValidation.policy.toExpr
        request entities result := by
  exact Soundness.certifiedPolicySound exampleValidation
    (Validation.Snapshot.typecheck_certificate examplePolicy default)
    typed accepted request entities wellFormed

-- The expression override invalidates evaluation and alignment, not typechecking.
#eval LeanPoo.Proof.Debug.explainPatch
  (Composition.alignedProofObject exampleEvaluation exampleValidation)
  (Composition.replaceExprPatch exampleEvaluation (.lit (.bool true)))

-- The policy override invalidates typechecking and alignment, not evaluation.
#eval LeanPoo.Proof.Debug.explainPatch
  (Composition.alignedProofObject exampleEvaluation exampleValidation)
  (Composition.replacePolicyPatch exampleValidation examplePolicy)
