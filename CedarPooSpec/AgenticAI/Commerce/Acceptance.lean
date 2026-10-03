/-! Single-root provider acceptance fence. The provider authenticates and persists
updates and serializes this check with its protected acceptance event. A root cut
at the issuer alone is not evidence that a provider installed the fence. -/
namespace CedarPooSpec.AgenticAI.Commerce

structure AuthorizationRoot where
  budgetScope : String
  mandateId : String
  deriving DecidableEq, Repr

structure RootFence where
  root : AuthorizationRoot
  generation : Nat
  retired : Bool
  deriving DecidableEq, Repr

structure AcceptanceTicket where
  root : AuthorizationRoot
  generation : Nat
  providerId : String
  operationId : String
  requestCommitment : String
  deriving DecidableEq, Repr

def RootFence.advance (current next : RootFence) : Option RootFence :=
  if next.root = current.root ∧ next.generation > current.generation ∧
      (current.retired = true → next.retired = true) then some next else none

def RootFence.accepts (fence : RootFence) (ticket : AcceptanceTicket)
    (providerId operationId requestCommitment : String) : Bool :=
  !fence.retired && decide (ticket.root = fence.root) &&
  decide (ticket.generation = fence.generation) &&
  !fence.root.budgetScope.isEmpty && !fence.root.mandateId.isEmpty &&
  !providerId.isEmpty && !operationId.isEmpty && !requestCommitment.isEmpty &&
  ticket.providerId == providerId && ticket.operationId == operationId &&
  ticket.requestCommitment == requestCommitment

theorem retiredFenceRejects (fence : RootFence) (ticket : AcceptanceTicket)
    (provider operation commitment : String) (h : fence.retired = true) :
    fence.accepts ticket provider operation commitment = false := by
  simp [RootFence.accepts, h]

theorem staleGenerationRejects (fence : RootFence) (ticket : AcceptanceTicket)
    (provider operation commitment : String) (h : ticket.generation ≠ fence.generation) :
    fence.accepts ticket provider operation commitment = false := by
  simp [RootFence.accepts, h]

theorem advanceIncreasesGeneration (current next : RootFence)
    (h : current.advance next = some next) : next.generation > current.generation := by
  simp only [RootFence.advance] at h
  split at h <;> simp_all

theorem retirementIsPermanent (current next : RootFence)
    (h : current.advance next = some next) (retired : current.retired = true) :
    next.retired = true := by
  simp only [RootFence.advance] at h
  split at h <;> simp_all

/-- Endpoint-owned state bound to the immutable dispatch commitment. Accepted
means the protected endpoint durably took responsibility; it is not settlement. -/
structure DispatchOwnership where
  requestCommitment : String
  generation : Nat
  owner : String
  accepted : Bool
  deriving DecidableEq, Repr

def DispatchOwnership.acquire (state : DispatchOwnership) (expected : Nat)
    (worker : String) : Option DispatchOwnership :=
  if state.accepted then none else
  if expected = state.generation ∧ ¬worker.isEmpty ∧ ¬state.requestCommitment.isEmpty then
    some { state with generation := state.generation + 1, owner := worker }
  else none

def DispatchOwnership.accept (state : DispatchOwnership) (generation : Nat)
    (worker commitment : String) : Option DispatchOwnership :=
  if state.accepted then none else
  if generation = state.generation ∧ worker = state.owner ∧ ¬worker.isEmpty ∧
      commitment = state.requestCommitment ∧ ¬commitment.isEmpty then
    some { state with accepted := true }
  else none

theorem acceptedCannotReacquire (state : DispatchOwnership) (expected : Nat)
    (worker : String) (h : state.accepted = true) : state.acquire expected worker = none := by
  simp [DispatchOwnership.acquire, h]

theorem acceptedCannotAcceptAgain (state : DispatchOwnership) (generation : Nat)
    (worker commitment : String) (h : state.accepted = true) :
    state.accept generation worker commitment = none := by
  simp [DispatchOwnership.accept, h]

theorem obsoleteOwnerCannotAccept (state : DispatchOwnership) (generation : Nat)
    (worker commitment : String) (h : generation ≠ state.generation) :
    state.accept generation worker commitment = none := by
  unfold DispatchOwnership.accept
  split <;> simp_all

end CedarPooSpec.AgenticAI.Commerce
