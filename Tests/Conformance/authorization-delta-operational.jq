# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

.qualified_decision_delta == "loss-only"
  and .qualified_policies_checked == 5
  and .decision_delta == "equivalent-in-schema"
  and .operational_error_policy == "underflow-guard"
  and .exact_operational_delta == "loss-only"
  and .exact_error_policy == "underflow-guard"
  and .deny_only_exact_delta == "equivalent-in-schema"
  and (.manifest.cases | length) == 4
  and .manifest.cases[0].expected == "allow"
  and .manifest.cases[0].expected_error_policies == []
  and .manifest.cases[1].expected == "allow"
  and .manifest.cases[1].expected_error_policies == ["underflow-guard"]
  and .manifest.cases[2].expected == "allow"
  and .manifest.cases[2].expected_error_policies == []
  and .manifest.cases[3].expected == "allow"
  and .manifest.cases[3].expected_error_policies == ["underflow-guard"]
