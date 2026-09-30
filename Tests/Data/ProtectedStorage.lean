import Productions.Data.ProtectedStorageFixture

namespace CedarPooSpec.Data.ProtectedStorageTests

open CedarPooSpec.Data.ProtectedStorageFixture

theorem exactIntentDecisions :
    (intentCases.map fun (_, intent, claim, current) => intent.admitted claim current) =
      [true, true, false, false, false, false, false, false, false, false,
       false, false, false, false] := by
  native_decide

theorem exactCommitDecisions :
    (publicationCases.map fun (_, publication, claim, current) =>
      publication.commitAdmitted claim current) =
      [true, false, false, false, false, false, false, false, false] := by
  native_decide

end CedarPooSpec.Data.ProtectedStorageTests
