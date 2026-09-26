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

structure Module where
  name : String
  parentOrders : List (List String) := []
  edits : List Edit := []

def Module.node (module : Module) : LeanPoo.C4.Node :=
  { name := module.name, parentOrders := module.parentOrders }

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

end CedarPooSpec.PolicyModules
