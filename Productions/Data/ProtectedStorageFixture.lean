import CedarPooSpec.Data.ProtectedRead
import Productions.Data.StorageEffectFixture
import Lean

namespace CedarPooSpec.Data.ProtectedStorageFixture

open CedarPooSpec.Data CedarPooSpec.Data.StorageEffectFixture Lean

private def obj (fields : List (String × Json)) : Json := Json.mkObj fields

private def intentJson (intent : ProtectionIntentV1) : Json :=
  obj [("version", toJson (1 : Nat)),
    ("storage", effectJson intent.storage),
    ("profile", toJson intent.profile),
    ("key_ref", toJson intent.keyRef),
    ("key_version", toJson intent.keyVersion),
    ("residency", toJson intent.residency)]

private def claimJson (claim : ProtectionClaimV1) : Json :=
  obj [("intent", intentJson claim.intent),
    ("epoch", toJson claim.epoch),
    ("expires_at", toJson claim.expiresAt),
    ("allowed", toJson claim.allowed)]

private def publicationJson (publication : ProtectedPublicationV1) : Json :=
  obj [("intent", intentJson publication.intent),
    ("outer_root_cid", toJson publication.outerRootCid),
    ("envelope_version", toJson publication.envelopeVersion),
    ("key_version", toJson publication.keyVersion)]

private def ackJson (ack : ProtectedPhysicalAckV1) : Json :=
  obj [("inner_root_cid", toJson ack.innerRootCid),
    ("outer_root_cid", toJson ack.outerRootCid),
    ("child_count", toJson ack.childCount),
    ("total_outer_bytes", toJson ack.totalOuterBytes)]

private def receiptJson (receipt : ProtectedCommitReceiptV1) : Json :=
  obj [("publication", publicationJson receipt.publication),
    ("child_count", toJson receipt.childCount),
    ("total_outer_bytes", toJson receipt.totalOuterBytes)]

private def dispositionJson : ProtectedCommitDispositionV1 → Json
  | .apply => toJson "apply"
  | .replay => toJson "replay"
  | .reject => toJson "reject"

private def readerJson (reader : Destination) : Json :=
  obj [("resource", CedarPooSpec.PolicyJson.entity reader.resource),
    ("tenant", toJson reader.tenant),
    ("accepted_owners", toJson
      (reader.acceptedOwners.map CedarPooSpec.PolicyJson.entity)),
    ("accepts_restricted", toJson reader.acceptsRestricted)]

private def readJson (read : ProtectedReadIntentV1) : Json :=
  obj [("version", toJson (1 : Nat)),
    ("operation_id", toJson read.operationId),
    ("subject", CedarPooSpec.PolicyJson.entity read.subject),
    ("purpose", toJson read.purpose),
    ("publication", publicationJson read.publication),
    ("reader", readerJson read.reader),
    ("policy_root", toJson read.policyRoot),
    ("lineage_revision", toJson read.lineageRevision)]

private def readClaimJson (claim : ProtectedReadClaimV1) : Json :=
  obj [("intent", readJson claim.intent),
    ("epoch", toJson claim.epoch),
    ("expires_at", toJson claim.expiresAt),
    ("allowed", toJson claim.allowed)]

def baseIntent : ProtectionIntentV1 :=
  { storage := { baseEffect with
      sources := [{ baseSource with restricted := true }],
      destination := { baseDestination with acceptsRestricted := true } },
    profile := "aes-256-gcm-v1", keyRef := "key-tenant-a",
    keyVersion := "key-version-7", residency := "us-east-1" }

def baseClaim : ProtectionClaimV1 :=
  { intent := baseIntent, epoch := 4, expiresAt := 100, allowed := true }

def basePublication : ProtectedPublicationV1 :=
  { intent := baseIntent,
    outerRootCid := "bafkreie7vj2rmiytc6plrz7n4bejnug2rzeypl2u3cnibf2aa4dhqdp6u4",
    envelopeVersion := 1, keyVersion := "key-version-7" }

def baseAck : ProtectedPhysicalAckV1 :=
  { innerRootCid := baseIntent.storage.snapshotCid,
    outerRootCid := basePublication.outerRootCid,
    childCount := 2, totalOuterBytes := 256 }

def baseReceipt : ProtectedCommitReceiptV1 :=
  { publication := basePublication, childCount := 2, totalOuterBytes := 256 }

private def readerSubject : Cedar.Spec.EntityUID :=
  ⟨⟨"Service", []⟩, "reader"⟩

def baseRead : ProtectedReadIntentV1 :=
  { operationId := "read-001", subject := readerSubject, purpose := "analysis",
    publication := basePublication, reader := baseIntent.storage.destination,
    policyRoot := "policy-root-1", lineageRevision := "lineage-1" }

def baseReadClaim : ProtectedReadClaimV1 :=
  { intent := baseRead, epoch := 4, expiresAt := 100, allowed := true }

