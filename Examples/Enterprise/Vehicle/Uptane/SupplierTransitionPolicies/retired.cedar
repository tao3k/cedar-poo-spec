// Generated from Lean-POO. Cedar assigns new IDs when parsing this text.
// POO policy ID: primary-version-manifest
permit(
  principal == PrimaryECU::"vehicle-primary",
  action == Action::"submit-manifest",
  resource
) when {
  context.manifestSignatureValid
};
