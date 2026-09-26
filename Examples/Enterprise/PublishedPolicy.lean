import Examples.Enterprise.DelegatedApproval

/-! A policy artifact is emitted only after schema and policy validation. -/

def main : IO Unit :=
  match CedarPooSpec.PolicyJson.publish
      CedarPooSpec.DelegatedApprovalExample.delegatedModel "Delegated"
      CedarPooSpec.DelegatedApprovalExample.delegatedSchema with
  | .ok publication => IO.println publication.json.compress
  | .error (.composition _) => throw (IO.userError "POO composition failed")
  | .error (.schema _) => throw (IO.userError "Cedar schema is invalid")
  | .error (.policy _) => throw (IO.userError "Cedar policy validation failed")
  | .error (.export _) => throw (IO.userError "Cedar export failed")
