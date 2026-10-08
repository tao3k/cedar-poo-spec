import CedarPooSpec.AgenticAI.Commerce.Delegation

/-!
One shared allocator for a principal mandate and all its delegated branches.
Every reservation charges the root and each ancestor on its exact lineage.
The Host reauthenticates current evidence and persists this transition with an
atomic revision comparison; this pure model is not a storage transaction.
-/

namespace CedarPooSpec.AgenticAI.Commerce

/-- Keep complete authority contents, so reusing an ID cannot reset its cap. -/
structure SharedReservation where
  lineage : List Mandate
  purchase : Purchase
  deriving DecidableEq, Repr

structure SharedBudget where
  root : Mandate
  now : Nat
  reservations : List SharedReservation
  revokedMandateIds : List String
  revision : Nat
  deriving DecidableEq, Repr

def SharedBudget.spentMinor (state : SharedBudget) : Nat :=
  (state.reservations.map (fun entry => entry.purchase.terms.amountMinor)).sum

/-- A grandchild's purchase also consumes the shared cap of its parent. -/
def SharedBudget.spentUnder (state : SharedBudget)
    (mandateId : String) : Nat :=
  ((state.reservations.filter (fun entry =>
    entry.lineage.any (fun mandate => mandate.mandateId == mandateId))).map
      (fun entry => entry.purchase.terms.amountMinor)).sum

private def SharedBudget.admitsLineage (state : SharedBudget)
    (lineage : List Mandate) (final : Mandate)
    (offer : MerchantOffer) (purchase : Purchase) : Bool :=
  lineage.all (fun mandate =>
    mandate.verified && state.now < mandate.expiresAt &&
    !state.revokedMandateIds.contains mandate.mandateId &&
    state.spentUnder mandate.mandateId + offer.terms.amountMinor <= mandate.totalCap &&
    state.reservations.all (fun entry => entry.lineage.all (fun previous =>
      previous.mandateId != mandate.mandateId || decide (previous = mandate)))) &&
  ({ mandate := final, now := state.now,
     spentMinor := state.spentUnder final.mandateId,
     reservations := state.reservations.map (·.purchase),
     revoked := false, revision := state.revision } : Budget).admits
       final offer purchase

/-- The expected revision belongs to the shared root, never to an individual child.
    Scope, ancestor caps, duplicate purchases/offers, and revocation are checked
    against the state that wins the Host's atomic transaction. -/
def SharedBudget.reserve (state : SharedBudget)
    (expectedRevision : Nat) (steps : List Delegation)
    (offer : MerchantOffer) (purchase : Purchase) : Option SharedBudget :=
  if expectedRevision = state.revision then
    if state.spentMinor + purchase.terms.amountMinor <= state.root.totalCap then
      match Delegation.resolveChain state.root steps with
      | none => none
      | some final =>
          let lineage := state.root :: steps.map (·.child)
          if state.admitsLineage lineage final offer purchase then
            some { state with
              reservations := { lineage, purchase } :: state.reservations,
              revision := state.revision + 1 }
          else none
    else none
  else none

/-- Revocation invalidates prepared revisions and every descendant of this ID. -/
def SharedBudget.revoke (state : SharedBudget)
    (mandateId : String) : SharedBudget :=
  { state with
    revokedMandateIds := mandateId :: state.revokedMandateIds
    revision := state.revision + 1 }

theorem sharedStaleRevisionCannotReserve (state : SharedBudget)
    (expectedRevision : Nat) (steps : List Delegation)
    (offer : MerchantOffer) (purchase : Purchase)
    (h : expectedRevision ≠ state.revision) :
    state.reserve expectedRevision steps offer purchase = none := by
  simp [SharedBudget.reserve, h]

theorem sharedReservationAdvancesRevision (state next : SharedBudget)
    (expectedRevision : Nat) (steps : List Delegation)
    (offer : MerchantOffer) (purchase : Purchase)
    (h : state.reserve expectedRevision steps offer purchase = some next) :
    next.revision = state.revision + 1 := by
  unfold SharedBudget.reserve at h
  split at h <;> simp_all
  split at h <;> simp_all
  rcases h with ⟨_, _, rfl⟩
  rfl

theorem sharedReservationPreservesRootCap (state next : SharedBudget)
    (expectedRevision : Nat) (steps : List Delegation)
    (offer : MerchantOffer) (purchase : Purchase)
    (h : state.reserve expectedRevision steps offer purchase = some next) :
    next.spentMinor <= state.root.totalCap := by
  unfold SharedBudget.reserve at h
  split at h <;> simp_all
  split at h <;> simp_all
  rcases h with ⟨hcap, _, rfl⟩
  simpa [SharedBudget.spentMinor, Nat.add_comm] using hcap

end CedarPooSpec.AgenticAI.Commerce
