import Cedar.Validation.Validator
import Cedar.Thm.Data.List.Lemmas
import LeanPoo.Proof.Invalidation
import Std.Data.HashSet.Lemmas

/-! Reuse Cedar's own per-policy validator across policy-set revisions. -/

namespace CedarPooSpec.PolicyValidation

open Cedar.Spec Cedar.Validation
open LeanPoo.Proof

def check (policy : Policy) (schema : Schema) : ValidationResult :=
  typecheckPolicyWithEnvironments typecheckPolicy policy schema

inductive Key where
  | policy
  | schema
  deriving DecidableEq

def Value : Key → Type
  | .policy => Policy
  | .schema => Schema

structure Snapshot where
  policy : Policy
  schema : Schema

def Snapshot.state (snapshot : Snapshot) : State Key Value
  | .policy => snapshot.policy
  | .schema => snapshot.schema

def policyObligation : Obligation Key Value where
  dependencies := [.policy, .schema]
  holds := fun state => check (state .policy) (state .schema) = .ok ()
  stable := by
    intro before after equal holds
    have hp := equal .policy (by simp)
    have hs := equal .schema (by simp)
    simpa [hp, hs] using holds

def Snapshot.proofObject (snapshot : Snapshot) : ProofObject Key Value where
  state := snapshot.state
  obligations := [policyObligation]

theorem Snapshot.certificate (snapshot : Snapshot)
    (valid : check snapshot.policy snapshot.schema = .ok ()) :
    Certificate snapshot.proofObject := by
  intro obligation membership
  have same : obligation = policyObligation := by
    simpa [Snapshot.proofObject] using membership
  subst obligation
  exact valid

theorem Snapshot.validOfCertificate (snapshot : Snapshot)
    (certificate : Certificate snapshot.proofObject) :
    check snapshot.policy snapshot.schema = .ok () :=
  certificate policyObligation (by simp [Snapshot.proofObject])

def replacePolicy (policy : Policy) : Patch Key Value := Patch.set .policy policy
def replaceSchema (schema : Schema) : Patch Key Value := Patch.set .schema schema

theorem policyChangeFootprint (policy : Policy) :
    changedDependencies policyObligation (replacePolicy policy) = [.policy] := by
  simp [changedDependencies, policyObligation, replacePolicy, Patch.set]

theorem schemaChangeFootprint (schema : Schema) :
    changedDependencies policyObligation (replaceSchema schema) = [.schema] := by
  simp [changedDependencies, policyObligation, replaceSchema, Patch.set]

/-- Cedar's policy-set validator succeeds exactly when each policy succeeds. -/
theorem validate_iff_each (policies : Policies) (schema : Schema) :
    validate policies schema = .ok () ↔
      ∀ policy ∈ policies, check policy schema = .ok () := by
  constructor
  · intro validated
    exact List.forM_ok_implies_all_ok policies (check · schema)
      (by simpa [validate, check] using validated)
  · intro each
    simpa [validate, check] using
      List.all_ok_implies_forM_ok policies (check · schema) each

/-- Only policy bodies absent from the old set need a new validation proof. -/
theorem validateFromReuse (before after : Policies) (schema : Schema)
    (baseline : validate before schema = .ok ())
    (fresh : ∀ policy ∈ after, policy ∉ before →
      check policy schema = .ok ()) :
    validate after schema = .ok () := by
  apply (validate_iff_each after schema).2
  intro policy member
  by_cases old : policy ∈ before
  · exact (validate_iff_each before schema).1 baseline policy old
  · exact fresh policy member old

/-- Concrete policy bodies requiring validation after a revision. -/
def freshPolicies (before after : Policies) : Policies :=
  after.filter fun policy => !decide (policy ∈ before)

/-- A cache can only contain a policy set certified by Cedar's validator. -/
structure ValidatedSet (schema : Schema) where
  policies : Policies
  validated : validate policies schema = .ok ()

private structure PolicyKey where
  policy : Policy
  deriving DecidableEq

private instance : BEq PolicyKey where
  beq left right := decide (left = right)

private instance : LawfulBEq PolicyKey := inferInstance

-- Hashing the ID narrows the lookup; Boolean equality still checks the entire body.
private instance : Hashable PolicyKey where
  hash key := hash key.policy.id

private def policyIndex (before : Policies) : Std.HashSet PolicyKey :=
  Std.HashSet.ofList (before.map PolicyKey.mk)

private theorem indexContains_iff_mem (before : Policies) (policy : Policy) :
    (policyIndex before).contains ⟨policy⟩ = true ↔ policy ∈ before := by
  simp [policyIndex, List.mem_map]

