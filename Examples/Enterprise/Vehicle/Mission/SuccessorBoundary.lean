import CedarPooSpec.Revision
import CedarPooSpec.PolicyJson
import CedarPooSpec.CompoundAuthorization
import Cedar.Validation.RequestEntityValidator

/-!
Tsai and Hariri (2026) study high-level driving commands that remain locally
safe but make a mission infeasible. This example projects a finite successor
summary into Cedar authorization. The paper uses fault injection, not a VLA
prompt-injection experiment; the VLA connection is a proposed application.
-/

namespace CedarPooSpec.SuccessorBoundaryExample

open Cedar.Spec Cedar.Data Cedar.Validation CedarPooSpec.PolicyModules
open CedarPooSpec.Soundness CedarPooSpec.PolicyValidation LeanPoo.Proof

def plannerType : EntityType := ⟨"MissionPlanner", []⟩
def routeType : EntityType := ⟨"RouteCandidate", []⟩
def actionType : EntityType := ⟨"Action", []⟩
def planner : EntityUID := ⟨plannerType, "untrusted-planner"⟩
def route : EntityUID := ⟨routeType, "proposed-route"⟩
def proceed : EntityUID := ⟨actionType, "proceed"⟩
def fallback : EntityUID := ⟨actionType, "fallback-handoff"⟩

def emptyEntry : EntitySchemaEntry := .standard ⟨Set.empty, Map.empty, none⟩
def contextType : RecordType := Map.make [
  ("routeApproved", .required (.bool .anyBool)),
  ("successorPlatformSafe", .required (.bool .anyBool)),
  ("successorMissionFeasible", .required (.bool .anyBool)),
  ("witnessBound", .required (.bool .anyBool)),
  ("horizonCurrent", .required (.bool .anyBool))]
def actionEntry : ActionSchemaEntry :=
  ⟨Set.make [plannerType], Set.make [routeType], Set.empty, contextType⟩
def schema : Schema :=
  ⟨Map.make [(plannerType, emptyEntry), (routeType, emptyEntry)],
    Map.make [(proceed, actionEntry), (fallback, actionEntry)]⟩
def emptyData : EntityData :=
  { attrs := Map.empty, ancestors := Set.empty, tags := Map.empty }
def entities : Entities := Map.make [
  (planner, emptyData), (route, emptyData),
  (proceed, actionSchemaEntryToEntityData actionEntry),
  (fallback, actionSchemaEntryToEntityData actionEntry)]

/- Each element is one predicted successor, not a sensor measurement. -/
structure Successor where
  collisionClear : Bool := true
  roadClear : Bool := true
  checkpointReachable : Bool := true
  restrictedClear : Bool := true
  budgetEnough : Bool := true
  deriving DecidableEq, Repr

def platformSafe (steps : List Successor) : Bool :=
  !steps.isEmpty && steps.all (fun step => step.collisionClear && step.roadClear)
def missionFeasible (steps : List Successor) : Bool :=
  !steps.isEmpty && steps.all (fun step =>
    step.checkpointReachable && step.restrictedClear && step.budgetEnough)

structure Candidate where
  steps : List Successor
  routeApproved : Bool := true
  witnessBound : Bool := true
  horizonCurrent : Bool := true

def request (action : EntityUID) (candidate : Candidate) : Request :=
  ⟨planner, action, route, Map.make [
    ("routeApproved", .prim (.bool candidate.routeApproved)),
    ("successorPlatformSafe", .prim (.bool (platformSafe candidate.steps))),
    ("successorMissionFeasible", .prim (.bool (missionFeasible candidate.steps))),
    ("witnessBound", .prim (.bool candidate.witnessBound)),
    ("horizonCurrent", .prim (.bool candidate.horizonCurrent))]⟩

