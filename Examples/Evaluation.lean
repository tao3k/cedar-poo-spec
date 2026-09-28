import CedarPooSpec

open Cedar.Spec
open CedarPooSpec.Evaluation

/-- An upstream Cedar expression can be embedded without translating its AST. -/
def exampleExpr : Expr := .lit (.bool true)

def exampleSnapshot : Snapshot :=
  Snapshot.evaluate exampleExpr default Cedar.Data.Map.empty "baseline"

#eval exampleSnapshot.result
#eval LeanPoo.Proof.changedDependencies evaluationObligation (renamePatch "renamed")
#eval LeanPoo.Proof.changedDependencies evaluationObligation
  (replaceExprPatch exampleSnapshot (.lit (.bool false)))

example : LeanPoo.Proof.Certificate exampleSnapshot.proofObject := by
  exact Snapshot.evaluate_certificate exampleExpr default Cedar.Data.Map.empty "baseline"

example : LeanPoo.Proof.Certificate
    (LeanPoo.Proof.append exampleSnapshot.proofObject (renamePatch "renamed")) := by
  apply rename_closes
  rfl

example : LeanPoo.Proof.Certificate
    (LeanPoo.Proof.append exampleSnapshot.proofObject
      (replaceExprPatch exampleSnapshot (.lit (.bool false)))) := by
  apply replaceExpr_closes
  rfl
