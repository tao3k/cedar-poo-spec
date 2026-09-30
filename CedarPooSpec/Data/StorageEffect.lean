import CedarPooSpec.Data.DerivedArtifact

/-!
A versioned, provider-neutral projection of one physical storage effect.
The Host authenticates every field, evaluates the selected Cedar policy and
atomically redeems an approval. This pure check neither signs a claim nor
performs I/O. The wire projection represents EntityUID as separate type/id
fields and a CID as its canonical lowercase CIDv1 base32 text.
-/

namespace CedarPooSpec.Data

open Cedar.Spec

inductive StorageTier where
  | durableLocal
  | remote
  deriving BEq, DecidableEq, Repr

structure StorageEffectV1 where
  operationId : String
  subject : EntityUID
  purpose : String
  snapshotCid : String
  sources : List SourceLabel
  destination : Destination
  tier : StorageTier
  policyRoot : String
  lineageRevision : String
  deriving DecidableEq

structure StorageClaimV1 where
  effect : StorageEffectV1
  epoch : Nat
  expiresAt : Nat
  allowed : Bool
  deriving DecidableEq

structure CurrentStorageStateV1 where
  policyRoot : String
  lineageRevision : String
  epoch : Nat
  now : Nat
  deriving DecidableEq

private def uidNonempty (uid : EntityUID) : Bool :=
  !(toString uid.ty).isEmpty && !uid.eid.isEmpty

/-- Raw storage is restricted to unrestricted sources even when a destination
    could accept restricted material through a separately protected path. -/
def StorageEffectV1.rawAdmitted (effect : StorageEffectV1)
    (claim : StorageClaimV1) (current : CurrentStorageStateV1) : Bool :=
  !effect.operationId.isEmpty && uidNonempty effect.subject &&
  !effect.purpose.isEmpty &&
  !effect.snapshotCid.isEmpty && !effect.policyRoot.isEmpty &&
  !effect.lineageRevision.isEmpty &&
  uidNonempty effect.destination.resource && !effect.destination.tenant.isEmpty &&
  !effect.sources.isEmpty && effect.sources.length ≤ 64 &&
  !effect.destination.acceptedOwners.isEmpty &&
  effect.destination.acceptedOwners.length ≤ 64 &&
  (effect.destination.acceptedOwners.all uidNonempty) &&
  (effect.sources.all fun source =>
    uidNonempty source.resource && uidNonempty source.owner && !source.tenant.isEmpty) &&
  decide (effect = claim.effect) && claim.allowed &&
  current.policyRoot == effect.policyRoot &&
  current.lineageRevision == effect.lineageRevision &&
  current.epoch == claim.epoch && current.now < claim.expiresAt &&
  (effect.sources.all fun source => !source.restricted) &&
  ({ digest := effect.snapshotCid, sources := effect.sources } : DerivedArtifact).canFlowTo
    effect.destination

end CedarPooSpec.Data
