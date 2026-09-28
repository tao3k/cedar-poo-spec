import CedarPooSpec.TemplateValidation
import CedarPooSpec.Revision

/-!
Ticket sharing follows Cedar's documented discretionary-access pattern:
an application links a principal and resource into a reusable template.
The identities and tickets here are fictive. Device posture is an additional
authority-projected condition in the revised template.
-/

namespace CedarPooSpec.TicketSharingExample

open Cedar.Spec Cedar.Validation Cedar.Data
open CedarPooSpec.PolicyModules CedarPooSpec.Soundness
open CedarPooSpec.TemplateValidation
open LeanPoo.Proof

def userType : EntityType := ⟨"User", []⟩
def ticketType : EntityType := ⟨"Ticket", []⟩
def actionType : EntityType := ⟨"Action", []⟩
def readAction : EntityUID := ⟨actionType, "read"⟩

def userEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.empty, none⟩
def ticketEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.make [("status", .required .string)], none⟩
def contextType : RecordType :=
  Map.make [("deviceTrusted", .required (.bool .anyBool))]
def actionEntry : ActionSchemaEntry :=
  ⟨Set.make [userType], Set.make [ticketType], Set.empty, contextType⟩
def schema : Schema :=
  ⟨Map.make [(userType, userEntry), (ticketType, ticketEntry)],
   Map.make [(readAction, actionEntry)]⟩

def alice : EntityUID := ⟨userType, "alice"⟩
def bob : EntityUID := ⟨userType, "bob"⟩
def ticketA : EntityUID := ⟨ticketType, "ticket-a"⟩
def ticketB : EntityUID := ⟨ticketType, "ticket-b"⟩
def entityData (attrs : Map String Value) : EntityData :=
  { attrs, ancestors := Set.empty, tags := Map.empty }
def ticketEntities (statusA statusB : String) : Entities := Map.make [
  (alice, entityData Map.empty),
  (bob, entityData Map.empty),
  (ticketA, entityData (Map.make [("status", .prim (.string statusA))])),
  (ticketB, entityData (Map.make [("status", .prim (.string statusB))])),
  (readAction, actionSchemaEntryToEntityData actionEntry)]
def entities : Entities := ticketEntities "OPEN" "OPEN"
def closedEntities : Entities := ticketEntities "CLOSED" "OPEN"

def openTicket : Expr :=
  .binaryApp .eq (.getAttr (.var .resource) "status") (.lit (.string "OPEN"))
def trustedDevice : Expr := .getAttr (.var .context) "deviceTrusted"

def contributorV1 : Template :=
  { effect := .permit
    principalScope := .principalScope (.eq (.slot "?principal"))
    actionScope := .actionScope (.eq readAction)
    resourceScope := .resourceScope (.eq (.slot "?resource"))
    condition := [{ kind := .when, body := openTicket }] }
def contributorV2 : Template :=
  { contributorV1 with
    condition := [{ kind := .when, body := .and openTicket trustedDevice }] }
def viewer : Template := contributorV1

def templatesV1 : Templates :=
  Map.make [("contributor", contributorV1), ("viewer", viewer)]
def templatesV2 : Templates :=
  Map.make [("contributor", contributorV2), ("viewer", viewer)]

def slotEnv (principal resource : EntityUID) : SlotEnv :=
  Map.make [("?principal", principal), ("?resource", resource)]
def linked (id templateId : String) (principal resource : EntityUID) :
    TemplateLinkedPolicy :=
  { id, templateId, slotEnv := slotEnv principal resource }
def links : TemplateLinkedPolicies := [
  linked "alice-ticket-a" "contributor" alice ticketA,
  linked "bob-ticket-b" "contributor" bob ticketB,
  linked "bob-ticket-a" "viewer" bob ticketA]

def policiesV1 : Policies :=
  (Cedar.Spec.link? templatesV1 links).toOption.get (by native_decide)
def policiesV2 : Policies :=
  (Cedar.Spec.link? templatesV2 links).toOption.get (by native_decide)

def baseline : LinkedSet schema :=
  (LinkedSet.create schema templatesV1 links).toOption.get (by native_decide)
def revised : LinkedSet schema :=
  (baseline.tryRefresh templatesV2 links).toOption.get (by native_decide)

theorem linkedBodies :
    baseline.validated.policies = policiesV1 ∧
    revised.validated.policies = policiesV2 := by
  native_decide

