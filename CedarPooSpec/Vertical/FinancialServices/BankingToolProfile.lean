import CedarPooSpec.Vertical.FinancialServices.BankingToolOwner
import LeanPoo.Object.Definition

/-! A typed prototype for one banking tool owner. The parent keeps its
original action list; an inherited slot rebuilds the owner from final self. -/

namespace CedarPooSpec.Vertical.FinancialServices.BankingToolProfile

open Cedar.Spec LeanPoo

inductive Key where
  | actions
  | owner
  deriving DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable

abbrev Value : Key → Type
  | .actions => List EntityUID
  | .owner => BankingToolOwner

abbrev Object := LeanPoo.Object.Memoized Key Value

def define (name : String) (initial : BankingToolOwner) :
    Except C4.Error Object :=
  LeanPoo.Object.define name do
    LeanPoo.Object.Declaration.Builder.value .actions initial.actions
    LeanPoo.Object.Declaration.Builder.slot .owner
      (.self fun self =>
        (self .actions).map fun actions => { initial with actions })

def onActions (parent : Object) (name : String) (actions : List EntityUID) :
    Except C4.Error Object :=
  parent.extendWith name do
    LeanPoo.Object.Declaration.Builder.value .actions actions

def owner? (profile : Object) : Option BankingToolOwner :=
  profile.read .owner

end CedarPooSpec.Vertical.FinancialServices.BankingToolProfile
