// Generated from Lean-POO. Cedar assigns new IDs when parsing this text.
// POO policy ID: expense-exposure
permit(
  principal is AnyCompany::User,
  action in [AnyCompany::Action::"listTeamExpenses",AnyCompany::Action::"rejectExpense"],
  resource is AnyCompany::Expense
);
