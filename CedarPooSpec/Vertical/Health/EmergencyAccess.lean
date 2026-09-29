import CedarPooSpec.PolicyModules

/-!
A patient-bound emergency read is one owned Cedar permit slot. A provisional
grant can be strengthened with session, incapacity, treatment-purpose, and
device premises through a Lean-POO overlay. The Host must authenticate each
projected fact and separately record the access event.
-/

namespace CedarPooSpec.Vertical.Health

open Cedar.Spec CedarPooSpec.PolicyModules

structure EmergencyAccess where
  policyId : PolicyID
  action : EntityUID
  grantKey : String := "breakGlassGranted"
  sessionKey : String := "sessionActive"
  incapacityKey : String := "patientUnableToConsent"
  treatmentKey : String := "treatmentPurpose"
  sessionPatientKey : String := "sessionPatient"
  recordPatientKey : String := "patient"
  deviceKey : String := "deviceTrusted"

private def context (key : String) : Expr := .getAttr (.var .context) key

def EmergencyAccess.patientMatches (access : EmergencyAccess) : Expr :=
  .binaryApp .eq (context access.sessionPatientKey)
    (.getAttr (.var .resource) access.recordPatientKey)

def EmergencyAccess.provisional (access : EmergencyAccess) : Policy :=
  let body : Expr := .and (context access.grantKey) access.patientMatches
  { id := access.policyId, effect := .permit,
    principalScope := .principalScope .any,
    actionScope := .actionScope (.eq access.action),
    resourceScope := .resourceScope .any,
    condition := [{ kind := .when, body }] }

def EmergencyAccess.valid (access : EmergencyAccess) : Expr :=
  .and (context access.grantKey)
    (.and (context access.sessionKey)
      (.and (context access.incapacityKey)
        (.and (context access.treatmentKey) access.patientMatches)))

def EmergencyAccess.bounded (access : EmergencyAccess) : Policy :=
  let valid := access.valid
  let body : Expr := .and valid (context access.deviceKey)
  { access.provisional with condition := [{ kind := .when, body }] }

def EmergencyAccess.introduce (access : EmergencyAccess) : Edit :=
  .extend access.provisional

def EmergencyAccess.strengthen (access : EmergencyAccess) : Edit :=
  .overlay access.bounded

def EmergencyAccess.withdraw (access : EmergencyAccess) : Edit :=
  .remove access.policyId

end CedarPooSpec.Vertical.Health
