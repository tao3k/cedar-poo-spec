import CedarPooSpec.Cloud.Pipeline.ReleaseBoundary
import CedarPooSpec.Cloud.Pipeline.Evidence
import CedarPooSpec.PolicyJson

/-!
Synthetic pipeline release based on Google Cloud Threat Intelligence's 2026
cross-stage hardening guidance. No real Google, GitHub, or registry state is
read here; the Host must attest the projected facts and execute the effect.
-/

namespace CedarPooSpec.Cloud.Pipeline.GoogleThreatCase

open Cedar.Spec Cedar.Data Cedar.Validation CedarPooSpec.PolicyModules
open CedarPooSpec.Cloud.Pipeline CedarPooSpec.Governance

def builderType : EntityType := ⟨"Builder", []⟩
def artifactType : EntityType := ⟨"Artifact", []⟩
def provenanceType : EntityType := ⟨"Provenance", []⟩
def actionType : EntityType := ⟨"Action", []⟩
def builder : EntityUID := ⟨builderType, "release-bot"⟩
def candidate : EntityUID := ⟨artifactType, "service-release"⟩
def unaffected : EntityUID := ⟨artifactType, "independent-release"⟩
def promote : EntityUID := ⟨actionType, "promote"⟩
def candidateProvenance : EntityUID := ⟨provenanceType, "candidate-build"⟩
def independentProvenance : EntityUID := ⟨provenanceType, "independent-build"⟩
def substitutedSource : EntityUID := ⟨provenanceType, "other-source"⟩
def substitutedWorkflow : EntityUID := ⟨provenanceType, "other-workflow"⟩
def substitutedAudience : EntityUID := ⟨provenanceType, "other-audience"⟩
def substitutedBuilder : EntityUID := ⟨provenanceType, "other-builder"⟩
def substitutedSubject : EntityUID := ⟨provenanceType, "other-subject"⟩

def fields : List String := ProvenanceClaim.fields

def signals : List String :=
  ["reviewed", "protectedRef", "lockVerified",
    "dependenciesQuarantined", "actionsPinned", "ephemeralRunner",
    "cacheIsolated", "untrustedPrBlocked", "signatureVerified",
    "provenanceVerified", "incidentActive"]

def contextType : RecordType := Map.make
  (fields.map (fun key => (key, .required .string)) ++
    signals.map (fun key => (key, .required (.bool .anyBool))) ++
    [("provenance", .required (.entity provenanceType))])

def artifactEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.make
    (fields.map (fun key => (key, .required .string)) ++
      [("affected", .required (.bool .anyBool))]), none⟩

def provenanceEntry : EntitySchemaEntry := ProvenanceClaim.schemaEntry

def actionEntry : ActionSchemaEntry :=
  ⟨Set.make [builderType], Set.make [artifactType], Set.empty, contextType⟩

def schema : Schema :=
  ⟨Map.make [(builderType, .standard ⟨Set.empty, Map.empty, none⟩),
    (artifactType, artifactEntry), (provenanceType, provenanceEntry)],
    Map.make [(promote, actionEntry)]⟩

structure Target extends ProvenanceClaim where
  sourceRepository : String := "repo-a"
  sourceCommit : String := "commit-a"
  workflow : String := "release-workflow"
  lockDigest : String := "lock-a"
  oidcAudience : String := "registry-release"
  buildType : String := "trusted-build"
  artifactDigest : String := "sha256:candidate"
  builderIdentity : String := "trusted-builder"
  affected : Bool := true

def targetValues (target : Target) : List (String × Value) :=
  target.toProvenanceClaim.values

def artifactData (target : Target) : EntityData :=
  { attrs := Map.make (targetValues target ++
      [("affected", .prim (.bool target.affected))]),
    ancestors := Set.empty, tags := Map.empty }

def provenanceData (target : Target) : EntityData :=
  target.toProvenanceClaim.entityData

def emptyData : EntityData :=
  { attrs := Map.empty, ancestors := Set.empty, tags := Map.empty }

