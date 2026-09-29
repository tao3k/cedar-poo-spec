import Examples.Enterprise.AWS.FinancialServices.ClaimSettlement
import CedarPooSpec.Admission.Handoff

/-! A synthetic Host admission for the proposed insurance-to-bank handoff.
Gateway decisions remain in ClaimSettlement; the Host must authenticate the
grant and bind its claim digest to the actual data and payment effect. -/

namespace CedarPooSpec.AWS.ClaimSettlementHandoff

open CedarPooSpec.Admission CedarPooSpec.AWS.ClaimSettlement

structure Selection where
  caseId : String
  claimDigest : String
  actors : Actors
  claimRoot : String := "FailClosed"
  bankRoot : String := "OwnerCombined"
  mode : String := "SourceM2M"
  geography : Option String := some "US"
  currentEpoch : Nat := 7
  now : Nat := 10

def Selection.scope (selection : Selection) : Handoff.Scope :=
  ⟨selection.caseId, selection.claimDigest,
    selection.actors.adjuster, selection.actors.bankOperator,
    selection.claimRoot, selection.bankRoot, selection.mode⟩

def selected : Selection :=
  { caseId := "claim-001", claimDigest := "sha256:claim-001",
    actors := sampleActors }

def caseProfile : Handoff.Object :=
  (Handoff.define "Claim001" selected.scope).toOption.get
    (by native_decide)

def otherCaseProfile : Handoff.Object :=
  (Handoff.onCase caseProfile "Claim002" "claim-002" "sha256:claim-002")
    |>.toOption.get (by native_decide)

def grant : Handoff.Grant :=
  { scope := selected.scope, epoch := 7, expiresAt := 20 }

/-- The configured POO profile and authenticated grant must both cover the
    Host-selected case, data digest, actors, and policy roots. -/
def admitted (profile : Handoff.Object) (handoff : Handoff.Grant)
    (selection : Selection) : Bool :=
  match Handoff.scope? profile with
  | none => false
  | some configured =>
      configured == selection.scope &&
      handoff.admits configured selection.currentEpoch selection.now &&
      gatewayPlanAllows selection.claimRoot selection.bankRoot selection.mode
        selection.actors selection.geography

end CedarPooSpec.AWS.ClaimSettlementHandoff
