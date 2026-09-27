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

def namespaceCollisionSchema : Cedar.Validation.Schema :=
  ⟨Map.make [
    (⟨"X", ["A", "B"]⟩, .standard ⟨Set.empty, Map.empty, none⟩),
    (⟨"Y", ["A::B"]⟩, .standard ⟨Set.empty, Map.empty, none⟩)],
    Map.empty⟩

def rejectsNamespaceCollision : Bool :=
  match CedarPooSpec.SchemaJson.schema namespaceCollisionSchema with
  | .error (.invalidSchema _) => true
  | _ => false

theorem rejectsNamespaceCollisionFully :
    rejectsNamespaceCollision = true := by native_decide

def rejectsNamespaceCollisionPublication : Bool :=
  match CedarPooSpec.PolicyJson.publish emptyModel "Empty" namespaceCollisionSchema with
  | .error (.schema _) => true
  | _ => false

theorem rejectsNamespaceCollisionPublicationFully :
    rejectsNamespaceCollisionPublication = true := by native_decide

def typeCollisionSchema : Cedar.Validation.Schema :=
  ⟨Map.make [
    (⟨"B::X", ["A"]⟩, .standard ⟨Set.empty, Map.empty, none⟩),
    (⟨"X", ["A", "B"]⟩, .standard ⟨Set.empty, Map.empty, none⟩)],
    Map.empty⟩

def rejectsTypeCollision : Bool :=
  match CedarPooSpec.SchemaJson.schema typeCollisionSchema with
  | .error (.invalidSchema _) => true
  | _ => false

theorem rejectsTypeCollisionFully :
    rejectsTypeCollision = true := by native_decide

def rejectsTypeCollisionPublication : Bool :=
  match CedarPooSpec.PolicyJson.publish emptyModel "Empty" typeCollisionSchema with
  | .error (.schema _) => true
  | _ => false

theorem rejectsTypeCollisionPublicationFully :
    rejectsTypeCollisionPublication = true := by native_decide

end CedarPooSpec.SchemaProjectionExample
