import Cedar.Spec.Entities

/-!
One payment instruction, with separate authorization, audit, and Host effect
boundaries. The audit policy chooses any positive number of evidence stages;
AI and human reviewers are evidence sources, not the identity of the payment.
The Host authenticates evidence and performs durable execution.
-/

namespace CedarPooSpec.Vertical.FinancialServices

open Cedar.Spec

inductive PaymentAuthorityMode where
  | direct | delegated
  deriving DecidableEq, Repr

/-- The concrete payment object. `instrument` identifies the payment rail;
    instrument-specific details and any mandate must be bound by a canonical
    Host serialization before execution. -/
structure PaymentOperation where
  authorityMode : PaymentAuthorityMode
  payerAccount : EntityUID
  origin : EntityUID
  instrument : String
  beneficiary : String
  amount : String
  asset : String
  network : String
  feeCap : String
  mandateRef : String
  nonce : String
  proposer : String
  policyEpoch : Nat
  expiresAt : Nat
  deriving DecidableEq, Repr

/-- Authorization is a separate decision about the exact operation. The Host
    supplies `verified` only after evaluating its active policy without errors. -/
structure PaymentAuthorization where
  payment : PaymentOperation
  allowed : Bool
  verified : Bool
  deriving DecidableEq, Repr

inductive AuditKind where
  | model | human | rule | external
  deriving DecidableEq, Repr

inductive AuditVerdict where
  | pass | escalate | deny
  deriving DecidableEq, Repr

/-- `verified` is supplied by the Host after authenticating the source. -/
structure AuditEvidence where
  payment : PaymentOperation
  kind : AuditKind
  source : String
  actor : String
  verdict : AuditVerdict
  verified : Bool
  expiresAt : Nat
  deriving DecidableEq, Repr

structure AuditRequirement where
  kind : AuditKind
  source : String
  minimum : Nat
  excludeProposer : Bool := false
  deriving DecidableEq, Repr

/-- The policy owns the number and kinds of required audit stages. -/
structure PaymentAuditPolicy where
  requirements : List AuditRequirement
  distinctHumanActors : Bool := false
  deriving DecidableEq, Repr

structure PaymentState where
  policyEpoch : Nat
  now : Nat
  usedNonces : List String
  deriving DecidableEq, Repr

def PaymentOperation.wellFormed (payment : PaymentOperation) : Bool :=
  !payment.instrument.isEmpty && !payment.beneficiary.isEmpty &&
  !payment.amount.isEmpty && !payment.asset.isEmpty &&
  !payment.network.isEmpty && !payment.feeCap.isEmpty &&
  !payment.nonce.isEmpty && !payment.proposer.isEmpty &&
  (payment.authorityMode == .direct || !payment.mandateRef.isEmpty)

private def validEvidence (payment : PaymentOperation) (now : Nat)
    (evidence : AuditEvidence) : Bool :=
  evidence.payment == payment && evidence.verified &&
  !evidence.source.isEmpty && !evidence.actor.isEmpty &&
  now < evidence.expiresAt && evidence.verdict == .pass

private def matchingActors (payment : PaymentOperation) (now : Nat)
    (evidence : List AuditEvidence) (requirement : AuditRequirement) : List String :=
  (evidence.filter fun item =>
    validEvidence payment now item && item.kind == requirement.kind &&
    item.source == requirement.source &&
    (!requirement.excludeProposer || item.actor != payment.proposer)).map
      AuditEvidence.actor

/-- All submitted evidence must be current, verified, and affirmative. A
    requirement counts distinct actors from its named source; a policy may
    additionally require distinct human actors across all human stages. -/
def PaymentAuditPolicy.accepts (policy : PaymentAuditPolicy)
    (payment : PaymentOperation) (now : Nat)
    (evidence : List AuditEvidence) : Bool :=
  !policy.requirements.isEmpty &&
  evidence.all (validEvidence payment now) &&
  policy.requirements.all (fun requirement =>
    !requirement.source.isEmpty && requirement.minimum > 0 &&
    (matchingActors payment now evidence requirement).eraseDups.length >=
      requirement.minimum) &&
  (!policy.distinctHumanActors ||
    let humans := (evidence.filter fun item => item.kind == .human).map AuditEvidence.actor
    humans.eraseDups.length == humans.length)

/-- Authorization, audit, and transaction freshness are separate checks. -/
def PaymentOperation.admissible (payment : PaymentOperation)
    (authorization : PaymentAuthorization) (policy : PaymentAuditPolicy)
    (state : PaymentState) (evidence : List AuditEvidence) : Bool :=
  authorization.verified && authorization.allowed &&
  authorization.payment == payment && payment.wellFormed &&
  payment.policyEpoch == state.policyEpoch && state.now < payment.expiresAt &&
  !(state.usedNonces.contains payment.nonce) &&
  policy.accepts payment state.now evidence

/-- Pure reservation. The Host must combine nonce reservation and the actual
    payment effect atomically; this function does not execute a transfer. -/
def PaymentOperation.reserve (payment : PaymentOperation)
    (authorization : PaymentAuthorization) (policy : PaymentAuditPolicy)
    (state : PaymentState) (evidence : List AuditEvidence) : Option PaymentState :=
  if payment.admissible authorization policy state evidence then
    some { state with usedNonces := payment.nonce :: state.usedNonces }
  else none

theorem deniedAuthorizationCannotReserve (payment : PaymentOperation)
    (authorization : PaymentAuthorization) (policy : PaymentAuditPolicy)
    (state : PaymentState) (evidence : List AuditEvidence)
    (h : authorization.allowed = false) :
    payment.reserve authorization policy state evidence = none := by
  simp [PaymentOperation.reserve, PaymentOperation.admissible, h]

theorem reservationConsumesNonce (payment : PaymentOperation)
    (authorization : PaymentAuthorization) (policy : PaymentAuditPolicy)
    (state next : PaymentState) (evidence : List AuditEvidence)
    (h : payment.reserve authorization policy state evidence = some next) :
    next.usedNonces = payment.nonce :: state.usedNonces := by
  unfold PaymentOperation.reserve at h
  split at h
  · cases h
    rfl
  · simp at h

theorem reservedPaymentCannotReplay (payment : PaymentOperation)
    (authorization : PaymentAuthorization) (policy : PaymentAuditPolicy)
    (state next : PaymentState) (evidence : List AuditEvidence)
    (h : payment.reserve authorization policy state evidence = some next) :
    payment.reserve authorization policy next evidence = none := by
  have hnonce := reservationConsumesNonce payment authorization policy state next evidence h
  simp [PaymentOperation.reserve, PaymentOperation.admissible, hnonce]

end CedarPooSpec.Vertical.FinancialServices
