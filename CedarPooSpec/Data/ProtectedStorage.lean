import CedarPooSpec.Data.StorageEffect

/-!
Provider-neutral protected storage contract. The intent is admitted before
encryption or provider I/O. The publication is checked again after the outer
root exists and before the Host commits a discoverable result. The Host must
authenticate the projected facts, verify both snapshot closures, evaluate
Cedar, and atomically redeem and persist the operation. These pure checks do
not perform those effects or prove that any bytes were encrypted.
-/

namespace CedarPooSpec.Data

open Cedar.Spec

/-- The inner snapshot CID remains the source identity. The profile, key
    reference and residency are Host-selected public identifiers, never key
    material. -/
structure ProtectionIntentV1 where
  storage : StorageEffectV1
  profile : String
  keyRef : String
  keyVersion : String
  residency : String
  deriving DecidableEq

structure ProtectionClaimV1 where
  intent : ProtectionIntentV1
  epoch : Nat
  expiresAt : Nat
  allowed : Bool
  deriving DecidableEq

/-- This records the proposed outer identity after encryption. The Host checks
    the actual envelope and complete manifest against these fields. -/
structure ProtectedPublicationV1 where
  intent : ProtectionIntentV1
  outerRootCid : String
  envelopeVersion : Nat
  keyVersion : String
  deriving DecidableEq

private def uidNonempty (uid : EntityUID) : Bool :=
  !(toString uid.ty).isEmpty && !uid.eid.isEmpty

private def wellFormed (intent : ProtectionIntentV1) : Bool :=
  let effect := intent.storage
  !effect.operationId.isEmpty && uidNonempty effect.subject &&
  !effect.purpose.isEmpty && !effect.snapshotCid.isEmpty &&
  !effect.policyRoot.isEmpty && !effect.lineageRevision.isEmpty &&
  uidNonempty effect.destination.resource && !effect.destination.tenant.isEmpty &&
  !effect.sources.isEmpty && effect.sources.length ≤ 64 &&
  !effect.destination.acceptedOwners.isEmpty &&
  effect.destination.acceptedOwners.length ≤ 64 &&
  effect.destination.acceptedOwners.all uidNonempty &&
  effect.sources.all (fun source =>
    uidNonempty source.resource && uidNonempty source.owner && !source.tenant.isEmpty) &&
  !intent.profile.isEmpty && !intent.keyRef.isEmpty &&
  !intent.keyVersion.isEmpty && !intent.residency.isEmpty

/-- Restricted labels may enter only a destination that explicitly accepts
    them. Protection does not declassify a source. -/
def ProtectionIntentV1.admitted (intent : ProtectionIntentV1)
    (claim : ProtectionClaimV1) (current : CurrentStorageStateV1) : Bool :=
  wellFormed intent && decide (intent = claim.intent) && claim.allowed &&
  current.policyRoot == intent.storage.policyRoot &&
  current.lineageRevision == intent.storage.lineageRevision &&
  current.epoch == claim.epoch && current.now < claim.expiresAt &&
  ({ digest := intent.storage.snapshotCid, sources := intent.storage.sources } :
    DerivedArtifact).canFlowTo intent.storage.destination

/-- Recheck current authority at the commit boundary. Outer identity is
    distinct from the plaintext inner identity; the Host must verify that the
    outer CID names authenticated ciphertext and a complete protected root. -/
def ProtectedPublicationV1.commitAdmitted (publication : ProtectedPublicationV1)
    (claim : ProtectionClaimV1) (current : CurrentStorageStateV1) : Bool :=
  publication.intent.admitted claim current &&
  !publication.outerRootCid.isEmpty &&
  publication.outerRootCid != publication.intent.storage.snapshotCid &&
  publication.envelopeVersion == 1 &&
  publication.keyVersion == publication.intent.keyVersion

end CedarPooSpec.Data
