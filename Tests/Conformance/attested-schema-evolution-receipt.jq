# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

(.before_schema_sha256 | test("^[0-9a-f]{64}$"))
  and (.after_schema_sha256 | test("^[0-9a-f]{64}$"))
  and .before_schema_sha256 != .after_schema_sha256
  and (.replay | length) == 6
  and all(.replay[]; .error_policy_ids == [])
