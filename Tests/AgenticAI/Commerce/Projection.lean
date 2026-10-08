import CedarPooSpec.AgenticAI.Commerce.Projection

/-! Cross-language fixture for the signed mandate and offer consumer test. -/

namespace CedarPooSpec.AgenticAI.CommerceProjectionTest

open Cedar.Spec
open CedarPooSpec.AgenticAI.Commerce

def mandate : Mandate :=
  { mandateId := "trip-root",
    principal := ⟨⟨"Account", ["finance"]⟩, "buyer"⟩,
    agentId := "travel-agent",
    agentPublicKey := "02550f471003f3df97c3df506ac797f6721fb1a1fb7b8f6f83d224498a65c88e24",
    allowedMerchants := ["ride-seller"],
    allowedProducts := ["airport-ride"],
    asset := "HKD", perPurchaseCap := 50000, totalCap := 80000,
    policyEpoch := 4, expiresAt := 30, verified := false }

def offer : MerchantOffer :=
  { terms :=
      { merchantId := "ride-seller", productId := "airport-ride", offerId := "quote-42",
        checkoutCommitment := "0dcd288f9f89451152756de580eb2a1b5a49bcb0fcd00944dbf95a6180883257",
        amountMinor := 30000, asset := "HKD" },
    expiresAt := 20, verified := false }

def child : Mandate :=
  { mandate with
    mandateId := "trip-child",
    agentId := "booking-agent",
    agentPublicKey := "0273103ec30b3ccf57daae08e93534aef144a35940cf6bbba12a0cf7cbd5d65a64",
    perPurchaseCap := 40000, totalCap := 60000, expiresAt := 25 }

def sharedBefore : SharedBudget :=
  { root := { mandate with verified := true }, now := 10, reservations := [],
    revokedMandateIds := [], revision := 1 }

def sharedPurchase : Purchase :=
  { purchaseId := "buy-child", mandateId := child.mandateId,
    agentId := child.agentId, terms := offer.terms }

def sharedAfter : SharedBudget :=
  { sharedBefore with
    reservations := [{
      lineage := [sharedBefore.root, { child with verified := true }]
      purchase := sharedPurchase }]
    revision := 2 }

theorem sharedProjectionIsExactTransition :
    sharedBefore.reserve 1 [{
      issuerAgentId := mandate.agentId, parent := sharedBefore.root
      child := { child with verified := true }, verified := true }]
      { offer with verified := true } sharedPurchase = some sharedAfter := by decide

-- Content IDs are opaque in Lean. Rust resolves these two template fields from
-- the actual before/after bytes; every semantic reservation field is exported.
def committedCredential : Credential :=
  { credentialId := "credential-42", issuerId := "wallet",
    receipt := {
      scope := "buyer-trip-root", operationId := sharedPurchase.purchaseId,
      expectedRevision := 1, expectedContentId := "host-before-content-id",
      committedRevision := 2, committedContentId := "host-committed-content-id",
      reservation := {
        lineage := [sharedBefore.root, { child with verified := true }]
        purchase := sharedPurchase }, verified := true },
    expiresAt := 18, verified := true }

theorem committedCredentialProjectionAccepted :
    sharedAfter.acceptsCredential "buyer-trip-root" { offer with verified := true }
      sharedPurchase committedCredential = true := by decide

def dispatch : PaymentDispatch :=
  { providerId := "processor", idempotencyKey := "host-derived-idempotency-key",
    credential := committedCredential,
    authority := ⟨⟨"buyer-trip-root", "trip-root"⟩, 7, false⟩ }
def consumptionBefore : ConsumptionLedger :=
  { budgetScope := "buyer-trip-root", revision := 1, requests := [] }
def consumptionAfter : ConsumptionLedger :=
  { consumptionBefore with revision := 2, requests := [dispatch] }
theorem consumptionProjectionIsExactClaim :
    consumptionBefore.claim 1 sharedAfter { offer with verified := true }
      sharedPurchase dispatch = some consumptionAfter := by decide

def fixture : Lean.Json := Lean.Json.mkObj [
  ("mandate", mandate.claimsJson),
  ("offer", offer.claimsJson),
  ("lineage", Lean.toJson ([mandate.claimsJson, child.claimsJson] : List Lean.Json)),
  ("sharedBefore", sharedBefore.claimsJson),
  ("sharedAfter", sharedAfter.claimsJson),
  ("credentialTemplate", committedCredential.claimsJson),
  ("consumptionBefore", consumptionBefore.claimsJson),
  ("consumptionAfterTemplate", consumptionAfter.claimsJson)]

end CedarPooSpec.AgenticAI.CommerceProjectionTest

def main : IO Unit :=
  IO.println CedarPooSpec.AgenticAI.CommerceProjectionTest.fixture.compress
