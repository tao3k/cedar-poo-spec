import Examples.Enterprise.Agent.MultiAccountBanking.MultiAccountBanking
import CedarPooSpec.SchemaJson

namespace CedarPooSpec.MultiAccountBankingValidatedExport

open CedarPooSpec.MultiAccountBankingExample

def manifest : Except String Lean.Json := do
  let mut rows : List Lean.Json := []
  for (label, action) in [
    ("customer", customer), ("accounts", accounts), ("balance", balance),
    ("profile", profile), ("update-balance", updateBalance),
    ("delete-customer", deleteCustomer), ("payments", payments),
    ("transfer", transfer), ("beneficiaries", beneficiaries),
    ("schedule-payment", schedulePayment), ("loans", loans),
    ("credit-score", creditScore), ("eligibility", eligibility),
    ("emi-details", emiDetails), ("calculate-emi", calculateEmi),
    ("lending-policy", lendingPolicy), ("tools-list", listTools),
    ("initialize", initializeAction)] do
    for (root, variant) in [("SampleBroad", "source"),
                            ("OwnerCombined", "owners")] do
      let row ← CedarPooSpec.PolicyJson.authorizationCase
        s!"{variant}-{label}" variant model root
        (request banker action) entities
      rows := rows ++ [row]
  CedarPooSpec.SchemaJson.validatedManifest schema rows

end CedarPooSpec.MultiAccountBankingValidatedExport
