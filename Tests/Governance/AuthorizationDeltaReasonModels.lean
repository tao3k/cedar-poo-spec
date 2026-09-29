import Examples.Governance.TicketSharing

namespace CedarPooSpec.AuthorizationDeltaReasonModels

open Cedar.Spec CedarPooSpec.PolicyModules CedarPooSpec.TicketSharingExample

def primary : Policy :=
  (policiesV1.find? (·.id == "alice-ticket-a")).get (by native_decide)

def fallback : Policy := { primary with id := "alice-ticket-a-fallback" }

def incidentVeto : Policy :=
  { primary with
    id := "incident-veto",
    effect := .forbid,
    condition := [{ kind := .when, body := .lit (.bool true) }] }

def sharedModel : Model :=
  let base := (({ modules := [] } : Model).mix "Shared" []
    [.extend primary, .extend fallback]).toOption.get (by native_decide)
  (base.extend "OneGrantRemoved" "Shared" [.remove primary.id]).toOption.get
    (by native_decide)

def maskedModel : Model :=
  let base := (({ modules := [] } : Model).mix "Masked" []
    [.extend primary, .extend fallback, .extend incidentVeto]).toOption.get
      (by native_decide)
  (base.extend "MaskedOneRemoved" "Masked" [.remove primary.id]).toOption.get
    (by native_decide)

def ownerModel : Model :=
  (sharedModel.extend "OwnershipShift" "Shared" [.overlay primary]).toOption.get
    (by native_decide)

end CedarPooSpec.AuthorizationDeltaReasonModels
