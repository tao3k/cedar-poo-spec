import CedarPooSpec.Governance.Veto

/-!
Shared authorization controls for a patient-bound clinical exchange. The
Host supplies authenticated identifier and payload evidence. This module
does not parse documents, verify terminology, or certify interoperability.
-/

namespace CedarPooSpec.Vertical.Health.ClinicalExchange

open Cedar.Spec CedarPooSpec.Governance

private def attr (source : Var) (name : String) : Expr :=
  .getAttr (.var source) name
private def fact (name : String) : Expr := attr .context name
private def negated (body : Expr) : Expr := .unaryApp .not body

/-- A common patient/identifier boundary for clinical reads or writes. -/
structure PatientBinding where
  policyId : PolicyID
  actionScope : ActionScope
  patientAttribute : String := "patient"
  subjectPatientFact : String := "subjectPatient"
  identifierVerifiedFact : String := "identifierVerified"

def PatientBinding.control (binding : PatientBinding) : Veto :=
  { policyId := binding.policyId, actionScope := binding.actionScope,
    denyWhen := .or
      (negated (.binaryApp .eq
        (attr .resource binding.patientAttribute)
        (fact binding.subjectPatientFact)))
      (negated (fact binding.identifierVerifiedFact)) }

/-- Reuse a Host-attested payload only for the document digest it covered. -/
structure PayloadBinding where
  policyId : PolicyID
  actionScope : ActionScope
  contentAttestedFact : String := "contentAttested"
  digestMatchesFact : String := "sourceDigestMatches"

def PayloadBinding.control (binding : PayloadBinding) : Veto :=
  { policyId := binding.policyId, actionScope := binding.actionScope,
    denyWhen := .or (negated (fact binding.contentAttestedFact))
      (negated (fact binding.digestMatchesFact)) }

end CedarPooSpec.Vertical.Health.ClinicalExchange
