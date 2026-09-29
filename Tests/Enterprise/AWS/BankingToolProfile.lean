import Examples.Enterprise.AWS.FinancialServices.MultiAccountBanking.MultiAccountBanking

namespace CedarPooSpec.AWS.BankingToolProfileTest

open CedarPooSpec.MultiAccountBankingExample
open CedarPooSpec.Vertical.FinancialServices

def expectedPaused : BankingToolOwner :=
  { transactionTemplate with actions := transactionTools.filter (· != transfer) }

theorem transactionPauseAndRecoveryUseOneOwnerPrototype :
    transactionProfile.read .actions = some transactionTools ∧
    pausedTransactionProfile.read .actions =
      some (transactionTools.filter (· != transfer)) ∧
    resumedTransactionProfile.read .actions = some transactionTools ∧
    pausedTransactionProfile.plan.precedence =
      ["TransferPausedTools", "TransactionTools"] ∧
    resumedTransactionProfile.plan.precedence =
      ["TransferResumedTools", "TransferPausedTools", "TransactionTools"] ∧
    transactionOwner.policy = transactionTemplate.policy ∧
    pausedTransactionOwner.policy = expectedPaused.policy ∧
    resumedTransactionOwner.policy = transactionTemplate.policy := by
  native_decide

end CedarPooSpec.AWS.BankingToolProfileTest
