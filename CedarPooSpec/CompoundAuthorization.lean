import CedarPooSpec.PolicyModules
import Cedar.Spec.Authorizer

/-!
Compound authorization evaluates several Cedar requests against one compiled
POO root and one caller-supplied entity snapshot. The caller remains
responsible for atomic business execution and authentic input facts.
-/

namespace CedarPooSpec.CompoundAuthorization

open Cedar.Spec CedarPooSpec.PolicyModules

/-- A compound receipt binds all responses to one exact POO compilation. -/
structure Receipt (model : Model) (root : String) (requests : List Request)
    (entities : Entities) where
  policies : Policies
  compiled : model.compile root = .ok policies
  responses : List Response
  evaluated : responses = requests.map (fun req => isAuthorized req entities policies)

/-- Every query must allow, and no query may have a policy evaluation error. -/
def Receipt.allowed {model : Model} {root : String} {requests : List Request}
    {entities : Entities} (receipt : Receipt model root requests entities) : Bool :=
  !requests.isEmpty &&
    receipt.responses.all (fun response =>
      response.decision == .allow && response.erroringPolicies.isEmpty)

/-- Compile once, then evaluate all requests against the same policy set. -/
def authorizeAll (model : Model) (root : String) (requests : List Request)
    (entities : Entities) : Except PolicyModules.Error (Receipt model root requests entities) :=
  match hc : model.compile root with
  | .error error => .error error
  | .ok policies =>
      .ok ⟨policies, hc, requests.map (fun req => isAuthorized req entities policies), rfl⟩

end CedarPooSpec.CompoundAuthorization
