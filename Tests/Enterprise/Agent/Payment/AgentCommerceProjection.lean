import CedarPooSpec.Vertical.FinancialServices.AgentCommerceProjection

/-! Cross-language fixture for the signed mandate and offer consumer test. -/

namespace CedarPooSpec.AgentCommerceProjectionTest

open Cedar.Spec
open CedarPooSpec.Vertical.FinancialServices

def mandate : AgentCommerceMandate :=
  { mandateId := "trip-root",
    principal := ⟨⟨"Account", ["finance"]⟩, "buyer"⟩,
    agentId := "travel-agent",
    agentPublicKey := "02550f471003f3df97c3df506ac797f6721fb1a1fb7b8f6f83d224498a65c88e24",
    allowedMerchants := ["ride-seller"],
    allowedProducts := ["airport-ride"],
    asset := "HKD", perPurchaseCap := 50000, totalCap := 80000,
    policyEpoch := 4, expiresAt := 30, verified := false }

def offer : AgentMerchantOffer :=
  { terms :=
      { merchantId := "ride-seller", productId := "airport-ride", offerId := "quote-42",
        checkoutCommitment := "0dcd288f9f89451152756de580eb2a1b5a49bcb0fcd00944dbf95a6180883257",
        amountMinor := 30000, asset := "HKD" },
    expiresAt := 20, verified := false }

def fixture : Lean.Json := Lean.Json.mkObj [
  ("mandate", mandate.claimsJson),
  ("offer", offer.claimsJson)]

end CedarPooSpec.AgentCommerceProjectionTest

def main : IO Unit :=
  IO.println CedarPooSpec.AgentCommerceProjectionTest.fixture.compress
