import CedarPooSpec.Vertical.FinancialServices.AgentCommerce
import Lean

/-!
JSON claims shared with the optional Rust `lean-mandate-offer-projection` API.
They deliberately omit `verified`: only a trusted Host may set that flag after
comparing these fields with live Rust `VerifiedMandate` / `VerifiedOffer` values
and checking current time, key status, policy, and revocation state.
-/

namespace CedarPooSpec.Vertical.FinancialServices

private def object (fields : List (String × Lean.Json)) : Lean.Json :=
  Lean.Json.mkObj fields

/-- Serialize every mandate field except the Host-owned `verified` bit. -/
def AgentCommerceMandate.claimsJson (mandate : AgentCommerceMandate) : Lean.Json :=
  object [
    ("mandateId", Lean.toJson mandate.mandateId),
    ("principal", object [
      ("ty", object [
        ("id", Lean.toJson mandate.principal.ty.id),
        ("path", Lean.toJson mandate.principal.ty.path)]),
      ("eid", Lean.toJson mandate.principal.eid)]),
    ("agentId", Lean.toJson mandate.agentId),
    ("agentPublicKey", Lean.toJson mandate.agentPublicKey),
    ("allowedMerchants", Lean.toJson mandate.allowedMerchants),
    ("allowedProducts", Lean.toJson mandate.allowedProducts),
    ("asset", Lean.toJson mandate.asset),
    ("perPurchaseCap", Lean.toJson mandate.perPurchaseCap),
    ("totalCap", Lean.toJson mandate.totalCap),
    ("policyEpoch", Lean.toJson mandate.policyEpoch),
    ("expiresAt", Lean.toJson mandate.expiresAt)]

/-- Serialize every merchant-offer field except the Host-owned `verified` bit. -/
def AgentMerchantOffer.claimsJson (offer : AgentMerchantOffer) : Lean.Json :=
  object [
    ("terms", object [
      ("merchantId", Lean.toJson offer.terms.merchantId),
      ("productId", Lean.toJson offer.terms.productId),
      ("offerId", Lean.toJson offer.terms.offerId),
      ("checkoutCommitment", Lean.toJson offer.terms.checkoutCommitment),
      ("amountMinor", Lean.toJson offer.terms.amountMinor),
      ("asset", Lean.toJson offer.terms.asset)]),
    ("expiresAt", Lean.toJson offer.expiresAt)]

end CedarPooSpec.Vertical.FinancialServices