def intentCases : List (String × ProtectionIntentV1 × ProtectionClaimV1 × CurrentStorageStateV1) :=
  [("restricted-accepted", baseIntent, baseClaim, baseCurrent),
   ("unrestricted-accepted", { baseIntent with storage := baseEffect },
      { baseClaim with intent := { baseIntent with storage := baseEffect } }, baseCurrent),
   ("restricted-destination-denied", { baseIntent with
      storage := { baseIntent.storage with destination := baseDestination } },
      { baseClaim with intent := { baseIntent with
        storage := { baseIntent.storage with destination := baseDestination } } }, baseCurrent),
   ("tenant", { baseIntent with storage := { baseIntent.storage with
      sources := [{ baseSource with restricted := true, tenant := "tenant-b" }] } },
      { baseClaim with intent := { baseIntent with storage := { baseIntent.storage with
        sources := [{ baseSource with restricted := true, tenant := "tenant-b" }] } } }, baseCurrent),
   ("profile-substitution", baseIntent,
      { baseClaim with intent := { baseIntent with profile := "other" } }, baseCurrent),
   ("key-substitution", baseIntent,
      { baseClaim with intent := { baseIntent with keyRef := "other" } }, baseCurrent),
   ("key-version-substitution", baseIntent,
      { baseClaim with intent := { baseIntent with keyVersion := "other" } }, baseCurrent),
   ("residency-substitution", baseIntent,
      { baseClaim with intent := { baseIntent with residency := "other" } }, baseCurrent),
   ("stale-policy", baseIntent, baseClaim,
      { baseCurrent with policyRoot := "policy-root-2" }),
   ("stale-lineage", baseIntent, baseClaim,
      { baseCurrent with lineageRevision := "lineage-2" }),
   ("stale-epoch", baseIntent, baseClaim, { baseCurrent with epoch := 5 }),
   ("expired", baseIntent, baseClaim, { baseCurrent with now := 100 }),
   ("denied", baseIntent, { baseClaim with allowed := false }, baseCurrent),
   ("missing-profile", { baseIntent with profile := "" },
      { baseClaim with intent := { baseIntent with profile := "" } }, baseCurrent)]

def publicationCases : List
    (String × ProtectedPublicationV1 × ProtectionClaimV1 × CurrentStorageStateV1) :=
  [("commit", basePublication, baseClaim, baseCurrent),
   ("inner-as-outer", { basePublication with
      outerRootCid := baseIntent.storage.snapshotCid }, baseClaim, baseCurrent),
   ("missing-outer", { basePublication with outerRootCid := "" }, baseClaim, baseCurrent),
   ("version", { basePublication with envelopeVersion := 2 }, baseClaim, baseCurrent),
   ("missing-key-version", { basePublication with keyVersion := "" }, baseClaim, baseCurrent),
   ("different-key-version", { basePublication with keyVersion := "old-version" },
      baseClaim, baseCurrent),
   ("revoked-before-commit", basePublication, baseClaim,
      { baseCurrent with epoch := 5 }),
   ("expired-before-commit", basePublication, baseClaim,
      { baseCurrent with now := 100 }),
   ("different-operation", basePublication,
      { baseClaim with intent := { baseIntent with
        storage := { baseIntent.storage with operationId := "op-002" } } }, baseCurrent)]

def commitCases : List
    (String × ProtectedPublicationV1 × ProtectionClaimV1 × CurrentStorageStateV1 ×
     Option ProtectedPhysicalAckV1 × Option ProtectedCommitReceiptV1) :=
  [("fresh-ack", basePublication, baseClaim, baseCurrent, some baseAck, none),
   ("missing-ack", basePublication, baseClaim, baseCurrent, none, none),
   ("wrong-inner", basePublication, baseClaim, baseCurrent,
      some { baseAck with innerRootCid := basePublication.outerRootCid }, none),
   ("wrong-outer", basePublication, baseClaim, baseCurrent,
      some { baseAck with outerRootCid := baseIntent.storage.snapshotCid }, none),
   ("empty-physical", basePublication, baseClaim, baseCurrent,
      some { baseAck with totalOuterBytes := 0 }, none),
   ("too-many-children", basePublication, baseClaim, baseCurrent,
      some { baseAck with childCount := 4097 }, none),
   ("revoked-after-root", basePublication, baseClaim,
      { baseCurrent with epoch := 5 }, some baseAck, none),
   ("expired-after-root", basePublication, baseClaim,
      { baseCurrent with now := 100 }, some baseAck, none),
   ("denied-after-root", basePublication, { baseClaim with allowed := false },
      baseCurrent, some baseAck, none),
   ("exact-replay-after-expiry", basePublication, baseClaim,
      { baseCurrent with now := 100 }, none, some baseReceipt),
   ("conflicting-root-replay", basePublication, baseClaim, baseCurrent, none,
      some { baseReceipt with publication := { basePublication with
        outerRootCid := baseIntent.storage.snapshotCid } }),
   ("conflicting-operation-replay", basePublication, baseClaim, baseCurrent, none,
      some { baseReceipt with publication := { basePublication with
        intent := { baseIntent with storage := { baseIntent.storage with operationId := "op-002" } } } }),
   ("invalid-receipt", basePublication, baseClaim, baseCurrent, none,
      some { baseReceipt with totalOuterBytes := 0 }),
   ("malformed-replay", { basePublication with envelopeVersion := 2 },
      baseClaim, baseCurrent, none,
      some { baseReceipt with publication := { basePublication with envelopeVersion := 2 } })]

