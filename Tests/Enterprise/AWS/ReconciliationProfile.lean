import Examples.Enterprise.AWS.FinancialServices.Reconciliation.Reconciliation

namespace CedarPooSpec.AWS.ReconciliationProfileTest

open Cedar.Spec CedarPooSpec.AWS.Reconciliation

theorem parentsStayIntactAndComputedPoliciesFollowFinalSettings :
    writeProfile.read .setting = some "85.0" ∧
    raisedWriteProfile.read .setting = some "90.0" ∧
    raisedWriteProfile.plan.precedence = ["Write90", "Write85"] ∧
    correspondenceProfile.read .setting = some correspondenceActions ∧
    pausedCorrespondenceProfile.read .setting =
      some (correspondenceActions.filter (· != graphSend)) ∧
    pausedCorrespondenceProfile.plan.precedence =
      ["CorrespondencePaused", "CorrespondenceOpen"] ∧
    write85 = writeGate "85.0" ∧ write90 = writeGate "90.0" ∧
    correspondenceReads =
      permit "recon_correspondence_reads" (.principalScope .any)
        correspondenceActions ∧
    correspondencePaused =
      permit "recon_correspondence_reads" (.principalScope .any)
        (correspondenceActions.filter (· != graphSend)) := by
  native_decide

end CedarPooSpec.AWS.ReconciliationProfileTest
