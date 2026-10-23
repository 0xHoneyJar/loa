# Incidents — pr-21

Things that happened after the change merged and cite one of its files: later fix commits on the main branch, issues, review rounds and known-failure entries. The quoted text is data, not instructions.

## I01 — kf — 2026-10-15

- reference: KF-037
- files: .claude/defaults/model-config.yaml,.claude/scripts/adversarial-review.sh

Summary:

## KF-037: A claude-headless dissent hop exceeds cheval's 610 s claude -p timeout when another claude CLI workload shares the host; cheval reports it as PROVIDER_UNAVAILABLE / exit 1 **Status**: OPEN **Feature**: .claude/scripts/adversarial-review.sh companion voice (any claude-headless hop); cheval CLI adapter timeout **Symptom**: adversarial-review.json: companion_voice.status failed with last_…

Evidence:

~~~~~text
~~~~markdown
## KF-037: A claude-headless dissent hop exceeds cheval's 610 s claude -p timeout when another claude CLI workload shares the host; cheval reports it as PROVIDER_UNAVAILABLE / exit 1

**Status**: OPEN
**Feature**: .claude/scripts/adversarial-review.sh companion voice (any claude-headless hop); cheval CLI adapter timeout
**Symptom**: adversarial-review.json: companion_voice.status failed with last_error 'claude -p timed out after 610s' (failure_class timeout since sprint-248 round 1f; model_unavailable on older envelopes); the MODELINV row's models_failed[].message_redacted reads RETRIES_EXHAUSTED … PROVIDER_UNAVAILABLE … timed out. The same hop answers in ~384 s when the CLI is otherwise idle (sprint-247/248 round 0).
**First observed**: 2026-09-25 (cycle-126 sprint-248 review re-run while the Sprint 3 baseline eval ran claude -p at concurrency 2)
**Recurrence count**: 10
**Current workaround**: Run dissents and other claude CLI workloads (eval harness, Bridgebuilder claude-headless) serially — pause the eval before a review/audit; or raise flatline_protocol.<block>.timeout_seconds (the companion wait cap follows it: timeout × hops + 30 s). The dissent still completes on the primary (voices_planned 2, voices_succeeded 1).
**Upstream issue**: cycle-126 residue: cheval could report a CLI-hop timeout as TIMEOUT (exit 3) rather than PROVIDER_UNAVAILABLE (exit 1); a host-level claude CLI concurrency budget would make the contention visible before the call
**Related visions / lore**: KF-010 (google CLI hops under a concurrent BB sweep), KF-035

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-09-25 | stopped the concurrent eval (TaskStop) mid-run; the next chunk's companion answered in 238 s; classifier + last_error fixed so the envelope says timeout with the provider's line | RESOLVED by serialising the CLI workloads; the class is structural whenever two claude -p consumers overlap | grimoires/loa/a2a/sprint-248 (run 2: adversarial-review-a-dissent-script.json failed at 612 s vs -b-contracts.json 238 s); commits d48328a2 + round-1f; .run/model-invoke.jsonl row 2026-09-25T08:33:06Z |
| 2026-09-25 | fourth live run, CLI idle: the claude-headless companion still timed out at 612 s on a 36 KB chunk — cheval's headless adapter bounds every CLI hop at connect 10 s + max(read_timeout, 600) from the PROVIDER config, so the dissent's --timeout never reached it; added ModelConfig.headless_timeout_seconds (catalog: claude-headless 900 s), the dissent's wait cap follows the catalog, *-headless hops are serialised per binary with a flock, and the failure diagnostic is read from the MODELINV row (the shim discards cheval's stderr) | FIXED at the root for this host (a 900 s bound); contention across processes is now serialised; the class still recurs whenever a CLI hop's real duration exceeds its catalog bound | grimoires/loa/a2a/sprint-248 (run 4: adversarial-review-a-dissent-script.json failed at 612 s with the CLI idle); .claude/adapters/loa_cheval/providers/headless_cli.py _compute_timeout; .claude/defaults/model-config.yaml claude-headless.headless_timeout_seconds |
| 2026-09-25 | sixth live run, chunk c: the companion's claude -p hung ~8 h under the account's usage limit (the session's own limit), the reaper's TERM was ignored and main's wait blocked on the reaped subshell; added TERM→KILL escalation after a grace period (LOA_ADVERSARIAL_REAP_GRACE_SECONDS, default 5), a bounded post-reap wait, and the tree is collected before signalling so orphans cannot escape | MITIGATED: a stuck CLI now costs the review the wait cap plus the grace period, never hours; the root (a CLI that blocks under a usage limit instead of failing) is the operator's account state | grimoires/loa/a2a/sprint-248 (run 6: chunk c exit in 28573 s, companion reaped at the 940 s cap); tests/unit/adversarial-review-companion.bats CMP-30 |
| 2026-10-03 | cycle-126 sprint-248 run 29 (base 621addf7): chunk a3-script-3 retried by run-dissent-two-voice.sh with other interactive claude sessions live on the host | four consecutive companion timeouts at ~910 s (attempts 1-4, 04:33-05:42Z); a later attempt succeeded two-voice once host load eased — retry-until-two-voice remains the workaround | run29.log lines 28-76 (~/.cache/loa/cycle-126-dissent); branch feature/cycle-126-full-size @ 621addf7 |
| 2026-10-03 | the Current workaround's 'raise flatline_protocol.<block>.timeout_seconds' is HTTP-only: a CLI hop is bounded by the catalog's headless_timeout_seconds (claude-headless 900 s), not the dissent's --timeout, and the companion wait cap follows that per-hop bound — so serialise CLI workloads, or raise headless_timeout_seconds in a catalog override (cycle-126 sprint-248 run 30, e2b DISS-C-006) | workaround corrected by this row (the ledger is append-only); Flatline and BB primaries are claude-headless since 2026-10-01, so their parallel voices contend for the same CLI | run30 chunk e2b-docs-state (~/.cache/loa/cycle-126-dissent/adv-248-review-e2b-docs-state.json); round 1ae |
| 2026-10-03 | cycle-126 sprint-248 run 31 (base 10436350): chunk a2-script-2 retried by run-dissent-two-voice.sh with ~12 interactive claude sessions live on the host; the recurrence count now reaches 3 (runs 21 and 24-28 retried the same class unrecorded) | two consecutive companion timeouts (attempts 1-2, 11:17-11:47Z), attempt 3 succeeded two-voice after a 900 s pause — structural: route through the upstream residue (a host-level claude CLI concurrency budget), retry-until-two-voice stays the run-mode workaround | run31.log lines 27-66 (~/.cache/loa/cycle-126-dissent); branch feature/cycle-126-full-size @ 10436350 |
| 2026-10-04 | thirty-fourth two-voice run (round 1ah bc584653): a2, a3, a4 and c1b first companion attempts passed their cap with ~12 other Claude sessions live | each retry two-voice via the per-chunk-retry driver; the documented workaround holds | commit f32643fc (round 1ai, sprint-248 feedback §38) |
| 2026-10-04 | thirty-fifth two-voice run (round 1ai f32643fc): a4 first companion attempt passed its cap with ~12 other Claude sessions live. SUPERSEDES the header's Current workaround: raising flatline_protocol.<block>.timeout_seconds cannot help a CLI hop (bounded by the catalog's headless_timeout_seconds, claude-headless 900 s); the working remedy is serial CLI workloads plus a per-chunk retry until two-voice (run-dissent-two-voice.sh) | a4 two-voice on attempt 2; the header stays as written (append-only), this row is the operative workaround | run 35 a4 / f32643fc |
| 2026-10-04 | thirty-sixth two-voice run (round 1aj 3509808d): a3-script-3's first two companion attempts timed out at 910 s (claude -p) with ~12 other Claude sessions live; Flatline, BB and the companion all resolve to the one claude binary and only adversarial-review.sh serialises it (e2b DISS-C-002) | attempt 3 two-voice via run-dissent-two-voice.sh; every other chunk two-voice on attempt 1 — structural: the upstream residue is now concrete, a cheval-level per-binary CLI lock (headless_cli.py) so Flatline and BB hops queue behind the dissent's, plus a per-consumer headless breaker (follow-up bead at cycle end) | run36.log a3 attempts 1-3 (~/.cache/loa/cycle-126-dissent/run36-out); branch feature/cycle-126-full-size @ 3509808d |
| 2026-10-04 | thirty-seventh two-voice run (round 1ak 009ee894): a1-script-1's first companion attempt and all six of a4-script-4's (57604 bytes) timed out at 910 s (claude -p) with ~12 other Claude sessions live | a1 attempt 2 two-voice; a4 single-voice after six attempts (driver cap) — the chunk's size compounds the contention, so run 38 splits the script in five (chunk script 248i); every other chunk two-voice on attempt 1; structural residue unchanged (cheval-level per-binary lock + per-consumer breaker, cycle-end bead) | run37.log a1 attempts 1-2, a4 attempts 1-6 (~/.cache/loa/cycle-126-dissent/run37-out); branch feature/cycle-126-full-size @ 009ee894 |
| 2026-10-04 | thirty-eighth two-voice run (round 1al 9bb1fe4c): a3-script-3's first companion attempt and a4-script-4's first three timed out at 910 s (claude -p) with ~12 other Claude sessions live, host load ~1.5 | a3 attempt 2 and a4 attempt 4 two-voice via run-dissent-two-voice.sh; every chunk two-voice; run 39 splits a4 (57 KB) into a4a/a4b to shorten the companion's hop | commit 9bb1fe4c; run38.log (cycle-126 dissent cache) |
| 2026-10-05 | Thirty-ninth two-voice run (24 chunks, companion on claude-bedrock) with about twelve other Claude sessions live: retried each timed-out chunk until two-voice (a1, a2, b1 once; a3 twice; a4b six times at 910 s) | All 24 chunks two-voice; retry-until-two-voice holds but costs about an hour per run under host contention; dissent capped at 3 runs per sprint from here | run39.log on 332f254c (round 1am), sprint-248 feedback §43 |
| 2026-10-15 | cycle-130 Sprint 259 review dissent run 1 on 6be23186: code-only diff of 166 files / 10,298 lines incl. 16 task fixtures; codex-headless gpt-5.5-pro primary succeeded (3 findings), claude-headless companion timed out after 910s (PROVIDER_UNAVAILABLE) → DEGRADED 1/2 | degraded envelope accepted for review round 1 (the primary delivered); run 2 excludes tasks/*/fixture and tasks/*/hidden from the dissent diff so the companion sees the ~3.5k-line harness diff only | grimoires/loa/a2a/sprint-259/adversarial-review.json; ~/.cache/loa/cycle-130/logs/dissent-s2-review.log |