theorem twoChangedOneReused :
    (PolicyValidation.freshPolicies policiesV1 policiesV2).length = 2 ∧
    policiesV2.length = 3 := by
  native_decide

def brokenLink : TemplateLinkedPolicy :=
  { id := "missing-resource", templateId := "contributor",
    slotEnv := Map.make [("?principal", alice)] }
theorem missingSlotRejected :
    (match baseline.tryRefresh templatesV1 (brokenLink :: links) with
     | .error (.link _) => true
     | _ => false) = true := by
  native_decide

def brokenTemplate : Template :=
  { contributorV1 with condition :=
      [{ kind := .when, body := .lit (.string "not-a-Boolean") }] }
def brokenTemplates : Templates :=
  Map.make [("contributor", brokenTemplate), ("viewer", viewer)]
theorem invalidTemplateRejected :
    (match baseline.tryRefresh brokenTemplates links with
     | .error (.validate _) => true
     | _ => false) = true := by
  native_decide

def revokedLinks : TemplateLinkedPolicies :=
  links.filter fun link => link.id != "bob-ticket-b"
def revokedPolicies : Policies :=
  (Cedar.Spec.link? templatesV2 revokedLinks).toOption.get (by native_decide)

def postureReconciliation : Reconciliation policiesV1 policiesV2 :=
  (Edit.reconcile policiesV1 policiesV2).toOption.get (by native_decide)
def revokedReconciliation : Reconciliation policiesV2 revokedPolicies :=
  (Edit.reconcile policiesV2 revokedPolicies).toOption.get (by native_decide)

def published : Module :=
  { name := "Published", edits := Edit.extendAll policiesV1 }
def posture : Module :=
  { name := "Posture", parentOrders := [["Published"]],
    edits := postureReconciliation.edits }
def revoked : Module :=
  { name := "Revoked", parentOrders := [["Posture"]],
    edits := revokedReconciliation.edits }
def model : Model := { modules := [published, posture, revoked] }
def finalPolicies : Policies :=
  (model.compile "Revoked").toOption.get (by native_decide)
def revokedLinked : LinkedSet schema :=
  (revised.tryRefresh templatesV2 revokedLinks).toOption.get (by native_decide)

def expandedLinks : TemplateLinkedPolicies :=
  revokedLinks ++ [linked "alice-ticket-b" "contributor" alice ticketB]
def expandedPolicies : Policies :=
  (Cedar.Spec.link? templatesV2 expandedLinks).toOption.get (by native_decide)
def expandedReconciliation : Reconciliation finalPolicies expandedPolicies :=
  (Edit.reconcile finalPolicies expandedPolicies).toOption.get (by native_decide)
def expanded : Module :=
  { name := "Expanded", parentOrders := [["Revoked"]],
    edits := expandedReconciliation.edits }
def expandedModel : Model :=
  { modules := [published, posture, revoked, expanded] }
def expandedLinked : LinkedSet schema :=
  (revokedLinked.tryRefresh templatesV2 expandedLinks).toOption.get (by native_decide)

theorem linkChurnAligned :
    (expandedModel.compile "Expanded").toOption = some expandedPolicies ∧
    expandedLinked.validated.policies = expandedPolicies ∧
    expandedReconciliation.edits.length = 1 := by
  native_decide

theorem reconciliationRejectsDuplicates :
    (match Edit.reconcile policiesV1 (policiesV1 ++ [policiesV1.head!]) with
     | .error (.duplicateInputIds "after") => true
     | _ => false) = true := by
  native_decide

theorem revokedAligned : revokedLinked.validated.policies = finalPolicies := by
  native_decide

theorem compiledRevisions :
    (model.compile "Published").toOption = some policiesV1 ∧
    (model.compile "Posture").toOption = some policiesV2 ∧
    finalPolicies.length = 2 := by
  native_decide

def policyRevision : Revision :=
  (model.compileRevision "Published" "Posture").toOption.get (by native_decide)
theorem policyRevisionBodies :
    policyRevision.beforePolicies = policiesV1 ∧
    policyRevision.afterPolicies = policiesV2 := by
  native_decide

def aliceV2 : Policy :=
  (contributorV2.link? "alice-ticket-a" (slotEnv alice ticketA)).toOption.get
    (by native_decide)
def bobV2 : Policy :=
  (contributorV2.link? "bob-ticket-b" (slotEnv bob ticketB)).toOption.get
    (by native_decide)

