import CedarPooSpec.AgenticAI.Commerce.Budget

/-!
One-step scope attenuation and an exact chain of agent-to-agent delegations.
The Host authenticates each issuer and child mandate before setting `verified`.
The chain grants authority only; shared-budget reservation for child agents
requires a separately specified durable allocator.
-/

namespace CedarPooSpec.AgenticAI.Commerce

/-- A child can narrow the principal's merchant, product, amount, and time
    constraints, but cannot widen them or change the principal or asset. -/
def Mandate.attenuates (parent child : Mandate) : Bool :=
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
structure Delegation where
  issuerAgentId : String
  parent : Mandate
  child : Mandate
  verified : Bool
  deriving DecidableEq, Repr

def Delegation.applies (step : Delegation)
    (parent : Mandate) : Bool :=
  step.verified && step.issuerAgentId == parent.agentId &&
  decide (step.parent = parent) && parent.attenuates step.child

/-- Every hop names the preceding mandate and uses identities and keys not
    already present in this exact chain. -/
private def Delegation.resolveWithSeen (current : Mandate)
    (seenMandates seenAgents seenKeys : List String) :
    List Delegation → Option Mandate
  | [] => some current
  | step :: rest =>
      if step.applies current &&
          !seenMandates.contains step.child.mandateId &&
          !seenAgents.contains step.child.agentId &&
          !seenKeys.contains step.child.agentPublicKey then
        resolveWithSeen step.child
          (step.child.mandateId :: seenMandates)
          (step.child.agentId :: seenAgents)
          (step.child.agentPublicKey :: seenKeys) rest
      else none

def Delegation.resolveChain (root : Mandate)
    (steps : List Delegation) : Option Mandate :=
  resolveWithSeen root [root.mandateId] [root.agentId] [root.agentPublicKey] steps

end CedarPooSpec.AgenticAI.Commerce
