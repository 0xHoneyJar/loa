# Reviewer concerns — sprint-1 (PR: sprint-257, cycle-129 FR-7 / FR-8)

Scope: pr/head.diff (80 files, 6583 insertions). Cite as head/<path>:<line>.

## Concerns found by the primary reviewer

1. Locality is a label, not a property. `hop-locality.py` (classify, lines 116-134), `modelinv.hop_locality_of` (476),
   `openai_adapter._transport_policy` (221) and Bridgebuilder `isLocalVoice` (config.ts 726-733) call a hop `local`
   whenever its model entry or provider block says `dispatch_group: local`. Nothing checks that the provider's endpoint
   host is loopback/RFC1918/localhost or that the provider is not a CLI hop. Reproduced: a declared provider with
   endpoint https://api.together.xyz/v1 and `dispatch_group: local` classifies `local`; under `hounfour.locality:
   local_voices` the dissent, Flatline and Bridgebuilder would dispatch to it.
2. Bridgebuilder trusted config only governs Bridgebuilder's own plan; every voice dispatches through cheval, which
   reads the CHECKOUT's `.loa.config.yaml`. On a PR-head checkout the head can change a trusted provider's endpoint
   (or aliases) and cheval sends the prompt and the `{env:VAR}` credential there. SKILL.md 117-118 claims the keys
   "follow the trusted-source precedence even when the checkout is a PR head".
3. dispatcher.sh 78-90: exit 3 is treated as completed-degraded and converted to exit 0 without checking that the run
   JSON (a `verdicts` array) exists on stdout.
4. model-health-probe.sh 1469-1475: `_probe_configured` validates with the probe allowlist, so a configured https
   provider on a non-allowlisted host (Example 3, Azure) is "endpoint refused" while cheval admits it.
5. Budget gate now sums primary + companion first hop + advisory voices (adversarial-review.sh 4329-4335) but
   `.loa.config.yaml.example` 1624-1627 still says the companion voice is NOT counted.
6. config.ts 482: any literal `auth` is keyless in Bridgebuilder; cheval normalises only `auth: "local"`.
7. endpoint-validator.py 1047/1054: `localhost` opt-in is admitted with the claim it is "never resolved"; it is
   resolved by the OS resolver when the request is sent.
8. Advisory voices: each hop is still bounded by `timeout_seconds` (60 default); `advisory_timeout_seconds` is only an
   outer bound.
9. README.md 22 links a CHANGELOG entry that this PR does not add.

## Areas the dissenter should probe
- adversarial-review.sh advisory walker / block (3800-4030) — process lifecycle, jq operand sizes, sidecar disable.
- endpoint_policy.py / endpoint-validator.py step 1.5 — opt-in host comparison, IPv4-mapped IPv6, `127.1` forms.
- base.py TransportPolicy — httpx/urllib redirect and proxy handling on the streaming path.
- openai_adapter.py — schema-rejection retry heuristic, keyless header omission.
- flatline-orchestrator.sh locality gate memoisation and tertiary cache mutation.
