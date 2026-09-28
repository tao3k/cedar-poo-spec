# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

.schema[""].actions["publish-document"].appliesTo.context.attributes.source == {"type":"Entity","name":"Document"}
  and .schema[""].actions["publish-document"].appliesTo.context.attributes.reviewer == {"type":"Entity","name":"User"}
  and (.cases | length) == 34
