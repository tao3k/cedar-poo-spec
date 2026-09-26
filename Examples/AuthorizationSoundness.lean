import CedarPooSpec.Soundness

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
def entities : Entities :=
  Map.make [(action, actionSchemaEntryToEntityData actionEntry)]
def policies : Policies := [default]

private theorem okOfIsOk {ε : Type} (result : Except ε Unit)
    (h : result.isOk = true) : result = .ok () := by
  cases result with
  | ok value => cases value; rfl
  | error _ => cases h

def snapshot : AuthorizationSnapshot := ⟨policies, schema, request, entities⟩

/-- A concrete, nonempty Cedar policy set closes all four obligations. -/
theorem certificate : Certificate snapshot.proofObject :=
  snapshot.certificate
    (okOfIsOk _ (by native_decide))
    (okOfIsOk _ (by native_decide))
    (okOfIsOk _ (by native_decide))
    (okOfIsOk _ (by native_decide))

example : Cedar.Thm.AllEvaluateToBool policies request entities :=
  certifiedAuthorizationSound snapshot certificate

-- Omitting the action entity invalidates the entity-validation premise.
#guard !(validateEntities schema Map.empty).isOk

end CedarPooSpec.AuthorizationSoundnessExample
