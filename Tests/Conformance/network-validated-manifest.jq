# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

.schema[""].actions.query.appliesTo.context.attributes.sourceIp == {"type":"Extension","name":"ipaddr"}
  and (.cases | length) == 9
