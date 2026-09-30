# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

.sensitive_before == [true, true]
  and .sensitive_after == [true, false]
  and .budget_before == [true, true, true, true]
  and .budget_after == [true, true, false, false]
  and .masked_before == [true, true]
  and .masked_after == [false, true]
  and .sensitive_same_input == [true, true]
  and .sensitive_direct_difference == [false, true]
  and .budget_same_input == [true, true, true, false]
  and .budget_direct_difference == [false, false, true, false]
  and .budget_divergent_input_difference == [false, false, false, true]
  and .sensitive_owner == "History"
  and .different_later_context == true
  and .operation_substitution_rejected == true
  and .bounded_alphabet_size == 3
  and .bounded_horizon == 3
  and .bounded_sequence_count == 39
  and .bounded_by_length == [3, 9, 27]
  and .bounded_gains == 0
  and .bounded_direct_loss_sequences == 33
  and .bounded_divergent_loss_sequences == 16
  and .bounded_input_effect_under_before_sequences == 0
  and .bounded_input_effect_under_after_sequences == 5
  and .budget_final_policy_diff_at_both_inputs == true
  and .budget_final_no_input_decision_diff == true
  and .masked_final_policy_diff_at_before_input == true
  and .masked_final_input_effect_under_after_policy == true
  and .bounded_cap_rejected == true
  and (.manifest.cases | length) == 440
  and (.manifest.cases[:12] | map(.expected)) ==
    ["allow", "allow", "allow", "deny",
     "allow", "allow", "allow", "allow",
     "allow", "allow", "deny", "deny"]
  and (all(.manifest.cases[]; .expected_error_policies == []))
