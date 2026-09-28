/-!
Model the knowledge revealed by a person's cumulative asset exposure. A
single low-sensitivity fragment can participate in a sensitive combination.
Asset owners define the catalog, task needs, and critical combinations; this
module does not discover information flow or infer an employee's intent.
-/

namespace CedarPooSpec.Governance.Personnel.KnowledgeScope

structure Fragment (Asset Fact : Type) where
  asset : Asset
  reveals : List Fact

structure Task (Fact : Type) where
  needs : List Fact

structure Boundary (Fact : Type) where
  criticalCombinations : List (List Fact)

structure Ledger (Asset : Type) where
  observed : List Asset := []

/-- A person retains knowledge of previously observed assets after a grant is
    withdrawn. The Host supplies observations from actual mediated effects. -/
def Ledger.observe {Asset : Type} [BEq Asset] (ledger : Ledger Asset)
    (asset : Asset) : Ledger Asset :=
  if ledger.observed.contains asset then ledger
  else { observed := ledger.observed ++ [asset] }

def revealed {Asset Fact : Type} [BEq Asset]
    (catalog : List (Fragment Asset Fact)) (ledger : Ledger Asset) : List Fact :=
  (catalog.filter (fun fragment => ledger.observed.contains fragment.asset)).flatMap
    Fragment.reveals

structure Assessment where
  taskCovered : Bool
  criticalCombinationExposed : Bool
  observedAssetCount : Nat
  deriving BEq, Repr

/-- Compare task sufficiency and exposure using the same observed assets. -/
def assess {Asset Fact : Type} [BEq Asset] [BEq Fact]
    (catalog : List (Fragment Asset Fact)) (ledger : Ledger Asset)
    (task : Task Fact) (boundary : Boundary Fact) : Assessment :=
  let known := revealed catalog ledger
  { taskCovered := task.needs.all known.contains
    criticalCombinationExposed := boundary.criticalCombinations.any
      (fun combination => combination.all known.contains)
    observedAssetCount := ledger.observed.length }

inductive AdmissionError where
  | criticalCombination
  deriving BEq, Repr

/-- Check one proposed observation against the person's cumulative ledger.
    The Host must make admission and ledger persistence atomic with the real
    read or download; this pure check alone cannot enforce that ordering. -/
def admit {Asset Fact : Type} [BEq Asset] [BEq Fact]
    (catalog : List (Fragment Asset Fact)) (boundary : Boundary Fact)
    (ledger : Ledger Asset) (asset : Asset) :
    Except AdmissionError (Ledger Asset) :=
  let next := ledger.observe asset
  let known := revealed catalog next
  if boundary.criticalCombinations.any
      (fun combination => combination.all known.contains) then
    .error .criticalCombination
  else .ok next

end CedarPooSpec.Governance.Personnel.KnowledgeScope
