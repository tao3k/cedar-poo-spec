([.[].root] | sort) == ["AgentIncident", "HospitalSiv", "OneWayHmac", "RandomizedGcm", "Recovered", "ResultRelease"] and all(.[]; (.policies.staticPolicies | has("legacy-reidentify") | not))
