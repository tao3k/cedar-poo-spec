# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

(.before.schema[""].entityTypes.Dataset.shape.attributes | has("classification") | not)
  and .after.schema[""].entityTypes.Dataset.shape.attributes.classification == {"type":"String","required":false}
