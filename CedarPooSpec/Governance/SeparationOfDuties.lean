import CedarPooSpec.Governance.Veto

/-!
An independently owned segregation rule: the current principal cannot
perform an action on a resource whose recorded prior actor is that principal.
The Host owns the provenance of the prior-actor entity attribute.
-/

namespace CedarPooSpec.Governance

open Cedar.Spec CedarPooSpec.PolicyModules

structure SeparationOfDuties where
  policyId : PolicyID
  actionScope : ActionScope
  priorActorAttribute : String
  principalScope : PrincipalScope := .principalScope .any
  resourceScope : ResourceScope := .resourceScope .any

def SeparationOfDuties.veto (rule : SeparationOfDuties) : Veto :=
  { policyId := rule.policyId, actionScope := rule.actionScope,
    principalScope := rule.principalScope,
    resourceScope := rule.resourceScope,
    denyWhen := .binaryApp .eq (.var .principal)
      (.getAttr (.var .resource) rule.priorActorAttribute) }

def SeparationOfDuties.edit (rule : SeparationOfDuties)
    (change : Veto.Change) : Edit :=
  rule.veto.edit change

end CedarPooSpec.Governance
