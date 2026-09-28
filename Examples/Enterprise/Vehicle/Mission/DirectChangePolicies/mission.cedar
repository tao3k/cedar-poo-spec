permit(
  principal == MissionPlanner::"untrusted-planner",
  action == Action::"fallback-handoff",
  resource
) when {
  context.routeApproved
};

forbid(
  principal == MissionPlanner::"untrusted-planner",
  action == Action::"proceed",
  resource
) when {
  !(context.successorMissionFeasible)
};

permit(
  principal == MissionPlanner::"untrusted-planner",
  action == Action::"proceed",
  resource
) when {
  context.routeApproved
};
