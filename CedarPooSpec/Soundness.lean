import CedarPooSpec.Validation
import Cedar.Thm.Validation

/-! Transport Cedar's existing typechecker soundness through a proof object. -/

namespace CedarPooSpec.Soundness

open Cedar.Spec
open Cedar.Validation
open LeanPoo.Proof

/-- The proof object certifies that its stored result came from Cedar's
    typechecker; Cedar's own theorem supplies the semantic guarantee. -/
theorem certifiedPolicySound (snapshot : Validation.Snapshot)
    (certificate : Certificate snapshot.proofObject)
    (typed : TypedExpr)
    (accepted : snapshot.result = .ok typed)
    (request : Request) (entities : Entities)
    (wellFormed : Cedar.Thm.InstanceOfWellFormedEnvironment
      request entities snapshot.environment) :
    ∃ result : Bool,
      Cedar.Thm.EvaluatesTo snapshot.policy.toExpr request entities result := by
  have checkerResult :
      typecheckPolicy snapshot.policy snapshot.environment = .ok typed := by
    have certified := certificate Validation.typecheckObligation
      (by simp [Validation.Snapshot.proofObject])
    change snapshot.result =
      typecheckPolicy snapshot.policy snapshot.environment at certified
    rw [certified] at accepted
    exact accepted
  exact Cedar.Thm.typecheck_policy_is_sound wellFormed checkerResult

end CedarPooSpec.Soundness

namespace CedarPooSpec.Soundness

open Cedar.Spec
open Cedar.Validation
open LeanPoo.Proof

inductive AuthorizationKey where
  | policies
  | schema
  | request
  | entities
  deriving DecidableEq

def AuthorizationValue : AuthorizationKey → Type
  | .policies => Policies
  | .schema => Schema
  | .request => Request
  | .entities => Entities

structure AuthorizationSnapshot where
  policies : Policies
  schema : Schema
  request : Request
  entities : Entities

def AuthorizationSnapshot.state (snapshot : AuthorizationSnapshot) :
    State AuthorizationKey AuthorizationValue
  | .policies => snapshot.policies
  | .schema => snapshot.schema
  | .request => snapshot.request
  | .entities => snapshot.entities

def schemaObligation : Obligation AuthorizationKey AuthorizationValue where
  dependencies := [.schema]
  holds := fun state => (state .schema).validateWellFormed = .ok ()
  stable := by
    intro before after equal holds
    simpa [← equal .schema (by simp)] using holds

def policiesObligation : Obligation AuthorizationKey AuthorizationValue where
  dependencies := [.policies, .schema]
  holds := fun state => validate (state .policies) (state .schema) = .ok ()
  stable := by
    intro before after equal holds
    have hp := equal .policies (by simp)
    have hs := equal .schema (by simp)
    simpa [hp, hs] using holds

def requestObligation : Obligation AuthorizationKey AuthorizationValue where
  dependencies := [.schema, .request]
  holds := fun state => validateRequest (state .schema) (state .request) = .ok ()
  stable := by
    intro before after equal holds
    have hs := equal .schema (by simp)
    have hr := equal .request (by simp)
    simpa [hs, hr] using holds

def entitiesObligation : Obligation AuthorizationKey AuthorizationValue where
  dependencies := [.schema, .entities]
  holds := fun state => validateEntities (state .schema) (state .entities) = .ok ()
  stable := by
    intro before after equal holds
    have hs := equal .schema (by simp)
    have he := equal .entities (by simp)
    simpa [hs, he] using holds

def AuthorizationSnapshot.proofObject (snapshot : AuthorizationSnapshot) :
    ProofObject AuthorizationKey AuthorizationValue where
  state := snapshot.state
  obligations := [schemaObligation, policiesObligation,
    requestObligation, entitiesObligation]

theorem AuthorizationSnapshot.certificate (snapshot : AuthorizationSnapshot)
    (hwf : snapshot.schema.validateWellFormed = .ok ())
    (hp : validate snapshot.policies snapshot.schema = .ok ())
    (hr : validateRequest snapshot.schema snapshot.request = .ok ())
    (he : validateEntities snapshot.schema snapshot.entities = .ok ()) :
    Certificate snapshot.proofObject := by
  intro obligation membership
  simp [AuthorizationSnapshot.proofObject] at membership
  rcases membership with rfl | rfl | rfl | rfl
  · exact hwf
  · exact hp
  · exact hr
  · exact he

/-- A closed Lean-POO certificate supplies exactly Cedar's four premises. -/
theorem certifiedAuthorizationSound (snapshot : AuthorizationSnapshot)
    (certificate : Certificate snapshot.proofObject) :
    Cedar.Thm.AllEvaluateToBool snapshot.policies snapshot.request snapshot.entities := by
  have hwf := certificate schemaObligation (by simp [AuthorizationSnapshot.proofObject])
  have hp := certificate policiesObligation (by simp [AuthorizationSnapshot.proofObject])
  have hr := certificate requestObligation (by simp [AuthorizationSnapshot.proofObject])
  have he := certificate entitiesObligation (by simp [AuthorizationSnapshot.proofObject])
  exact Cedar.Thm.validation_is_sound snapshot.policies snapshot.schema
    snapshot.request snapshot.entities hwf hp hr he

/-- Response-level error classification retains Cedar's unique-ID premise. -/
theorem certifiedAuthorizationSoundResponse (snapshot : AuthorizationSnapshot)
    (certificate : Certificate snapshot.proofObject)
    (uniqueIds : Cedar.Thm.PolicyIdsUnique snapshot.policies) :
    ∀ p ∈ snapshot.policies,
      p.id ∈ (isAuthorized snapshot.request snapshot.entities
        snapshot.policies).erroringPolicies →
        evaluate p.toExpr snapshot.request snapshot.entities =
          .error .entityDoesNotExist ∨
        evaluate p.toExpr snapshot.request snapshot.entities =
          .error .extensionError ∨
        evaluate p.toExpr snapshot.request snapshot.entities =
          .error .arithBoundsError := by
  have hwf := certificate schemaObligation (by simp [AuthorizationSnapshot.proofObject])
  have hp := certificate policiesObligation (by simp [AuthorizationSnapshot.proofObject])
  have hr := certificate requestObligation (by simp [AuthorizationSnapshot.proofObject])
  have he := certificate entitiesObligation (by simp [AuthorizationSnapshot.proofObject])
  exact Cedar.Thm.validation_is_sound_response snapshot.policies snapshot.schema
    snapshot.request snapshot.entities uniqueIds hwf hp hr he

end CedarPooSpec.Soundness