theorem freshLinkedExact :
    policyRevision.freshPolicies = [aliceV2, bobV2] := by
  native_decide

private theorem okOfIsOk {ε : Type} (result : Except ε Unit)
    (accepted : result.isOk = true) : result = .ok () := by
  cases result with
  | ok value => cases value; rfl
  | error _ => cases accepted

theorem freshLinkedValid :
    ∀ policy ∈ policyRevision.freshPolicies,
    PolicyValidation.check policy schema = .ok () := by
  intro policy member
  rw [freshLinkedExact] at member
  simp only [List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with same | same
  · subst policy
    exact okOfIsOk _ (by native_decide)
  · subst policy
    exact okOfIsOk _ (by native_decide)

theorem freshLinkedCertificates :
    ∀ policy ∈ policyRevision.freshPolicies,
      Certificate (PolicyValidation.Snapshot.mk policy schema).proofObject := by
  intro policy member
  exact (PolicyValidation.Snapshot.mk policy schema).certificate
    (freshLinkedValid policy member)

def request (principal resource : EntityUID) (trusted : Bool) : Request :=
  ⟨principal, readAction, resource,
   Map.make [("deviceTrusted", .prim (.bool trusted))]⟩

def baselineSnapshot : AuthorizationSnapshot :=
  policyRevision.beforeSnapshot schema (request bob ticketA false) entities
theorem baselineCertificate : Certificate baselineSnapshot.proofObject :=
  baselineSnapshot.certificateOfChecks (by native_decide)

theorem revisedCertificate :
    Certificate
      (policyRevision.afterSnapshot schema (request bob ticketA false) entities).proofObject :=
  policyRevision.authorizationCertificate schema (request bob ticketA false) entities
    baselineCertificate
    freshLinkedCertificates

example : Cedar.Thm.AllEvaluateToBool policyRevision.afterPolicies
    (request bob ticketA false) entities :=
  certifiedAuthorizationSound
    (policyRevision.afterSnapshot schema (request bob ticketA false) entities)
    revisedCertificate

def revokeRevision : Revision :=
  (model.compileRevision "Posture" "Revoked").toOption.get (by native_decide)
theorem revokeStartsFromRevised :
    revokeRevision.beforePolicies = policyRevision.afterPolicies := by
  native_decide
theorem revokeNeedsNoNewBodies : revokeRevision.freshPolicies = [] := by
  native_decide

theorem revokedCertificate :
    Certificate
      (revokeRevision.afterSnapshot schema (request bob ticketA false) entities).proofObject := by
  have aligned :
      revokeRevision.beforeSnapshot schema (request bob ticketA false) entities =
        policyRevision.afterSnapshot schema (request bob ticketA false) entities := by
    simp [Revision.beforeSnapshot, Revision.afterSnapshot, revokeStartsFromRevised]
  have previous :
      Certificate
        (revokeRevision.beforeSnapshot schema (request bob ticketA false) entities).proofObject := by
    rw [aligned]
    exact revisedCertificate
  apply revokeRevision.authorizationCertificate schema (request bob ticketA false)
    entities previous
  intro policy member
  simp [revokeNeedsNoNewBodies] at member

example : Cedar.Thm.AllEvaluateToBool revokeRevision.afterPolicies
    (request bob ticketA false) entities :=
  certifiedAuthorizationSound
    (revokeRevision.afterSnapshot schema (request bob ticketA false) entities)
    revokedCertificate

def decisionsConform : Bool :=
  (isAuthorized (request alice ticketA false) entities policiesV1).decision == .allow &&
  (isAuthorized (request alice ticketA false) entities policiesV2).decision == .deny &&
  (isAuthorized (request alice ticketA true) entities policiesV2).decision == .allow &&
  (isAuthorized (request bob ticketA false) entities policiesV2).decision == .allow &&
  (isAuthorized (request bob ticketB true) entities policiesV2).decision == .allow &&
  (isAuthorized (request alice ticketA true) closedEntities policiesV2).decision == .deny &&
  (isAuthorized (request bob ticketA false) entities finalPolicies).decision == .allow &&
  (isAuthorized (request bob ticketB true) entities finalPolicies).decision == .deny
  &&
  (isAuthorized (request alice ticketB true) entities expandedPolicies).decision == .allow
theorem decisionsConformFully : decisionsConform = true := by native_decide

end CedarPooSpec.TicketSharingExample
