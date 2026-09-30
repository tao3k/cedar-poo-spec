import CedarPooSpec.Data.ProtectedStorage
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
          (publication.commitDisposition claim current physical existing))]))]

end CedarPooSpec.Data.ProtectedStorageFixture
