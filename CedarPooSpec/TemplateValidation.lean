import CedarPooSpec.PolicyValidation
import Cedar.Spec.Template

/-! Link Cedar templates through Cedar itself, then reuse certified policy bodies. -/

namespace CedarPooSpec.TemplateValidation

open Cedar.Spec Cedar.Validation

inductive Error where
  | link (message : String)
  | validate (error : ValidationError)
  deriving Repr

/-- A linked policy set whose materialization and validation are both certified. -/
structure LinkedSet (schema : Schema) where
  templates : Templates
  links : TemplateLinkedPolicies
  validated : PolicyValidation.ValidatedSet schema
  linked : Cedar.Spec.link? templates links = .ok validated.policies

/-- Construct the first revision using Cedar's own linker and validator. -/
def LinkedSet.create (schema : Schema) (templates : Templates)
    (links : TemplateLinkedPolicies) : Except Error (LinkedSet schema) :=
  match hlink : Cedar.Spec.link? templates links with
  | .error message => .error (.link message)
  | .ok policies =>
      match hvalid : Cedar.Validation.validate policies schema with
      | .error error => .error (.validate error)
      | .ok () => .ok {
          templates
          links
          validated := ⟨policies, hvalid⟩
          linked := hlink }

/-- Re-link every policy through Cedar, then check only bodies absent from the
    certified baseline. The cache theorem preserves Cedar's first error. -/
def LinkedSet.tryRefresh (baseline : LinkedSet schema) (templates : Templates)
    (links : TemplateLinkedPolicies) : Except Error (LinkedSet schema) :=
  match hlink : Cedar.Spec.link? templates links with
  | .error message => .error (.link message)
  | .ok policies =>
      match hvalid : PolicyValidation.incrementalValidate baseline.validated policies with
      | .error error => .error (.validate error)
      | .ok () => .ok {
          templates
          links
          validated := baseline.validated.refresh policies hvalid
          linked := by simpa [PolicyValidation.ValidatedSet.refresh] using hlink }

theorem LinkedSet.incremental_eq_validate (baseline : LinkedSet schema)
    (policies : Policies) :
    PolicyValidation.incrementalValidate baseline.validated policies =
      Cedar.Validation.validate policies schema :=
  PolicyValidation.incrementalValidate_eq_validate baseline.validated policies

end CedarPooSpec.TemplateValidation
