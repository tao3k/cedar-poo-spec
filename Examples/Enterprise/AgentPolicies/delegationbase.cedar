// Generated from Lean-POO. Cedar assigns new IDs when parsing this text.
// POO policy ID: agent-delegation
permit(
  principal == Agent::"orchestrator",
  action == Action::"delegate",
  resource == Agent::"data-bot"
) when {
  true
};
