import CedarPooSpec.Pseudonymization.Tabular
import Lean.Data.Json

/-! A provider input projection for the existing Google SDP Rust boundary.
This serializes a selected row and catalog lineage; it does not issue a
request, authenticate a response, or implement a cryptographic operation. -/

namespace CedarPooSpec.Platform.Google.SensitiveDataProtection

open CedarPooSpec.Pseudonymization

def selectedTableJson (recipe : AesSivTableRecipe)
    (selected : AesSivTableInput) : Lean.Json := Lean.Json.mkObj [
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

end CedarPooSpec.Platform.Google.SensitiveDataProtection