def entities : Entities := Map.make
  [(builder, emptyData),
   (candidate, artifactData {}),
   (unaffected, artifactData
     { sourceCommit := "commit-b", lockDigest := "lock-b",
       artifactDigest := "sha256:independent", affected := false }),
   (candidateProvenance, provenanceData {}),
   (independentProvenance, provenanceData
     { sourceCommit := "commit-b", lockDigest := "lock-b",
       artifactDigest := "sha256:independent" }),
   (substitutedSource, provenanceData { sourceCommit := "other-commit" }),
   (substitutedWorkflow, provenanceData { workflow := "other-workflow" }),
   (substitutedAudience, provenanceData { oidcAudience := "other-audience" }),
   (substitutedBuilder, provenanceData { builderIdentity := "other-builder" }),
   (substitutedSubject, provenanceData { artifactDigest := "sha256:other" }),
   (promote, actionSchemaEntryToEntityData actionEntry)]

structure Facts extends Target where
  provenance : EntityUID := candidateProvenance
  reviewed : Bool := true
  protectedRef : Bool := true
  lockVerified : Bool := true
  dependenciesQuarantined : Bool := true
  actionsPinned : Bool := true
  ephemeralRunner : Bool := true
  cacheIsolated : Bool := true
  untrustedPrBlocked : Bool := true
  signatureVerified : Bool := true
  provenanceVerified : Bool := true
  incidentActive : Bool := false

def context (facts : Facts) : Map String Value := Map.make
  (targetValues facts.toTarget ++
   [("reviewed", .prim (.bool facts.reviewed)),
    ("protectedRef", .prim (.bool facts.protectedRef)),
    ("lockVerified", .prim (.bool facts.lockVerified)),
    ("dependenciesQuarantined", .prim (.bool facts.dependenciesQuarantined)),
    ("actionsPinned", .prim (.bool facts.actionsPinned)),
    ("ephemeralRunner", .prim (.bool facts.ephemeralRunner)),
    ("cacheIsolated", .prim (.bool facts.cacheIsolated)),
    ("untrustedPrBlocked", .prim (.bool facts.untrustedPrBlocked)),
    ("signatureVerified", .prim (.bool facts.signatureVerified)),
    ("provenanceVerified", .prim (.bool facts.provenanceVerified)),
    ("incidentActive", .prim (.bool facts.incidentActive)),
    ("provenance", .prim (.entityUID facts.provenance))])

def request (resource : EntityUID) (facts : Facts) : Request :=
  ⟨builder, promote, resource, context facts⟩

def grant : Policy :=
  { id := "candidate-promotion", effect := .permit,
    principalScope := .principalScope (.eq builder),
    actionScope := .actionScope (.eq promote),
    resourceScope := .resourceScope (.is artifactType), condition := [] }

def boundary (stage : Stage) : ReleaseBoundary :=
  { policyId := s!"pipeline-{stage.name}"
    actionScope := .actionScope (.eq promote)
    resourceScope := .resourceScope (.is artifactType)
    stage }

def incident : Veto :=
  { policyId := "affected-artifact-quarantine",
    actionScope := .actionScope (.eq promote),
    resourceScope := .resourceScope (.is artifactType),
    denyWhen := .and (.getAttr (.var .resource) "affected")
      (.getAttr (.var .context) "incidentActive") }

/-- Independent stage owners become one C4 policy object; later incident and
    recovery revisions leave every unaffected stage owner reusable. -/
def modelResult : Except LeanPoo.Object.CombineError Model := do
  let base ← (Model.define "Base" [.extend grant]).mapError .c4
  let source ← (Model.define "Source" [(boundary .source).veto.edit .introduce]).mapError .c4
  let dependency ← (Model.define "Dependencies"
    [(boundary .dependencies).veto.edit .introduce]).mapError .c4
  let runner ← (Model.define "Runner" [(boundary .runner).veto.edit .introduce]).mapError .c4
  let artifact ← (Model.define "Artifact" [(boundary .artifact).veto.edit .introduce]).mapError .c4
  let provenance ← (Model.define "Provenance"
    [(boundary .provenance).veto.edit .introduce]).mapError .c4
  let sourceBound ← base.combine "Base" [(source, "Source")] "SourceBound"
  let dependencyBound ← sourceBound.combine "SourceBound"
    [(dependency, "Dependencies")] "DependencyBound"
  let runnerBound ← dependencyBound.combine "DependencyBound"
    [(runner, "Runner")] "RunnerBound"
  let artifactBound ← runnerBound.combine "RunnerBound"
    [(artifact, "Artifact")] "ArtifactBound"
  let releaseReady ← artifactBound.combine "ArtifactBound"
    [(provenance, "Provenance")] "ReleaseReady"
  let quarantined ← (releaseReady.extend "Quarantined" "ReleaseReady"
    [incident.edit .introduce]).mapError .c4
  (quarantined.extend "Recovered" "Quarantined"
    [incident.edit .withdraw]).mapError .c4

