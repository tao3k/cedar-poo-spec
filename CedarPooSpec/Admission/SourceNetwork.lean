import CedarPooSpec.PolicyModules

/-!
A source-network admission boundary over Cedar's IP extension. The Host
authenticates the projected source address; the library only constructs the
Cedar forbid and its owned Lean-POO edit.
-/

namespace CedarPooSpec.Admission

open Cedar.Spec CedarPooSpec.PolicyModules

structure SourceNetwork where
  policyId : PolicyID
  principalScope : PrincipalScope
  actionScope : ActionScope
  resourceScope : ResourceScope
  acceptedRange : String
  contextKey : String := "sourceIp"

def SourceNetwork.inside (boundary : SourceNetwork) : Expr :=
  .call .isInRange [
    .getAttr (.var .context) boundary.contextKey,
    .call .ip [.lit (.string boundary.acceptedRange)]]

def SourceNetwork.policy (boundary : SourceNetwork) : Policy :=
  { id := boundary.policyId, effect := .forbid,
    principalScope := boundary.principalScope,
    actionScope := boundary.actionScope,
    resourceScope := boundary.resourceScope,
    condition := [{ kind := .when, body := .unaryApp .not boundary.inside }] }

inductive SourceNetwork.Change where
  | introduce
  | revise
  | withdraw

def SourceNetwork.edit (boundary : SourceNetwork) : SourceNetwork.Change → Edit
  | .introduce => .extend boundary.policy
  | .revise => .overlay boundary.policy
  | .withdraw => .remove boundary.policyId

end CedarPooSpec.Admission
