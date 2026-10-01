import Examples.Enterprise.Agent.Payment.PaymentAudit
import CedarPooSpec.Vertical.FinancialServices.PaymentLifecycle

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

def state : PaymentState :=
  { policyEpoch := 7, auditPolicy, now := 10, usedNonces := [] }
def authorization : PaymentAuthorization :=
  { payment, auditPolicy, allowed := true, verified := true }

def modelEvidence : AuditEvidence :=
  { payment, auditPolicy, kind := .model, source := "risk-v1", actor := "risk-engine",
    verdict := .pass, verified := true, expiresAt := 18 }
def riskHuman : AuditEvidence :=
  { payment, auditPolicy, kind := .human, source := "risk", actor := "risk-officer",
    verdict := .pass, verified := true, expiresAt := 19 }
def complianceHuman : AuditEvidence :=
  { payment, auditPolicy, kind := .human, source := "compliance",
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
    oneStage.accepts payment state.now
      [{ modelEvidence with auditPolicy := oneStage }] = true := by decide
theorem humanOnlyAccepted :
    humanOnly.accepts payment state.now
      [{ riskHuman with auditPolicy := humanOnly }] = true := by decide
theorem emptyPlanDenied :
    ({ requirements := [] } : PaymentAuditPolicy).accepts payment state.now [] = false := by decide
theorem twoStagesAccepted :
    twoStages.accepts payment state.now
      [{ modelEvidence with auditPolicy := twoStages },
        { riskHuman with auditPolicy := twoStages }] = true := by decide
theorem oldEvidenceCannotSatisfyNewPlan :
    oneStage.accepts payment state.now [modelEvidence] = false := by decide
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
    { payment with beneficiary := "attacker" }.admissible authorization
      state threeEvidence = false := by decide
theorem changedFeeDenied :
    { payment with feeCap := "9.0000" }.admissible authorization
      state threeEvidence = false := by decide
theorem delegatedWithoutMandateDenied :
    { payment with mandateRef := "" }.wellFormed = false := by decide
theorem directWithoutMandateWellFormed :
    { payment with authorityMode := .direct, mandateRef := "" }.wellFormed = true := by decide
theorem differentAuthorizationDenied :
    payment.admissible { authorization with payment :=
      { payment with beneficiary := "attacker" } }
      state threeEvidence = false := by decide
theorem unverifiedAuthorizationDenied :
    payment.admissible { authorization with verified := false }
      state threeEvidence = false := by decide
theorem weakenedAuditPolicyDenied :
    payment.admissible authorization { state with auditPolicy := oneStage }
      [modelEvidence] = false := by decide
theorem recapturedAuthorizationStillRejectsOldEvidence :
    payment.admissible { authorization with auditPolicy := oneStage }
      { state with auditPolicy := oneStage } [modelEvidence] = false := by decide
theorem weakenedAdapterDenied :
    reserveWithCedar payment { state with auditPolicy := oneStage }
      [modelEvidence] = none := by native_decide
theorem staleEpochDenied :
    payment.admissible authorization { state with policyEpoch := 8 }
      threeEvidence = false := by decide
theorem expiredEvidenceDenied :
    auditPolicy.accepts payment 18 threeEvidence = false := by decide
theorem repeatedNonceDenied :
    (payment.reserve authorization state threeEvidence).bind
      (fun next => payment.reserve authorization next threeEvidence) = none := by decide
theorem deniedCedarCannotReserve :
    payment.reserve { authorization with allowed := false }
      state threeEvidence = none := by
  exact deniedAuthorizationCannotReserve payment
    { authorization with allowed := false } state threeEvidence (by decide)

theorem cedarAllowsFixture : cedarAllowed payment = true := by native_decide
theorem cedarDeniesExcessAmount :
    cedarAllowed { payment with amount := "100.0001" } = false := by native_decide
theorem cedarDeniesMalformedAmount :
    cedarAllowed { payment with amount := "not-an-amount" } = false := by native_decide
theorem cedarReservationConsumesNonce :
    (reserveWithCedar payment state threeEvidence).map
      (fun next => next.usedNonces) = some [payment.nonce] := by native_decide

def pending : PaymentAttempt := { payment, phase := .reserved }
def submitted : PaymentAttempt := { payment, phase := .submitted }
def accepted : PaymentAttempt :=
  { payment, phase := .accepted, providerReference := some "provider-42" }
def acceptedEvidence : ProcessorEvidence :=
  { payment, idempotencyKey := payment.nonce,
    providerReference := "provider-42", outcome := .accepted,
    verified := true }
def settledEvidence : ProcessorEvidence :=
  { payment, idempotencyKey := payment.nonce,
    providerReference := "provider-42", outcome := .settled,
    verified := true }

theorem prepareConsumesNonce :
    (payment.prepare authorization state threeEvidence).map
      (fun result => result.1.usedNonces) = some [payment.nonce] := by decide
theorem firstSubmitAllowed : pending.submit =
    some (submitted, { payment, idempotencyKey := payment.nonce }) := by decide
theorem emptyKeyCannotSubmit :
    ({ pending with payment := { payment with nonce := "" } }).submit = none := by decide
theorem lostResponseCannotResubmit : submitted.submit = none := by decide
theorem uncertainResponseCanQuery : submitted.statusQuery =
    some { payment, idempotencyKey := payment.nonce,
           providerReference := none } := by decide
theorem acceptedCanQueryByReference : accepted.statusQuery =
    some { payment, idempotencyKey := payment.nonce,
           providerReference := some "provider-42" } := by decide
theorem finalAttemptCannotQuery :
    ({ accepted with phase := .settled }).statusQuery = none := by decide
theorem processorAcceptanceIsNotSettlement :
    (submitted.observe acceptedEvidence).map PaymentAttempt.phase =
      some .accepted := by decide
theorem matchingSettlementFinalizes :
    (accepted.observe settledEvidence).map PaymentAttempt.phase =
      some .settled := by decide
theorem matchingRejectionFinalizes :
    (accepted.observe { settledEvidence with outcome := .rejected }).map
      PaymentAttempt.phase = some .rejected := by decide
theorem wrongProviderReferenceDenied :
    accepted.observe { settledEvidence with providerReference := "other" } =
      none := by decide
theorem changedPaymentObservationDenied :
    submitted.observe { settledEvidence with payment :=
      { payment with beneficiary := "attacker" } } = none := by decide
theorem wrongIdempotencyKeyDenied :
    submitted.observe { settledEvidence with idempotencyKey := "other" } =
      none := by decide
theorem wrongKeyCannotFinalizeAccepted :
    accepted.observe { settledEvidence with idempotencyKey := "other" } =
      none := by decide
theorem unverifiedProcessorObservationDenied :
    submitted.observe { settledEvidence with verified := false } = none := by decide
theorem settledAttemptIsTerminal :
    ({ payment, phase := .settled,
       providerReference := some "provider-42" } : PaymentAttempt).observe
      settledEvidence = none := by decide
theorem rejectedAttemptIsTerminal :
    ({ payment, phase := .rejected,
       providerReference := some "provider-42" } : PaymentAttempt).observe
      settledEvidence = none := by decide

end CedarPooSpec.AgentPaymentAuditTest
