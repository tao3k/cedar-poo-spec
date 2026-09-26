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

-- The expression override invalidates evaluation and alignment, not typechecking.
#eval LeanPoo.Proof.Debug.explainPatch
  (Composition.alignedProofObject exampleEvaluation exampleValidation)
  (Composition.replaceExprPatch exampleEvaluation (.lit (.bool true)))

-- The policy override invalidates typechecking and alignment, not evaluation.
#eval LeanPoo.Proof.Debug.explainPatch
  (Composition.alignedProofObject exampleEvaluation exampleValidation)
  (Composition.replacePolicyPatch exampleValidation examplePolicy)
