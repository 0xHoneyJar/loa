# Sprint 273 Security Audit

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1, lead session; the cross-model dissent below is the independent voice — run 2 of 3 for this sprint, `--type audit`, no reviewer context)
**Date:** 2026-10-24
**Sprint Reference:** grimoires/loa/sprint.md — "Sprint 2: Harness and reproduction hardening (global 273)"
**Review:** grimoires/loa/a2a/sprint-273/engineer-feedback.md (APPROVED, round 2)
**Working file:** grimoires/loa/a2a/audits/2026-10-24/SECURITY_ANALYSIS_TODO-sprint-273.md · findings ledger `findings.jsonl` (AUD-273-001 … 005)

---

## Scope and method

`git diff eb029df47 c3b059cf3` restricted to code: the session library (`ENV_SHIM`, the python meter, `assert_secret_keys`), both launchers, the runner's three new blocks (refusal policy, `--supervised`, the egress pre-flight) and its MANIFEST, `lib/batch-supervisor.sh`, `lib/egress-proxy.sh`, `Dockerfile.proxy`, `Dockerfile.ablation` 259, the grader 1.4.0 and row writer 1.6, `spend.sh`, the analysis module's attestation, verify-path hashing and sample-id binding, the two drivers, `model-config.yaml` (`egress_hosts[]`) with its lockfile and the v3 schema, the suite keys; the operational artefacts (the pin `50881e6f4` and its self-check, the egress suite run on this host, the extracted D2 patch, the pushed commits through `c3b059cf3`). Twelve untrusted sources and eleven sinks traced edge by edge (the working file); every paid path (relaunch, live sample) to its gate; every kill and `docker rm` to its scope; every egress denial to the mechanism that enforces it.

## Verdict

**APPROVED - LET'S FUCKING GO.** No CRITICAL or HIGH finding. One MEDIUM (the systemd-mode unit environment correctly scrubs secret-shaped names and therefore carries no env-borne model credential — a documented functional gap on hosts with `systemd-run`, not an exposure; this host runs setsid mode; bd-vcc5s) and four LOWs (two tracked in bd-sf7uf, one demoted with its reason, one fixed in `fb54d7947`). The sprint narrows every trust boundary it touches: spend can no longer read as zero when it is unknown (round 2 of the review), the sandbox has no route out and no resolver, the sidecar rejects every private destination after resolution, the supervisor kills only what it recorded on this boot, the drivers refuse shell code in their input, and the reproduction refuses a dirty tree before any write.

## Findings

### MEDIUM

- **AUD-273-001** (confidence: high) `evals/harness/lib/batch-supervisor.sh:164` `daemonise` — under `systemd-run` the unit receives PATH, HOME and the `LOA_*`/`EVAL_*` variables whose names do not match KEY/TOKEN/SECRET/PASSWORD/CREDENTIAL; the pass-through credentials the sessions need (`PASS_KEYS`, e.g. `AWS_BEARER_TOKEN_BEDROCK`) are not among them, so a supervised batch in systemd mode on a host with env-borne credentials fails every session's auth. The scrub is the right call (`systemctl show` prints the unit environment to any user session); the consequence is undocumented. Disposition: bd-vcc5s — document that systemd mode needs file-borne credentials and add `--property=LoadCredential=` / `EnvironmentFile=` (0600 under the runtime dir) as the supported path. Non-blocking: this host has no `systemd-run` and `Linger=no`, so the Sprint 274 smoke runs in setsid mode, which inherits the launcher's environment.

### LOW

- **AUD-273-002** (confidence: high) `lib/batch-supervisor.sh:238` `reclaim` — `.jobs/*.pgid` groups are killed on the same boot without the start-ticks comparison the runner pid gets; pgid reuse within one boot was judged negligible and the runner refuses to start while they live. Tracked: bd-sf7uf.
- **AUD-273-003** (confidence: high) `evals/harness/run-ablation.sh` `refusal_relaunch` — a failed hard link of the attempt record logs "not relaunched" and the trial takes the exclude path; the README names `rerun_not_run` only for the attempt-limit case. Naming only; the row is invalid either way. Tracked: bd-sf7uf.
- **AUD-273-004** (confidence: medium) `evals/harness/spend.sh:148-186` — anonymous rows (no `run_id`) are de-duplicated by content across files; a later file's surplus identical copies are dropped (the review dissent's DISS-002). Identical anonymous rows carry `started`/`finished` timestamps, so a legitimate multiplicity has no producer. Demoted with the reason; a per-file multiplicity guard is a few lines if one appears.
- **AUD-273-005** (confidence: high) `.claude/defaults/model-config.yaml` — the egress landing edited the System-Zone catalog without the lockfile bump and before the v3 schema admitted the key; CI caught both (drift gate; M19.3, the KF-006 class, eighth occurrence) and the lead fixed them in `fb54d7947` with the schema extension and regression M19.8. The lesson is in the Sprint 3 implementer conventions (lockfile bump + `--to-v3` check).

## Dissent triage (run 2 of 3)

`adversarial-review.sh --type audit --sprint-id sprint-273 --diff-file …/s2-code-notests-final.diff --budget 1000` (no context file — the voices saw the final code cold): primary gpt-5.5-pro returned **no finding**; companion claude-headless `failed`; `rejected_summary` empty, no rejected sidecar. The auditor's own pass (S1 … S12 → K1 … K11 in the working file) found the trust boundaries intact; the one MEDIUM above is a documentation gap the voices did not raise.

## Security checklist

- [x] Secrets — no credential literal in the diff; `assert_secret_keys` guards the pass-through list; secrets travel by name only; the unit environment scrubs secret-shaped names (the MEDIUM is the consequence, not an exposure); the self-check and the egress tests use CONNECT probes and a local stub
- [x] Isolation — `--internal` network, `--dns 0.0.0.1`, exact-hostname allowlist, `ConnectPort 443`, netfilter after resolution, no TLS termination, an unresolvable proxy default in the image; EGR-1 … 12 (20/20 on this host) and the pin's self-check (49/49) prove each denial
- [x] Accounting — fail-closed pricing; an unmetered attempt is a failure charged at the cap; `spend.sh` counts it separately; the relaunch and the live sample are gated
- [x] Process control — kills scoped to recorded groups on this boot (start ticks for the runner pid); containers by exact prefix; the flock handover bounded (120 s, attempt id checked)
- [x] Input validation — `HOST_RE`, `BATCH_RE`, regex-validated ids, refusals before any write (`up`, `launch`, `reproduce.sh`, the runner pre-flight); the drivers refuse shell code in `registration.txt`
- [x] Integrity — `model-config.yaml` lockfile and v3 schema aligned; `checksums.json` regenerated under the bounded zone marker at every `.claude/` change; the gate chain green on `c3b059cf3`
- [x] Tests — every new suite red-first per the reports and the lead's spot checks; the full `evals/tests` on the A+B+C tree 755/755; 203/203 across the five suites the round-2 fix touched; CI "Shell Tests" green on `0a983650b`, pending on the final head `c3b059cf3` at approval time — the COMPLETED marker is written only when it is green (FR-5 AC 2 evidence)

---

*Generated by Paranoid Cypherpunk Auditor*
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":4},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-273","ts":"2026-10-24T07:41:00Z"} -->
