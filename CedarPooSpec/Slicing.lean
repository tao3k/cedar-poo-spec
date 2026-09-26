import CedarPooSpec.Soundness
import LeanPoo.Proof.Product

/-! Cedar entity slicing with the authorization and level premises in one proof object. -/

namespace CedarPooSpec.Slicing

open Cedar.Spec Cedar.Validation LeanPoo.Proof

abbrev Key := Sum Soundness.AuthorizationKey Unit
abbrev Value := SumValue Soundness.AuthorizationValue (fun _ : Unit => Nat)

structure Snapshot where
  authorization : Soundness.AuthorizationSnapshot
  level : Nat

private def levelObject (level : Nat) : ProofObject Unit (fun _ => Nat) where
  state := fun _ => level
  obligations := []

/-- Level validation depends on the policies, schema, and requested level. -/
def levelObligation : Obligation Key Value where
  dependencies := [.inl .policies, .inl .schema, .inr ()]
  holds := fun state =>
    validateWithLevel (state (.inl .policies)) (state (.inl .schema))
      (state (.inr ())) = .ok ()
  stable := by
    intro before after equal holds
    have hp := equal (.inl .policies) (by simp)
    have hs := equal (.inl .schema) (by simp)
    have hl := equal (.inr ()) (by simp)
    simpa [hp, hs, hl] using holds

def Snapshot.proofObject (snapshot : Snapshot) : ProofObject Key Value :=
  (snapshot.authorization.proofObject.pair
    (levelObject snapshot.level)).withObligation levelObligation

/-- Closure also depends on the request and entity store, unlike level validation. -/
def closureObligation : Obligation Key Value where
  dependencies := [.inl .request, .inl .entities, .inr ()]
  holds := fun state =>
    (state (.inl .entities)).closedAtLevel
      (state (.inl .request)) (state (.inr ()))
  stable := by
    intro before after equal holds
    have hr := equal (.inl .request) (by simp)
    have he := equal (.inl .entities) (by simp)
    have hl := equal (.inr ()) (by simp)
    simpa [hr, he, hl] using holds

def Snapshot.closedProofObject (snapshot : Snapshot) : ProofObject Key Value :=
  snapshot.proofObject.withObligation closureObligation

theorem Snapshot.certificate (snapshot : Snapshot)
    (authorizationCertificate : Certificate snapshot.authorization.proofObject)
    (levelValidated : validateWithLevel snapshot.authorization.policies
      snapshot.authorization.schema snapshot.level = .ok ()) :
    Certificate snapshot.proofObject := by
  exact Certificate.withObligation
    (snapshot.authorization.proofObject.pair (levelObject snapshot.level))
    (Certificate.pair snapshot.authorization.proofObject
      (levelObject snapshot.level) authorizationCertificate (by
        intro obligation membership
        simp [levelObject] at membership))
    levelObligation levelValidated

theorem Snapshot.closedCertificate (snapshot : Snapshot)
    (certificate : Certificate snapshot.proofObject)
    (closed : snapshot.authorization.entities.closedAtLevel
      snapshot.authorization.request snapshot.level) :
    Certificate snapshot.closedProofObject :=
  Certificate.withObligation snapshot.proofObject certificate closureObligation closed

private theorem Snapshot.validationFacts (snapshot : Snapshot)
    (certificate : Certificate snapshot.proofObject) :
    snapshot.authorization.schema.validateWellFormed = .ok () ∧
    validateRequest snapshot.authorization.schema snapshot.authorization.request = .ok () ∧
    validateEntities snapshot.authorization.schema snapshot.authorization.entities = .ok () ∧
    validateWithLevel snapshot.authorization.policies
      snapshot.authorization.schema snapshot.level = .ok () := by
  have hwf := certificate Soundness.schemaObligation.left (by
    simp [Snapshot.proofObject, ProofObject.withObligation,
      Soundness.AuthorizationSnapshot.proofObject, ProofObject.pair, levelObject])
  have hr := certificate Soundness.requestObligation.left (by
    simp [Snapshot.proofObject, ProofObject.withObligation,
      Soundness.AuthorizationSnapshot.proofObject, ProofObject.pair, levelObject])
  have he := certificate Soundness.entitiesObligation.left (by
    simp [Snapshot.proofObject, ProofObject.withObligation,
      Soundness.AuthorizationSnapshot.proofObject, ProofObject.pair, levelObject])
  have hl := certificate levelObligation (by
    simp [Snapshot.proofObject, ProofObject.withObligation])
  exact ⟨hwf, hr, he, hl⟩

/-- The certified slice gives the same Cedar authorization response. -/
theorem certifiedSlice (snapshot : Snapshot)
    (certificate : Certificate snapshot.proofObject) :
    isAuthorized snapshot.authorization.request snapshot.authorization.entities
      snapshot.authorization.policies =
    isAuthorized snapshot.authorization.request
      (snapshot.authorization.entities.sliceAtLevel
        snapshot.authorization.request snapshot.level)
      snapshot.authorization.policies := by
  obtain ⟨hwf, hr, he, hl⟩ := snapshot.validationFacts certificate
  exact Cedar.Thm.validate_with_level_is_sound hwf hr he hl

/-- A closed level certificate excludes missing-entity evaluation errors. -/
theorem certifiedNoMissingEntity (snapshot : Snapshot)
    (certificate : Certificate snapshot.closedProofObject) :
    ∀ policy ∈ snapshot.authorization.policies,
      evaluate policy.toExpr snapshot.authorization.request
        snapshot.authorization.entities ≠ .error .entityDoesNotExist := by
  have sliceCertificate : Certificate snapshot.proofObject := by
    intro obligation membership
    exact certificate obligation (List.mem_append.mpr (Or.inl membership))
  obtain ⟨hwf, hr, he, hl⟩ := snapshot.validationFacts sliceCertificate
  have closed := certificate closureObligation (by
    simp [Snapshot.closedProofObject, ProofObject.withObligation])
  exact Cedar.Thm.validate_with_level_no_dne hwf hr he closed hl

end CedarPooSpec.Slicing
