# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

length == ($manifest[0].cases | length)
  and length == 32
  and all(.[]; (.schema_sha256 | test("^[0-9a-f]{64}$"))
  and .replay.error_policy_ids == []
  and .replay.error_free_allow == (.replay.decision == "allow"))
