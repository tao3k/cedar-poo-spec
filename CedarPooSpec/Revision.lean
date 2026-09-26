import CedarPooSpec.PolicyModules
import CedarPooSpec.Soundness
import CedarPooSpec.PolicyValidation
import LeanPoo.Proof.Batch

/-! Connect a C4 policy revision to the authorization proof object's patch. -/

namespace CedarPooSpec.PolicyModules

open LeanPoo.Proof
open CedarPooSpec.Soundness

def Revision.beforePolicies (revision : Revision) : Cedar.Spec.Policies :=
  revision.before.policies.map CompiledPolicy.policy

def Revision.afterPolicies (revision : Revision) : Cedar.Spec.Policies :=
  revision.after.policies.map CompiledPolicy.policy

def Revision.freshPolicies (revision : Revision) : Cedar.Spec.Policies :=
  PolicyValidation.freshPolicies revision.beforePolicies revision.afterPolicies

/-- Reclose Cedar's whole-set validation from unchanged bodies and fresh checks. -/
theorem Revision.validateAfter (revision : Revision) (schema : Cedar.Validation.Schema)
    (baseline : Cedar.Validation.validate revision.beforePolicies schema = .ok ())
    (fresh : ∀ policy ∈ revision.freshPolicies,
      PolicyValidation.check policy schema = .ok ()) :
    Cedar.Validation.validate revision.afterPolicies schema = .ok () :=
  PolicyValidation.validateFromFresh revision.beforePolicies
    revision.afterPolicies schema baseline fresh

def Revision.authorizationPatch (revision : Revision) :
    Patch AuthorizationKey AuthorizationValue :=
  if decide (revision.beforePolicies = revision.afterPolicies) then Patch.empty
  else Patch.set .policies revision.afterPolicies

def Revision.beforeSnapshot (revision : Revision) (schema : Cedar.Validation.Schema)
    (request : Cedar.Spec.Request) (entities : Cedar.Spec.Entities) :
    AuthorizationSnapshot :=
  ⟨revision.beforePolicies, schema, request, entities⟩

def Revision.afterSnapshot (revision : Revision) (schema : Cedar.Validation.Schema)
    (request : Cedar.Spec.Request) (entities : Cedar.Spec.Entities) :
    AuthorizationSnapshot :=
  ⟨revision.afterPolicies, schema, request, entities⟩

/-- The diagnostic patch materializes exactly the revised proof object. -/
theorem Revision.authorizationPatch_object (revision : Revision)
    (schema : Cedar.Validation.Schema) (request : Cedar.Spec.Request)
    (entities : Cedar.Spec.Entities) :
    append (revision.beforeSnapshot schema request entities).proofObject
      revision.authorizationPatch =
      (revision.afterSnapshot schema request entities).proofObject := by
  by_cases same : revision.beforePolicies = revision.afterPolicies
  · simp [Revision.authorizationPatch, same, Patch.empty, append,
      Revision.beforeSnapshot, Revision.afterSnapshot,
      AuthorizationSnapshot.proofObject]
  · apply (ProofObject.mk.injEq _ _ _ _).mpr
    constructor
    · funext key
      cases key <;> simp [Revision.authorizationPatch, same, Patch.set,
        Revision.beforeSnapshot, Revision.afterSnapshot,
        AuthorizationSnapshot.proofObject, AuthorizationSnapshot.state]
      all_goals rfl
    · simp [Revision.authorizationPatch, same, Patch.set,
        Revision.beforeSnapshot,
        AuthorizationSnapshot.proofObject]

/-- Reuse the unchanged Cedar premises and reclose policy validation from
    exactly the policy bodies absent from the baseline. -/
theorem Revision.authorizationCertificate (revision : Revision)
    (schema : Cedar.Validation.Schema) (request : Cedar.Spec.Request)
    (entities : Cedar.Spec.Entities)
    (baseline : Certificate (revision.beforeSnapshot schema request entities).proofObject)
    (fresh : ∀ policy ∈ revision.freshPolicies,
      PolicyValidation.check policy schema = .ok ()) :
    Certificate (revision.afterSnapshot schema request entities).proofObject := by
  have hwf : schema.validateWellFormed = .ok () :=
    baseline schemaObligation
      (by simp [Revision.beforeSnapshot, AuthorizationSnapshot.proofObject])
  have hp : Cedar.Validation.validate revision.beforePolicies schema = .ok () :=
    baseline policiesObligation
      (by simp [Revision.beforeSnapshot, AuthorizationSnapshot.proofObject])
  have hr : Cedar.Validation.validateRequest schema request = .ok () :=
    baseline requestObligation
      (by simp [Revision.beforeSnapshot, AuthorizationSnapshot.proofObject])
  have he : Cedar.Validation.validateEntities schema entities = .ok () :=
    baseline entitiesObligation
      (by simp [Revision.beforeSnapshot, AuthorizationSnapshot.proofObject])
  exact (revision.afterSnapshot schema request entities).certificate
    hwf (revision.validateAfter schema hp fresh) hr he

theorem Revision.patchedAuthorizationCertificate (revision : Revision)
    (schema : Cedar.Validation.Schema) (request : Cedar.Spec.Request)
    (entities : Cedar.Spec.Entities)
    (baseline : Certificate (revision.beforeSnapshot schema request entities).proofObject)
    (fresh : ∀ policy ∈ revision.freshPolicies,
      PolicyValidation.check policy schema = .ok ()) :
    Certificate (append
      (revision.beforeSnapshot schema request entities).proofObject
      revision.authorizationPatch) := by
  rw [revision.authorizationPatch_object]
  exact revision.authorizationCertificate schema request entities baseline fresh

end CedarPooSpec.PolicyModules
