import CedarPooSpec.Data.ProtectedStorage

/-!
Provider-neutral protected read projection. Reading requires a new decision
for the exact committed receipt and reader. A write approval, commit
replay, ciphertext cache hit, or possession of a key is not read authority.
The Host authenticates the ledger row, current lineage, reader and claim.
-/

namespace CedarPooSpec.Data

open Cedar.Spec

structure ProtectedReadIntent where
  operationId : String
  subject : EntityUID
  purpose : String
  receipt : ProtectedCommitReceipt
  reader : Destination
  policyRoot : String
  lineageRevision : String
  deriving DecidableEq

structure ProtectedReadClaim where
  intent : ProtectedReadIntent
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
def ProtectedReadIntent.admitted (read : ProtectedReadIntent)
    (claim : ProtectedReadClaim) (current : CurrentStorageState)
    (committed : Option ProtectedCommitReceipt) : Bool :=
  !read.operationId.isEmpty && uidNonempty read.subject &&
  !read.purpose.isEmpty && !read.policyRoot.isEmpty &&
  !read.lineageRevision.isEmpty && readerWellFormed read.reader &&
  read.receipt.publication.wellFormed &&
  read.receipt.totalOuterBytes > 0 && read.receipt.childCount ≤ 4096 &&
  (match committed with
   | some receipt => decide (receipt = read.receipt)
   | none => false) &&
  decide (claim.intent = read) && claim.allowed &&
  current.policyRoot == read.policyRoot &&
  current.lineageRevision == read.lineageRevision &&
  current.epoch == claim.epoch && current.now < claim.expiresAt &&
  ({ digest := read.receipt.publication.intent.storage.snapshotCid,
     sources := read.receipt.publication.intent.storage.sources } : DerivedArtifact).canFlowTo read.reader

/-- A read may release plaintext only when the same claim and exact committed
    receipt remain current after all cache/provider I/O and verification.
    The Host supplies two independently refreshed, authenticated observations. -/
def ProtectedReadIntent.releaseAdmitted (read : ProtectedReadIntent)
    (claim : ProtectedReadClaim)
    (before after : CurrentStorageState)
    (committedBefore committedAfter : Option ProtectedCommitReceipt) : Bool :=
  read.admitted claim before committedBefore &&
  before.now ≤ after.now &&
  read.admitted claim after committedAfter

end CedarPooSpec.Data