def readCases : List
    (String × ProtectedReadIntentV1 × ProtectedReadClaimV1 × CurrentStorageStateV1 ×
     Option ProtectedCommitReceiptV1) :=
  [("read-allowed", baseRead, baseReadClaim, baseCurrent, some baseReceipt),
   ("fresh-read-after-write-expiry", baseRead,
      { baseReadClaim with epoch := 5, expiresAt := 200 },
      { baseCurrent with epoch := 5, now := 101 }, some baseReceipt),
   ("missing-commit", baseRead, baseReadClaim, baseCurrent, none),
   ("different-root-commit", baseRead, baseReadClaim, baseCurrent,
      some { baseReceipt with publication := { basePublication with
        outerRootCid := baseIntent.storage.snapshotCid } }),
   ("invalid-commit", baseRead, baseReadClaim, baseCurrent,
      some { baseReceipt with totalOuterBytes := 0 }),
   ("stale-policy", baseRead, baseReadClaim,
      { baseCurrent with policyRoot := "policy-root-2" }, some baseReceipt),
   ("stale-lineage", baseRead, baseReadClaim,
      { baseCurrent with lineageRevision := "lineage-2" }, some baseReceipt),
   ("stale-epoch", baseRead, baseReadClaim,
      { baseCurrent with epoch := 5 }, some baseReceipt),
   ("expired", baseRead, baseReadClaim,
      { baseCurrent with now := 100 }, some baseReceipt),
   ("denied", baseRead, { baseReadClaim with allowed := false },
      baseCurrent, some baseReceipt),
   ("claim-other-operation", baseRead,
      { baseReadClaim with intent := { baseRead with operationId := "read-002" } },
      baseCurrent, some baseReceipt),
   ("claim-other-subject", baseRead,
      { baseReadClaim with intent := { baseRead with subject := baseIntent.storage.subject } },
      baseCurrent, some baseReceipt),
   ("reader-tenant", { baseRead with reader :=
      { baseRead.reader with tenant := "tenant-b" } },
      { baseReadClaim with intent := { baseRead with reader :=
        { baseRead.reader with tenant := "tenant-b" } } },
      baseCurrent, some baseReceipt),
   ("reader-owner", { baseRead with reader :=
      { baseRead.reader with acceptedOwners := [] } },
      { baseReadClaim with intent := { baseRead with reader :=
        { baseRead.reader with acceptedOwners := [] } } },
      baseCurrent, some baseReceipt),
   ("restricted-reader", { baseRead with reader :=
      { baseRead.reader with acceptsRestricted := false } },
      { baseReadClaim with intent := { baseRead with reader :=
        { baseRead.reader with acceptsRestricted := false } } },
      baseCurrent, some baseReceipt)]

def fixture : Json :=
  obj [("schema", toJson "cedar-poo-protected-storage-v1"),
    ("intent_cases", toJson (intentCases.map fun (name, intent, claim, current) =>
      obj [("name", toJson name), ("intent", intentJson intent),
        ("claim", claimJson claim), ("current", currentJson current),
        ("allow", toJson (intent.admitted claim current))])),
    ("publication_cases", toJson (publicationCases.map fun (name, publication, claim, current) =>
      obj [("name", toJson name), ("publication", publicationJson publication),
        ("claim", claimJson claim), ("current", currentJson current),
        ("allow", toJson (publication.preRootAdmitted claim current))])),
    ("commit_cases", toJson (commitCases.map fun (name, publication, claim, current,
        physical, existing) =>
      obj [("name", toJson name), ("publication", publicationJson publication),
        ("claim", claimJson claim), ("current", currentJson current),
        ("physical", physical.elim Json.null ackJson),
        ("existing", existing.elim Json.null receiptJson),
        ("disposition", dispositionJson
          (publication.commitDisposition claim current physical existing))])),
    ("read_cases", toJson (readCases.map fun (name, read, claim, current, committed) =>
      obj [("name", toJson name), ("read", readJson read),
        ("claim", readClaimJson claim), ("current", currentJson current),
        ("committed", committed.elim Json.null receiptJson),
        ("allow", toJson (read.admitted claim current committed))]))]

end CedarPooSpec.Data.ProtectedStorageFixture
