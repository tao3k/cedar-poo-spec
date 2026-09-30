import Productions.Pseudonymization.TableBatchFixture

namespace CedarPooSpec.Pseudonymization.TableBatchTests

open CedarPooSpec.Pseudonymization.TableBatchFixture

theorem exactBatchDecisions :
    (cases.filter fun (_, recipe, rows, maxRows, maxBytes) =>
      (recipe.selectBatch rows maxRows maxBytes).isOk).length = 2 ∧
    cases.length = 13 := by
  native_decide

end CedarPooSpec.Pseudonymization.TableBatchTests
