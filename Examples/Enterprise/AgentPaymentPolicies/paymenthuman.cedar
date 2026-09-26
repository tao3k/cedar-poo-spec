// Generated from Lean-POO. Cedar assigns new IDs when parsing this text.
// POO policy ID: agent-payment
permit(
  principal == Agent::"finance-bot",
  action == Action::"transfer",
  resource in AccountGroup::"Approved"
) when {
  (((context.amount).greaterThan(decimal("0.0000"))) && ((context.amount).lessThanOrEqual(decimal("100.0000")))) && (((context.origin) in Role::"Admin") && ((context.origin).mfa))
};
