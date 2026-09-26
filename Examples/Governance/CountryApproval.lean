import CedarPooSpec.PolicyJson

/-!
Resource-specific approver roles follow Cedar's documented country timesheet
pattern. The broad legacy grant and classification veto are explicit local
revision assumptions, with fictive identities and records.
-/

namespace CedarPooSpec.CountryApprovalExample

open Cedar.Spec Cedar.Data CedarPooSpec.PolicyModules

def userType : EntityType := ⟨"User", []⟩
def roleType : EntityType := ⟨"Role", []⟩
def sheetType : EntityType := ⟨"Timesheet", []⟩
def groupType : EntityType := ⟨"TimesheetGrp", []⟩
def actionType : EntityType := ⟨"Action", []⟩

def alice : EntityUID := ⟨userType, "alice"⟩
def bob : EntityUID := ⟨userType, "bob"⟩
def charlie : EntityUID := ⟨userType, "charlie"⟩
def france : EntityUID := ⟨roleType, "Approver-France"⟩
def germany : EntityUID := ⟨roleType, "Approver-Germany"⟩
def uk : EntityUID := ⟨roleType, "Approver-UK"⟩
def japan : EntityUID := ⟨roleType, "Approver-Japan"⟩
def europe : EntityUID := ⟨roleType, "Approver-Europe"⟩
def frenchTeam : EntityUID := ⟨roleType, "French-Team"⟩
def frenchSheets : EntityUID := ⟨groupType, "French-timesheets"⟩
def germanSheets : EntityUID := ⟨groupType, "German-timesheets"⟩
def ukSheets : EntityUID := ⟨groupType, "UK-timesheets"⟩
def japaneseSheets : EntityUID := ⟨groupType, "Japanese-timesheets"⟩
def europeanSheets : EntityUID := ⟨groupType, "European-timesheets"⟩
def parisSheets : EntityUID := ⟨groupType, "Paris-timesheets"⟩
def frenchSheet : EntityUID := ⟨sheetType, "fr-1"⟩
def germanSheet : EntityUID := ⟨sheetType, "de-1"⟩
def ukSheet : EntityUID := ⟨sheetType, "uk-1"⟩
def japaneseSheet : EntityUID := ⟨sheetType, "jp-1"⟩
def restrictedSheet : EntityUID := ⟨sheetType, "fr-restricted"⟩
def approve : EntityUID := ⟨actionType, "approve"⟩
def review : EntityUID := ⟨actionType, "review"⟩
def delete : EntityUID := ⟨actionType, "delete"⟩
def approverActions : EntityUID := ⟨actionType, "ApproverActions"⟩

def data (parents : List EntityUID := []) (tags : List (String × Value) := []) :
    EntityData :=
  { attrs := Map.empty, ancestors := Set.make parents, tags := Map.make tags }

def entities : Entities := Map.make [
  (alice, data [frenchTeam, france, europe] [("clearance", .prim (.string "restricted"))]),
  (bob, data [germany, uk, japan, europe]),
  (charlie, data [france, europe]),
  (frenchTeam, data [france, europe]),
  (france, data [europe]), (germany, data [europe]),
  (uk, data [europe]), (japan, data), (europe, data),
  (frenchSheets, data [europeanSheets]),
  (germanSheets, data [europeanSheets]),
  (ukSheets, data [europeanSheets]),
  (japaneseSheets, data), (europeanSheets, data),
  (parisSheets, data [frenchSheets, europeanSheets]),
  (frenchSheet, data [parisSheets, frenchSheets, europeanSheets]),
  (restrictedSheet, data [parisSheets, frenchSheets, europeanSheets]
    [("classification", .prim (.string "restricted"))]),
  (germanSheet, data [germanSheets, europeanSheets]),
  (ukSheet, data [ukSheets, europeanSheets]),
  (japaneseSheet, data [japaneseSheets]),
  (approve, data [approverActions]), (review, data [approverActions]),
  (delete, data), (approverActions, data)]

