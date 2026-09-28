# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

[.[] | select(.replay.case_name | startswith("dispatch-"))] | (map(.replay.case_name) | sort) == ["dispatch-allow-publishdispatched", "dispatch-allow-publishgoverned", "dispatch-deny-publishdispatched", "dispatch-deny-publishgoverned"]
  and (map(.replay.decision) | unique) == ["allow", "deny"]
  and (group_by(.replay.request_sha256) | length == 2
  and all(.[]; length == 2
  and (map(.replay.policies_sha256) | unique | length) == 1
  and (map(.replay.decision) | unique | length) == 1))
