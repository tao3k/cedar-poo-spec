// Generated from Lean-POO. Cedar assigns new IDs when parsing this text.
// POO policy ID: gateway-protocol
permit(
  principal is AgentCore::OAuthUser,
  action in [AgentCore::Action::"tools/list",AgentCore::Action::"initialize"],
  resource == AgentCore::Gateway::"lobfederation-gateway"
);

// POO policy ID: lending-owned-tools
permit(
  principal is AgentCore::OAuthUser,
  action in [AgentCore::Action::"lending-wealth___get_loans",AgentCore::Action::"lending-wealth___get_credit_score",AgentCore::Action::"lending-wealth___check_eligibility",AgentCore::Action::"lending-wealth___get_emi_details",AgentCore::Action::"lending-wealth___calculate_emi",AgentCore::Action::"lending-wealth___search_lending_policies"],
  resource == AgentCore::Gateway::"lobfederation-gateway"
);

// POO policy ID: retail-owned-tools
permit(
  principal is AgentCore::OAuthUser,
  action in [AgentCore::Action::"retail-banking___get_customer",AgentCore::Action::"retail-banking___get_accounts",AgentCore::Action::"retail-banking___get_balance",AgentCore::Action::"retail-banking___get_profile",AgentCore::Action::"retail-banking___update_balance"],
  resource == AgentCore::Gateway::"lobfederation-gateway"
);

// POO policy ID: sample-delete-customer-veto
forbid(
  principal is AgentCore::OAuthUser,
  action == AgentCore::Action::"retail-banking___delete_customer",
  resource == AgentCore::Gateway::"lobfederation-gateway"
);

// POO policy ID: transaction-owned-tools
permit(
  principal is AgentCore::OAuthUser,
  action in [AgentCore::Action::"transaction-banking___get_payments",AgentCore::Action::"transaction-banking___transfer_funds",AgentCore::Action::"transaction-banking___get_beneficiaries",AgentCore::Action::"transaction-banking___schedule_payment"],
  resource == AgentCore::Gateway::"lobfederation-gateway"
);