def countryPolicy (id : String) (role group : EntityUID) : Policy :=
  { id, effect := .permit,
    principalScope := .principalScope (.mem role),
    actionScope := .actionScope (.mem approverActions),
    resourceScope := .resourceScope (.mem group),
    condition := [] }

-- This legacy grant is intentionally too broad; the integrated root removes it.
def legacyEurope : Policy :=
  { id := "legacy-europe", effect := .permit,
    principalScope := .principalScope (.mem europe),
    actionScope := .actionInAny [approve, review],
    resourceScope := .resourceScope (.mem europeanSheets),
    condition := [] }

def tag (subject : Expr) (key : String) : Expr :=
  .binaryApp .getTag subject (.lit (.string key))
def hasTag (subject : Expr) (key : String) : Expr :=
  .binaryApp .hasTag subject (.lit (.string key))
def sensitiveCondition : Expr :=
  .and (hasTag (.var .resource) "classification")
    (.unaryApp .not (.and (hasTag (.var .principal) "clearance")
      (.binaryApp .eq (tag (.var .principal) "clearance")
        (tag (.var .resource) "classification"))))
def sensitiveVeto : Policy :=
  { id := "restricted-clearance", effect := .forbid,
    principalScope := .principalScope .any,
    actionScope := .actionScope (.mem approverActions),
    resourceScope := .resourceScope (.is sheetType),
    condition := [{ kind := .when, body := sensitiveCondition }] }

def model : Model := { modules := [
  { name := "Base", edits := [
      .extend (countryPolicy "france" france frenchSheets),
      .extend (countryPolicy "germany" germany germanSheets),
      .extend legacyEurope] },
  { name := "Expansion", parentOrders := [["Base"]], edits := [
      .extend (countryPolicy "uk" uk ukSheets),
      .extend (countryPolicy "japan" japan japaneseSheets)] },
  { name := "Sensitive", parentOrders := [["Base"]],
    edits := [.extend sensitiveVeto] },
  { name := "Integrated", parentOrders := [["Expansion", "Sensitive"]],
    edits := [.remove "legacy-europe"] }] }

def request (principal action resource : EntityUID) : Request :=
  ⟨principal, action, resource, Map.empty⟩

def cases : List (String × String × Request × Decision) := [
  ("legacy-cross-country", "Base", request alice approve germanSheet, .allow),
  ("integrated-cross-country", "Integrated", request alice approve germanSheet, .deny),
  ("france-nested-role", "Integrated", request alice approve frenchSheet, .allow),
  ("france-review-action", "Integrated", request alice review frenchSheet, .allow),
  ("france-unrelated-action", "Integrated", request alice delete frenchSheet, .deny),
  ("germany-role", "Integrated", request bob approve germanSheet, .allow),
  ("uk-expansion", "Integrated", request bob approve ukSheet, .allow),
  ("japan-expansion", "Integrated", request bob approve japaneseSheet, .allow),
  ("japan-cross-country", "Integrated", request alice approve japaneseSheet, .deny),
  ("restricted-cleared", "Integrated", request alice approve restrictedSheet, .allow),
  ("restricted-before-veto", "Expansion", request charlie approve restrictedSheet, .allow),
  ("restricted-after-veto", "Integrated", request charlie approve restrictedSheet, .deny)]

def decisionsExact : Bool := cases.all fun (_, root, req, expected) =>
  match model.compile root with
  | .error _ => false
  | .ok policies =>
      let response := isAuthorized req entities policies
      response.decision == expected && response.erroringPolicies.isEmpty

theorem decisionsExactFully : decisionsExact = true := by native_decide

theorem integratedRemovesBroadGrant :
    ((model.compile "Integrated").toOption.getD []).map Policy.id =
      ["france", "germany", "restricted-clearance", "uk", "japan"] := by native_decide

def incompleteEntities : Entities := Map.make [
  (alice, data [frenchTeam]),
  (frenchTeam, data [france]),
  (france, data)]

theorem incompleteHierarchyRejected :
    (match CedarPooSpec.PolicyJson.entities incompleteEntities with
     | .error (.incompleteEntityAncestors _) => true
     | _ => false) = true := by native_decide

end CedarPooSpec.CountryApprovalExample
