import Productions.Data.ProtectedStorageFixture

namespace CedarPooSpec.Data.ProtectedStorageTests

open CedarPooSpec.Data.ProtectedStorageFixture

theorem exactIntentDecisions :
    (intentCases.map fun (_, intent, claim, current) => intent.admitted claim current) =
      [true, true, false, false, false, false, false, false, false, false,
       false, false, false, false] := by
  native_decide

theorem exactPreRootDecisions :
    (publicationCases.map fun (_, publication, claim, current) =>
      publication.preRootAdmitted claim current) =
      [true, false, false, false, false, false, false, false, false] := by
  native_decide

theorem exactCommitDispositions :
    (commitCases.map fun (_, publication, claim, current, physical, existing) =>
      publication.commitDisposition claim current physical existing) =
      [.apply, .reject, .reject, .reject, .reject, .reject, .reject,
       .reject, .reject, .replay, .reject, .reject, .reject, .reject] := by
  native_decide

end CedarPooSpec.Data.ProtectedStorageTests
