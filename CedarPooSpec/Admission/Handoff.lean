import Cedar.Spec.Policy
import LeanPoo.Object.Definition

/-! A value-level cross-organization handoff contract. A trusted Host must
authenticate the grant and bind its claim digest to the actual data before
calling admission. This module does not issue or verify credentials. -/

namespace CedarPooSpec.Admission.Handoff

open Cedar.Spec LeanPoo

structure Scope where
  caseId : String
  claimDigest : String
  sourceActor : EntityUID
  targetActor : EntityUID
  sourceRoot : String
  targetRoot : String
  credentialMode : String
  deriving BEq

structure Grant where
  scope : Scope
  epoch : Nat
  expiresAt : Nat

/-- Exact scope, current epoch, and expiration are checked after Host
    authentication. Revocation advances the Host's epoch. -/
def Grant.admits (grant : Grant) (expected : Scope)
    (currentEpoch now : Nat) : Bool :=
  !expected.caseId.isEmpty && !expected.claimDigest.isEmpty &&
  !expected.sourceRoot.isEmpty && !expected.targetRoot.isEmpty &&
  !expected.credentialMode.isEmpty &&
  expected.sourceActor != expected.targetActor &&
  grant.scope == expected && grant.epoch == currentEpoch &&
  now < grant.expiresAt

inductive Key where
  | caseId
  | claimDigest
  | scope
  deriving DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable

abbrev Value : Key → Type
  | .caseId => String
  | .claimDigest => String
  | .scope => Scope

abbrev Object := LeanPoo.Object.Memoized Key Value

def define (name : String) (initial : Scope) : Except C4.Error Object :=
  LeanPoo.Object.define name do
    LeanPoo.Object.Declaration.Builder.value .caseId initial.caseId
    LeanPoo.Object.Declaration.Builder.value .claimDigest initial.claimDigest
    LeanPoo.Object.Declaration.Builder.slot .scope
      (.self fun self => do
        let caseId ← self .caseId
        let claimDigest ← self .claimDigest
        pure ⟨caseId, claimDigest, initial.sourceActor, initial.targetActor,
          initial.sourceRoot, initial.targetRoot, initial.credentialMode⟩)

def onCase (parent : Object) (name caseId claimDigest : String) :
    Except C4.Error Object :=
  parent.extendWith name do
    LeanPoo.Object.Declaration.Builder.value .caseId caseId
    LeanPoo.Object.Declaration.Builder.value .claimDigest claimDigest

def scope? (profile : Object) : Option Scope := profile.read .scope

end CedarPooSpec.Admission.Handoff
