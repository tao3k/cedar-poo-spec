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
structure ProtectionIntent where
  storage : StorageEffect
  profile : String
  keyRef : String
  keyVersion : String
  residency : String
  deriving DecidableEq

structure ProtectionClaim where
  intent : ProtectionIntent
  epoch : Nat
  expiresAt : Nat
  allowed : Bool
  deriving DecidableEq

/-- This records the proposed outer identity after encryption. The Host checks
    the actual envelope and complete manifest against these fields. -/
structure ProtectedPublication where
  intent : ProtectionIntent
  outerRootCid : String
  envelopeVersion : Nat
  keyVersion : String
  deriving DecidableEq

private def uidNonempty (uid : EntityUID) : Bool :=
  !(toString uid.ty).isEmpty && !uid.eid.isEmpty

private def intentWellFormed (intent : ProtectionIntent) : Bool :=
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
def ProtectionIntent.admitted (intent : ProtectionIntent)
    (claim : ProtectionClaim) (current : CurrentStorageState) : Bool :=
  intentWellFormed intent && decide (intent = claim.intent) && claim.allowed &&
  current.policyRoot == intent.storage.policyRoot &&
  current.lineageRevision == intent.storage.lineageRevision &&
  current.epoch == claim.epoch && current.now < claim.expiresAt &&
  ({ digest := intent.storage.snapshotCid, sources := intent.storage.sources } :
    DerivedArtifact).canFlowTo intent.storage.destination

/-- Recheck current authority immediately before publishing the protected
    manifest root. This is not the later Host ledger commit. -/
def ProtectedPublication.preRootAdmitted (publication : ProtectedPublication)
    (claim : ProtectionClaim) (current : CurrentStorageState) : Bool :=
  publication.intent.admitted claim current &&
  !publication.outerRootCid.isEmpty &&
  publication.outerRootCid != publication.intent.storage.snapshotCid &&
  publication.envelopeVersion == 1 &&
  publication.keyVersion == publication.intent.keyVersion

/-- Projected acknowledgement of a successful physical root write. Only the
    publishing library can issue a trustworthy acknowledgement; the pure SPEC
    does not prove provider I/O. -/
structure ProtectedPhysicalAck where
  innerRootCid : String
  outerRootCid : String
  childCount : Nat
  totalOuterBytes : Nat
  deriving DecidableEq

/-- Host-owned ledger entry, stored atomically with approval redemption,
    discoverability and audit. An existing entry is authenticated input. -/
structure ProtectedCommitReceipt where
  publication : ProtectedPublication
  childCount : Nat
  totalOuterBytes : Nat
  deriving DecidableEq

inductive ProtectedCommitDisposition where
  | apply
  | replay
  | reject
  deriving DecidableEq, Repr

/-- Static identity checks shared by commit and later protected reads. -/
def ProtectedPublication.wellFormed (publication : ProtectedPublication) : Bool :=
  intentWellFormed publication.intent &&
  !publication.outerRootCid.isEmpty &&
  publication.outerRootCid != publication.intent.storage.snapshotCid &&
  publication.envelopeVersion == 1 &&
  publication.keyVersion == publication.intent.keyVersion

/-- Decide whether a Host may atomically create a commit receipt, replay an
    exact committed operation, or reject it. A replay creates no new effect and
    grants no read authorization. An uncommitted request needs a physical root
    acknowledgement and fresh authority. The Host owns the atomic ledger CAS. -/
def ProtectedPublication.commitDisposition (publication : ProtectedPublication)
    (claim : ProtectionClaim) (current : CurrentStorageState)
    (physical : Option ProtectedPhysicalAck)
    (existing : Option ProtectedCommitReceipt) : ProtectedCommitDisposition :=
  match existing with
  | some receipt =>
    if publication.wellFormed &&
       receipt.publication == publication &&
       receipt.totalOuterBytes > 0 && receipt.childCount ≤ 4096 then
      .replay
    else .reject
  | none =>
    match physical with
    | some ack =>
      if publication.preRootAdmitted claim current &&
         ack.innerRootCid == publication.intent.storage.snapshotCid &&
         ack.outerRootCid == publication.outerRootCid &&
         ack.totalOuterBytes > 0 && ack.childCount ≤ 4096 then
        .apply
      else .reject
    | none => .reject

end CedarPooSpec.Data
