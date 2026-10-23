# Reviewer concerns for the dissent (sprint-1 / PR sprint-257)

1. `hounfour.locality: local_voices` trusts the `dispatch_group: local` label (hop-locality.py, config.ts isLocalVoice, modelinv.hop_locality_of) without checking the provider endpoint host is loopback/RFC1918/localhost — a hosted https endpoint labelled local passes the posture.
2. Bridgebuilder trusted-config gates only admission; cheval reads the checkout's `.loa.config.yaml` for endpoint/auth at dispatch, so a PR head can re-point a trusted keyless provider.
3. cheval itself never refuses hosted hops under local_voices; only four shell/TS planners do.
4. Budget gate now sums primary + companion + advisory at catalog prices; example comment still says "ONE dissent call"; at gpt-5.5-pro the estimate is ~4x the old one.
5. model-health-probe `--provider <configured>` applies the hosted host allowlist the cheval loader skips; the Azure example is refused.
6. dispatcher.sh accepts any exit 3 as completed-degraded without a run JSON.
7. localhost opt-in is resolved by the system resolver though docs say never resolved.
8. enforce_context_window alias never set by cheval; unterminated <think> swallows the answer.
