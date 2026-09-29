import Examples.Health.MultiHospitalAI

namespace CedarPooSpec.MultiHospitalAITest

open Cedar.Spec CedarPooSpec.MultiHospitalAIExample

theorem catalogIsAcyclic : catalog.validate = .ok () := by native_decide

theorem withdrawalIsLocal :
    catalog.affected ["hospital-b-record"] = .ok
      ["hospital-b-record", "hospital-b-fragment", "joint-index",
        "agent-prompt", "study-result"] := by native_decide

theorem independentFragmentRemainsAvailable :
    catalog.available ["hospital-b-record"] "hospital-a-fragment" =
      .ok true := by native_decide

theorem unknownSourceFailsClosed :
    catalog.affected ["unverified-record"] =
      .error (.unknownWithdrawal "unverified-record") := by native_decide

theorem cyclicCatalogRejected :
    (⟨[⟨"a", .fragment, ["b"]⟩, ⟨"b", .fragment, ["a"]⟩]⟩ :
      CedarPooSpec.Data.Lineage.Catalog).validate =
      .error (.missingParent "a" "b") := by native_decide

theorem duplicateArtifactRejected :
    (⟨[⟨"a", .source, []⟩, ⟨"a", .result, ["a"]⟩]⟩ :
      CedarPooSpec.Data.Lineage.Catalog).validate =
      .error (.duplicate "a") := by native_decide

theorem researchCanDeriveBeforeWithdrawal :
    researchDecision "HospitalStudy" "r1" derive jointIndex "joint-index" [] =
      .ok (some .allow) := by native_decide

theorem wrappingKeyChangePreservesDeclaredJoin :
    hospitalAProfile.sameRecipe hospitalBProfile = true := by native_decide

theorem tokenKeyChangeBlocksResearchJoin :
    researchDecision "HospitalStudy" "r1" derive jointIndex "joint-index" []
      { hospitalBProfile with lineage :=
        { hospitalBProfile.lineage with tokenKeyVersion := "dek-2" } } =
      .ok (some .deny) := by native_decide

theorem withdrawnSourceBlocksSharedIndex :
    researchDecision "HospitalStudy" "r2" derive jointIndex "joint-index"
      ["hospital-b-record"] = .ok (some .deny) := by native_decide

theorem withdrawnSourceBlocksResultRelease :
    researchDecision "HospitalStudy" "r2" release studyResult "study-result"
      ["hospital-b-record"] = .ok (some .deny) := by native_decide

theorem treatmentOwnerRemainsIndependent :
    clinicalDecision "r2" = some .allow := by native_decide

theorem treatmentRequiresPatientBinding :
    decision "HospitalStudy" "r2"
      (request clinician emergencyRead hospitalB
        { targetArtifact := "hospital-b-record", lineageRevision := "r2",
          lineageAvailable := false, purpose := "treatment",
          emergencyActive := true }) = some .deny := by native_decide

theorem researchCannotDeriveDirectlyFromClinicalSource :
    researchDecision "HospitalStudy" "r1" derive hospitalB
      "hospital-b-record" [] = .ok (some .deny) := by native_decide

theorem wrongArtifactCannotReuseAvailability :
    (do
      let facts ← factsFor "study-result" []
      return decision "HospitalStudy" "r1"
        (request researcher derive jointIndex facts)) =
      (.ok (some .deny) : Except CedarPooSpec.Data.Lineage.Error (Option Decision)) := by
  native_decide

theorem oldLineageRevisionCannotReuseAvailability :
    (do
      let facts ← factsFor "joint-index" [] "r1"
      return decision "HospitalStudy" "r2"
        (request researcher derive jointIndex facts)) =
      (.ok (some .deny) : Except CedarPooSpec.Data.Lineage.Error (Option Decision)) := by
  native_decide

theorem incidentOnlyBlocksResultRelease :
    researchDecision "OutputIncident" "r1" release studyResult "study-result" [] =
      .ok (some .deny) := by native_decide

theorem recoveryRestoresResearchRelease :
    researchDecision "Recovered" "r1" release studyResult "study-result" [] =
      .ok (some .allow) := by native_decide

end CedarPooSpec.MultiHospitalAITest
