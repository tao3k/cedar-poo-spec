import CedarPooSpec.PolicyModules

/-!
An independently owned denial control. Cedar still owns the policy AST,
validation, and permit/forbid decision. This object only binds a stable policy
identity and denial predicate to one POO edit slot.
-/

namespace CedarPooSpec.Governance

open Cedar.Spec CedarPooSpec.PolicyModules

structure Veto where
  policyId : PolicyID
  actionScope : ActionScope
  denyWhen : Expr
  principalScope : PrincipalScope := .principalScope .any
  resourceScope : ResourceScope := .resourceScope .any

def Veto.policy (control : Veto) : Policy :=
  { id := control.policyId, effect := .forbid,
    principalScope := control.principalScope,
    actionScope := control.actionScope,
    resourceScope := control.resourceScope,
    condition := [{ kind := .when, body := control.denyWhen }] }

inductive Veto.Change where
  | introduce
  | revise
  | withdraw

def Veto.edit (control : Veto) : Veto.Change → Edit
  | .introduce => .extend control.policy
  | .revise => .overlay control.policy
  | .withdraw => .remove control.policyId

/-- Several action-specific vetoes can share one independent owner module. -/
def Veto.moduleMany (name parent : String) (change : Veto.Change)
    (controls : List Veto) : Module :=
  { name, parentOrders := [[parent]],
    edits := controls.map (·.edit change) }

def Veto.module (control : Veto) (name parent : String)
    (change : Veto.Change) : Module :=
  Veto.moduleMany name parent change [control]

end CedarPooSpec.Governance
