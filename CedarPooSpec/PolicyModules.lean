import Cedar.Spec.Policy
import LeanPoo.C4.Linearize

/-!
C4 composes policy-producing modules. Edit intent is explicit; the result is
an ordinary Cedar policy set, and Cedar still owns permit/forbid aggregation.
-/

namespace CedarPooSpec.PolicyModules

open Cedar.Spec

inductive Edit where
  | extend (policy : Policy)
  | overlay (policy : Policy)
  | remove (policyId : PolicyID)

/-- Lift a generated policy family into explicit POO edits. -/
def Edit.extendAll (policies : Policies) : List Edit :=
  policies.map Edit.extend

def Edit.overlayAll (policies : Policies) : List Edit :=
  policies.map Edit.overlay

structure Module where
  name : String
  parentOrders : List (List String) := []
  suffix : Bool := false
  edits : List Edit := []

def Module.node (module : Module) : LeanPoo.C4.Node :=
  { name := module.name, parentOrders := module.parentOrders,
    suffix := module.suffix }

structure Model where
  modules : List Module

def Model.graph (model : Model) : LeanPoo.C4.Graph :=
  { nodes := model.modules.map Module.node }

inductive Error where
  | c4 (error : LeanPoo.C4.Error)
  | missingModule (name : String)
  | policyAlreadyExists (id : PolicyID)
  | missingPolicy (id : PolicyID)
  | competingEdits (id previousOwner currentOwner : String)
  | duplicateInputIds (side : String)
  | unrepresentableOrder
  deriving Repr, BEq

/-- A surviving policy and the modules responsible for its origin and latest edit. -/
structure CompiledPolicy where
  policy : Policy
  introducedBy : String
  lastEditedBy : String

structure AppliedEdit where
  moduleName : String
  edit : Edit

structure Compilation where
  policies : List CompiledPolicy
  applied : List AppliedEdit

private def applyEdit (owner : String) (ancestors : List String)
    (current : List CompiledPolicy) : Edit → Except Error (List CompiledPolicy)
  | .extend policy =>
      if current.any (fun entry => entry.policy.id == policy.id) then
        .error (.policyAlreadyExists policy.id)
      else .ok (current ++ [{ policy, introducedBy := owner, lastEditedBy := owner }])
  | .overlay policy => do
      let some previous := current.find? (fun entry => entry.policy.id == policy.id)
        | throw (.missingPolicy policy.id)
      if !ancestors.contains previous.lastEditedBy then
        throw (.competingEdits policy.id previous.lastEditedBy owner)
      return current.map fun entry =>
        if entry.policy.id == policy.id then
          { entry with policy := policy, lastEditedBy := owner }
        else entry
  | .remove id => do
      let some previous := current.find? (fun entry => entry.policy.id == id)
        | throw (.missingPolicy id)
      if !ancestors.contains previous.lastEditedBy then
        throw (.competingEdits id previous.lastEditedBy owner)
      return current.filter (fun entry => entry.policy.id != id)

/-- Apply inherited modules base first, retaining surviving policies and edits. -/
def Model.compileWithTrace (model : Model) (root : String) :
    Except Error Compilation := do
  let order ← (LeanPoo.C4.linearize model.graph root).mapError .c4
  let reversed ← order.reverse.foldlM (fun current name => do
    let some module := model.modules.find? (fun item => item.name == name)
      | throw (.missingModule name)
    let ancestors ← (LeanPoo.C4.linearize model.graph name).mapError .c4
    module.edits.foldlM (fun state edit => do
      let policies ← applyEdit name ancestors state.policies edit
      return { policies, applied := { moduleName := name, edit } :: state.applied })
      current) ({ policies := [], applied := [] } : Compilation)
  return { reversed with applied := reversed.applied.reverse }

def Model.compileWithProvenance (model : Model) (root : String) :
    Except Error (List CompiledPolicy) :=
  (model.compileWithTrace root).map Compilation.policies

/-- Materialize the compiled policies for Cedar's validator and authorizer. -/
def Model.compile (model : Model) (root : String) : Except Error Policies :=
  (model.compileWithProvenance root).map (·.map CompiledPolicy.policy)

/-- Check a generated edit sequence with the same C4 compiler used by public
    policy modules. New policies append; existing policy order is preserved. -/
def Edit.replay (before : Policies) (edits : List Edit) : Except Error Policies :=
  ({ modules := [
      { name := "Before", edits := Edit.extendAll before },
      { name := "Next", parentOrders := [["Before"]], edits }] } : Model).compile "Next"

/-- A generated revision carries an equality receipt from the C4 compiler. -/
structure Reconciliation (before after : Policies) where
  edits : List Edit
  replays : Edit.replay before edits = .ok after

private def Edit.candidates (before after : Policies) : List Edit :=
  let removals := before.filterMap fun old =>
    if after.any (fun policy => policy.id == old.id) then none
    else some (.remove old.id)
  let overlays := after.filterMap fun policy =>
    match before.find? (fun old => old.id == policy.id) with
    | some old => if decide (old = policy) then none else some (.overlay policy)
    | none => none
  let extensions := after.filterMap fun policy =>
    if before.any (fun old => old.id == policy.id) then none
    else some (.extend policy)
  removals ++ overlays ++ extensions

/-- Turn a generated policy revision into extend, overlay, and remove edits.
    Reject duplicate IDs and ordering changes that these edits cannot express;
    the returned proof certifies the exact Cedar policy list after C4 replay. -/
def Edit.reconcile (before after : Policies) :
    Except Error (Reconciliation before after) :=
  if !(decide (before.map Policy.id).Nodup) then .error (.duplicateInputIds "before")
  else if !(decide (after.map Policy.id).Nodup) then .error (.duplicateInputIds "after")
  else
    let edits := Edit.candidates before after
    match replayed : Edit.replay before edits with
    | .error error => .error error
    | .ok actual =>
        if same : actual = after then
          .ok ⟨edits, by simpa [same] using replayed⟩
        else .error .unrepresentableOrder

/-- Compare policy bodies by ID, ignoring provenance-only changes. -/
def Compilation.changedPolicyIds (before after : Compilation) : List PolicyID :=
  let ids := ((before.policies.map (·.policy.id)) ++
    (after.policies.map (·.policy.id))).eraseDups
  ids.filter fun id =>
    let old : Option Policy :=
      (before.policies.find? (fun item => item.policy.id == id)).map (·.policy)
    let new : Option Policy :=
      (after.policies.find? (fun item => item.policy.id == id)).map (·.policy)
    !decide (old = new)

structure Revision where
  before : Compilation
  after : Compilation

def Model.compileRevision (model : Model) (beforeRoot afterRoot : String) :
    Except Error Revision := do
  return {
    before := (← model.compileWithTrace beforeRoot)
    after := (← model.compileWithTrace afterRoot)
  }

def Revision.changedPolicyIds (revision : Revision) : List PolicyID :=
  Compilation.changedPolicyIds revision.before revision.after

end CedarPooSpec.PolicyModules
