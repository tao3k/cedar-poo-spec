# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

.schema.Data.entityTypes.Classification.enum == ["public","restricted"]
  and .schema.Data.entityTypes.Document.shape.attributes.classification == {"type":"Entity","name":"Data::Classification"}
  and .schema.Org.actions.read.appliesTo.principalTypes == ["Org::User"]
  and .schema.Org.actions.read.appliesTo.resourceTypes == ["Data::Document"]
  and (.cases | length) == 4
