# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

.posture.status == "no-expansion-in-schema"
  and .posture.environments_checked == 1
  and .new_grant.status == "expanded"
  and .new_grant.environments_checked == 1
  and (.new_grant.counterexamples | length) > 0
  and (.posture_impact.gains | length) == 0
  and .posture_impact.classification == "loss-only"
  and (.posture_impact.losses | length) > 0
  and .posture_impact.losses[0].before_reasons == ["bob-ticket-b"]
  and .posture_impact.losses[0].request.context.deviceTrusted == false
  and (.new_grant_impact.gains | length) > 0
  and .new_grant_impact.classification == "gain-only"
  and (.new_grant_impact.losses | length) == 0
  and .new_grant_impact.gains[0].after_reasons == ["alice-ticket-b"]
  and (.posture_explanation.changes | map(.policy_id) | sort) == ["alice-ticket-a", "bob-ticket-b"]
  and (all(.posture_explanation.changes[]; .after_owner.last_edited_by == "Posture" and .after_edits[-1] == {"module":"Posture","operation":"overlay"}))
  and (.posture_explanation.proof.fresh_policy_ids | sort) == ["alice-ticket-a", "bob-ticket-b"]
  and .posture_explanation.proof.reused_policy_ids == ["bob-ticket-a"]
  and .posture_explanation.proof.authorization_dependencies == ["policies"]
  and (.posture_explanation.potentially_invalidated_roots | index("Revoked")) != null
  and .new_grant_explanation.changes[0].policy_id == "alice-ticket-b"
  and .new_grant_explanation.changes[0].after_owner.last_edited_by == "Expanded"
  and .new_grant_explanation.changes[0].after_edits == [{"module":"Expanded","operation":"extend"}]
  and .new_grant_explanation.proof.fresh_policy_ids == ["alice-ticket-b"]
  and (.new_grant_explanation.proof.reused_policy_ids | sort) == ["alice-ticket-a", "bob-ticket-a"]
  and .new_grant_explanation.potentially_invalidated_roots == ["Expanded"]
  and (.posture_manifest.cases | length) == 2
  and (.manifest.cases | length) == 2
