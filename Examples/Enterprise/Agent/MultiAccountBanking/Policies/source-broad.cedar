// Generated from Lean-POO. Cedar assigns new IDs when parsing this text.
// POO policy ID: sample-broad-permit
permit(
  principal is AgentCore::OAuthUser,
  action,
  resource == AgentCore::Gateway::"lobfederation-gateway"
);

// POO policy ID: sample-delete-customer-veto
forbid(
  principal is AgentCore::OAuthUser,
  action == AgentCore::Action::"retail-banking___delete_customer",
  resource == AgentCore::Gateway::"lobfederation-gateway"
);
