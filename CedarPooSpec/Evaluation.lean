import Cedar.Spec.Evaluator
import LeanPoo.Proof.Invalidation

/-!
A Cedar evaluation snapshot interpreted as a Lean-POO proof object.

The Cedar evaluator is used directly. This adapter owns only the dependency
footprint and the certificate that binds a stored result to that evaluator.
-/

namespace CedarPooSpec.Evaluation

open Cedar.Spec
open LeanPoo.Proof

inductive Key where
  | expr
  | request
  | entities
  | result
  | label
deriving DecidableEq, Repr

def Value : Key → Type
  | .expr => Expr
  | .request => Request
  | .entities => Entities
  | .result => Result Cedar.Spec.Value
  | .label => String

structure Snapshot where
  expr : Expr
  request : Request
  entities : Entities
  result : Result Cedar.Spec.Value
  label : String

def Snapshot.evaluate (expr : Expr) (request : Request)
    (entities : Entities) (label : String := "") : Snapshot where
  expr := expr
  request := request
  entities := entities
  result := Cedar.Spec.evaluate expr request entities
  label := label

def Snapshot.state (snapshot : Snapshot) : State Key Value
  | .expr => snapshot.expr
  | .request => snapshot.request
  | .entities => snapshot.entities
  | .result => snapshot.result
  | .label => snapshot.label

def evaluationObligation : Obligation Key Value where
  dependencies := [.expr, .request, .entities, .result]
  holds := fun state =>
    state .result = Cedar.Spec.evaluate (state .expr) (state .request) (state .entities)
  stable := by
    intro before after equal holds
    have he : before .expr = after .expr := equal .expr (by simp)
    have hr : before .request = after .request := equal .request (by simp)
    have hs : before .entities = after .entities := equal .entities (by simp)
    have hv : before .result = after .result := equal .result (by simp)
    simpa [he, hr, hs, hv] using holds

def Snapshot.proofObject (snapshot : Snapshot) : ProofObject Key Value where
  state := snapshot.state
  obligations := [evaluationObligation]

theorem Snapshot.certificate (snapshot : Snapshot)
    (valid : snapshot.result =
      Cedar.Spec.evaluate snapshot.expr snapshot.request snapshot.entities) :
    Certificate snapshot.proofObject := by
  intro obligation membership
  have same : obligation = evaluationObligation := by
    simpa [Snapshot.proofObject] using membership
  subst obligation
  exact valid

theorem Snapshot.evaluate_certificate (expr : Expr) (request : Request)
    (entities : Entities) (label : String := "") :
    Certificate (Snapshot.evaluate expr request entities label).proofObject :=
  Snapshot.certificate _ rfl

/-- Labels are descriptive metadata; changing them preserves evaluation. -/
def renamePatch (label : String) : Patch Key Value :=
  Patch.set .label label

theorem rename_reuses (snapshot : Snapshot)
    (valid : snapshot.result =
      Cedar.Spec.evaluate snapshot.expr snapshot.request snapshot.entities)
    (label : String) :
    evaluationObligation.holds
      (append snapshot.proofObject (renamePatch label)).state := by
  apply reuse snapshot.proofObject (renamePatch label)
    (snapshot.certificate valid) evaluationObligation
  · simp [Snapshot.proofObject]
  · intro key dependency
    cases key <;> simp [evaluationObligation, renamePatch, Patch.set] at dependency ⊢

theorem rename_changed_dependencies (label : String) :
    changedDependencies evaluationObligation (renamePatch label) = [] := by
  simp [changedDependencies, evaluationObligation, renamePatch, Patch.set]

theorem rename_closes (snapshot : Snapshot)
    (valid : snapshot.result =
      Cedar.Spec.evaluate snapshot.expr snapshot.request snapshot.entities)
    (label : String) :
    Certificate (append snapshot.proofObject (renamePatch label)) := by
  apply closePending snapshot.proofObject (renamePatch label)
    (snapshot.certificate valid)
  intro obligation membership
  simp [pending, Snapshot.proofObject, renamePatch, Patch.set] at membership
  rcases membership with ⟨rfl, changed⟩
  exact False.elim (changed (rename_changed_dependencies label))

/-- Re-evaluation after an expression override produces a new certificate. -/
def Snapshot.replaceExpr (snapshot : Snapshot) (expr : Expr) : Snapshot :=
  Snapshot.evaluate expr snapshot.request snapshot.entities snapshot.label

theorem Snapshot.replaceExpr_certificate (snapshot : Snapshot) (expr : Expr) :
    Certificate (snapshot.replaceExpr expr).proofObject :=
  Snapshot.evaluate_certificate expr snapshot.request snapshot.entities snapshot.label

/-- Changing an expression also writes its freshly evaluated result. -/
def replaceExprPatch (snapshot : Snapshot) (expr : Expr) : Patch Key Value :=
  (Patch.set .expr expr).then
    (Patch.set .result
      (Cedar.Spec.evaluate expr snapshot.request snapshot.entities))

theorem replaceExpr_changed_dependencies (snapshot : Snapshot) (expr : Expr) :
    changedDependencies evaluationObligation (replaceExprPatch snapshot expr) =
      [.expr, .result] := by
  simp [changedDependencies, evaluationObligation, replaceExprPatch,
    Patch.then, Patch.set]

theorem replaceExpr_patch_state (snapshot : Snapshot) (expr : Expr) :
    (append snapshot.proofObject (replaceExprPatch snapshot expr)).state =
      (snapshot.replaceExpr expr).state := by
  funext key
  cases key <;> simp [append, Snapshot.proofObject, Snapshot.state,
    Snapshot.replaceExpr, Snapshot.evaluate, replaceExprPatch, Patch.then, Patch.set] <;> rfl

/-- The pending Cedar obligation is discharged by the upstream evaluator. -/
theorem replaceExpr_closes (snapshot : Snapshot)
    (valid : snapshot.result =
      Cedar.Spec.evaluate snapshot.expr snapshot.request snapshot.entities)
    (expr : Expr) :
    Certificate (append snapshot.proofObject (replaceExprPatch snapshot expr)) := by
  apply closePending snapshot.proofObject (replaceExprPatch snapshot expr)
    (snapshot.certificate valid)
  intro obligation membership
  have owned : obligation ∈ snapshot.proofObject.obligations := by
    simp only [pending, List.mem_append] at membership
    rcases membership with old | fresh
    · exact (List.mem_filter.mp old).1
    · simp [replaceExprPatch, Patch.then, Patch.set] at fresh
  have same : obligation = evaluationObligation := by
    simpa [Snapshot.proofObject] using owned
  subst obligation
  rw [replaceExpr_patch_state]
  exact (snapshot.replaceExpr_certificate expr) evaluationObligation
    (by simp [Snapshot.proofObject])

end CedarPooSpec.Evaluation
