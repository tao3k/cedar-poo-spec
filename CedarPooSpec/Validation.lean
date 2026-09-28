import Cedar.Validation.Validator
import LeanPoo.Proof.Product

/-! A Cedar policy typechecking result carried by a Lean-POO proof object. -/

namespace CedarPooSpec.Validation

open Cedar.Spec
open Cedar.Validation
open LeanPoo.Proof

inductive Key where
  | policy
  | environment
  | result
  | label
deriving DecidableEq, Repr

def Value : Key → Type
  | .policy => Policy
  | .environment => TypeEnv
  | .result => Except ValidationError TypedExpr
  | .label => String

structure Snapshot where
  policy : Policy
  environment : TypeEnv
  result : Except ValidationError TypedExpr
  label : String

def Snapshot.typecheck (policy : Policy) (environment : TypeEnv)
    (label : String := "") : Snapshot where
  policy := policy
  environment := environment
  result := typecheckPolicy policy environment
  label := label

def Snapshot.state (snapshot : Snapshot) : State Key Value
  | .policy => snapshot.policy
  | .environment => snapshot.environment
  | .result => snapshot.result
  | .label => snapshot.label

def typecheckObligation : Obligation Key Value where
  dependencies := [.policy, .environment, .result]
  holds := fun state =>
    state .result = typecheckPolicy (state .policy) (state .environment)
  stable := by
    intro before after equal holds
    have hp : before .policy = after .policy := equal .policy (by simp)
    have he : before .environment = after .environment := equal .environment (by simp)
    have hr : before .result = after .result := equal .result (by simp)
    simpa [hp, he, hr] using holds

def Snapshot.proofObject (snapshot : Snapshot) : ProofObject Key Value where
  state := snapshot.state
  obligations := [typecheckObligation]

theorem Snapshot.certificate (snapshot : Snapshot)
    (valid : snapshot.result =
      typecheckPolicy snapshot.policy snapshot.environment) :
    Certificate snapshot.proofObject := by
  intro obligation membership
  have same : obligation = typecheckObligation := by
    simpa [Snapshot.proofObject] using membership
  subst obligation
  exact valid

theorem Snapshot.typecheck_certificate (policy : Policy)
    (environment : TypeEnv) (label : String := "") :
    Certificate (Snapshot.typecheck policy environment label).proofObject :=
  Snapshot.certificate _ rfl

def renamePatch (label : String) : Patch Key Value :=
  Patch.set .label label

theorem rename_changed_dependencies (label : String) :
    changedDependencies typecheckObligation (renamePatch label) = [] := by
  simp [changedDependencies, typecheckObligation, renamePatch, Patch.set]

def Snapshot.replacePolicy (snapshot : Snapshot) (policy : Policy) : Snapshot :=
  Snapshot.typecheck policy snapshot.environment snapshot.label

def replacePolicyPatch (snapshot : Snapshot) (policy : Policy) : Patch Key Value :=
  (Patch.set .policy policy).then
    (Patch.set .result (typecheckPolicy policy snapshot.environment))

theorem replacePolicy_changed_dependencies (snapshot : Snapshot)
    (policy : Policy) :
    changedDependencies typecheckObligation (replacePolicyPatch snapshot policy) =
      [.policy, .result] := by
  simp [changedDependencies, typecheckObligation, replacePolicyPatch,
    Patch.then, Patch.set]

theorem replacePolicy_patch_state (snapshot : Snapshot) (policy : Policy) :
    (append snapshot.proofObject (replacePolicyPatch snapshot policy)).state =
      (snapshot.replacePolicy policy).state := by
  funext key
  cases key <;> simp [append, Snapshot.proofObject, Snapshot.state,
    Snapshot.replacePolicy, Snapshot.typecheck, replacePolicyPatch, Patch.then,
    Patch.set] <;> rfl

theorem replacePolicy_closes (snapshot : Snapshot)
    (valid : snapshot.result =
      typecheckPolicy snapshot.policy snapshot.environment)
    (policy : Policy) :
    Certificate (append snapshot.proofObject
      (replacePolicyPatch snapshot policy)) := by
  apply closePending snapshot.proofObject (replacePolicyPatch snapshot policy)
    (snapshot.certificate valid)
  intro obligation membership
  have owned : obligation ∈ snapshot.proofObject.obligations := by
    simp only [pending, List.mem_append] at membership
    rcases membership with old | fresh
    · exact (List.mem_filter.mp old).1
    · simp [replacePolicyPatch, Patch.then, Patch.set] at fresh
  have same : obligation = typecheckObligation := by
    simpa [Snapshot.proofObject] using owned
  subst obligation
  rw [replacePolicy_patch_state]
  exact (Snapshot.typecheck_certificate policy snapshot.environment snapshot.label)
    typecheckObligation (by simp [Snapshot.proofObject])

end CedarPooSpec.Validation
