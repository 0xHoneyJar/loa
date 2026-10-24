All good

Observations documented and non-blocking after round 2; the round-1 required change landed (see § Round 2). See Observations below.

# Sprint 273 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1, lead session; the cross-model dissent below is the independent voice)
**Date:** 2026-10-24
**Sprint Reference:** grimoires/loa/sprint.md — "Sprint 2: Harness and reproduction hardening (global 273)"
**Implementation Report:** grimoires/loa/a2a/sprint-273/reviewer.md (+ reviewer-{a,b,c,d2,e}.md, e2e.md)

---

## Overall Assessment

The sprint delivers the harness the next measurement needs: one session library whose meter fails closed, a descriptor shim that reaches the hard limit, the secrecy assertion, a worktree-attested reproduction with a live sample gated on a clean engine, judge packets bound to a sample id, drivers that cannot escape their checkout, generated fixtures, a grader whose two false-positive shapes are exempt with a 396-pair regression and a 517-directory re-grade, a refusal policy recorded before execution with immutable attempt records, a restartable batch supervisor with durable identity, and an egress block that the container suite proves on this host (20/20) and the pin's self-check confirms (49/49). The pipeline version is pinned (`50881e6f4`, DEC-0906). Nothing under `evals/results/`, the record branch or the cycle-132 reads changed.