def ctx (name : String) : Expr := .getAttr (.var .context) name
def neg (body : Expr) : Expr := .unaryApp .not body
def policy (id : String) (effect : Effect) (action : EntityUID)
    (body : Expr) : Policy :=
  { id, effect,
    principalScope := .principalScope (.eq planner),
    actionScope := .actionScope (.eq action),
    resourceScope := .resourceScope .any,
    condition := [{ kind := .when, body }] }

def nominal : Policy :=
  policy "nominal-route" .permit proceed (ctx "routeApproved")
def safeFallback : Policy :=
  policy "fallback-handoff" .permit fallback (.lit (.bool true))
def platformChecked : Policy :=
  { nominal with condition := [
      { kind := .when,
        body := .and (ctx "routeApproved") (ctx "successorPlatformSafe") }] }
def missionVeto : Policy :=
  policy "mission-infeasible" .forbid proceed
    (neg (ctx "successorMissionFeasible"))
def evidenceVeto : Policy :=
  policy "unbound-successor-witness" .forbid proceed
    (neg (ctx "witnessBound"))
def currentEvidenceVeto : Policy :=
  { evidenceVeto with condition := [
      { kind := .when,
        body := neg (.and (ctx "witnessBound") (ctx "horizonCurrent")) }] }

def model : Model := { modules := [
  { name := "Base", edits := [.extend nominal, .extend safeFallback] },
  { name := "Platform", parentOrders := [["Base"]],
    edits := [.overlay platformChecked] },
  { name := "Mission", parentOrders := [["Base"]],
    edits := [.extend missionVeto] },
  { name := "Evidence", parentOrders := [["Base"]],
    edits := [.extend evidenceVeto] },
  { name := "Integrated", parentOrders := [["Platform", "Mission", "Evidence"]] },
  { name := "Current", parentOrders := [["Integrated"]],
    edits := [.overlay currentEvidenceVeto] }] }

def authorized (root : String) (action : EntityUID) (candidate : Candidate) : Bool :=
  match CedarPooSpec.CompoundAuthorization.authorizeLayers model
      [(root, request action candidate)] entities with
  | .error _ => false
  | .ok receipts => CedarPooSpec.CompoundAuthorization.layersAllowed receipts

def clear : Candidate := { steps := [{}, {}] }
def collision : Candidate :=
  { steps := [{}, { collisionClear := false }] }
def roadExit : Candidate :=
  { steps := [{}, { roadClear := false }] }
def skippedCheckpoint : Candidate :=
  { steps := [{}, { checkpointReachable := false }] }
def restrictedRegion : Candidate :=
  { steps := [{}, { restrictedClear := false }] }
def depletedBudget : Candidate :=
  { steps := [{}, { budgetEnough := false }] }
def unbound : Candidate := { clear with witnessBound := false }
def stale : Candidate := { clear with horizonCurrent := false }
def emptyHorizon : Candidate := { steps := [] }

def cases : List (String × String × EntityUID × Candidate × Bool) := [
  ("base-misses-future-collision", "Base", proceed, collision, true),
  ("platform-blocks-future-collision", "Platform", proceed, collision, false),
  ("platform-misses-checkpoint", "Platform", proceed, skippedCheckpoint, true),
  ("mission-blocks-checkpoint", "Mission", proceed, skippedCheckpoint, false),
  ("mission-misses-future-collision", "Mission", proceed, collision, true),
  ("evidence-blocks-unbound-witness", "Evidence", proceed, unbound, false),
  ("integrated-allows-admissible", "Integrated", proceed, clear, true),
  ("integrated-blocks-collision", "Integrated", proceed, collision, false),
  ("integrated-blocks-road-exit", "Integrated", proceed, roadExit, false),
  ("integrated-blocks-skipped-checkpoint", "Integrated", proceed, skippedCheckpoint, false),
  ("integrated-blocks-restricted-region", "Integrated", proceed, restrictedRegion, false),
  ("integrated-blocks-budget-exhaustion", "Integrated", proceed, depletedBudget, false),
  ("integrated-rejects-empty-horizon", "Integrated", proceed, emptyHorizon, false),
  ("integrated-blocks-unbound-witness", "Integrated", proceed, unbound, false),
  ("integrated-allows-stale-horizon", "Integrated", proceed, stale, true),
  ("current-blocks-stale-horizon", "Current", proceed, stale, false),
  ("current-allows-fresh-horizon", "Current", proceed, clear, true),
  ("current-keeps-fallback-available", "Current", fallback, collision, true)]