private def incrementalValidateCore (index : Std.HashSet PolicyKey) :
    (after : Policies) → Schema → ValidationResult
  | [], _ => .ok ()
  | policy :: rest, schema => do
      if !(index.contains ⟨policy⟩) then check policy schema
      incrementalValidateCore index rest schema

/-- Skip any whole policy body present in a certified baseline, including after reordering. -/
def incrementalValidate (baseline : ValidatedSet schema) (after : Policies) :
    ValidationResult :=
  incrementalValidateCore (policyIndex baseline.policies) after schema

/-- The incremental result, including its first error, is Cedar's result. -/
private theorem incrementalValidateCore_eq_validate (before after : Policies)
    (schema : Schema) (baseline : validate before schema = .ok ()) :
    incrementalValidateCore (policyIndex before) after schema = validate after schema := by
  induction after with
  | nil => rfl
  | cons policy rest inductionHypothesis =>
      by_cases old : policy ∈ before
      · have hit : (policyIndex before).contains ⟨policy⟩ = true :=
          (indexContains_iff_mem before policy).2 old
        have oldValid := (validate_iff_each before schema).1 baseline policy old
        have oldValidRaw :
            typecheckPolicyWithEnvironments typecheckPolicy policy schema = .ok () :=
          oldValid
        simpa [incrementalValidateCore, hit, validate, check,
          List.forM_eq_forM, oldValidRaw] using inductionHypothesis
      · have miss : (policyIndex before).contains ⟨policy⟩ = false := by
          cases h : (policyIndex before).contains ⟨policy⟩ with
          | false => rfl
          | true => exact False.elim (old ((indexContains_iff_mem before policy).1 h))
        have congruent := congrArg (fun result : ValidationResult =>
          check policy schema >>= fun _ => result) inductionHypothesis
        simpa [incrementalValidateCore, miss, validate,
          List.forM_eq_forM, check] using congruent

theorem incrementalValidate_eq_validate (baseline : ValidatedSet schema)
    (after : Policies) :
    incrementalValidate baseline after = validate after schema :=
  incrementalValidateCore_eq_validate baseline.policies after schema
    baseline.validated

/-- Advance the cache only after the incremental Cedar check succeeds. -/
def ValidatedSet.refresh (baseline : ValidatedSet schema) (after : Policies)
    (accepted : incrementalValidate baseline after = .ok ()) :
    ValidatedSet schema :=
  ⟨after, by simpa [incrementalValidate_eq_validate] using accepted⟩

def ValidatedSet.tryRefresh (baseline : ValidatedSet schema) (after : Policies) :
    Except ValidationError (ValidatedSet schema) :=
  match result : incrementalValidate baseline after with
  | .ok () => .ok (baseline.refresh after result)
  | .error error => .error error

theorem validateFromFresh (before after : Policies) (schema : Schema)
    (baseline : validate before schema = .ok ())
    (fresh : ∀ policy ∈ freshPolicies before after,
      check policy schema = .ok ()) :
    validate after schema = .ok () := by
  apply validateFromReuse before after schema baseline
  intro policy member absent
  apply fresh policy
  simp [freshPolicies, member, absent]

/-- A finite collection of independent Lean-POO policy certificates. -/
structure Bundle (policies : Policies) (schema : Schema) : Prop where
  certified : ∀ policy ∈ policies,
    Certificate (Snapshot.mk policy schema).proofObject

theorem Bundle.ofValidate (policies : Policies) (schema : Schema)
    (validated : validate policies schema = .ok ()) : Bundle policies schema := by
  refine ⟨?_⟩
  intro policy member
  exact (Snapshot.mk policy schema).certificate
    ((validate_iff_each policies schema).1 validated policy member)

theorem Bundle.validate (policies : Policies) (schema : Schema)
    (bundle : Bundle policies schema) : validate policies schema = .ok () := by
  apply (validate_iff_each policies schema).2
  intro policy member
  exact (Snapshot.mk policy schema).validOfCertificate
    (bundle.certified policy member)

theorem Bundle.reviseSameSchema (before after : Policies) (schema : Schema)
    (baseline : Bundle before schema)
    (fresh : ∀ policy ∈ freshPolicies before after,
      Certificate (Snapshot.mk policy schema).proofObject) :
    Bundle after schema := by
  refine ⟨?_⟩
  intro policy member
  by_cases old : policy ∈ before
  · exact baseline.certified policy old
  · apply fresh policy
    simp [freshPolicies, member, old]

end CedarPooSpec.PolicyValidation
