import Cedar.Validation.EnvironmentValidator

/-!
Validate Cedar schema definitions even when no action generates a request
environment. Callers then run Cedar's full request-environment validation.
-/

namespace CedarPooSpec.SchemaAdmission

open Cedar.Validation

def validateDefinitions (schema : Schema) : EnvironmentValidationResult := do
  let env : TypeEnv := { ets := schema.ets, acts := schema.acts, reqty := default }
  schema.ets.validateWellFormed env
  schema.acts.validateWellFormed env

end CedarPooSpec.SchemaAdmission
