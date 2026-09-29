# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

.posture.status == "no-expansion-in-schema"
  and .posture.environments_checked == 1
  and .new_grant.status == "expanded"
  and .new_grant.environments_checked == 1
  and (.new_grant.counterexamples | length) > 0
