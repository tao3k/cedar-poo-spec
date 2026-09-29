# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

.qualified_decision_delta == "loss-only"
  and .qualified_policies_checked == 5
  and .decision_delta == "equivalent-in-schema"
  and .operational_error_policy == "underflow-guard"
  and (.manifest.cases | length) == 2
  and .manifest.cases[0].expected == "allow"
  and .manifest.cases[0].expected_error_policies == []
  and .manifest.cases[1].expected == "allow"
  and .manifest.cases[1].expected_error_policies == ["underflow-guard"]
