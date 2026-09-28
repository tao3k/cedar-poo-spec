import CedarPooSpec.Vertical.Health.ClinicalExchange

/-!
Australian eMR contribution profile for Cedar authorization. FHIR, AUCDI,
AU Core, identifier-service, and terminology conformance remain Host inputs.
The instance owner selects applicable published versions and validates them.
-/

namespace CedarPooSpec.Vertical.Health.Region.Australia

open Cedar.Spec CedarPooSpec.PolicyModules CedarPooSpec.Governance

private def attr (source : Var) (name : String) : Expr :=
  .getAttr (.var source) name
private def fact (name : String) : Expr := attr .context name
private def equals (left right : Expr) : Expr := .binaryApp .eq left right
private def literal (value : String) : Expr := .lit (.string value)
private def negated (body : Expr) : Expr := .unaryApp .not body

/-- An application-chosen eMR document upload slot. -/
structure EMRUpload where
  policyId : PolicyID
  action : EntityUID
  principalKind : String
  documentKind : String
  purpose : String
  kindAttribute : String := "kind"
  patientAttribute : String := "patient"
  subjectPatientFact : String := "subjectPatient"
  purposeFact : String := "purpose"
  identifierVerifiedFact : String := "ihiVerified"
  patientDeclinedFact : String := "patientDeclinedUpload"
  contentAttestedFact : String := "contentAttested"
  digestMatchesFact : String := "sourceDigestMatches"

def EMRUpload.policy (profile : EMRUpload) : Policy :=
  { id := profile.policyId, effect := .permit,
    principalScope := .principalScope .any,
    actionScope := .actionScope (.eq profile.action),
    resourceScope := .resourceScope .any,
    condition := [{ kind := .when, body := (
      .and (equals (attr .principal profile.kindAttribute)
        (literal profile.principalKind))
        (.and (equals (attr .resource profile.kindAttribute)
          (literal profile.documentKind))
          (.and (equals (attr .resource profile.patientAttribute)
            (fact profile.subjectPatientFact))
            (.and (equals (fact profile.purposeFact) (literal profile.purpose))
              (.and (fact profile.identifierVerifiedFact)
                (.and (negated (fact profile.patientDeclinedFact))
                  (.and (fact profile.contentAttestedFact)
                    (fact profile.digestMatchesFact)))))))) }] }

def EMRUpload.strengthen (profile : EMRUpload) : Edit :=
  .overlay profile.policy

def EMRUpload.patientInstruction (profile : EMRUpload)
    (policyId : PolicyID) : Veto :=
  { policyId, actionScope := .actionScope (.eq profile.action),
    denyWhen := fact profile.patientDeclinedFact }

end CedarPooSpec.Vertical.Health.Region.Australia
