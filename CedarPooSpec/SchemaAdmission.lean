import Cedar.Validation.EnvironmentValidator

/-!
Validate Cedar schema names and definitions even when no action generates a
request environment. Callers then run Cedar's full request-environment check.
-/

namespace CedarPooSpec.SchemaAdmission

open Cedar.Spec Cedar.Data Cedar.Validation

def validateDefinitions (schema : Schema) : EnvironmentValidationResult := do
  let paths := ((schema.ets.toList.map fun (pair : EntityType × EntitySchemaEntry) => pair.1.path) ++
    (schema.acts.toList.map fun (pair : EntityUID × ActionSchemaEntry) => pair.1.ty.path)).eraseDups
  if !(decide ((paths.map (String.intercalate "::")).Nodup)) then
    throw (.typeError "schema namespace paths collide after Cedar qualification")
  let types := ((schema.ets.toList.map fun (pair : EntityType × EntitySchemaEntry) => pair.1) ++
    (schema.acts.toList.map fun (pair : EntityUID × ActionSchemaEntry) => pair.1.ty)).eraseDups
  if !(decide ((types.map toString).Nodup)) then
    throw (.typeError "schema entity types collide after Cedar qualification")
  let env : TypeEnv := { ets := schema.ets, acts := schema.acts, reqty := default }
  schema.ets.validateWellFormed env
  schema.acts.validateWellFormed env

end CedarPooSpec.SchemaAdmission
