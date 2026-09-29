import Cedar.Spec.Policy

/-!
Typed source provenance for a derived result. The Host authenticates source
labels and binds them to the actual transformation and output bytes.
-/

namespace CedarPooSpec.Data

open Cedar.Spec

structure SourceLabel where
  resource : EntityUID
  owner : EntityUID
  tenant : String
  restricted : Bool
  deriving DecidableEq

structure DerivedArtifact where
  digest : String
  sources : List SourceLabel
  deriving DecidableEq

structure Destination where
  resource : EntityUID
  tenant : String
  acceptedOwners : List EntityUID
  acceptsRestricted : Bool
  deriving DecidableEq

/-- A derived result retains every declared source; transformation alone
    cannot drop a restricted source label. -/
def DerivedArtifact.combine (left right : DerivedArtifact)
    (resultDigest : String) : DerivedArtifact :=
  { digest := resultDigest, sources := left.sources ++ right.sources }

/-- A source can flow only to a destination that accepts its tenant, owner,
    and sensitivity. This is a label check, not semantic declassification. -/
def DerivedArtifact.canFlowTo (artifact : DerivedArtifact)
    (destination : Destination) : Bool :=
  !artifact.digest.isEmpty && !artifact.sources.isEmpty &&
    artifact.sources.all fun source =>
      source.tenant == destination.tenant &&
      destination.acceptedOwners.contains source.owner &&
      (!source.restricted || destination.acceptsRestricted)

end CedarPooSpec.Data
