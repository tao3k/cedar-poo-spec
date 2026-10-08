import CedarPooSpec.AgenticAI.Commerce.SharedBudget

/-!
A credential is bound to an authenticated committed reservation, including the
shared revision, content IDs and complete authority lineage. Lean treats receipt
and signature verification as Host assertions. Acceptance alone establishes no single-use
or payment-effect right; an issuer/provider must separately enforce those rules.
-/

namespace CedarPooSpec.AgenticAI.Commerce

/-- Host-authenticated conditional commit, never an uncommitted proposal. -/
structure ReservationCommitReceipt where
  scope : String
  operationId : String
  expectedRevision : Nat
  expectedContentId : String
  committedRevision : Nat
  committedContentId : String
  reservation : SharedReservation
  verified : Bool
  deriving DecidableEq, Repr

/-- The exact receipt and reservation replace independently substitutable terms. -/
structure Credential where
  credentialId : String
  issuerId : String
  receipt : ReservationCommitReceipt
  expiresAt : Nat
  verified : Bool
  deriving DecidableEq, Repr

private def validLineage : List Mandate → Bool
  | [] => false
  | root :: rest =>
    let steps := (root :: rest).zip rest |>.map (fun (parent, child) =>
      ({ issuerAgentId := parent.agentId, parent, child, verified := true } : Delegation))
    Delegation.resolveChain root steps == (root :: rest).getLast?

/-- Revalidate current scope, lineage and accounting without charging a second
    reservation. A later head can retain an earlier committed reservation. -/
def SharedBudget.acceptsCredential (state : SharedBudget) (scope : String)
    (offer : MerchantOffer) (purchase : Purchase) (credential : Credential) : Bool :=
  if state.reservations.contains credential.receipt.reservation then
    let receipt := credential.receipt
    let lineage := receipt.reservation.lineage
    let final := lineage.getLast?
    receipt.verified && credential.verified && offer.verified &&
    !scope.isEmpty && receipt.scope == scope &&
    !credential.credentialId.isEmpty && !credential.issuerId.isEmpty &&
    receipt.operationId == purchase.purchaseId && !receipt.operationId.isEmpty &&
    !receipt.expectedContentId.isEmpty && !receipt.committedContentId.isEmpty &&
    receipt.expectedContentId != receipt.committedContentId &&
    receipt.expectedRevision > 0 &&
    receipt.committedRevision == receipt.expectedRevision + 1 &&
    receipt.committedRevision <= state.revision &&
    decide (receipt.reservation.purchase = purchase) &&
    decide (purchase.terms = offer.terms) &&
    lineage.head? == some state.root && validLineage lineage &&
    final.any (fun mandate => purchase.mandateId == mandate.mandateId &&
      purchase.agentId == mandate.agentId &&
      mandate.allowedMerchants.contains purchase.terms.merchantId &&
      mandate.allowedProducts.contains purchase.terms.productId &&
      purchase.terms.asset == mandate.asset &&
      purchase.terms.amountMinor <= mandate.perPurchaseCap) &&
    lineage.all (fun mandate => mandate.verified &&
      !state.revokedMandateIds.contains mandate.mandateId &&
      state.now < mandate.expiresAt && credential.expiresAt <= mandate.expiresAt &&
      state.spentUnder mandate.mandateId <= mandate.totalCap &&
      state.reservations.all (fun entry => entry.lineage.all (fun previous =>
        previous.mandateId != mandate.mandateId || decide (previous = mandate)))) &&
    state.spentMinor <= state.root.totalCap &&
    !purchase.terms.checkoutCommitment.isEmpty && purchase.terms.amountMinor > 0 &&
    state.now < offer.expiresAt && state.now < credential.expiresAt &&
    credential.expiresAt <= offer.expiresAt
  else false

theorem acceptedCredentialHasCurrentReservation (state : SharedBudget) (scope : String)
    (offer : MerchantOffer) (purchase : Purchase) (credential : Credential)
    (h : state.acceptsCredential scope offer purchase credential = true) :
    state.reservations.contains credential.receipt.reservation = true := by
  unfold SharedBudget.acceptsCredential at h
  split at h <;> simp_all

theorem acceptedCredentialHasAuthenticatedCommit (state : SharedBudget) (scope : String)
    (offer : MerchantOffer) (purchase : Purchase) (credential : Credential)
    (h : state.acceptsCredential scope offer purchase credential = true) :
    credential.receipt.verified = true := by
  unfold SharedBudget.acceptsCredential at h
  split at h <;> simp_all

end CedarPooSpec.AgenticAI.Commerce
