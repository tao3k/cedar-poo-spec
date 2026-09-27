// Generated from Lean-POO. Cedar assigns new IDs when parsing this text.
// POO policy ID: agent-payment
permit(
  principal == Agent::"finance-bot",
  action == Action::"transfer",
  resource
) when {
  true
};

// POO policy ID: unapproved-account
forbid(
  principal == Agent::"finance-bot",
  action == Action::"transfer",
  resource
) when {
  !(resource in AccountGroup::"Approved")
};
