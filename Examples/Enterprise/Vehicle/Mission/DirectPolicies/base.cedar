permit(
  principal == MissionPlanner::"untrusted-planner",
  action == Action::"fallback-handoff",
  resource
) when {
  true
};

permit(
  principal == MissionPlanner::"untrusted-planner",
  action == Action::"proceed",
  resource
) when {
  context.routeApproved
};
