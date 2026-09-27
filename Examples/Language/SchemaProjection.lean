import CedarPooSpec.SchemaJson
import Examples.Language.ScopeAndPattern

namespace CedarPooSpec.SchemaProjectionExample

open Cedar.Spec Cedar.Data CedarPooSpec.ScopeAndPatternExample

def missingType : EntityType := ⟨"Missing", []⟩

def danglingAncestorSchema : Cedar.Validation.Schema :=
  ⟨Map.make [(userType, .standard ⟨Set.make [missingType], Map.empty, none⟩)],
    Map.empty⟩

def rejectsDanglingAncestor : Bool :=
  match CedarPooSpec.SchemaJson.schema danglingAncestorSchema with
  | .error (.invalidSchema _) => true
  | _ => false

theorem rejectsDanglingAncestorFully : rejectsDanglingAncestor = true := by native_decide

def emptyModel : CedarPooSpec.PolicyModules.Model :=
  { modules := [{ name := "Empty", edits := [] }] }

def rejectsDanglingPublication : Bool :=
  match CedarPooSpec.PolicyJson.publish emptyModel "Empty" danglingAncestorSchema with
  | .error (.schema _) => true
  | _ => false

theorem rejectsDanglingPublicationFully :
    rejectsDanglingPublication = true := by native_decide

end CedarPooSpec.SchemaProjectionExample
