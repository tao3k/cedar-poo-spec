import Cedar.Validation.Validator
import Cedar.Thm.Data.List.Lemmas

/-! Reuse Cedar's own per-policy validator across policy-set revisions. -/

namespace CedarPooSpec.PolicyValidation

open Cedar.Spec Cedar.Validation

def check (policy : Policy) (schema : Schema) : ValidationResult :=
  typecheckPolicyWithEnvironments typecheckPolicy policy schema

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

theorem validateFromFresh (before after : Policies) (schema : Schema)
    (baseline : validate before schema = .ok ())
    (fresh : ∀ policy ∈ freshPolicies before after,
      check policy schema = .ok ()) :
    validate after schema = .ok () := by
  apply validateFromReuse before after schema baseline
  intro policy member absent
  apply fresh policy
  simp [freshPolicies, member, absent]

end CedarPooSpec.PolicyValidation
