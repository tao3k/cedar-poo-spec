import Cedar.Spec.Policy
import LeanPoo.Object.Definition

/-! A typed LeanPOO profile for one Cedar policy owner. The setting is the
direct slot; the policy is an inherited computation over final self. Revising
the setting retains the parent object and regenerates only this policy. -/

namespace CedarPooSpec.PolicyProfile

open Cedar.Spec LeanPoo

inductive Key where
  | setting
  | policy
  deriving DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable

abbrev Value (Setting : Type) : Key → Type
  | .setting => Setting
  | .policy => Policy

abbrev Object (Setting : Type) := LeanPoo.Object.Memoized Key (Value Setting)

def define {Setting : Type} (name : String) (initial : Setting)
    (render : Setting → Policy) : Except C4.Error (Object Setting) :=
  LeanPoo.Object.define name do
    LeanPoo.Object.Declaration.Builder.value .setting initial
    LeanPoo.Object.Declaration.Builder.slot .policy
      (.self fun self => render <$> self .setting)

def revise {Setting : Type} (parent : Object Setting)
    (name : String) (setting : Setting) :
    Except C4.Error (Object Setting) :=
  parent.extendWith name do
    LeanPoo.Object.Declaration.Builder.value .setting setting

def policy? {Setting : Type} (profile : Object Setting) : Option Policy :=
  profile.read .policy

end CedarPooSpec.PolicyProfile
