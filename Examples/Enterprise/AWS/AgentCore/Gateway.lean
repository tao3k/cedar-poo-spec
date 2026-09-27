import CedarPooSpec.PolicyJson

/-! Shared AgentCore Gateway projection used by the insurance and banking
examples. Business-specific Cedar rules remain with their owning examples. -/

namespace CedarPooSpec.AWS.AgentCore

open Cedar.Spec Cedar.Data Cedar.Validation

def userType : EntityType := ⟨"OAuthUser", ["AgentCore"]⟩
def gatewayType : EntityType := ⟨"Gateway", ["AgentCore"]⟩
def actionType : EntityType := ⟨"Action", ["AgentCore"]⟩

def user (name : String) : EntityUID := ⟨userType, name⟩
def gateway (name : String) : EntityUID := ⟨gatewayType, name⟩
def action (name : String) : EntityUID := ⟨actionType, name⟩

def actionEntry (context : RecordType) : ActionSchemaEntry :=
  ⟨Set.make [userType], Set.make [gatewayType], Set.empty, context⟩

def entityData (tags : List (String × Value) := []) : EntityData :=
  { attrs := Map.empty, ancestors := Set.empty, tags := Map.make tags }

def scopedPolicy (id : String) (effect : Effect) (gatewayUID : EntityUID)
    (actions : ActionScope) (conditions : Conditions := []) : Policy :=
  { id, effect,
    principalScope := .principalScope (.is userType),
    actionScope := actions,
    resourceScope := .resourceScope (.eq gatewayUID),
    condition := conditions }

end CedarPooSpec.AWS.AgentCore
