import CedarPooSpec.PolicyJson

/-! Provider-neutral evidence projections for a release pipeline. The Host
authenticates these claims and owns their lifetime; these records only give
Lean and Cedar one stable shape for composition and exact-field comparison. -/

namespace CedarPooSpec.Cloud.Pipeline

open Cedar.Spec Cedar.Data Cedar.Validation

structure ProvenanceClaim where
  sourceRepository : String
  sourceCommit : String
  workflow : String
  lockDigest : String
  oidcAudience : String
  buildType : String
  artifactDigest : String
  builderIdentity : String

def ProvenanceClaim.fields : List String :=
  ["sourceRepository", "sourceCommit", "workflow", "lockDigest",
   "oidcAudience", "buildType", "artifactDigest", "builderIdentity"]

def ProvenanceClaim.values (claim : ProvenanceClaim) : List (String × Value) :=
  [("sourceRepository", .prim (.string claim.sourceRepository)),
   ("sourceCommit", .prim (.string claim.sourceCommit)),
   ("workflow", .prim (.string claim.workflow)),
   ("lockDigest", .prim (.string claim.lockDigest)),
   ("oidcAudience", .prim (.string claim.oidcAudience)),
   ("buildType", .prim (.string claim.buildType)),
   ("artifactDigest", .prim (.string claim.artifactDigest)),
   ("builderIdentity", .prim (.string claim.builderIdentity))]

def ProvenanceClaim.schemaEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.make
    (ProvenanceClaim.fields.map (fun key => (key, .required .string))), none⟩

def ProvenanceClaim.entityData (claim : ProvenanceClaim) : EntityData :=
  { attrs := Map.make claim.values, ancestors := Set.empty, tags := Map.empty }

/-- Host-projected record of the exact change admitted to a protected ref. -/
structure SourceChangeClaim where
  repository : String
  commit : String
  branch : String
  author : String
  reviewer : String
  reviewerHuman : Bool
  policyEpoch : Int64
  reviewApproved : Bool
  checksPassed : Bool
  branchProtected : Bool
  bypassUsed : Bool
  historyRewritten : Bool

def SourceChangeClaim.schemaEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.make [
    ("repository", .required .string),
    ("commit", .required .string),
    ("branch", .required .string),
    ("author", .required .string),
    ("reviewer", .required .string),
    ("reviewerHuman", .required (.bool .anyBool)),
    ("policyEpoch", .required .int),
    ("reviewApproved", .required (.bool .anyBool)),
    ("checksPassed", .required (.bool .anyBool)),
    ("branchProtected", .required (.bool .anyBool)),
    ("bypassUsed", .required (.bool .anyBool)),
    ("historyRewritten", .required (.bool .anyBool))], none⟩

def SourceChangeClaim.entityData (claim : SourceChangeClaim) : EntityData :=
  { attrs := Map.make [
      ("repository", .prim (.string claim.repository)),
      ("commit", .prim (.string claim.commit)),
      ("branch", .prim (.string claim.branch)),
      ("author", .prim (.string claim.author)),
      ("reviewer", .prim (.string claim.reviewer)),
      ("reviewerHuman", .prim (.bool claim.reviewerHuman)),
      ("policyEpoch", .prim (.int claim.policyEpoch)),
      ("reviewApproved", .prim (.bool claim.reviewApproved)),
      ("checksPassed", .prim (.bool claim.checksPassed)),
      ("branchProtected", .prim (.bool claim.branchProtected)),
      ("bypassUsed", .prim (.bool claim.bypassUsed)),
      ("historyRewritten", .prim (.bool claim.historyRewritten))],
    ancestors := Set.empty, tags := Map.empty }

structure AttestationClaim where
  subjectDigest : String
  attestor : String

def AttestationClaim.schemaEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.make [
    ("subjectDigest", .required .string),
    ("attestor", .required .string)], none⟩

def AttestationClaim.entityData (claim : AttestationClaim) : EntityData :=
  { attrs := Map.make [
      ("subjectDigest", .prim (.string claim.subjectDigest)),
      ("attestor", .prim (.string claim.attestor))],
    ancestors := Set.empty, tags := Map.empty }

structure ReleaseReceiptClaim where
  artifactDigest : String
  sourceCommit : String
  policyRoot : String
  epoch : Int64

def ReleaseReceiptClaim.schemaEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.make [
    ("artifactDigest", .required .string),
    ("sourceCommit", .required .string),
    ("policyRoot", .required .string),
    ("epoch", .required .int)], none⟩

def ReleaseReceiptClaim.entityData (claim : ReleaseReceiptClaim) : EntityData :=
  { attrs := Map.make [
      ("artifactDigest", .prim (.string claim.artifactDigest)),
      ("sourceCommit", .prim (.string claim.sourceCommit)),
      ("policyRoot", .prim (.string claim.policyRoot)),
      ("epoch", .prim (.int claim.epoch))],
    ancestors := Set.empty, tags := Map.empty }

end CedarPooSpec.Cloud.Pipeline