def casesExact : Bool := cases.all fun (_, root, action, candidate, expected) =>
  authorized root action candidate == expected
theorem casesExactFully : casesExact = true := by native_decide

def matrixColumns : List (String × Candidate) := [
  ("collision", collision), ("checkpoint", skippedCheckpoint),
  ("restricted", restrictedRegion), ("budget", depletedBudget),
  ("clear", clear), ("unbound", unbound), ("stale", stale)]
def matrixExpectations : List (String × List Bool) := [
  ("Base",       [true,  true,  true,  true,  true, true,  true]),
  ("Platform",   [false, true,  true,  true,  true, true,  true]),
  ("Mission",    [true,  false, false, false, true, true,  true]),
  ("Evidence",   [true,  true,  true,  true,  true, false, true]),
  ("Integrated", [false, false, false, false, true, false, true]),
  ("Current",    [false, false, false, false, true, false, false])]
def matrixCases : List (String × String × EntityUID × Candidate × Bool) :=
  matrixExpectations.flatMap fun (root, expected) =>
    (matrixColumns.zip expected).map fun ((label, candidate), allow) =>
      (s!"matrix-{root.toLower}-{label}", root, proceed, candidate, allow)
theorem matrixComplete : matrixCases.length = 42 := by native_decide
theorem matrixExact :
    matrixCases.all (fun (_, root, action, candidate, expected) =>
      authorized root action candidate == expected) = true := by native_decide

def rootsValidated : Bool :=
  ["Base", "Platform", "Mission", "Evidence", "Integrated", "Current"].all fun root =>
    (CedarPooSpec.PolicyJson.publish model root schema).isOk
theorem rootsValidatedFully : rootsValidated = true := by native_decide

def freshnessRevision : Revision :=
  (model.compileRevision "Integrated" "Current").toOption.get (by native_decide)
theorem freshnessDelta :
    freshnessRevision.changedPolicyIds = [evidenceVeto.id] ∧
    freshnessRevision.freshPolicies = [currentEvidenceVeto] := by native_decide

def witness : Request := request proceed stale
def before : AuthorizationSnapshot :=
  freshnessRevision.beforeSnapshot schema witness entities
theorem baselineCertificate : Certificate before.proofObject :=
  before.certificateOfChecks (by native_decide)
private theorem okOfIsOk {ε : Type} (result : Except ε Unit)
    (accepted : result.isOk = true) : result = .ok () := by
  cases result with
  | ok value => cases value; rfl
  | error _ => cases accepted
theorem freshCertificates :
    ∀ p ∈ freshnessRevision.freshPolicies,
      Certificate (Snapshot.mk p schema).proofObject := by
  intro p member
  rw [freshnessDelta.2] at member
  simp only [List.mem_cons, List.not_mem_nil, or_false] at member
  subst p
  exact (Snapshot.mk currentEvidenceVeto schema).certificate
    (okOfIsOk _ (by native_decide))
theorem currentCertificate :
    Certificate (freshnessRevision.afterSnapshot schema witness entities).proofObject :=
  freshnessRevision.authorizationCertificate schema witness entities
    (by simpa [before] using baselineCertificate) freshCertificates
example : Cedar.Thm.AllEvaluateToBool freshnessRevision.afterPolicies witness entities :=
  certifiedAuthorizationSound
    (freshnessRevision.afterSnapshot schema witness entities) currentCertificate

end CedarPooSpec.SuccessorBoundaryExample
