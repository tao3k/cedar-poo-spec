import CedarPooSpec.Pseudonymization
import Examples.Health.Pseudonymization

/-! A synthetic structured record whose AES-SIV context is selected from a
named field. The output fixture is consumed by the local RustCrypto test. -/

namespace CedarPooSpec.PseudonymizationExample.Tabular

open CedarPooSpec.Pseudonymization

def tokenProfile : TokenProfile :=
  { mode := .aesSiv, scope := "hospital-a", lineage := hospitalLineage }

def recipe : AesSivTableRecipe :=
  { dataset := "hospital-patients", valueField := "patient_id",
    contextField := "tenant_scope", profile := tokenProfile,
    admittedContext := some "hospital-a" }

def row : TableRow :=
  { fields := [("patient_id", "synthetic-patient-0001"),
    ("tenant_scope", "hospital-a")] }

theorem selectedContextComesFromTenantScopeColumn :
    recipe.select row = .ok ⟨"synthetic-patient-0001", "hospital-a"⟩ := by
  native_decide

theorem changedContextCannotUsePublishedScope :
    recipe.select { fields := [("patient_id", "synthetic-patient-0001"),
      ("tenant_scope", "study-two")] } = .error .contextNotAdmitted := by
  native_decide

theorem unrestrictedRecipeSelectsAnotherContext :
    { recipe with admittedContext := none }.select
      { fields := [("patient_id", "synthetic-patient-0001"),
        ("tenant_scope", "study-two")] } =
      .ok ⟨"synthetic-patient-0001", "study-two"⟩ := by
  native_decide

theorem differentRecordContextsAreNotJoinCompatible :
    recipe.compatibleInputs recipe
      ⟨"synthetic-patient-0001", "hospital-a"⟩
      ⟨"synthetic-patient-0001", "study-two"⟩ = false := by
  native_decide

theorem duplicatePatientColumnCannotSelect :
    recipe.select { fields := [("patient_id", "synthetic-patient-0001"),
      ("patient_id", "synthetic-patient-0002"),
      ("tenant_scope", "hospital-a")] } = .error .missingOrDuplicateValue := by
  native_decide

def fixture : Except String Lean.Json := do
  let selected ← (recipe.select row).mapError (fun _ => "invalid tabular AES-SIV selection")
  return Lean.Json.mkObj [
    ("dataset", Lean.toJson recipe.dataset),
    ("valueField", Lean.toJson recipe.valueField),
    ("contextField", Lean.toJson recipe.contextField),
    ("value", Lean.toJson selected.value),
    ("context", Lean.toJson selected.context),
    ("keyDomain", Lean.toJson recipe.profile.lineage.keyDomain),
    ("tokenKeyVersion", Lean.toJson recipe.profile.lineage.tokenKeyVersion),
    ("transformVersion", Lean.toJson recipe.profile.lineage.transformVersion),
    ("wrappingVersion", Lean.toJson recipe.profile.lineage.wrappingVersion),
    ("surrogateInfoType", Lean.toJson recipe.surrogateInfoType)]

end CedarPooSpec.PseudonymizationExample.Tabular
