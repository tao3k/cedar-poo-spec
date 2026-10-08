# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

.changed_decision_delta == "equivalent-in-schema"
  and .changed_policy == "alice-ticket-a"
  and .changed_reason_stable == false
  and .masked_reason_stable == true
  and .masked_queries == 3
  and .owner_reason_stable == true
  and .owner_provenance_stable == false
  and .owner_queries == 0
  and .flip_reason_stable == false
  and .flip_before_decision == "allow"
  and .flip_after_decision == "deny"
  and .duplicate_ids_rejected == true
  and (.manifest.cases | length) == 2
  and (all(.manifest.cases[]; .expected == "allow" and .expected_error_policies == []))
  and (.manifest.cases[0].expected_reasons | sort) == ["alice-ticket-a", "alice-ticket-a-fallback"]
  and .manifest.cases[1].expected_reasons == ["alice-ticket-a-fallback"]
