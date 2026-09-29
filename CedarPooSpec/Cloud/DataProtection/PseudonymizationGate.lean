import CedarPooSpec.Pseudonymization.Compatibility
import CedarPooSpec.Governance.Veto

/-! A cloud transformation gate over the provider-neutral token catalog.
The Host authenticates the selected profile, row context, release receipt,
and key authorization before projecting them into a Cedar request. -/

namespace CedarPooSpec.Cloud.DataProtection

open Cedar.Spec CedarPooSpec.Governance CedarPooSpec.Pseudonymization

private def field (source : Expr) (name : String) : Expr :=
  .getAttr source name

private def equal (left right : Expr) : Expr := .binaryApp .eq left right

/-- A deterministic cloud transformation requires the selected token recipe,
    admitted row context, key grant, and released implementation digest to
    match the target dataset. This expression does not execute encryption. -/
def pseudonymizationReady : Expr :=
  let target := Expr.var .resource
  let facts := Expr.var .context
  let selected := field facts "selectedProfile"
  let relation : TokenRelation := { source := selected, target := target }
  .and (equal (field target "mode") (.lit (.string "aes-siv")))
    (.and relation.sameRecipe
      (.and (equal (field selected "tenant") (field target "tenant"))
        (.and (field facts "keyAuthorized")
          (.and (equal (field facts "selectedContext")
            (field target "admittedContext"))
            (equal (field facts "releasedArtifactDigest")
              (field target "artifactDigest"))))))

structure PseudonymizationGate where
  policyId : PolicyID
  actionScope : ActionScope
  resourceScope : ResourceScope
  principalScope : PrincipalScope := .principalScope .any

def PseudonymizationGate.veto (gate : PseudonymizationGate) : Veto :=
  { policyId := gate.policyId
    actionScope := gate.actionScope
    resourceScope := gate.resourceScope
    principalScope := gate.principalScope
    denyWhen := .unaryApp .not pseudonymizationReady }

end CedarPooSpec.Cloud.DataProtection
