import Examples.Data.StorageEffectFixture

namespace CedarPooSpec.Data.StorageEffectTests

open CedarPooSpec.Data.StorageEffectFixture

/-- The exported matrix has two accepted raw effects and fifteen vetoes. -/
theorem exactRawStorageDecisions :
    (cases.map fun (_, effect, claim, current) => effect.rawAdmitted claim current) =
      [true, true, false, false, false, false, false, false, false, false, false,
       false, false, false, false, false, false] := by
  native_decide

end CedarPooSpec.Data.StorageEffectTests
