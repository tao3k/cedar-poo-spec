import CedarPooSpec.Data.ProtectionProfile
import Productions.Data.ProtectedStorageFixture

namespace CedarPooSpec.Data.ProtectionProfileTests

open CedarPooSpec.Data CedarPooSpec.Data.ProtectionProfile
open CedarPooSpec.Data.ProtectedStorageFixture

private def revisedIntent? : Option ProtectionIntent := do
  let parent ← (ProtectionProfile.define "base" baseIntent).toOption
  let child ← (ProtectionProfile.withKeyVersion parent "rotated" "key-version-8").toOption
  ProtectionProfile.intent? child

private def originalIntent? : Option ProtectionIntent := do
  let parent ← (ProtectionProfile.define "base" baseIntent).toOption
  ProtectionProfile.intent? parent

theorem inheritedIntentRecomputesKeyVersion :
    revisedIntent?.map (·.keyVersion) = some "key-version-8" := by
  native_decide

theorem parentRetainsOriginalVersion :
    originalIntent?.map (·.keyVersion) = some "key-version-7" := by
  native_decide

theorem revisionRetainsCustodyAndSource :
    revisedIntent?.map (·.storage) = some baseIntent.storage := by
  native_decide

end CedarPooSpec.Data.ProtectionProfileTests
