import Productions.Data.StorageProfileMatrix

namespace CedarPooSpec.Data.StorageProfileMatrixTests

open CedarPooSpec.Data.StorageProfileMatrix

theorem completeCrossProduct : cases.length = 16 := by native_decide

theorem rawAllowsFour :
    (cases.filter fun (_, effect, current) => rawAllowed effect current).length = 4 := by
  native_decide

theorem protectedAllowsSix :
    (cases.filter fun (_, effect, current) => protectedAllowed effect current).length = 6 := by
  native_decide

end CedarPooSpec.Data.StorageProfileMatrixTests
