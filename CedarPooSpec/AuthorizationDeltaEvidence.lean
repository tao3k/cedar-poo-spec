import CedarPooSpec.AuthorizationDelta
import LeanPoo.Proof.Invalidation

/-!
Explain a symbolic authorization delta using the same C4 compilation and
proof-dependency structures that produced its policy revision. Edit provenance
identifies candidate changes; it does not claim that one edit alone caused a
symbolic witness when multiple policy bodies changed.
-/

namespace CedarPooSpec.AuthorizationDelta

open Cedar.Spec CedarPooSpec.PolicyModules LeanPoo.Proof

/-- One policy body's owner metadata in a compiled C4 root. -/
structure PolicyOwner where
  introducedBy : String
  lastEditedBy : String
  deriving DecidableEq, Repr

/-- The three native POO policy edit forms. -/
inductive EditKind where
  | extend | overlay | remove
  deriving DecidableEq, Repr

/-- One applied POO operation affecting a policy ID. -/
structure EditSource where
  moduleName : String
  operation : EditKind
  deriving DecidableEq, Repr

/-- The before and after provenance of one changed policy body. -/
structure PolicyChange where
  id : PolicyID
  beforeOwner : Option PolicyOwner
  afterOwner : Option PolicyOwner
  beforeEdits : List EditSource
  afterEdits : List EditSource
  deriving Repr

private def owner? (compilation : Compilation) (id : PolicyID) : Option PolicyOwner :=
  (compilation.policies.find? (fun entry => entry.policy.id == id)).map fun entry =>
    ⟨entry.introducedBy, entry.lastEditedBy⟩

private def editSource (applied : AppliedEdit) : EditSource :=
  { moduleName := applied.moduleName
    operation := match applied.edit with
      | .extend _ => .extend
      | .overlay _ => .overlay
      | .remove _ => .remove }

private def editsFor (compilation : Compilation) (id : PolicyID) : List EditSource :=
  (compilation.applied.filter (fun entry => entry.edit.policyId == id)).map editSource

/-- Policy-body changes with both compiled owners and edit trails. -/
def Revision.policyChanges (revision : Revision) : List PolicyChange :=
  revision.changedPolicyIds.map fun id =>
    { id
      beforeOwner := owner? revision.before id
      afterOwner := owner? revision.after id
      beforeEdits := editsFor revision.before id
      afterEdits := editsFor revision.after id }

/-- Exact policy bodies needing new per-policy validation, plus the unchanged
    bodies whose certified validation can be reused with the same schema. -/
structure ProofFootprint where
  freshPolicyIds : List PolicyID
  reusedPolicyIds : List PolicyID
  authorizationDependencies : List CedarPooSpec.Soundness.AuthorizationKey

/-- Derive validation reuse and authorization invalidation from the existing
    proof-object patches rather than a second dependency model. -/
def Revision.proofFootprint (revision : Revision) : ProofFootprint :=
  { freshPolicyIds := revision.freshPolicies.map Policy.id
    reusedPolicyIds := (revision.afterPolicies.filter fun policy =>
      decide (policy ∈ revision.beforePolicies)).map Policy.id
    authorizationDependencies := changedDependencies
      CedarPooSpec.Soundness.policiesObligation revision.authorizationPatch }

/-- C4 descendants whose compilation may depend on the modules that last
    edited a changed policy. This is an invalidation set, not a behavioral
    witness or proof of individual edit causality. -/
def affectedRoots (model : Model) (changes : List PolicyChange) : List String :=
  let owners := changes.filterMap fun change =>
    match change.afterEdits.getLast? with
    | some source => some source.moduleName
    | none => change.beforeEdits.getLast?.map (·.moduleName)
  invalidatedNodes model.graph owners

/-- Symbolic result together with C4 provenance and proof-reuse footprint. -/
structure ExplainedReport where
  beforeRoot : String
  afterRoot : String
  symbolic : Report
  changes : List PolicyChange
  proof : ProofFootprint
  potentiallyInvalidatedRoots : List String

/-- Both authorization directions with the same C4 and proof evidence. -/
structure ExplainedImpactReport where
  beforeRoot : String
  afterRoot : String
  symbolic : ImpactReport
  changes : List PolicyChange
  proof : ProofFootprint
  potentiallyInvalidatedRoots : List String

/-- Compile one POO revision once, run Cedar's symbolic implication query,
    and attach the exact owner and dependency metadata of that revision. -/
def analyzeModelExplained (model : Model) (beforeRoot afterRoot : String)
    (schema : Cedar.Validation.Schema) : IO (Except Error ExplainedReport) := do
  let revision ← match model.compileRevision beforeRoot afterRoot with
    | .ok revision => pure revision
    | .error error => return .error (.compilation error)
  let result ← analyze revision schema
  return result.map fun symbolic =>
    let changes := Revision.policyChanges revision
    { beforeRoot, afterRoot, symbolic, changes
      proof := Revision.proofFootprint revision
      potentiallyInvalidatedRoots := affectedRoots model changes }

/-- Query gains and losses, retaining the revision's owner, patch, and proof
    footprint. An empty pair of witness lists means no change in the covered
    Cedar schema environments, subject to the solver boundary. -/
def analyzeModelImpactExplained (model : Model) (beforeRoot afterRoot : String)
    (schema : Cedar.Validation.Schema) : IO (Except Error ExplainedImpactReport) := do
  let revision ← match model.compileRevision beforeRoot afterRoot with
    | .ok revision => pure revision
    | .error error => return .error (.compilation error)
  let result ← analyzeImpact revision schema
  return result.map fun symbolic =>
    let changes := Revision.policyChanges revision
    { beforeRoot, afterRoot, symbolic, changes
      proof := Revision.proofFootprint revision
      potentiallyInvalidatedRoots := affectedRoots model changes }

end CedarPooSpec.AuthorizationDelta
