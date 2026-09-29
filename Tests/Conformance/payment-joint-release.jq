# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

.left_no_gain == true
  and .right_no_gain == true
  and .joint_gain == true
  and .left_changes == ["risk-payment-hold"]
  and .right_changes == ["compliance-payment-hold"]
  and (.joint_changes | sort) == ["compliance-payment-hold", "risk-payment-hold"]
  and .risk_owner == "RiskReleased"
  and .compliance_owner == "ComplianceReleased"
  and .release_requires_review == true
  and .stale_epoch_rejected == true
  and .changed_schema_rejected == true
  and .owner_only_change_rejected == true
  and .unrelated_owner_reused == true
  and .safe_release_current == true
  and .safe_release_stale_rejected == true
  and (.manifest.cases | map(.revision)) ==
    ["DualHold", "RiskReleased", "ComplianceReleased", "JointRelease"]
  and (.manifest.cases | map(.expected)) == ["deny", "deny", "deny", "allow"]
  and (all(.manifest.cases[]; .expected_error_policies == []))
  and (.manifest.cases[0].expected_reasons | sort) ==
    ["compliance-payment-hold", "risk-payment-hold"]
  and .manifest.cases[1].expected_reasons == ["compliance-payment-hold"]
  and .manifest.cases[2].expected_reasons == ["risk-payment-hold"]
  and .manifest.cases[3].expected_reasons == ["agent-payment"]
