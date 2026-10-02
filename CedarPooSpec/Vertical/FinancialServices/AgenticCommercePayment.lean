import CedarPooSpec.AgenticAI.Commerce.Credential
import CedarPooSpec.Vertical.FinancialServices.PaymentOperation

/-!
A public payment-operation adapter for an admitted agent purchase. This
profile uses HKD cents to show exact amount conversion. The Host still
authenticates the credential, checkout, and policy inputs, and must carry the
complete envelope to the provider. No card token is issued here.
-/

namespace CedarPooSpec.Vertical.FinancialServices

open CedarPooSpec.AgenticAI.Commerce

/-- This profile uses HKD cents while Cedar decimals use four fractional
    places. A canonical amount must therefore be an integer number of cents. -/
def canonicalHkdCents (text : String) : Option Nat := do
  let value ← Cedar.Spec.Ext.Decimal.decimal text
  if toString value != text then none else
  if value.toInt > 0 && value.toInt % 100 == 0 then
    some (value.toInt.toNat / 100)
  else none

structure AgenticCommercePaymentProfile where
  origin : Cedar.Spec.EntityUID
  instrument : String
  network : String
  feeCap : String
  verified : Bool
  deriving DecidableEq, Repr

/-- The full envelope is needed at the Host's credential and payment boundary;
    `checkoutCommitment` on `PaymentOperation` carries the offer binding into
    downstream payment evidence. -/
structure AgenticCommercePaymentEnvelope where
  offer : MerchantOffer
  purchase : Purchase
  credential : Credential
  payment : PaymentOperation
  deriving DecidableEq, Repr

/-- Check correspondence only. Cedar authorization and Host effect release are
    separate decisions after this predicate succeeds. -/
def AgenticCommercePaymentProfile.binds (profile : AgenticCommercePaymentProfile)
    (budget : Budget)
    (envelope : AgenticCommercePaymentEnvelope) : Bool :=
  profile.verified && !profile.instrument.isEmpty &&
  !profile.network.isEmpty &&
  budget.acceptsCredential envelope.offer envelope.purchase envelope.credential &&
  envelope.payment.wellFormed &&
  envelope.payment.authorityMode == .delegated &&
  decide (envelope.payment.payerAccount = budget.mandate.principal) &&
  decide (envelope.payment.origin = profile.origin) &&
  envelope.payment.instrument == profile.instrument &&
  envelope.payment.network == profile.network &&
  envelope.payment.feeCap == profile.feeCap &&
  envelope.payment.beneficiary == envelope.purchase.terms.merchantId &&
  envelope.payment.asset == envelope.purchase.terms.asset &&
  envelope.payment.checkoutCommitment ==
    envelope.purchase.terms.checkoutCommitment &&
  envelope.payment.mandateRef == envelope.purchase.mandateId &&
  envelope.payment.nonce == envelope.purchase.purchaseId &&
  envelope.payment.proposer == envelope.purchase.agentId &&
  envelope.payment.policyEpoch == budget.mandate.policyEpoch &&
  budget.now < envelope.payment.expiresAt &&
  envelope.payment.expiresAt <= budget.mandate.expiresAt &&
  envelope.payment.expiresAt <= envelope.offer.expiresAt &&
  envelope.payment.expiresAt <= envelope.credential.expiresAt &&
  canonicalHkdCents envelope.payment.amount ==
    some envelope.purchase.terms.amountMinor

end CedarPooSpec.Vertical.FinancialServices
