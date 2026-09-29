import Std.Data.HashSet

/-!
An ordered provenance catalog for data derived from other data. A parent must
already be present, so validation establishes a finite acyclic graph without
an independent graph traversal or a fixed recursion limit. The Host must
authenticate the catalog against actual data and transformation receipts.
-/

namespace CedarPooSpec.Data.Lineage

inductive Kind where
  | source | fragment | index | prompt | result | other (name : String)
  deriving Repr, BEq, DecidableEq

structure Artifact where
  id : String
  kind : Kind
  parents : List String := []
  deriving Repr, BEq, DecidableEq

inductive Error where
  | emptyId
  | duplicate (id : String)
  | missingParent (child parent : String)
  | unknownWithdrawal (id : String)
  deriving Repr, BEq, DecidableEq

structure Catalog where
  artifacts : List Artifact
  deriving Repr, BEq, DecidableEq

/-- Ordered registration rejects missing parents and therefore cycles. -/
def Catalog.validate (catalog : Catalog) : Except Error Unit := do
  let mut seen : Std.HashSet String := {}
  for artifact in catalog.artifacts do
    if artifact.id.isEmpty then throw .emptyId
    if seen.contains artifact.id then throw (.duplicate artifact.id)
    for parent in artifact.parents do
      if !seen.contains parent then throw (.missingParent artifact.id parent)
    seen := seen.insert artifact.id

/-- All descendants of withdrawn artifacts, including the withdrawn roots.
    An error never becomes an empty impact set. -/
def Catalog.affected (catalog : Catalog) (withdrawn : List String) :
    Except Error (List String) := do
  catalog.validate
  let ids := Std.HashSet.ofList (catalog.artifacts.map (·.id))
  let withdrawnSet := Std.HashSet.ofList withdrawn
  for id in withdrawn do
    if !ids.contains id then
      throw (.unknownWithdrawal id)
  let mut impacted : List String := []
  let mut impactedSet : Std.HashSet String := {}
  for artifact in catalog.artifacts do
    if withdrawnSet.contains artifact.id ||
        artifact.parents.any impactedSet.contains then
      impacted := artifact.id :: impacted
      impactedSet := impactedSet.insert artifact.id
  return impacted.reverse

/-- A target can be used only when it exists and no withdrawn ancestor reaches
    it. This is a catalog result, not an authorization or deletion receipt. -/
def Catalog.available (catalog : Catalog) (withdrawn : List String)
    (target : String) : Except Error Bool := do
  let affected ← catalog.affected withdrawn
  return catalog.artifacts.any (·.id == target) && !affected.contains target

end CedarPooSpec.Data.Lineage
