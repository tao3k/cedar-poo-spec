import CedarPooSpec.PolicyModules

/-!
An insurance claims-summary restriction owned by one policy ID. The
application supplies the authenticated policyholder condition and exact
Cedar scopes; a platform adapter may project identity into that condition.
-/

namespace CedarPooSpec.Vertical.FinancialServices

open Cedar.Spec CedarPooSpec.PolicyModules

structure ClaimSummaryVeto where
  policyId : PolicyID
  principalScope : PrincipalScope
  summaryAction : EntityUID
  resourceScope : ResourceScope
  policyholderCondition : Expr

def ClaimSummaryVeto.policy (control : ClaimSummaryVeto) : Policy :=
  { id := control.policyId, effect := .forbid,
    principalScope := control.principalScope,
    actionScope := .actionScope (.eq control.summaryAction),
    resourceScope := control.resourceScope,
    condition := [{ kind := .when, body := control.policyholderCondition }] }

def ClaimSummaryVeto.introduce (control : ClaimSummaryVeto) : Edit :=
  .extend control.policy

def ClaimSummaryVeto.revise (control : ClaimSummaryVeto) : Edit :=
  .overlay control.policy

def ClaimSummaryVeto.withdraw (control : ClaimSummaryVeto) : Edit :=
  .remove control.policyId

end CedarPooSpec.Vertical.FinancialServices
