import Examples.Enterprise.AWS.FinancialServices.ClaimSettlementHandoff

namespace CedarPooSpec.AWS.ClaimSettlementHandoffTest

open CedarPooSpec.Admission
open CedarPooSpec.AWS.ClaimSettlementHandoff

def otherSelection : Selection :=
  { selected with caseId := "claim-002", claimDigest := "sha256:claim-002" }

def otherGrant : Handoff.Grant :=
  { scope := otherSelection.scope, epoch := 7, expiresAt := 20 }

def wrongActorSelection : Selection :=
  let actors := { selected.actors with
    bankOperator := CedarPooSpec.MultiAccountBankingExample.colleague }
  { selected with actors }

theorem scopeIsInheritedButCaseDataMustMatch :
    caseProfile.read .caseId = some "claim-001" ∧
    otherCaseProfile.read .caseId = some "claim-002" ∧
    otherCaseProfile.plan.precedence = ["Claim002", "Claim001"] ∧
    admitted caseProfile grant selected = true ∧
    admitted otherCaseProfile otherGrant otherSelection = true ∧
    admitted otherCaseProfile grant selected = false ∧
    admitted caseProfile grant { selected with caseId := "claim-002" } = false ∧
    admitted caseProfile grant
      { selected with claimDigest := "sha256:other" } = false ∧
    admitted caseProfile grant wrongActorSelection = false ∧
    admitted caseProfile grant
      { selected with claimRoot := "SourceCombined" } = false ∧
    admitted caseProfile grant
      { selected with mode := "OBO" } = false ∧
    admitted caseProfile grant
      { selected with currentEpoch := 8 } = false ∧
    admitted caseProfile grant
      { selected with now := 20 } = false ∧
    admitted caseProfile grant
      { selected with geography := some "EU" } = false := by
  native_decide

end CedarPooSpec.AWS.ClaimSettlementHandoffTest
