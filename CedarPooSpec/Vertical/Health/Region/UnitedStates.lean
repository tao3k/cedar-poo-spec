import CedarPooSpec.Vertical.Health.ClinicalExchange

/-!
Application control objects for two distinct CMS payer API paths. The Host
owns payer applicability, FHIR/US Core/USCDI conformance, identity evidence,
treatment attribution, patient choice, and actual exchange. The module
provides selected authorization predicates for those application paths.
-/

namespace CedarPooSpec.Vertical.Health.Region.UnitedStates

open Cedar.Spec CedarPooSpec.PolicyModules CedarPooSpec.Governance

private def attr (source : Var) (name : String) : Expr :=
  .getAttr (.var source) name
private def fact (name : String) : Expr := attr .context name
private def equals (left right : Expr) : Expr := .binaryApp .eq left right
private def literal (value : String) : Expr := .lit (.string value)
private def negated (body : Expr) : Expr := .unaryApp .not body

inductive PayerPath where
  | providerAccess
  | payerToPayer

/-- One concrete payer exchange action, with path-specific patient choice. -/
structure PayerExchange where
  policyId : PolicyID
  action : EntityUID
  path : PayerPath
  principalKind : String
  resourceKind : String
  kindAttribute : String := "kind"
  patientAttribute : String := "patient"
  subjectPatientFact : String := "subjectPatient"
  identityVerifiedFact : String := "identityVerified"
  treatmentRelationshipFact : String := "treatmentRelationship"
  patientOptOutFact : String := "patientOptOut"
  patientOptInFact : String := "patientOptIn"
  contentAttestedFact : String := "contentAttested"
  digestMatchesFact : String := "sourceDigestMatches"

def PayerExchange.pathPremise (profile : PayerExchange) : Expr :=
  match profile.path with
  | .providerAccess =>
      .and (fact profile.treatmentRelationshipFact)
        (negated (fact profile.patientOptOutFact))
  | .payerToPayer => fact profile.patientOptInFact

def PayerExchange.policy (profile : PayerExchange) : Policy :=
  { id := profile.policyId, effect := .permit,
    principalScope := .principalScope .any,
    actionScope := .actionScope (.eq profile.action),
    resourceScope := .resourceScope .any,
    condition := [{ kind := .when, body := (
      .and (equals (attr .principal profile.kindAttribute)
        (literal profile.principalKind))
        (.and (equals (attr .resource profile.kindAttribute)
          (literal profile.resourceKind))
          (.and (equals (attr .resource profile.patientAttribute)
            (fact profile.subjectPatientFact))
            (.and (fact profile.identityVerifiedFact)
              (.and profile.pathPremise
                (.and (fact profile.contentAttestedFact)
                  (fact profile.digestMatchesFact))))))) }] }

def PayerExchange.strengthen (profile : PayerExchange) : Edit :=
  .overlay profile.policy

/-- An independently owned veto for the path's patient-choice rule. -/
def PayerExchange.patientChoice (profile : PayerExchange)
    (policyId : PolicyID) : Veto :=
  { policyId, actionScope := .actionScope (.eq profile.action),
    denyWhen := match profile.path with
      | .providerAccess => fact profile.patientOptOutFact
      | .payerToPayer => negated (fact profile.patientOptInFact) }

end CedarPooSpec.Vertical.Health.Region.UnitedStates
