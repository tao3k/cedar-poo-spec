import CedarPooSpec.PolicyModules

/-!
A scoped permit owned by one policy ID. Membership is evaluated by Cedar
against the caller's entity graph; this object does not duplicate that graph.
An owner can introduce, revise, or withdraw the same slot in a Lean-POO model.
-/

namespace CedarPooSpec.Governance

open Cedar.Spec CedarPooSpec.PolicyModules

structure MemberGrant where
  policyId : PolicyID
  principalGroup : EntityUID
  actionScope : ActionScope
  resourceGroup : EntityUID
  condition : List Condition := []

def MemberGrant.policy (grant : MemberGrant) : Policy :=
  { id := grant.policyId, effect := .permit,
    principalScope := .principalScope (.mem grant.principalGroup),
    actionScope := grant.actionScope,
    resourceScope := .resourceScope (.mem grant.resourceGroup),
    condition := grant.condition }

inductive MemberGrant.Change where
  | introduce
  | revise
  | withdraw

def MemberGrant.edit (grant : MemberGrant) : MemberGrant.Change → Edit
  | .introduce => .extend grant.policy
  | .revise => .overlay grant.policy
  | .withdraw => .remove grant.policyId

end CedarPooSpec.Governance
