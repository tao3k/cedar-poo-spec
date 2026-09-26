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

private structure OwnedPolicy where
  policy : Policy
  owner : String

private def applyEdit (owner : String) (ancestors : List String)
    (current : List OwnedPolicy) : Edit → Except Error (List OwnedPolicy)
  | .extend policy =>
      if current.any (fun entry => entry.policy.id == policy.id) then
        .error (.policyAlreadyExists policy.id)
      else .ok (current ++ [{ policy, owner }])
  | .overlay policy => do
      let some previous := current.find? (fun entry => entry.policy.id == policy.id)
        | throw (.missingPolicy policy.id)
      if !ancestors.contains previous.owner then
        throw (.competingEdits policy.id previous.owner owner)
      return current.map fun entry =>
        if entry.policy.id == policy.id then { policy, owner } else entry
  | .remove id => do
      let some previous := current.find? (fun entry => entry.policy.id == id)
        | throw (.missingPolicy id)
      if !ancestors.contains previous.owner then
        throw (.competingEdits id previous.owner owner)
      return current.filter (fun entry => entry.policy.id != id)

/-- Apply inherited modules base first; the root's explicit edits run last. -/
def Model.compile (model : Model) (root : String) : Except Error Policies := do
  let order ← (LeanPoo.C4.linearize model.graph root).mapError .c4
  let owned ← order.reverse.foldlM (fun current name => do
    let some module := model.modules.find? (fun item => item.name == name)
      | throw (.missingModule name)
    let ancestors ← (LeanPoo.C4.linearize model.graph name).mapError .c4
    module.edits.foldlM (applyEdit name ancestors) current) ([] : List OwnedPolicy)
  return owned.map OwnedPolicy.policy

end CedarPooSpec.PolicyModules
