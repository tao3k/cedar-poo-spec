import CedarPooSpec.Data.Lakehouse.LocationBoundary
import LeanPoo.Object.Definition

/-! A typed location-boundary prototype. Descendants replace only selected
fields; the inherited boundary slot reads the final object. -/

namespace CedarPooSpec.Data.Lakehouse.LocationProfile

open Cedar.Spec LeanPoo

inductive Key where
  | policyId
  | actionScope
  | location
  | denyMissing
  | boundary
  deriving DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable

abbrev Value : Key → Type
  | .policyId => PolicyID
  | .actionScope => ActionScope
  | .location => String
  | .denyMissing => Bool
  | .boundary => LocationBoundary

abbrev Object := LeanPoo.Object.Memoized Key Value

def define (name : String) (initial : LocationBoundary) :
    Except C4.Error Object :=
  LeanPoo.Object.define name do
    LeanPoo.Object.Declaration.Builder.value .policyId initial.policyId
    LeanPoo.Object.Declaration.Builder.value .actionScope initial.actionScope
    LeanPoo.Object.Declaration.Builder.value .location initial.deniedLocation
    LeanPoo.Object.Declaration.Builder.value .denyMissing initial.denyMissing
    LeanPoo.Object.Declaration.Builder.slot .boundary
      (.self fun self => do
        let policyId ← self .policyId
        let actionScope ← self .actionScope
        let deniedLocation ← self .location
        let denyMissing ← self .denyMissing
        pure { initial with policyId, actionScope, deniedLocation, denyMissing })

def boundary? (profile : Object) : Option LocationBoundary :=
  profile.read .boundary

end CedarPooSpec.Data.Lakehouse.LocationProfile
