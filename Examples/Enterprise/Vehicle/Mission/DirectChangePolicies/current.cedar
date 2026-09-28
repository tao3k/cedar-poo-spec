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
  ((context.routeApproved) && (context.successorPlatformSafe)) && ((context.successorMissionFeasible) && ((((context.proposalId) == (context.witnessProposalId)) && (((context.missionVersion) == (context.witnessMissionVersion)) && ((context.vehicleStateId) == (context.witnessVehicleStateId)))) && ((0 <= (context.observedTick)) && (((context.observedTick) <= (context.decisionTick)) && (((context.decisionTick) - (context.observedTick)) <= 2)))))
};

forbid(
  principal == MissionPlanner::"untrusted-planner",
  action == Action::"proceed",
  resource
) when {
  !(((context.proposalId) == (context.witnessProposalId)) && (((context.missionVersion) == (context.witnessMissionVersion)) && ((context.vehicleStateId) == (context.witnessVehicleStateId))))
};
