# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

.sensitive_before == [true, true]
  and .sensitive_after == [true, false]
  and .budget_before == [true, true, true, true]
  and .budget_after == [true, true, false, false]
  and .sensitive_same_input == [true, true]
  and .sensitive_direct_difference == [false, true]
  and .budget_same_input == [true, true, true, false]
  and .budget_direct_difference == [false, false, true, false]
  and .budget_divergent_input_difference == [false, false, false, true]
  and .sensitive_owner == "History"
  and .different_later_context == true
  and .operation_substitution_rejected == true
  and (.manifest.cases | length) == 12
  and (.manifest.cases | map(.expected)) ==
    ["allow", "allow", "allow", "deny",
     "allow", "allow", "allow", "allow",
     "allow", "allow", "deny", "deny"]
  and (all(.manifest.cases[]; .expected_error_policies == []))
