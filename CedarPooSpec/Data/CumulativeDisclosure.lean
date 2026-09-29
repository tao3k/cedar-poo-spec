/-!
A finite cumulative-disclosure ledger. The Host authenticates each candidate
set from the actual result and persists `record` atomically with budget and
audit updates. Cardinality is a singling-out indicator, not a privacy proof.
-/

namespace CedarPooSpec.Data.CumulativeDisclosure

structure Ledger where
  possibleIds : List String := []
  minimum : Nat := 0
  deriving DecidableEq

/-- Candidate IDs still compatible with every accepted disclosure. -/
def Ledger.narrowed (ledger : Ledger) (candidateIds : List String) : List String :=
  (ledger.possibleIds.filter fun id => candidateIds.contains id).eraseDups

def Ledger.admits (ledger : Ledger) (candidateIds : List String) : Bool :=
  ledger.minimum == 0 ||
    (!candidateIds.isEmpty &&
      (ledger.narrowed candidateIds).length >= ledger.minimum)

def Ledger.record (ledger : Ledger) (candidateIds : List String) : Option Ledger :=
  if !ledger.admits candidateIds then none
  else if ledger.minimum == 0 then some ledger
  else some { ledger with possibleIds := ledger.narrowed candidateIds }

end CedarPooSpec.Data.CumulativeDisclosure