def model : Model := modelResult.toOption.get (by native_decide)

def allowed (root : String) (resource : EntityUID) (facts : Facts) : Bool :=
  match model.compile root with
  | .error _ => false
  | .ok policies =>
      let response := isAuthorized (request resource facts) entities policies
      response.decision == .allow && response.erroringPolicies.isEmpty

def independentFacts : Facts :=
  { sourceCommit := "commit-b", lockDigest := "lock-b",
    artifactDigest := "sha256:independent", affected := false,
    provenance := independentProvenance }

def cases : List (String × String × EntityUID × Facts × Bool) := [
  ("base-accepts-wrong-commit", "Base", candidate,
    { sourceCommit := "other-commit" }, true),
  ("source-blocks-wrong-commit", "SourceBound", candidate,
    { sourceCommit := "other-commit" }, false),
  ("source-blocks-unreviewed-change", "SourceBound", candidate,
    { reviewed := false }, false),
  ("source-blocks-other-workflow", "SourceBound", candidate,
    { workflow := "untrusted-workflow" }, false),
  ("source-blocks-other-repository", "SourceBound", candidate,
    { sourceRepository := "other-repository" }, false),
  ("source-alone-misses-poisoned-package", "SourceBound", candidate,
    { dependenciesQuarantined := false }, true),
  ("dependency-blocks-poisoned-package", "DependencyBound", candidate,
    { dependenciesQuarantined := false }, false),
  ("dependency-blocks-mutable-action", "DependencyBound", candidate,
    { actionsPinned := false }, false),
  ("dependency-alone-misses-cache-poison", "DependencyBound", candidate,
    { cacheIsolated := false }, true),
  ("runner-blocks-cache-poison", "RunnerBound", candidate,
    { cacheIsolated := false }, false),
  ("runner-blocks-untrusted-pr", "RunnerBound", candidate,
    { untrustedPrBlocked := false }, false),
  ("runner-blocks-wrong-audience", "RunnerBound", candidate,
    { oidcAudience := "other-registry" }, false),
  ("runner-alone-misses-false-provenance", "RunnerBound", candidate,
    { provenanceVerified := false }, true),
  ("artifact-alone-misses-false-provenance", "ArtifactBound", candidate,
    { provenanceVerified := false }, true),
  ("provenance-blocks-unverified-claim", "ReleaseReady", candidate,
    { provenanceVerified := false }, false),
  ("artifact-alone-misses-source-substitution", "ArtifactBound", candidate,
    { provenance := substitutedSource }, true),
  ("provenance-blocks-source-substitution", "ReleaseReady", candidate,
    { provenance := substitutedSource }, false),
  ("provenance-blocks-workflow-substitution", "ReleaseReady", candidate,
    { provenance := substitutedWorkflow }, false),
  ("provenance-blocks-audience-substitution", "ReleaseReady", candidate,
    { provenance := substitutedAudience }, false),
  ("provenance-blocks-builder-substitution", "ReleaseReady", candidate,
    { provenance := substitutedBuilder }, false),
  ("provenance-blocks-subject-substitution", "ReleaseReady", candidate,
    { provenance := substitutedSubject }, false),
  ("artifact-blocks-unsigned-output", "ReleaseReady", candidate,
    { signatureVerified := false }, false),
  ("artifact-blocks-replaced-digest", "ReleaseReady", candidate,
    { artifactDigest := "sha256:replaced" }, false),
  ("artifact-blocks-wrong-builder", "ReleaseReady", candidate,
    { builderIdentity := "unexpected-builder" }, false),
  ("artifact-blocks-wrong-build-type", "ReleaseReady", candidate,
    { buildType := "untrusted-build" }, false),
  ("ready-promotion", "ReleaseReady", candidate, {}, true),
  ("incident-quarantines-affected", "Quarantined", candidate,
    { incidentActive := true }, false),
  ("incident-preserves-independent", "Quarantined", unaffected,
    { independentFacts with incidentActive := true }, true),
  ("recovery-restores-affected", "Recovered", candidate,
    { incidentActive := true }, true),
  ("recovery-keeps-cache-isolation", "Recovered", candidate,
    { cacheIsolated := false }, false)]

end CedarPooSpec.Cloud.Pipeline.GoogleThreatCase
