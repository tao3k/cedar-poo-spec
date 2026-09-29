# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

.schema[""].entityTypes.User.tags == {"type":"String"}
  and .schema[""].entityTypes.Timesheet.tags == {"type":"String"}
  and .schema[""].actions.approve.memberOf == [{"type":"Action","id":"ApproverActions"}]
  and (.cases | length) == 13
