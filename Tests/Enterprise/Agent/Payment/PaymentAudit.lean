import Examples.Enterprise.Agent.Payment.PaymentAudit

namespace CedarPooSpec.AgentPaymentAuditTest

open CedarPooSpec.Vertical.FinancialServices
open CedarPooSpec.AgentPaymentAuditExample
open CedarPooSpec.AgentPaymentExample
open CedarPooSpec.AgentDelegationExample

def payment : PaymentOperation :=
  { authorityMode := .delegated,
    payerAccount := approvedAccount, origin := admin,
    instrument := "bank-transfer", beneficiary := "merchant-42",
    amount := "50.0000", asset := "USD", network := "bank-rail",
    feeCap := "1.0000", mandateRef := "delegation-77",
    nonce := "payment-123", proposer := "finance-bot",
    policyEpoch := 7, expiresAt := 20 }

def state : PaymentState := { policyEpoch := 7, now := 10, usedNonces := [] }
def authorization : PaymentAuthorization :=
  { payment, allowed := true, verified := true }

def modelEvidence : AuditEvidence :=
  { payment, kind := .model, source := "risk-v1", actor := "risk-engine",
    verdict := .pass, verified := true, expiresAt := 18 }
def riskHuman : AuditEvidence :=
  { payment, kind := .human, source := "risk", actor := "risk-officer",
    verdict := .pass, verified := true, expiresAt := 19 }
def complianceHuman : AuditEvidence :=
  { payment, kind := .human, source := "compliance",
    actor := "compliance-officer", verdict := .pass,
    verified := true, expiresAt := 19 }

def oneStage : PaymentAuditPolicy :=
  { requirements := [{ kind := .model, source := "risk-v1", minimum := 1 }] }
def humanOnly : PaymentAuditPolicy :=
  { requirements := [{ kind := .human, source := "risk", minimum := 1,
                       excludeProposer := true }] }
def twoStages : PaymentAuditPolicy :=
  { requirements := oneStage.requirements ++
      [{ kind := .human, source := "risk", minimum := 1,
         excludeProposer := true }] }

def threeEvidence : List AuditEvidence := [modelEvidence, riskHuman, complianceHuman]

theorem oneStageAccepted :
    oneStage.accepts payment state.now [modelEvidence] = true := by decide
theorem humanOnlyAccepted :
    humanOnly.accepts payment state.now [riskHuman] = true := by decide
theorem emptyPlanDenied :
    ({ requirements := [] } : PaymentAuditPolicy).accepts payment state.now [] = false := by decide
theorem twoStagesAccepted :
    twoStages.accepts payment state.now [modelEvidence, riskHuman] = true := by decide
theorem threeStagesAccepted :
    auditPolicy.accepts payment state.now threeEvidence = true := by decide
theorem missingStageDenied :
    auditPolicy.accepts payment state.now [modelEvidence, riskHuman] = false := by decide
theorem adverseModelDenied :
    auditPolicy.accepts payment state.now
      [{ modelEvidence with verdict := .deny }, riskHuman, complianceHuman] = false := by decide
theorem escalateModelDenied :
    auditPolicy.accepts payment state.now
      [{ modelEvidence with verdict := .escalate }, riskHuman, complianceHuman] = false := by decide
theorem unverifiedModelDenied :
    auditPolicy.accepts payment state.now
      [{ modelEvidence with verified := false }, riskHuman, complianceHuman] = false := by decide
theorem sameHumanDenied :
    auditPolicy.accepts payment state.now
      [modelEvidence, riskHuman,
        { complianceHuman with actor := "risk-officer" }] = false := by decide
theorem proposerAsReviewerDenied :
    auditPolicy.accepts payment state.now
      [modelEvidence, { riskHuman with actor := "finance-bot" },
        complianceHuman] = false := by decide
theorem changedBeneficiaryDenied :
    { payment with beneficiary := "attacker" }.admissible authorization auditPolicy
      state threeEvidence = false := by decide
theorem changedFeeDenied :
    { payment with feeCap := "9.0000" }.admissible authorization auditPolicy
      state threeEvidence = false := by decide
theorem delegatedWithoutMandateDenied :
    { payment with mandateRef := "" }.wellFormed = false := by decide
theorem directWithoutMandateWellFormed :
    { payment with authorityMode := .direct, mandateRef := "" }.wellFormed = true := by decide
theorem differentAuthorizationDenied :
    payment.admissible { authorization with payment :=
      { payment with beneficiary := "attacker" } } auditPolicy
      state threeEvidence = false := by decide
theorem unverifiedAuthorizationDenied :
    payment.admissible { authorization with verified := false } auditPolicy
      state threeEvidence = false := by decide
theorem staleEpochDenied :
    payment.admissible authorization auditPolicy { state with policyEpoch := 8 }
      threeEvidence = false := by decide
theorem expiredEvidenceDenied :
    auditPolicy.accepts payment 18 threeEvidence = false := by decide
theorem repeatedNonceDenied :
    (payment.reserve authorization auditPolicy state threeEvidence).bind
      (fun next => payment.reserve authorization auditPolicy next threeEvidence) = none := by decide
theorem deniedCedarCannotReserve :
    payment.reserve { authorization with allowed := false } auditPolicy
      state threeEvidence = none := by
  exact deniedAuthorizationCannotReserve payment
    { authorization with allowed := false } auditPolicy state threeEvidence (by decide)

theorem cedarAllowsFixture : cedarAllowed payment = true := by native_decide
theorem cedarDeniesExcessAmount :
    cedarAllowed { payment with amount := "100.0001" } = false := by native_decide
theorem cedarDeniesMalformedAmount :
    cedarAllowed { payment with amount := "not-an-amount" } = false := by native_decide
theorem cedarReservationConsumesNonce :
    (reserveWithCedar payment state threeEvidence).map
      (fun next => next.usedNonces) = some [payment.nonce] := by native_decide

end CedarPooSpec.AgentPaymentAuditTest
