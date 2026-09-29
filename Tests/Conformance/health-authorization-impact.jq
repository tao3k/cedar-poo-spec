# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

.suspended.changed_policy_ids == ["agent-join-suspended"]
  and .suspended.environments_checked == .restored.environments_checked
  and (.suspended.gains | length) == 0
  and (.suspended.losses | length) == 1
  and .suspended.losses[0].before_decision == "allow"
  and .suspended.losses[0].after_decision == "deny"
  and .suspended.losses[0].after_reasons == ["agent-join-suspended"]
  and .restored.changed_policy_ids == ["agent-join-suspended"]
  and (.restored.gains | length) == 1
  and (.restored.losses | length) == 0
  and .restored.gains[0].before_decision == "deny"
  and .restored.gains[0].after_decision == "allow"
  and .approval_withdrawal.before_decision == "allow"
  and .approval_withdrawal.after_decision == "deny"
  and (.suspended_manifest.cases | length) == 2
  and (.restored_manifest.cases | length) == 2
  and (.approval_manifest.cases | length) == 2