One finding blocks the round. The session library distinguishes an attempt that produced no usage event from zero spend — as C-6 asks — but then lets it finish as a completed session whose `total_cost_usd` is 0 and whose `metering` field nothing downstream reads: an unknown spend consumed as an authoritative zero, the exact fail-open shape C-6 was written to remove. It is a small, well-located change (the two launchers' status tables, the row writer, the spend ledger) and is required before approval.

Code read, not the report: `lib/session-exec.sh` (`ENV_SHIM`: `/proc/self/fd` listing closed around the listing handle and `LOA_KEEP_FDS` — a malformed list exits 2; the closerange fallback split around kept descriptors with an infinite or ≤ 3 hard limit read as 1,048,576; `assert_secret_keys` over `PASS_KEYS` with the documented pattern; the python meter behind `price_for`/`price_events`/`unmetered_tail`), `blind-session.sh:195-200, 328-348, 470-505` (pre-launch price check before `mkdir`; the watchdog stop; the final status table), `pipeline-run.sh:559-568, 984-1066` (literal source of the lib, pre-launch pricing of every planned phase, the metering stop), `run-ablation.sh` (the refusal block `refusal_policy_of … refusal_collect`: policy from MANIFEST, the hard-linked immutable record, the 3-attempt limit, `REF_FRESH`; the `--supervised` exec block; the egress pre-flight with the two-condition bats escape; `write_manifest` carrying `supervisor` and `egress`), `lib/batch-supervisor.sh` (`take_lock` flock on fd 9 with the `launching` handover record; `daemonise` with the scrubbed `systemd-run` environment or `setsid`; `reclaim` — boot id compared first, `ident_alive` start-ticks before `kill_group` on the runner pid; `stop_containers` by docker name filter AND an exact prefix check; `uncertain_runs`), `lib/egress-proxy.sh` (`HOST_RE` lower-case hostnames only, ≤ 200; `up` refusals before any docker write; `record-address` bounded by `--max-s` and `--parent-pid`), `Dockerfile.proxy` (tinyproxy `FilterDefaultDeny` exact hostnames, `ConnectPort 443`; netfilter OUTPUT DROP, private/loopback/link-local/CGNAT/reserved REJECTed after resolution, tcp 443 to public IPv4 only, IPv6 dropped), `Dockerfile.ablation` 259 (CA bundle, unresolvable proxy default, the Claude Code version pinned and printed), `ablation-grade.sh` 1.4.0 (`heredoc_report_write`, `home_mount_probe`, the exempt records), `ablation-row.sh` 1.6 (the outcome and denominator rule, `--refusal-rate`), `evals/analysis/c132/reproduce.sh` (two pins, porcelain incl. untracked, exit table, live gating), `record_lite.py` (`sha256_file(verify=)`, the Mismatch on an unsafe target), `judge_defects.py` (`sample_id` stamping and binding, `--force`, grade-loaded validity), the two drivers (BASH_SOURCE roots, whitelist parsing), `spend.sh` (`(run_id, batch)` dedup; anonymous rows by content across files), `tests/synth.py`, `.claude/defaults/model-config.yaml` (`egress_hosts[]`), the suite keys, `tools/check-no-swallowed-jq.sh` (the lib glob), the lead's CI fixes (`run-ablation.sh` jq fragment; `model-config-v3.schema.json` `egress_hosts`; the lockfile).

Tests read and run by the reviewer on the integrated tree: A — session-exec 25, blind-session 15, pipeline-run +7, with ablation-grade 214/214; B — analysis pytest 232, analysis-c132 + manifest-v2 + spend bats 24/24; C — ablation-grade 80, ablation-row 49, refusal-policy 12, run-ablation 59, pipeline-run 92 = 299/299; the full `evals/tests` on the A+B+C tree 755/755; D3 — batch-supervisor 13 with run-ablation, refusal-policy, pipeline-run 183/183; D2 — egress-proxy 20/20 on this host (Docker 26.1.5), the runner suites 84/84 with the test escape; the pin's self-check 49/49; migrate-model-config 45/45 after the schema fix; the gate chain green at every landing; CI "Shell Tests" green on the A+B+C head `0a983650b`. Seams under test (sprint.md): a prices JSON lacking the model id (SE-3, BS-12, PR-c133-2), a killed driver under the supervisor (BSV-13), `git ls-remote github.com` from inside the sandbox (EGR-2, self-check), `reproduce.sh` in a dirty worktree (`test_reproduce.py`) — all four exercised.

**Verdict:** APPROVED (round 2, 2026-10-24T07:40Z). Round 1 (07:25Z) was CHANGES_REQUIRED on one blocking finding — the `unmetered_attempt` accounting; the fix landed as `256f88fbf` and was re-read (§ Round 2 below).

---

## Observations

### Round-1 required change (FIXED in round 2, commit `256f88fbf`)

- **Resolved in round 2 — was the round-1 blocking finding** (confidence: high; confirmed) `evals/harness/blind-session.sh:476-505`, `evals/harness/pipeline-run.sh:1063-1066`, `evals/harness/spend.sh`, `evals/harness/ablation-row.sh` — DISS-001 (voice: BLOCKING): an attempt that ran without any usage event and without a numeric result cost is classified `metering: unmetered_attempt` — and then finishes `status=completed exit_code=0` with `total_cost_usd` = estimate (0, no priced events) + ledger (0); `spend.sh`, `ablation-row.sh` and `run-ablation.sh` never read `metering`, so the row's unknown spend enters every total and every budget gate as 0. sdd.md C-6 (line 72) created the `unmetered_attempt` row "so accounting failure is distinguishable from zero spend": it is an accounting failure and must be handled as one. **Required change (implementer A, follow-up s2-a2):** `blind-session.sh` ends such a session `status=unmetered_attempt exit_code=1` with `total_cost_usd` charged at the cap (`cost_source: "cap_unmetered"`, `result_cost_usd: null`), never 0; `pipeline-run.sh` ends the run `infrastructure_error` (exit 2) with reason `unmetered_attempt: <label>` and the phase charged at its cap; `ablation-row.sh` marks the row `metering_unmetered: true` (already invalid as `infrastructure_error`); `spend.sh` counts such rows separately (`runs_rows_unmetered`), includes their cap charge in the authoritative total and names them on stderr; tests red first for each (SE/BS/PR, the row writer, the spend ledger). The distinct `metering` values stay so the class remains distinguishable.

### Non-blocking

- **MEDIUM** (confidence: high) `evals/harness/lib/batch-supervisor.sh` `daemonise` (`:164`) — under `systemd-run` the unit's environment is PATH, HOME and the `LOA_*`/`EVAL_*` names not matching KEY/TOKEN/SECRET/PASSWORD/CREDENTIAL; the model credentials the runner passes through (`PASS_KEYS` in `lib/session-exec.sh`: `AWS_BEARER_TOKEN_BEDROCK`, …) are therefore absent in systemd mode, so a supervised batch on a host with `systemd-run` and env-borne credentials would fail every session's auth. The scrub is right (`systemctl show` exposes the unit environment); the consequence is undocumented. Document that systemd mode needs file-borne credentials (the sandbox's read-only credential copies, an AWS profile) and name `--property=LoadCredential=`/`EnvironmentFile=` (0600 under the runtime dir) as the supported path for env-borne ones. This host runs setsid mode (no `systemd-run`, `Linger=no`), so the Sprint 274 smoke is unaffected. Follow-up bead.
- **LOW** (confidence: high) `lib/batch-supervisor.sh` `reclaim` (`:238`) — `.jobs/*.pgid` groups are killed on the same boot without the start-ticks comparison the runner pid gets; the implementer judged pgid reuse within one boot negligible and the runner refuses to start while they live. Acceptable; a `ticks_of` check per pgid file would close it.
- **LOW** (confidence: high) `run-ablation.sh` `refusal_relaunch` — when the attempt record cannot be hard-linked (another writer, or a results root on a filesystem without hard links) the trial is logged "not relaunched" and its row is the refused first attempt under the policy's exclude path; the README's `rerun_not_run` outcome names only the attempt-limit case. Name this case `rerun_not_run` too.
- **LOW** (confidence: medium) `evals/harness/spend.sh:148-186` — DISS-002 (voice: BLOCKING; reviewer: not a practical risk): anonymous rows (no `run_id`) are de-duplicated by canonical content across files, so a later file holding more identical copies than the first loses the surplus. Rows carry `started`/`finished` timestamps, so two byte-identical anonymous rows are the same row copied (exactly the tracked-copy vs results-root case the dedup targets); a legitimate multiplicity of identical anonymous rows has no real producer. Demoted; a per-file multiplicity guard would cost a few lines if one ever appears.
- **LOW** (confidence: high) landing — the egress patch landed with three CI-only consequences the lead fixed in `fb54d7947`: the eval trust-boundary lint misread a jq `| . as $a` fragment (rewritten), the closed v3 model-config schema rejected `egress_hosts` (KF-006 class, eighth occurrence — the schema now admits it, M19.8), and the model-config lockfile needed its checksum bump. Recorded in KF-006's attempts.
- **LOW** (confidence: high) process — implementer B's red run of the old `final.sh` rewrote a tracked file in the lead's tree (restored before any commit; DEC-0894); implementer D stalled and was replaced by D2 + D3; D2 stalled after running its suite and its work was taken from the worktree by the lead (DEC-0905). The egress and supervisor code was therefore reviewed by the lead without an implementer report for the egress half (the lead wrote `reviewer-d2.md` from the code and logs).

### Complexity (SIMPLICITY, non-blocking)

- `run-ablation.sh` gained three contiguous blocks (refusal, supervised, egress) from three implementers and now carries the MANIFEST merge of their fields; each block is marked and single-purpose, and the suites pin them. `SIMPLICITY[shrink]: no net-line reduction without moving the blocks into libs; the egress pre-flight is the only candidate (it already mirrors lib/egress-proxy.sh's checks). Lean enough. Ship (the round-1 finding is fixed).`

## Round 2 — the required change, re-read (lead; no further dissent run)

Commit `256f88fbf` (implementer A, s2-a2; diff read line by line): `blind-session.sh` — `elif [[ "$METERING" == unmetered_attempt ]]; then status=unmetered_attempt exit_code=1` in the status table beside `metering_incomplete`; cost.json `cost_source: cap_unmetered`, `total_cost_usd: $cap` when unmetered, `result_cost_usd` null; the spend row carries `cost_source` and `cap_usd` (the exit-trap path reads `cost_source` from cost.json with a `[a-z_]+` guard). `pipeline-run.sh` — `if [[ "$metering" == unmetered_attempt ]]; then finish infrastructure_error 2 "unmetered_attempt: $label"; fi` after the phase; the phase record's `cost_usd` is the cap allowance (`max(budget, 0)` micro-USD — the run cap minus the spend before the phase, since there is no per-phase cap) with `cost_source cap_unmetered`; `cost_micro` set to the allowance so `spent_usd` reaches the run cap. `ablation-row.sh` — `metering_unmetered` derived from the reason prefix or any phase's `metering`, additive (not required by `--validate`). `spend.sh` — rows with `metering == unmetered_attempt` or `metering_unmetered true` are counted in `runs_rows_unmetered`, a zero-cost row with a numeric `cap_usd` is charged `cap_usd` (`c = max(c, cap_usd)`), one stderr line names them; the JSON report carries the new figure. Tests: blind-session, pipeline-run, ablation-row, spend and session-exec 203/203 on the integrated tree; `test_spend.py` 3; the gate chain green. The distinct `metering` values stay, so the class remains distinguishable from zero spend as C-6 asks (DEC-0907). Required change: landed.

## Cross-model dissent triage (run 1 of 3)

`adversarial-review.sh --type review --sprint-id sprint-273 --diff-file …/s2-code-notests.diff --context-file reviewer-concerns.md --budget 1000`: primary gpt-5.5-pro completed with two findings (both marked BLOCKING by the voice); companion claude-headless **failed** — `RETRIES_EXHAUSTED PROVIDER_UNAVAILABLE timed out after 910s` on the 320 KB diff (KF-037, recurrence 11; attempt row added); `rejected_summary` empty, the rejected sidecar has zero rows. Triage: DISS-001 confirmed as the HIGH above; DISS-002 demoted to LOW (no real producer of identical anonymous rows). The companion's silence means the fourteen reviewer concerns were answered by one voice and the lead's own read; the audit's dissent run sees the final code.

## Rejected dissent payloads

None (`rejected_summary` empty; the sidecar file exists with zero rows).

---

## Acceptance Criteria Check

| Criterion (sprint.md, verbatim) | Status | Notes |
|---|---|---|
| PRD FR-6 AC 1–3 (sentinel on every listed condition; descriptors above 65535 and above a lowered soft limit closed; secrecy assertion; one copy of the mechanics; swallowed-jq scan covers the lib) | Pass (round 2) | the sentinel, the shim, the assertion and the one copy are in; the `unmetered_attempt` accounting (AC 1's spirit: never zero spend) is the HIGH above |
| PRD FR-7 AC 1–2 (pytest/bats per item; the cycle-132 record untouched; version note) | Pass | 232 pytest + 24 bats; the record, `evals/results/**` and the read numbers untouched; version notes present |
| PRD FR-8 AC 1–2 (shapes re-graded benign, every other fixture identical; policy recorded before execution with the row fields) | Pass | AG-c133-1 … 5, regress.sh 396 pairs, the 517-directory re-grade; RP-R1, RP-1, RP-2 |
| PRD FR-9 AC 1–2 (supervisor bats incl. lock, orphan reconciliation, atomic rows; container bats or dated quarantine; denied connects logged; image 259 pinned) | Pass | BSV-1 … 13; EGR-1 … 12 20/20 (no quarantine row); `denials`/`record-address`; image 259 in README § Pipeline version and the Dockerfile |
| Review APPROVED, audit APPROVED, ≤ 3 dissent runs | Review APPROVED (round 2; dissent run 1 of 3 used) | `/audit-sprint sprint-2` follows with dissent run 2 |

---

## Security Checklist

- [x] No hardcoded secrets — none in the diff; `assert_secret_keys` guards the pass-through list; the unit environment is scrubbed (see the MEDIUM for the consequence)
- [x] Input validation — hostnames by `HOST_RE`; batch names by `BATCH_RE`; bead and run ids by regex; refusals before any write in `egress-proxy.sh up`, `batch-supervisor.sh launch`, `reproduce.sh`, the runner's pre-flight
- [x] Isolation — internal network, DNS sinkhole, netfilter after resolution, exact-hostname allowlist, CONNECT 443 only, no TLS termination; the egress suite proves each denial on this host
- [x] No shell injection — argument arrays; jq via `--arg`/`--argjson`; Python under `-I`; the drivers refuse shell code in `registration.txt`
- [x] Process control — the supervisor kills only recorded groups on the same boot (start ticks for the runner pid) and containers by exact prefix
- [x] Error handling — one stderr line per refusal; typed exit codes per § 5.4; the metering failure path is fail-closed after round 2 (an unmetered attempt is a failure charged at the cap)

---

## Code Quality Summary

**Strengths:** every new mechanism arrived with red-first tests and, where it matters, a mutant proof or a real-data regression (1,565 transcripts, 396 grader pairs, 517 directories, 20 container cases); refusals precede writes throughout; the egress design puts the enforcement where the address is known.

**Areas for improvement:** the systemd-mode credential path (document; bd-vcc5s); the runner's three blocks (a later lib extraction); the LOWs in bd-sf7uf.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":5},"excluded":0,"sprint_id":"sprint-273","ts":"2026-10-24T07:40:00Z"} -->
