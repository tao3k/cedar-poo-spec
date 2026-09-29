# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

length == 34
  and all(.[]; (.schema_sha256 | test("^[0-9a-f]{64}$"))
  and .replay.error_policy_ids == [])
