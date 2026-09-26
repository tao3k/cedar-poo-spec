// Generated from Lean-POO. Cedar assigns new IDs when parsing this text.
// POO policy ID: no-self-approval
forbid(
  principal in Role::"Approver",
  action == Action::"approve",
  resource is PurchaseOrder
) when {
  principal == (resource.requester)
};

// POO policy ID: operations-approval
permit(
  principal in Role::"Approver",
  action == Action::"approve",
  resource in OrderGroup::"Operations"
) when {
  ((context.amount).lessThanOrEqual(resource.limit)) && ((((context.viaAgent).operator) == principal) && ((context.viaAgent).enabled))
};
