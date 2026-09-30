import CedarPooSpec.Data.ProtectedStorage

/-!
Provider-neutral protected read projection. Reading requires a new decision
for the exact committed publication and reader. A write approval, commit
replay, ciphertext cache hit, or possession of a key is not read authority.
The Host authenticates the ledger row, current lineage, reader and claim.
-/

namespace CedarPooSpec.Data

open Cedar.Spec

structure ProtectedReadIntentV1 where
  operationId : String
  subject : EntityUID
  purpose : String
  publication : ProtectedPublicationV1
  reader : Destination
  policyRoot : String
  lineageRevision : String
  deriving DecidableEq

structure ProtectedReadClaimV1 where
  intent : ProtectedReadIntentV1
  epoch : Nat
  expiresAt : Nat
  allowed : Bool
  deriving DecidableEq

private def uidNonempty (uid : EntityUID) : Bool :=
  !(toString uid.ty).isEmpty && !uid.eid.isEmpty

private def readerWellFormed (reader : Destination) : Bool :=
  uidNonempty reader.resource && !reader.tenant.isEmpty &&
  !reader.acceptedOwners.isEmpty && reader.acceptedOwners.length ≤ 64 &&
  reader.acceptedOwners.all uidNonempty

/-- A new read needs an authenticated, exact committed row and current
    authorization for its own actor, purpose and reader. This check precedes
    both cache and provider GET; it does not authenticate its Host inputs. -/
def ProtectedReadIntentV1.admitted (read : ProtectedReadIntentV1)
    (claim : ProtectedReadClaimV1) (current : CurrentStorageStateV1)
    (committed : Option ProtectedCommitReceiptV1) : Bool :=
  !read.operationId.isEmpty && uidNonempty read.subject &&
  !read.purpose.isEmpty && !read.policyRoot.isEmpty &&
  !read.lineageRevision.isEmpty && readerWellFormed read.reader &&
  read.publication.wellFormed &&
  (match committed with
   | some receipt => receipt.publication == read.publication &&
       receipt.totalOuterBytes > 0 && receipt.childCount ≤ 4096
   | none => false) &&
  decide (claim.intent = read) && claim.allowed &&
  current.policyRoot == read.policyRoot &&
  current.lineageRevision == read.lineageRevision &&
  current.epoch == claim.epoch && current.now < claim.expiresAt &&
  ({ digest := read.publication.intent.storage.snapshotCid,
     sources := read.publication.intent.storage.sources } : DerivedArtifact).canFlowTo read.reader

end CedarPooSpec.Data
