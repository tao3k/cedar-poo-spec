import Examples.Enterprise.PaymentRelease

/-! Emit the integrated payment policy set after Lean Cedar validation. -/

def main : IO Unit :=
  match CedarPooSpec.PolicyJson.publish
      CedarPooSpec.PaymentReleaseExample.model "Integrated"
      CedarPooSpec.PaymentReleaseExample.schema with
  | .ok publication => IO.println publication.json.compress
  | .error (.composition _) => throw (IO.userError "POO composition failed")
  | .error (.schema _) => throw (IO.userError "Cedar schema is invalid")
  | .error (.policy _) => throw (IO.userError "Cedar policy validation failed")
  | .error (.export _) => throw (IO.userError "Cedar export failed")
