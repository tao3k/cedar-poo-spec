import Examples.Enterprise.AWS.AgenticPlatform.Expense.Expense

namespace CedarPooSpec.AWS.ExpenseDepartmentProfileTest

open CedarPooSpec.AWS.Expense

theorem departmentRuleIsInheritedAcrossDistinctOwners :
    (teamDepartmentProfile.read .setting).map (·.action) = some listTeam ∧
    (rejectionDepartmentProfile.read .setting).map (·.action) = some reject ∧
    rejectionDepartmentProfile.plan.precedence =
      ["RejectionDepartment", "TeamDepartment"] ∧
    crossDepartment =
      veto "team-row-boundary" listTeam
        (unequal (attr .principal "department") (attr .resource "department")) ∧
    rejectScope =
      veto "reject-department-boundary" reject
        (unequal (attr .principal "department") (attr .resource "department")) := by
  native_decide

end CedarPooSpec.AWS.ExpenseDepartmentProfileTest
