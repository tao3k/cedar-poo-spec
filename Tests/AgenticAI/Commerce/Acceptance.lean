import CedarPooSpec.AgenticAI.Commerce.Acceptance
import Lean
namespace CedarPooSpec.AgenticAI.CommerceAcceptanceTest
open CedarPooSpec.AgenticAI.Commerce
open Lean

def root : AuthorizationRoot := ⟨"buyer-trip-root", "trip-root"⟩
def fence : RootFence := ⟨root, 7, false⟩
def ticket : AcceptanceTicket := ⟨root, 7, "processor", "purchase-42", "body-42"⟩
def retired : RootFence := ⟨root, 8, true⟩
def rotated : RootFence := ⟨root, 8, false⟩
def other : RootFence := ⟨⟨"unrelated", "other-root"⟩, 99, true⟩

theorem freshAccepts : fence.accepts ticket "processor" "purchase-42" "body-42" = true := by decide
theorem pausedThenRetiredRejects : retired.accepts ticket "processor" "purchase-42" "body-42" = false := by decide
theorem rotatedKeyRejects : rotated.accepts ticket "processor" "purchase-42" "body-42" = false := by decide
theorem retirementCannotReopen : retired.advance ⟨root, 9, false⟩ = none := by decide
theorem generationCannotRollback : rotated.advance fence = none := by decide
theorem otherRootCannotAdvance : fence.advance other = none := by decide

private def rootJson (r : AuthorizationRoot) : Json := Json.mkObj [
  ("budgetScope", toJson r.budgetScope), ("mandateId", toJson r.mandateId)]
private def fenceJson (f : RootFence) : Json := Json.mkObj [
  ("root", rootJson f.root), ("generation", toJson f.generation), ("retired", toJson f.retired)]
private def ticketJson (t : AcceptanceTicket) : Json := Json.mkObj [
  ("root", rootJson t.root), ("generation", toJson t.generation),
  ("providerId", toJson t.providerId), ("operationId", toJson t.operationId),
  ("requestCommitment", toJson t.requestCommitment)]
private def caseJson (name : String) (f : RootFence) (t : AcceptanceTicket)
    (provider operation commitment : String) : Json := Json.mkObj [
  ("name", toJson name), ("fence", fenceJson f), ("ticket", ticketJson t),
  ("provider", toJson provider), ("operation", toJson operation), ("commitment", toJson commitment),
  ("accepted", toJson (f.accepts t provider operation commitment))]

def ready : DispatchOwnership := ⟨"body-42", 0, "fresh", false⟩
def oldOwner : DispatchOwnership := ⟨"body-42", 1, "old", false⟩
def newOwner : DispatchOwnership := ⟨"body-42", 2, "new", false⟩
def accepted : DispatchOwnership := ⟨"body-42", 2, "new", true⟩
theorem firstOwnershipIsExact : ready.acquire 0 "old" = some oldOwner := by decide
theorem takeoverIsExact : oldOwner.acquire 1 "new" = some newOwner := by decide
theorem resumedOldOwnerIsDenied : newOwner.accept 1 "old" "body-42" = none := by decide
theorem acceptanceIsExact : newOwner.accept 2 "new" "body-42" = some accepted := by decide
theorem acceptedRecoveryCannotReopen : accepted.acquire 2 "restart" = none := by decide
private def ownershipJson (s : DispatchOwnership) : Json := Json.mkObj [
  ("requestCommitment", toJson s.requestCommitment), ("generation", toJson s.generation),
  ("owner", toJson s.owner), ("accepted", toJson s.accepted)]

def fixture : Json := Json.mkObj [
  ("schema", toJson "cedar-poo.commerce.acceptance.v1"),
  ("ownership", Json.mkObj [("ready", ownershipJson ready), ("old", ownershipJson oldOwner),
    ("new", ownershipJson newOwner), ("accepted", ownershipJson accepted)]),
  ("cases", toJson ([
    caseJson "fresh" fence ticket "processor" "purchase-42" "body-42",
    caseJson "retired" retired ticket "processor" "purchase-42" "body-42",
    caseJson "rotated" rotated ticket "processor" "purchase-42" "body-42",
    caseJson "wrong-root" other ticket "processor" "purchase-42" "body-42",
    caseJson "wrong-provider" fence ticket "other" "purchase-42" "body-42",
    caseJson "wrong-operation" fence ticket "processor" "another" "body-42",
    caseJson "wrong-body" fence ticket "processor" "purchase-42" "altered",
    caseJson "empty-body" fence ticket "processor" "purchase-42" ""] : List Json))]
end CedarPooSpec.AgenticAI.CommerceAcceptanceTest

def main : IO Unit := IO.println CedarPooSpec.AgenticAI.CommerceAcceptanceTest.fixture.compress
