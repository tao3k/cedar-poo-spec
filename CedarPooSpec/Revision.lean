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

def Revision.incrementalValidate (revision : Revision)
    (schema : Cedar.Validation.Schema)
    (baseline : Cedar.Validation.validate revision.beforePolicies schema = .ok ()) :
    Cedar.Validation.ValidationResult :=
  PolicyValidation.incrementalValidate ⟨revision.beforePolicies, baseline⟩
    revision.afterPolicies

theorem Revision.incrementalValidate_eq_validate (revision : Revision)
    (schema : Cedar.Validation.Schema)
    (baseline : Cedar.Validation.validate revision.beforePolicies schema = .ok ()) :
    revision.incrementalValidate schema baseline =
      Cedar.Validation.validate revision.afterPolicies schema :=
  PolicyValidation.incrementalValidate_eq_validate
    ⟨revision.beforePolicies, baseline⟩ revision.afterPolicies

def Revision.tryRefresh (revision : Revision)
    (baseline : PolicyValidation.ValidatedSet schema)
    (_aligned : baseline.policies = revision.beforePolicies) :
    Except Cedar.Validation.ValidationError
      (PolicyValidation.ValidatedSet schema) :=
  baseline.tryRefresh revision.afterPolicies

/-- Reclose Cedar's whole-set validation from unchanged bodies and fresh checks. -/
theorem Revision.validateAfter (revision : Revision) (schema : Cedar.Validation.Schema)
    (baseline : Cedar.Validation.validate revision.beforePolicies schema = .ok ())
    (fresh : ∀ policy ∈ revision.freshPolicies,
      Certificate (PolicyValidation.Snapshot.mk policy schema).proofObject) :
    Cedar.Validation.validate revision.afterPolicies schema = .ok () := by
  have beforeBundle := PolicyValidation.Bundle.ofValidate
    revision.beforePolicies schema baseline
  have afterBundle := PolicyValidation.Bundle.reviseSameSchema
    revision.beforePolicies revision.afterPolicies schema beforeBundle fresh
  exact afterBundle.validate revision.afterPolicies schema

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
      Certificate (PolicyValidation.Snapshot.mk policy schema).proofObject) :
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
      Certificate (PolicyValidation.Snapshot.mk policy schema).proofObject) :
    Certificate (append
      (revision.beforeSnapshot schema request entities).proofObject
      revision.authorizationPatch) := by
  rw [revision.authorizationPatch_object]
  exact revision.authorizationCertificate schema request entities baseline fresh

/-- A changed schema invalidates every per-policy certificate and the other
    schema-dependent Cedar premises. Reclose them against the new schema. -/
theorem Revision.authorizationCertificateWithSchema (revision : Revision)
    (schema : Cedar.Validation.Schema) (request : Cedar.Spec.Request)
    (entities : Cedar.Spec.Entities)
    (wellFormed : schema.validateWellFormed = .ok ())
    (policies : PolicyValidation.Bundle revision.afterPolicies schema)
    (requestValid : Cedar.Validation.validateRequest schema request = .ok ())
    (entitiesValid : Cedar.Validation.validateEntities schema entities = .ok ()) :
    Certificate (revision.afterSnapshot schema request entities).proofObject :=
  (revision.afterSnapshot schema request entities).certificate
    wellFormed (policies.validate revision.afterPolicies schema)
    requestValid entitiesValid

def Revision.authorizationPatchWithSchema (revision : Revision)
    (schema : Cedar.Validation.Schema) :
    Patch AuthorizationKey AuthorizationValue :=
  revision.authorizationPatch.then (Patch.set .schema schema)

theorem Revision.authorizationPatchWithSchema_object (revision : Revision)
    (beforeSchema afterSchema : Cedar.Validation.Schema)
    (request : Cedar.Spec.Request) (entities : Cedar.Spec.Entities) :
    append (revision.beforeSnapshot beforeSchema request entities).proofObject
      (revision.authorizationPatchWithSchema afterSchema) =
      (revision.afterSnapshot afterSchema request entities).proofObject := by
  unfold Revision.authorizationPatchWithSchema
  rw [← append_then, revision.authorizationPatch_object]
  apply (ProofObject.mk.injEq _ _ _ _).mpr
  constructor
  · funext key
    cases key <;> simp [Patch.set, Revision.afterSnapshot,
      AuthorizationSnapshot.proofObject, AuthorizationSnapshot.state]
    all_goals rfl
  · simp [Patch.set, Revision.afterSnapshot,
      AuthorizationSnapshot.proofObject]

theorem Revision.patchedAuthorizationCertificateWithSchema (revision : Revision)
    (beforeSchema afterSchema : Cedar.Validation.Schema)
    (request : Cedar.Spec.Request) (entities : Cedar.Spec.Entities)
    (wellFormed : afterSchema.validateWellFormed = .ok ())
    (policies : PolicyValidation.Bundle revision.afterPolicies afterSchema)
    (requestValid : Cedar.Validation.validateRequest afterSchema request = .ok ())
    (entitiesValid : Cedar.Validation.validateEntities afterSchema entities = .ok ()) :
    Certificate (append
      (revision.beforeSnapshot beforeSchema request entities).proofObject
      (revision.authorizationPatchWithSchema afterSchema)) := by
  rw [revision.authorizationPatchWithSchema_object]
  exact revision.authorizationCertificateWithSchema afterSchema request entities
    wellFormed policies requestValid entitiesValid

end CedarPooSpec.PolicyModules
