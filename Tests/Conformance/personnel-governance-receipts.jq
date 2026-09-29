# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

length == 40
  and all(.[];
    (.schema_sha256 | test("^[0-9a-f]{64}$"))
    and .replay.error_policy_ids == [])
  and ([.[] | select(.replay.decision == "allow") | .replay.case_name] | sort) == [
    "agent-explicit-release",
    "agent-with-delegation",
    "approved-release",
    "core-component-read",
    "core-product-download",
    "core-read",
    "departure-internal-read",
    "incident-still-reads",
    "intern-shared-read",
    "partner-after-extension",
    "recovered-release",
    "researcher-a-project-download",
    "researcher-a-project-read",
    "researcher-b-project-read",
    "researcher-shared-read",
    "scoped-integration-interface"
  ]