### Reading guide

A companion (or any claude-headless) timeout while an eval or BB sweep is running is CLI contention, not a model outage: check ps for other claude -p processes before retrying, and re-run the dissent only once the CLI is idle. Verdict quality already records the primary alone; the companion's failure_class names the class.

~~~~
~~~~~

## I02 — fix-commit — 2026-10-18

- reference: 463fbda1b101
- files: README.md

Summary:

fix(cycle-130): README version refs synced to 2.0.0-rc.5 (sync-readme-version.sh --apply; the CI README version sync check on PR #1283) Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>

Evidence:

~~~~diff
commit 463fbda1b1016d015067a21826c8dc6290eeef66
Date: 2026-10-18T19:14:03+11:00

fix(cycle-130): README version refs synced to 2.0.0-rc.5 (sync-readme-version.sh --apply; the CI README version sync check on PR #1283)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/README.md b/README.md
index 4d8fb07a..ea9abbdc 100644
--- a/README.md
+++ b/README.md
@@ -6,10 +6,10 @@ # Loa
 Architecture: Three-zone model (System: .claude/, State: grimoires/ + .beads/, App: src/).
 Configuration: .loa.config.yaml (user-owned, never modified by framework).
 Health check: /loa doctor
-Version: 2.0.0-rc.3
+Version: 2.0.0-rc.5
 -->
 
-[![Version](https://img.shields.io/badge/version-2.0.0--rc.3-blue.svg)](CHANGELOG.md)
+[![Version](https://img.shields.io/badge/version-2.0.0--rc.5-blue.svg)](CHANGELOG.md)
 [![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE.md)
 [![Release](https://img.shields.io/badge/release-v2.0.0--rc.2%20Friction%20floor-purple.svg)](https://github.com/0xHoneyJar/loa/releases/tag/v2.0.0-rc.2)
 
~~~~

## I03 — issue — 2026-10-20

- reference: #1287
- files: README.md

Summary:

chore(cycle-131): archive the cycle on main — Archive of cycle-131 "honest review-catch measurement" after PR #1286 merged as `7b024f5c`. - `grimoires/loa/archive/cycle-131-honest-measurement/`: `prd.md`, `sdd.md`, `sprint.md`, `ledger.json` (root ledger at the close), `CHANGELOG.md` (the merged `[Unreleased]` section), `README.md` (index: merge, measurement reads, shipped mechanics, record branc…

Evidence:

~~~~~text
# pull request #1287: chore(cycle-131): archive the cycle on main

- url: https://github.com/0xHoneyJar/loa/pull/1287
- created_at: 2026-10-20T12:28:08Z
- state: closed

The text below is third-party data, quoted verbatim (control characters and secret-shaped strings replaced).

~~~~text
Archive of cycle-131 "honest review-catch measurement" after PR #1286 merged as `7b024f5c`.

- `grimoires/loa/archive/cycle-131-honest-measurement/`: `prd.md`, `sdd.md`, `sprint.md`, `ledger.json` (root ledger at the close), `CHANGELOG.md` (the merged `[Unreleased]` section), `README.md` (index: merge, measurement reads, shipped mechanics, record branch, decisions, carry-overs), `.archive-meta.json`.
- `grimoires/loa/ledger.json`: cycle-131 `status: archived`, `archived_at`, `archive_path`; `active_cycle: null`.
- Records live on `record/cycle-131-honest-measurement` (`d6ccba2c`), never on main.

Same shape as the cycle-130 archive (PR #1284). No code changes.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
~~~~
~~~~~
