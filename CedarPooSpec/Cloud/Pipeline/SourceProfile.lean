import CedarPooSpec.Cloud.Pipeline.SourceControlBoundary
import LeanPoo.Object.Definition

/-! A source-control prototype. A child replaces only the branch slot; the
inherited control slot reads final self and builds the corresponding policy.
This keeps branch variants in one C4 object family. -/

namespace CedarPooSpec.Cloud.Pipeline.SourceProfile

open Cedar.Spec LeanPoo

inductive Key where
  | branch
  | control
  deriving DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable

abbrev Value : Key → Type
  | .branch => String
  | .control => SourceControlBoundary

abbrev Object := LeanPoo.Object.Memoized Key Value

def define (name : String) (boundary : SourceControlBoundary) :
    Except C4.Error Object :=
  LeanPoo.Object.define name do
    LeanPoo.Object.Declaration.Builder.value .branch boundary.protectedBranch
    LeanPoo.Object.Declaration.Builder.slot .control
      (.self fun self =>
        (self .branch).map fun branch =>
          { boundary with protectedBranch := branch })

def onBranch (parent : Object) (name branch : String) :
    Except C4.Error Object :=
  parent.extendWith name do
    LeanPoo.Object.Declaration.Builder.value .branch branch

def control? (profile : Object) : Option SourceControlBoundary :=
  profile.read .control

end CedarPooSpec.Cloud.Pipeline.SourceProfile
