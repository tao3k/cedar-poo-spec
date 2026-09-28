import CedarPooSpec.Slicing

namespace CedarPooSpec.AuthorizationSoundnessExample

open Cedar.Spec Cedar.Validation Cedar.Data
open CedarPooSpec.Soundness
open LeanPoo.Proof

def userType : EntityType := ⟨"User", []⟩
def resourceType : EntityType := ⟨"Resource", []⟩
def actionType : EntityType := ⟨"Action", []⟩
def action : EntityUID := ⟨actionType, "read"⟩
def entityEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.empty, none⟩
def actionEntry : ActionSchemaEntry :=
  ⟨Set.make [userType], Set.make [resourceType], Set.empty, Map.empty⟩
def schema : Schema :=
  ⟨Map.make [(userType, entityEntry), (resourceType, entityEntry)],
   Map.make [(action, actionEntry)]⟩
def request : Request :=
  ⟨⟨userType, "alice"⟩, action, ⟨resourceType, "file"⟩, Map.empty⟩
def plainEntity : EntityData :=
  { attrs := Map.empty, ancestors := Set.empty, tags := Map.empty }
def entities : Entities :=
  Map.make [(request.principal, plainEntity),
    (action, actionSchemaEntryToEntityData actionEntry),
    (request.resource, plainEntity),
    (⟨resourceType, "unrelated"⟩, plainEntity)]
def policies : Policies := [default]

private theorem okOfIsOk {ε : Type} (result : Except ε Unit)
    (h : result.isOk = true) : result = .ok () := by
  cases result with
  | ok value => cases value; rfl
  | error _ => cases h

def snapshot : AuthorizationSnapshot := ⟨policies, schema, request, entities⟩

/-- A concrete, nonempty Cedar policy set closes all four obligations. -/
theorem certificate : Certificate snapshot.proofObject :=
  snapshot.certificateOfChecks (by native_decide)

example : Cedar.Thm.AllEvaluateToBool policies request entities :=
  certifiedAuthorizationSound snapshot certificate

def sliceSnapshot : CedarPooSpec.Slicing.Snapshot := ⟨snapshot, 1⟩

theorem sliceCertificate : Certificate sliceSnapshot.proofObject :=
  sliceSnapshot.certificate certificate
    (okOfIsOk _ (by native_decide))

example : isAuthorized request entities policies =
    isAuthorized request (entities.sliceAtLevel request 1) policies :=
  CedarPooSpec.Slicing.certifiedSlice sliceSnapshot sliceCertificate

theorem closedSliceCertificate : Certificate sliceSnapshot.closedProofObject :=
  sliceSnapshot.closedCertificate sliceCertificate (by native_decide)

example : ∀ policy ∈ policies,
    evaluate policy.toExpr request entities ≠ .error .entityDoesNotExist :=
  CedarPooSpec.Slicing.certifiedNoMissingEntity
    sliceSnapshot closedSliceCertificate

-- The slice keeps the three request roots and drops the unrelated entity.
#guard entities.size == 4
#guard (entities.sliceAtLevel request 1).size == 3
#guard entities.closedAtLevel request 1
#guard !Entities.closedAtLevel
  (Map.make [(action, actionSchemaEntryToEntityData actionEntry)]) request 1

-- Level validation tracks its exact policy, schema, and level inputs.
#guard match changedDependencies CedarPooSpec.Slicing.levelObligation
    (Patch.set (.inl .policies) policies) with
  | [.inl .policies] => true
  | _ => false
#guard match changedDependencies CedarPooSpec.Slicing.levelObligation
    (Patch.set (.inl .schema) schema) with
  | [.inl .schema] => true
  | _ => false
#guard match changedDependencies CedarPooSpec.Slicing.levelObligation
    (Patch.set (Value := CedarPooSpec.Slicing.Value) (.inr ()) (1 : Nat)) with
  | [.inr ()] => true
  | _ => false
#guard (changedDependencies CedarPooSpec.Slicing.levelObligation
  (Patch.set (.inl .request) request)).isEmpty
#guard (changedDependencies CedarPooSpec.Slicing.levelObligation
  (Patch.set (.inl .entities) entities)).isEmpty

-- Closure instead tracks the request, entities, and level.
#guard match changedDependencies CedarPooSpec.Slicing.closureObligation
    (Patch.set (.inl .request) request) with
  | [.inl .request] => true
  | _ => false
#guard match changedDependencies CedarPooSpec.Slicing.closureObligation
    (Patch.set (.inl .entities) entities) with
  | [.inl .entities] => true
  | _ => false
#guard match changedDependencies CedarPooSpec.Slicing.closureObligation
    (Patch.set (Value := CedarPooSpec.Slicing.Value) (.inr ()) (2 : Nat)) with
  | [.inr ()] => true
  | _ => false
#guard (changedDependencies CedarPooSpec.Slicing.closureObligation
  (Patch.set (.inl .policies) policies)).isEmpty
#guard (changedDependencies CedarPooSpec.Slicing.closureObligation
  (Patch.set (.inl .schema) schema)).isEmpty

-- Omitting the action entity invalidates the entity-validation premise.
#guard !(validateEntities schema Map.empty).isOk

end CedarPooSpec.AuthorizationSoundnessExample
