import Examples.Enterprise.Personnel.SourceCustody
import CedarPooSpec.Governance.Personnel.Admission

namespace CedarPooSpec.SourceCustodyTest

open Cedar.Validation CedarPooSpec.SourceCustodyExample

theorem startupDecisions :
    decision "SmallTeam" normalRead = true ∧
    decision "SmallTeam" stolenRead = false ∧
    decision "SmallTeam" researcherRead = true ∧
    decision "SmallTeam" researcherCrown = false ∧
    decision "SmallTeam" internSharedRead = true ∧
    decision "SmallTeam" internResearchRead = false ∧
    decision "SmallTeam" internResearchDownload = false ∧
    decision "SmallTeam" researcherARead = true ∧
    decision "SmallTeam" researcherAWrongProjectRead = false ∧
    decision "SmallTeam" researcherBRead = true ∧
    decision "Isolated" researcherAInterfaceRead = false ∧
    decision "SmallTeam" researcherAInterfaceRead = true ∧
    decision "SmallTeam" researcherAFullBRead = false ∧
    decision "SmallTeam" researcherADownload = true ∧
    decision "SmallTeam" researcherBWrongDownload = false ∧
    decision "SmallTeam" founderDownload = true ∧
    decision "SmallTeam" founderCrownDownload = false ∧
    decision "SmallTeam" agentReadWithoutDelegation = false ∧
    decision "SmallTeam" agentReadWithDelegation = true ∧
    decision "SmallTeam" agentReadAfterExpiry = false ∧
    decision "SmallTeam" (approvedRelease 1) = true ∧
    decision "SmallTeam" (approvedRelease 2) = false ∧
    decision "SmallTeam" normalSliceRead = true ∧
    decision "SmallTeam" attemptedExternalTransfer = false ∧
    decision "SmallTeam" attemptedAgentTransfer = false ∧
    decision "SmallTeam" (agentRelease readDelegation) = false ∧
    decision "SmallTeam" (agentRelease releaseDelegation) = true ∧
    decision "SmallTeam" attemptedPartialSale = false ∧
    decision "SmallTeam" crownRelease = false := by
  native_decide

theorem personnelLifecycle :
    decisionIn "SmallTeam" departingEntities normalRead = true ∧
    decisionIn "SmallTeam" departingEntities founderDownload = false ∧
    decisionIn "SmallTeam" departingEntities (approvedRelease 1) = false ∧
    decisionIn "SmallTeam" separatedEntities normalRead = false ∧
    decisionIn "SmallTeam" separatedEntities agentReadWithDelegation = false := by
  native_decide

theorem taskKnowledgeTradeoff :
    isolatedAssessment.taskCovered = false ∧
    isolatedAssessment.criticalCombinationExposed = false ∧
    interfaceAssessment.taskCovered = true ∧
    interfaceAssessment.criticalCombinationExposed = false ∧
    fullSourceAssessment.taskCovered = true ∧
    fullSourceAssessment.criticalCombinationExposed = true ∧
    (fullSourceExposure.observe researchBSource).observed =
      fullSourceExposure.observed := by
  native_decide

def interfaceAdmitted : Bool :=
  match CedarPooSpec.Governance.Personnel.KnowledgeScope.admit
      knowledgeCatalog architectureBoundary isolatedExposure researchBInterface with
  | .ok ledger => ledger.observed == interfaceExposure.observed
  | .error _ => false
def fullSourceRejected : Bool :=
  match CedarPooSpec.Governance.Personnel.KnowledgeScope.admit
      knowledgeCatalog architectureBoundary isolatedExposure researchBSource with
  | .error .criticalCombination => true
  | _ => false

theorem cumulativeKnowledgeAdmission :
    interfaceAdmitted = true ∧ fullSourceRejected = true := by
  native_decide

def integratedInterfaceAdmitted : Bool :=
  match CedarPooSpec.Governance.Personnel.authorizeAndObserve model "SmallTeam"
      entities researcherAInterfaceRead researcherAInterfaceRead.effect
      researcherAInterfaceRead.state knowledgeCatalog architectureBoundary
      isolatedExposure with
  | .ok (receipt, ledger) => receipt.allowed &&
      ledger.observed == interfaceExposure.observed
  | .error _ => false

def integratedFullSourceRejected : Bool :=
  match CedarPooSpec.Governance.Personnel.authorizeAndObserve model "SmallTeam"
      entities founderReadB founderReadB.effect founderReadB.state
      knowledgeCatalog architectureBoundary isolatedExposure with
  | .error (.knowledge .criticalCombination) => true
  | _ => false

def trustedCoreException : Bool :=
  let explicitlyAccepted : CedarPooSpec.Governance.Personnel.KnowledgeScope.Boundary String :=
    ⟨[]⟩
  match CedarPooSpec.Governance.Personnel.authorizeAndObserve model "SmallTeam"
      entities founderReadB founderReadB.effect founderReadB.state
      knowledgeCatalog explicitlyAccepted isolatedExposure with
  | .ok (receipt, ledger) => receipt.allowed &&
      ledger.observed == fullSourceExposure.observed
  | .error _ => false

theorem integratedKnowledgeBoundary :
    integratedInterfaceAdmitted = true ∧
    integratedFullSourceRejected = true ∧
    trustedCoreException = true := by
  native_decide

theorem organizationAndIncidentDecisions :
    partnerRead "SmallTeam" = false ∧
    partnerRead "LargeTeam" = true ∧
    decision "LargeTeam" incidentRelease = false ∧
    decision "Incident" (approvedRelease 1) = false ∧
    decision "Incident" normalRead = true ∧
    decision "Recovered" (approvedRelease 1) = true := by
  native_decide

def validRoot (root : String) : Bool :=
  match model.compile root with
  | .error _ => false
  | .ok policies =>
      match validate policies schema with
      | .ok () => true
      | .error _ => false

theorem policiesValidate :
    validRoot "Isolated" = true ∧
    validRoot "SmallTeam" = true ∧
    validRoot "LargeTeam" = true ∧
    validRoot "Incident" = true ∧
    validRoot "Recovered" = true := by
  native_decide

def wrongEpochRejected : Bool :=
  let operation := approvedRelease 1
  let later := { operation.state with epoch := 2 }
  match CedarPooSpec.Admission.BoundOperation.authorize operation
      operation.effect later model "SmallTeam" entities with
  | .error .stateMismatch => true
  | _ => false

def divertedDestinationRejected : Bool :=
  let operation := approvedRelease 1
  let diverted := { operation.effect with destination := competitorSink }
  match CedarPooSpec.Admission.BoundOperation.authorize operation
      diverted operation.state model "SmallTeam" entities with
  | .error .effectMismatch => true
  | _ => false

theorem executionMustMatchAdmission :
    wrongEpochRejected = true ∧
    divertedDestinationRejected = true := by
  native_decide

end CedarPooSpec.SourceCustodyTest
