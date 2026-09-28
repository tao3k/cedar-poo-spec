# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

.freeze.status == "no-expansion-in-schema"
  and .freeze.environments_checked == 4
  and .restore.status == "expanded"
  and .restore.environments_checked == 4
  and (.restore.counterexamples | length) > 0
