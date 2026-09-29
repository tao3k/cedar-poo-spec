# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

.decision_delta == "equivalent-in-schema"
  and .reason_policy == "alice-ticket-a"
  and .reason_stable == false
  and .before_owner == "Shared"
  and (.invalidated_roots | index("OneGrantRemoved")) != null
  and .masked_unresolved == ["alice-ticket-a"]
  and .stable_same_root == true
  and (.manifest.cases | length) == 2
  and (all(.manifest.cases[]; .expected == "allow" and .expected_error_policies == []))
  and (.manifest.cases[0].expected_reasons | sort) == ["alice-ticket-a", "alice-ticket-a-fallback"]
  and .manifest.cases[1].expected_reasons == ["alice-ticket-a-fallback"]
