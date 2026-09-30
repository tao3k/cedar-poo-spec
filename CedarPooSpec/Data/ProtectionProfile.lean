import CedarPooSpec.Data.ProtectedStorage
import LeanPoo.Object.Definition

/-!
LeanPoo-owned composition for protected storage profiles. The public wire
contract remains `ProtectionIntentV1`; this object family owns configuration
inheritance and recomputes the final intent when a child overrides a slot.
-/

namespace CedarPooSpec.Data.ProtectionProfile

open CedarPooSpec.Data LeanPoo

inductive Key where
  | storage
  | profile
  | keyRef
  | keyVersion
  | residency
  | intent
  deriving DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable

abbrev Value : Key → Type
  | .storage => StorageEffectV1
  | .profile | .keyRef | .keyVersion | .residency => String
  | .intent => ProtectionIntentV1

abbrev Object := LeanPoo.Object.Memoized Key Value

def define (name : String) (intent : ProtectionIntentV1) :
    Except C4.Error Object :=
  LeanPoo.Object.define name do
    LeanPoo.Object.Declaration.Builder.value .storage intent.storage
    LeanPoo.Object.Declaration.Builder.value .profile intent.profile
    LeanPoo.Object.Declaration.Builder.value .keyRef intent.keyRef
    LeanPoo.Object.Declaration.Builder.value .keyVersion intent.keyVersion
    LeanPoo.Object.Declaration.Builder.value .residency intent.residency
    LeanPoo.Object.Declaration.Builder.slot .intent
      (.self fun self => do
        let storage ← self .storage
        let profile ← self .profile
        let keyRef ← self .keyRef
        let keyVersion ← self .keyVersion
        let residency ← self .residency
        pure { storage, profile, keyRef, keyVersion, residency })

def withStorage (parent : Object) (name : String) (storage : StorageEffectV1) :
    Except C4.Error Object :=
  parent.extendWith name do
    LeanPoo.Object.Declaration.Builder.value .storage storage

def withKeyVersion (parent : Object) (name keyVersion : String) :
    Except C4.Error Object :=
  parent.extendWith name do
    LeanPoo.Object.Declaration.Builder.value .keyVersion keyVersion

def intent? (profile : Object) : Option ProtectionIntentV1 :=
  profile.read .intent

end CedarPooSpec.Data.ProtectionProfile
