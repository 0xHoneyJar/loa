# Reviewer concerns — sprint-1 (PR: sprint-257, cycle-129)

Scope: pr/head.diff (80 files). Areas the lead reviewer wants a second voice on:

1. Locality rule drift: hop-locality.py and Bridgebuilder isLocalVoice honour a provider-level dispatch_group, but cheval's
   TransportPolicy (openai_adapter._transport_policy) and MODELINV hop_locality_of read the model entry only. Under
   local_voices a provider-level declaration is planned as local without the request-time rules.
2. Bridgebuilder exit 3 (DEGRADED) default: are there callers of bridgebuilder-review/resources/entry.sh other than
   spiral-harness.sh and the session-cap-bb dispatcher that treat any non-zero exit as failure?
3. Budget gate: .loa.config.yaml.example still says budget_cents gates ONE dissent call and that the companion voice is not
   counted; the new estimate sums primary + companion + advisory voices.
4. Advisory voices run process_findings (incl. KF-004 repair) concurrently in background subshells; any shared-state or
   sidecar leak into the a2a directory?
5. endpoint-validator.py validate_declared_endpoint admits a hostname containing `{region}` braces (bedrock template).
6. openai_adapter _names_response_format: any HTTP 400 mentioning json_schema (including a schema-content rejection from a
   server that supports response_format) triggers the unenforced retry.
7. parseProviderDecls treats any literal auth as keyless; cheval normalises only "local".
