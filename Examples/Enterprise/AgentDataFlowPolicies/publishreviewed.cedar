// Generated from Lean-POO. Cedar assigns new IDs when parsing this text.
// POO policy ID: agent-document-publish
permit(
  principal == Agent::"knowledge-bot",
  action == Action::"publish-document",
  resource
) when {
  (((resource.tenant) == ((context.source).tenant)) && (((resource.visibility) == "internal") || (((context.source).classification) == "public"))) && (((resource.visibility) == "internal") || ((context.approved) && (((context.reviewer) in Role::"Security") && (((context.reviewer).mfa) && (!((context.reviewer) == (context.origin)))))))
};
