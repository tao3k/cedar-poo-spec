// Generated from Lean-POO. Cedar assigns new IDs when parsing this text.
// POO policy ID: fleet-command
permit(
  principal == FleetOperator::"fleet-ops",
  action == Action::"publish-command",
  resource
) when {
  context.channelAuthenticated
};

// POO policy ID: fleet-deployment
permit(
  principal == FleetOperator::"fleet-ops",
  action == Action::"deploy-update",
  resource
) when {
  (context.channelAuthenticated) && (((context.packageSigned) && (resource.compatible)) && (context.safeToUpdate))
};

// POO policy ID: oem-approval
permit(
  principal == SecurityReviewer::"oem-security",
  action == Action::"approve-update",
  resource
) when {
  (context.channelAuthenticated) && ((context.trialPassed) && (context.releaseApproved))
};
