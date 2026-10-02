import CedarPooSpec.Vertical.FinancialServices.AgentCommerce

/-!
One-step scope attenuation and an exact chain of agent-to-agent delegations.
The Host authenticates each issuer and child mandate before setting `verified`.
The chain grants authority only; shared-budget reservation for child agents
requires a separately specified durable allocator.
-/

namespace CedarPooSpec.Vertical.FinancialServices

/-- A child can narrow the principal's merchant, product, amount, and time
    constraints, but cannot widen them or change the principal or asset. -/
def AgentCommerceMandate.attenuates (parent child : AgentCommerceMandate) : Bool :=
  parent.verified && child.verified &&
  !child.mandateId.isEmpty && !child.agentId.isEmpty &&
  !child.agentPublicKey.isEmpty &&
  child.mandateId != parent.mandateId && child.agentId != parent.agentId &&
  child.agentPublicKey != parent.agentPublicKey &&
  decide (child.principal = parent.principal) &&
  child.policyEpoch == parent.policyEpoch && child.asset == parent.asset &&
  !child.allowedMerchants.isEmpty && !child.allowedProducts.isEmpty &&
  child.allowedMerchants.all (parent.allowedMerchants.contains ·) &&
  child.allowedProducts.all (parent.allowedProducts.contains ·) &&
  child.perPurchaseCap <= parent.perPurchaseCap &&
  child.totalCap <= parent.totalCap && child.expiresAt <= parent.expiresAt

/-- `verified` asserts that the Host authenticated the parent agent's grant
    of this exact child mandate. Structural scope checking remains local. -/
structure AgentCommerceDelegation where
  issuerAgentId : String
  parent : AgentCommerceMandate
  child : AgentCommerceMandate
  verified : Bool
  deriving DecidableEq, Repr

def AgentCommerceDelegation.applies (step : AgentCommerceDelegation)
    (parent : AgentCommerceMandate) : Bool :=
  step.verified && step.issuerAgentId == parent.agentId &&
  decide (step.parent = parent) && parent.attenuates step.child

/-- Every hop must name the exact preceding mandate and its agent issuer. -/
def AgentCommerceDelegation.resolveChain (root : AgentCommerceMandate) :
    List AgentCommerceDelegation → Option AgentCommerceMandate
  | [] => some root
  | step :: rest =>
      if step.applies root then resolveChain step.child rest else none

end CedarPooSpec.Vertical.FinancialServices
