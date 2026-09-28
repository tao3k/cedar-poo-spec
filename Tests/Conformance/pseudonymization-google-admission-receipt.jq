.kind == "offline-google-sdp-admission"
and .providerCalled == false
and .staleRaceRejected == true
and .unissuedBeforeTokenizationRejected == true
and .unissuedTokenRejected == true
and .deniedAgentRejected == true
and .wrongScopeRejected == true
and .revokedRejected == true
and .auditFailureRejected == true
and .responseSwapRejected == true
and .endpointSwapRejected == true
and .policyChangeRejected == true
and .auditEntries == 2
and ([.audits[] | .schemaSha256, .policiesSha256,
     .cedarRequestSha256, .googleRequestSha256,
     .googleResponseSha256] | all(.[]; test("^[0-9a-f]{64}$")))
