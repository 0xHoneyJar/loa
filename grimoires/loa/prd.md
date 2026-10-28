# Product Requirements Document: Performance follow-ups (cycle-137)

**Version:** 1.1
**Date:** 2026-10-28
**Revision:** 1.1 integrates the Flatline PRD review (6 blockers, 47 medium items — dispositions in Appendix C): one authoritative release predicate, evidence bound to commit SHAs, an exact allowed-failure list, memo and cache invalidation tests, verify-chains snapshot semantics, a publish-summary stage.
**Author:** Requirements Agent (Claude Fable 5.1, unattended)
**Status:** Draft — autonomous cycle on the operator's instruction of 2026-10-28 ("(1) do formal gates and then release when ready and you can also work through the open beads")
**Cycle:** `cycle-137-performance-followups` (ledger), branch `feature/cycle-137-performance`
**Grounding:** brownfield; no `/ride` run — the grounding reads are the loop's own artifacts and the code paths named per section (Appendix B); the brief is `grimoires/loa/context/cycle-137-brief.md`

---

## Table of Contents

1. Executive Summary
2. Problem Statement
3. Goals & Success Metrics
4. User Personas & Use Cases
5. Functional Requirements
6. Non-Functional Requirements
7. User Experience
8. Technical Considerations
9. Scope & Prioritization
10. Success Criteria
11. Risks & Mitigation
12. Timeline & Milestones
13. Appendix A — Goals
14. Appendix B — Grounding reads
15. Appendix C — Flatline PRD review dispositions

> Sources: this document's sections

---

## Executive Summary

On 2026-10-27/28 a 22-pass `extreme-software-optimization` skill loop produced 20 commits (395795939 … c0d41f5e3) that cut the framework's own overhead: the repo-map generator 4658 → 1219 ms, grimoire-index 1819 → 826 ms, the known-failures SessionStart hook 488 → 15 ms, the Write/Edit PreToolUse chain about 78 → 62 ms, the Stop guard 24 → 14 ms, and a deterministic spawn-budget guard. Every pass was profiled first, proven byte-identical old-vs-new on golden and adversarial fixtures, reviewed by a fresh Opus 5.5 agent and verified by the orchestrator — but the loop ran outside `/implement`, so the formal `/review-sprint` and `/audit-sprint` gates never ran, the branch is unpublished, and the loop left six follow-up beads.

This cycle lands the loop through the formal gates as Sprint 1 (global 281, review and audit fixes only), closes the six beads as Sprint 2 (global 282: a latent KF field-parsing defect, four further spawn reductions with byte-identical output, two slow test files, and a security-sensitive batching design that may end as a documented deferral), and ships one PR through a Bridgebuilder round, the record branch, the archive and the `v2.0.0-rc.9` release candidate.

> Sources: `grimoires/loa/context/cycle-137-brief.md`; `.skill-loop-progress.md` § LOOP 2; `grimoires/loa/reports/perf/eso-loop-2026-10-27.md`; beads bd-atk7q, bd-gv5jf, bd-h5tcn, bd-1mfm7, bd-wctli, bd-09z1i (`br show`)

---

## Problem Statement

### The Problem

1. **Unreviewed by the framework's own gates.** The 20 loop commits touch 18 System Zone files plus `checksums.json` (enumerated in § System Zone authorization: hooks on the per-tool-call path, `compat-lib.sh` sourced by about 78 scripts, the cheval provider registry, the repo-map engine). CLAUDE.md requires every code change to pass `/review-sprint` and `/audit-sprint`; the loop's per-pass Opus reviews are evidence, not the gate.
2. **Six findings left open.** (a) `loa-kf-surface.sh:103-104` and `grimoire-index.sh:100-101` parse a `**Label**: value` or `**Label (x):**` field but not `**Label (x)**:`; a digit-less `## KF-abc:` heading does not reset `cur`, so its Symptom lands on the previous entry (latent: the live file has 0 such entries). (b) `loa-status.sh:862-869` reads the same `.loa.config.yaml` six times with `yq` (~40 ms) and `agy_gate_warn_once` (`agy-gate-lib.sh:300-304`) re-reads the opt-in node (~25 ms). (c) `profile-lib.sh` serves `karpathy_principles.diff_lines_per_task` from the live path (`_loa_pl_live`, `yq`+`jq`, ~10 ms) on every Write/Edit because it is not a profile knob (`.claude/data/profiles.yaml` lists only `surgical_diff_warning`). (d) `grimoire-index.sh:222` parses the 1,100-row `decisions.yaml` with `yq -o=json` on every run (~175-210 ms, the remaining floor) and re-parses the 600 KB index JSON twice in write mode (lines 299-330, ~25 ms). (e) `tests/unit/adversarial-review-companion.bats` exceeds 900 s (284 tests; 300 s `sleep` holder processes and 0.1 s polls at lines 182-232) and `block-destructive-bash.bats` runs its cycle-125 corpus in three tests (lines 1546-1583, ~28 s each). (f) `audit-envelope.sh verify-chain` costs ~155 ms per chain file because `_check_trust_store` (`audit_envelope.py:500`) spawns a second Python process (`audit-signing-helper.py trust-store-verify`, line 719) per call — a deliberate TOCTOU defence pinned by `tests/security/test_audit_trust_policy.py`.
3. **Nothing shipped.** `v2.0.0-rc.8` is the latest release; the branch is local.

### User Pain Points

- The maintainer cannot merge the loop without the gates the repository promises every contributor.
- Every session start, every edit and every `/loa` still pays avoidable spawns on the paths the loop did not reach.
- Two test files make the 51-minute unit suite longer than it needs to be and make CI timing fragile.

### Current State

Branch `feature/cycle-137-performance` = `main` 9e23cbf84 + the 20 loop commits + the kickoff commit; `check-loa.sh` passes (`checksums.json` refreshed); the full unit suite on the loop head shows only the 3 pre-existing `semver-evidence` failures (KF-034) and one load-sensitive timing test (CMP-37) that passes alone.

### Desired State

Sprint 281 review `All good` and audit `APPROVED` on the loop; the six beads closed with red-first tests and byte-identical output (or one deferred with a decision row); one PR merged on green checks; record and archive; `v2.0.0-rc.9` published.

> Sources: `.claude/hooks/loa-kf-surface.sh:103-115`, `.claude/scripts/grimoire-index.sh:100-115, 216-230, 296-330`, `.claude/scripts/loa-status.sh:848-870`, `.claude/scripts/lib/agy-gate-lib.sh:122-139, 203-205, 300-304`, `.claude/scripts/lib/profile-lib.sh:28-75, 212-260`, `.claude/data/profiles.yaml:28-48`, `tests/unit/adversarial-review-companion.bats:182-232`, `tests/unit/block-destructive-bash.bats:1546-1583`, `.claude/adapters/loa_cheval/audit_envelope.py:414, 500, 580, 719`, `~/.cache/loa/eso-loop/final-table.tsv`, `~/.cache/loa/eso-loop/bats-final/unit.tap`

---

## Goals & Success Metrics

### Primary Goals

- G-1: Sprint 281 — `/review-sprint` ends `All good` and `/audit-sprint` ends `APPROVED` on the 20 loop commits, with every review or audit fix landed red-first and the loop's parity proofs re-run on the final head.
- G-2: Sprint 282 — beads bd-atk7q, bd-gv5jf, bd-h5tcn, bd-1mfm7 closed with a commit and a red-first test each; bd-wctli (test-only) closed with a commit, the TAP-set parity evidence and the negative control of FR-6; bd-09z1i closed by implementation or deferred under the deferral rule of § Release predicate (R-2) with a decision row naming the security reason.
- G-3: the loop's gains hold on the shipped head: in the re-baseline of the sixteen loop commands no command a loop pass touched has a mean above 110 % of its `final-table.tsv` mean (faster is fine; the four untouched rows are recorded, not asserted), and `tests/unit/perf-spawn-budget.bats` is green on every landed commit.
- G-4: the full `tests/unit` suite on the final head fails only the three tests of the allowed-failure list (§ Release predicate R-4, KF-034) and those fail identically on `main` under the same host condition; `adversarial-review-companion.bats` passes in a serial run of the whole file on an idle host (a `-f CMP-37` run alone is diagnostic, not acceptance evidence).
- G-5: one PR from `feature/cycle-137-performance`, Bridgebuilder ≤ 2 rounds non-degraded, merged when every required check is green on the exact head, record branch and archive as every cycle.
- G-6: `v2.0.0-rc.9` published from the post-merge candidate with the CHANGELOG heading and version markers in place.

### Key Performance Indicators (KPIs)

- Measured with one benchmark protocol (§ Non-Functional Requirements → Performance): `loa-status.sh` mean ≥ 40 ms below the same-session old mirror after FR-3 (the AC and this KPI are the same threshold); karpathy hook trace shows no `yq` on the warm-cache path after FR-4; `grimoire-index.sh` warm run ≤ 650 ms (from 826) and its cold run ≤ old mirror + 40 ms after FR-5; `adversarial-review-companion.bats` ≤ 300 s serial (or the measured floor recorded by a decision row) and the three `block-destructive-bash.bats` corpus tests sharing one corpus run after FR-6.
- Parity: every FR-3/4/5 change byte-identical old-vs-new on the live inputs and the named fixtures (stdout, stderr, rc, written files).
- Cycle meter spend ≤ USD 30 (Flatline reviews, dissent runs, Bridgebuilder rounds on subscription routes; real charges ≈ 0).

### Constraints

- System Zone writes carry `checksums.json` and `REPO-MAP.md` regenerated in the same commit (DEC-0824); red-first tests for behaviour changes (test-only changes prove themselves by TAP-set parity plus a negative control); no NEW timing-based tests — the one retained latency test in `block-destructive-bash.bats` is grandfathered and the spawn-budget guard is the deterministic form; `br` contract calls untouched.
- Evidence binds to SHAs: every review, audit, parity and performance artefact names the head commit it was produced on (`reviewed_head: <sha>` in the verdict files, the head sha in each e2e table). A code commit after a verdict invalidates it and the gate re-runs on the new head (a verify-only pass is enough when the diff is a gate fix); docs-only commits (paths under `grimoires/`, `CHANGELOG.md`, `README.md`, `.loa-version.json`, `.skill-loop-progress.md`) do not.
- Bounded loops: at most three fix → re-review iterations per gate and at most two Bridgebuilder rounds; the next finding HALTs the cycle with the state recorded (`.run/sprint-plan-state.json` HALTED, a NOTES entry, the open bead) instead of a fourth attempt.
- One PR for both sprints (DEC-0960 pattern); ≤ 3 dissent runs per gate; the archive is the separate housekeeping merge.
- Never edit the cycle-132 … 136 records; secret scan before every push; NOTES.md stays under the notes-size guard (rotate first if needed).

> Sources: `grimoires/loa/context/cycle-137-brief.md` § Constraints; DEC-0824, DEC-0960; `.claude/hooks/safety/notes-size-guard.sh:28-34`

---

## User Personas & Use Cases

### Primary Persona: The maintainer (operator)

Asked for the formal gates, a release, and the beads. Reads the ELI5 summary and the decision rows; decides nothing mid-cycle.

### Secondary Persona: A downstream mount operator

Runs the same hooks on every tool call in their own repository; gains the loop's latency cuts on `/update-loa`; must see no behaviour change.

### Tertiary Persona: The lead agent and its implementers

Needs crisp seams: each bead is one file or one lib with an existing bats suite, a parity harness pattern (old-vs-new mirror in a real directory) and a measured target.

### Use Cases

- UC-1: a session starts → SessionStart hooks finish in ~110 ms instead of ~600 ms; the KF table is identical.
- UC-2: an agent edits a file → the PreToolUse chain costs ~62 ms and the karpathy PostToolUse hook no longer spawns `yq` for its threshold knob.
- UC-3: the operator runs `/loa` → one `yq` read of the model ceilings instead of six; identical status lines.
- UC-4: CI runs the unit suite → the companion and block-destructive files finish in minutes, same pass/fail set.
- UC-5: a release consumer installs `--tag v2.0.0-rc.9`.

> Sources: `grimoires/loa/reports/perf/eso-loop-2026-10-27.md` § Before and after; `.claude/settings.json` hooks; `grimoires/loa/context/cycle-137-brief.md`

---

## Functional Requirements

### FR-1: Land the optimisation loop through the formal gates (Sprint 281)
**Priority:** Must Have
**Description:** The 20 loop commits are the sprint's implementation. The engineer's report `grimoires/loa/a2a/sprint-281/reviewer.md` walks every productive pass (target, lever, parity proof, tests, measurement, review verdict, commit) and every documented no-change (passes 12 and 15). `/review-sprint` and `/audit-sprint` run against it; findings land as red-first fix commits with `checksums.json` and REPO-MAP regenerated; the loop's parity harnesses (`~/.cache/loa/eso-loop/pass-*/`) are re-run on the final head for any file a fix touches.
**Acceptance Criteria:**
- [ ] `reviewer.md` carries an `## AC Verification` walkthrough: for each of the 20 productive passes (1–11, 13, 14, 16–22) the parity evidence (what was compared, on which inputs), the covering bats files and counts, the before/after measurement, the review verdict and the commit hash; passes 12 and 15 with their floors.
- [ ] Review ends `All good`; audit ends `APPROVED`; `verdict-derive.sh --gate review|audit` CONSISTENT; the `COMPLETED` marker is written; the ledger marks sprint 281 completed.
- [ ] Every fix commit from the gates is red-first where it changes behaviour, and byte-identical old-vs-new where it changes a loop file's implementation.
- [ ] `tests/unit/perf-spawn-budget.bats` 6/6 on the final Sprint 281 head; `check-loa.sh` passes; `repo-map-gen.sh --validate` passes.
- [ ] Each verdict file (`engineer-feedback.md`, `auditor-sprint-feedback.md`) names the head sha it reviewed; any later code commit on the branch re-runs that gate before the sprint is `COMPLETED`.
- [ ] Revert path: a finding that cannot be fixed within the sprint reverts that single pass commit — after checking that no later pass depends on it (shared helpers such as `compat-lib.sh`, cache conventions, mirror-harness assumptions) — with `checksums.json` + REPO-MAP regenerated in the revert commit and a `proposed` decision row.
- [ ] Evidence preserved in reviewable storage: the per-pass `REPORT.md` and `review/VERDICT.md` files, `final-table.tsv`, `baseline/*.json`, `final/*.json`, `rebaseline.sh` and the two TAP files are copied from `~/.cache/loa/eso-loop/` to `grimoires/loa/a2a/sprint-281/evidence/` (the record branch carries `a2a/`); a clean checkout plus that directory reproduces every number cited.
**Dependencies:** NOTES.md rotated first (Task 1.0 prerequisite) so Sprint 281 logging cannot trip the 200 KiB guard.

> Sources: `.skill-loop-progress.md` § LOOP 2 (passes 1–22); `~/.cache/loa/eso-loop/pass-*/REPORT.md` and `review/VERDICT.md`; `.claude/skills/reviewing-code/SKILL.md` § Phase 4; `.claude/skills/auditing-security/SKILL.md`

### FR-2: KF field-variant parsing and heading reset (bd-atk7q)
**Priority:** Should Have
**Description:** In both KF parsers (`loa-kf-surface.sh` `fieldval`, `grimoire-index.sh` `emit_kf` `fieldval`) a field line of the form `**Label (qualifier)**: value` (colon outside the bold) is parsed exactly like `**Label**: value` and `**Label (qualifier):** value`; a `## KF-<non-digits>:` heading resets the current entry (`cur = ""`) so its field lines are attributed to no entry. The two parsers stay textually aligned (the comment at `grimoire-index.sh:93-99` promises "both field variants").
**Acceptance Criteria:**
- [ ] bats, red first: a fixture with `**Symptom (short)**: s` yields symptom `s` in both the hook's table and the index TSV; `**Symptom (short):** s` still yields `s`; a `## KF-abc:` entry followed by `**Symptom**: x` leaves the previous entry's symptom unchanged and emits no row for `KF-abc`.
- [ ] On the live `known-failures.md` (0 variant entries, 63 numeric headings) the hook's stdout and `grimoire-index.sh --tsv/--json/write` outputs are byte-identical to the pre-change outputs.
- [ ] `perf-spawn-budget.bats` kf-surface and grimoire-index counts stay within budget.
- [ ] Drift guard: a bats test extracts the `fieldval` function body and the heading rule from both `loa-kf-surface.sh` and `grimoire-index.sh` and asserts the regex lines are identical, so the two parsers cannot diverge silently again.
- [ ] Diagnostic behaviour for a non-numeric `## KF-abc:` heading is a silent reset (fail-open, no stderr line) — the hook's stderr stays byte-identical on every input and `grimoire-index.sh --validate` remains the drift reporter.
- [ ] Both awk programs run under every awk available on the ship host (mawk, busybox awk, `gawk --posix`; absent interpreters skipped and named) with identical output on the fixture set.
**Dependencies:** FR-1 (lands after the gates).

> Sources: `.claude/hooks/loa-kf-surface.sh:96-125`, `.claude/scripts/grimoire-index.sh:93-128`; `~/.cache/loa/eso-loop/pass-6/review/VERDICT.md` (fixtures fx_e, fx_all); `grep -c '^## KF-[0-9]+:' grimoires/loa/known-failures.md` = 63, variant count 0

### FR-3: loa-status config reads (bd-gv5jf)
**Priority:** Should Have
**Description:** `_anthropic_ceiling_json` reads the alias and five model fields with one `yq` invocation emitting one value per line (the same `//` defaults; a line count other than six or a `yq` failure falls back to the current per-field reads); `agy_gate_warn_once` and `agy_opted_in` in `agy-gate-lib.sh` obtain the opt-in node through a parent-shell memo wrapper that stores its result in a shell variable (no command substitution, so the memo survives the call): the memo is valid only while its key `<config path>|<dev>:<inode>:<size>:<mtime>` matches a fresh `stat` of the file; any component change, a `stat` failure or a different config path invalidates it and the node is re-read. The memo is process-local; a caller inside `$(...)` cannot populate it (today's cost, documented). Every caller of the two functions — `loa-status.sh`, `run-preflight.sh`, `flatline-orchestrator.sh`, `adversarial-review.sh` — keeps its behaviour. Output bytes of `loa-status.sh` (human and `--json`) are unchanged.
**Acceptance Criteria:**
- [ ] Old-vs-new mirror parity (stdout with ages normalised, stderr, rc) on the live config, `--json`, `--help`, an unknown flag, a `PATH` without `yq`, and a config whose `aliases.opus` is absent, whose model lacks `effective_input_ceiling`, and whose `agy_opt_in` is true / false / the string "true" / absent.
- [ ] bats green: `loa-status-providers.bats`, `agy-gate-conformance.bats`, `flatline-tertiary-agy-opt-in.bats`, every `loa-status*.bats`.
- [ ] hyperfine (`-N -i`, 10 runs): `loa-status.sh` mean falls by ≥ 40 ms against the same-session old mirror; the `yq` count in a `bash -x` trace of `_anthropic_ceiling_json` is 1 and the trace shows the six-line fast path taken (no per-field read) on the live config.
- [ ] Six-line protocol fixtures (fast path or verbatim fallback, output identical either way): malformed YAML, a map where a scalar is expected, a value with an embedded newline, explicit `null`, explicit `false`, an empty final field, all optional fields absent, `yq` failing.
- [ ] Memo fixtures in `agy-gate-conformance.bats`: hit on an unchanged file; miss after a same-size in-place rewrite `true` → `false` with a distinct mtime (`touch -d`); miss after replacement by `mv` (new inode); miss after deletion (node absent, no error); miss after switching config paths within one process; a `$(...)` caller still gets the right answer.
- [ ] Caller coverage: old-vs-new mirror parity for `loa-status.sh` (human, `--json`) and `run-preflight.sh` (human, `--json`); bats green for `flatline-tertiary-agy-opt-in.bats`, `agy-gate-conformance.bats` and the adversarial-review agy cases.
**Dependencies:** FR-1.

> Sources: `.claude/scripts/loa-status.sh:848-870, 818-830, 895-900`, `.claude/scripts/lib/agy-gate-lib.sh:122-139, 203-215, 300-320`; `.skill-loop-progress.md` pass 14 and pass 20 hotspot tables

### FR-4: Profile-lib serves the karpathy threshold knob from the cache (bd-h5tcn)
**Priority:** Should Have
**Description:** `karpathy_principles.diff_lines_per_task` becomes a cached knob: `profiles.yaml` lists it under a new top-level `cached_keys:` and the cache builder in `profile-lib.sh:120-160` records it in `.run/effective-config.json` so `loa_knob` hits the cache (a per-process memo is useless here — the karpathy hook is a fresh process per tool call — and is not an option). The cache id stays content-derived (config + profiles + floor), so the first run after upgrade rebuilds it; a cache built from an older `profiles.yaml` without the key simply lacks the entry and `loa_knob` falls back to the live read. The value semantics (`.loa.config.yaml` override, profile default, hard default 100, non-integer fallback) and the stale-cache / missing-cache / missing-`yq` paths are unchanged.
**Acceptance Criteria:**
- [ ] bats red first in `profile-lib.bats` (or `karpathy-config-schema.bats`): with a warm cache the knob resolves without spawning `yq` (trace assertion), and the resolved value equals the live-path value for an override, a profile default and the hard default.
- [ ] The karpathy hook's state JSONL and summary are byte-identical old-vs-new across the pass-19 fixture matrix (session-id shapes × checkpoint shapes); `karpathy-*.bats` green; `profile-lib.bats` green.
- [ ] `perf-spawn-budget.bats` gains a karpathy target with a fixed fixture and cache, measured and budgeted in the same commit.
- [ ] Migration fixtures: an `.run/effective-config.json` built from the previous `profiles.yaml` (knob entry absent) → `loa_knob` returns the live-path value; a stale `id` → rebuild; `loa_profile` output byte-identical before and after; the cache JSON differs only by the new knob entry.
- [ ] Value classification mirrors the live path exactly: explicit `null`, empty string, `false`, `0` and non-scalar values resolve on the warm path to what `_loa_pl_live` returns today for the same config (fixtures for each).
**Dependencies:** FR-1.

> Sources: `.claude/scripts/lib/profile-lib.sh:28-75, 120-160, 212-260`, `.claude/data/profiles.yaml:28-48`, `.claude/hooks/quality/karpathy-surgical-diff-check.sh:36-50`; `~/.cache/loa/eso-loop/pass-19/REPORT.md` § Hotspot

### FR-5: grimoire-index decisions family cache and write-mode folds (bd-1mfm7)
**Priority:** Should Have
**Description:** The decisions family rows (the TSV `emit_decisions` produces) are cached under `.run/perf-cache/` keyed on the sha256 of `decisions.yaml` and the script version; a hit skips `yq`; a miss, a key mismatch, a missing, truncated, altered or unparsable cache, or `LOA_GRIMOIRE_INDEX_NO_CACHE=1` (an env knob documented in the header comment — no new CLI flag, so `--help` stays byte-identical; it disables both reading and writing) takes today's path and rewrites the cache atomically (exclusive `mktemp` in the cache directory, `umask 077`, symlink refusal on the directory and the file re-checked immediately before the rename, `mv -f -T` / `mv -f`, never fatal, never under `CI`/`GITHUB_ACTIONS`). The yq gate runs before the cache lookup, so a host without mikefarah `yq` emits today's skip NOTE and never consults a cache left behind. Trust model: the cached rows are the post-sanitisation output of the jq `s` filter; the reader accepts the file only when the header matches (`v1:<sha256 of decisions.yaml>:<yq major.minor>:<jq major.minor>:<row count>`), the row count matches and every row has the exact field count with no byte outside the sanitiser's output alphabet; anything else is a miss. A forged cache can be planted only by someone who can already write `decisions.yaml`. The write-mode `bad` check and final `.total` read come from one jq program that preserves the root object. `--validate`, `--tsv`, `--json` and write-mode outputs are byte-identical with no normalisation (the index embeds no timestamp or run id).
**Acceptance Criteria:**
- [ ] Old-vs-new parity on the live grimoire for `--tsv`, `--json`, `--validate` (stdout, stderr, rc) and write mode (stdout, stderr, `INDEX.md`, `grimoire-index.json`), cold and warm; a fixture with an edited `decisions.yaml` row invalidates the cache (the new row appears); a corrupt cache file, a symlinked cache file and a read-only `.run` all give today's output and exit codes.
- [ ] bats red first in `grimoire-index.bats`: cache hit skips `yq` (trace assertion), cache miss rebuilds, invalidation on content change, corrupt cache ignored.
- [ ] hyperfine warm run mean ≤ 650 ms (from 826) and cold run mean ≤ old mirror + 40 ms on the same host; `perf-spawn-budget.bats` grimoire-index budget updated in the same commit with the reason.
- [ ] Cache robustness fixtures: a cache created with `yq` present then read with `yq` absent (skip NOTE, no cache read); a syntactically valid cache with one row removed, one row altered, a wrong key, a wrong row count (each a miss); a symlinked `.run/perf-cache` directory (no write, no read); two concurrent writers (last rename wins, both outputs correct); `decisions.yaml` rewritten between key computation and row emission (the cache is not written when the content hash differs after parsing); `git check-ignore .run/perf-cache/x` succeeds so a downstream mount's `git status` stays clean.
**Dependencies:** FR-1.

> Sources: `.claude/scripts/grimoire-index.sh:216-250, 296-330`; `.claude/hooks/safety/zone-write-guard.sh` (`.run/perf-cache` precedent, 2026-07 pass 6); `.skill-loop-progress.md` passes 4, 5, 20

### FR-6: Two slow test files (bd-wctli)
**Priority:** Should Have
**Description:** `adversarial-review-companion.bats`: the 300 s holder processes and fixed sleeps in the test-owned `cheval` shim (the stub defined inside the bats file, lines 160–240) become injectable waits — an env knob (`CMP_STUB_HOLD_S`) read ONLY by that shim and the test bodies, never by production code, default the current values, overridden in the test's `setup` — and polls that spin to a 30 s ceiling stop at the first observable event; every test still demonstrates the same synchronisation states before asserting (holder ready, lock contended, released, timed out, cleaned up); no assertion changes. CMP-37 is NOT made deterministic (it asserts a real ordering with a real wait and is out of scope); its acceptance evidence is a serial whole-file run on an idle host. `block-destructive-bash.bats`: the cycle-125 corpus runs once in `setup_file` into `$BATS_FILE_TMPDIR` (status, stdout and stderr captured without failing `setup_file`; each corpus test asserts status 0 and JSON validity first); `-f` selection and `--jobs` still run `setup_file` once per file process; the latency test keeps its own measurement from that one run.
**Acceptance Criteria:**
- [ ] The pass/fail/skip set per test name is identical before and after for both files (serial runs, TAP lines compared); no assertion text, expected value or skip condition changes.
- [ ] `adversarial-review-companion.bats` serial wall time ≤ 300 s on the ship host (from > 900 s); the three corpus tests in `block-destructive-bash.bats` run the corpus once (trace or counter evidence).
- [ ] CI's `bats-tests.yml` Shell Tests job green on the PR head.
- [ ] Negative control (the red-first substitute for a test-only change): with the shortened waits active, each affected companion test fails when its asserted behaviour is deliberately broken (holder exits early; reaper disabled), then passes again with the break removed — recorded per test name.
- [ ] Baseline procedure: `bats -T` serial on the idle ship host, median of three runs, before and after; if the file stays above 300 s the measured floor and the remaining per-test costs are recorded and the AC moves to the floor by a `proposed` decision row written before `/review-sprint sprint-2`.
**Dependencies:** FR-1.

> Sources: `tests/unit/adversarial-review-companion.bats:182-232`, `tests/unit/block-destructive-bash.bats:812-845, 1546-1590`; `~/.cache/loa/eso-loop/pass-21/REPORT.md` § Profile

### FR-7: audit-envelope verify-chain batching (bd-09z1i)
**Priority:** Could Have
**Description:** The SDD decides between (a) one `audit-envelope.sh verify-chains <path>…` entry — one Python process that calls the unchanged `audit_verify_chain(path)` per argument — and (b) deferral. Snapshot semantics for (a): every path is verified exactly as a per-call invocation would verify it at that moment; `_check_trust_store` is untouched, so its in-process cache (keyed by store path and content) re-authenticates the store through the subprocess snapshot whenever the store's content changes between two paths, and a store that becomes INVALID or is deleted between paths fails every later path while earlier results stand. Equivalence is proven by a test that mutates the trust store between paths (replace with a store revoking the signing key; tamper; delete) and asserts the batch results equal fresh per-call results under the same schedule; if that test cannot be made to pass without touching `_check_trust_store`, batching is deferred. Results are machine-readable, one record per input path in argument order; a missing record or an abnormal process exit is fail-closed (every path without a record counts as FAILED). The decision row names the TOCTOU argument either way.
**Acceptance Criteria:**
- [ ] If (a): `tests/security/test_audit_trust_policy.py` and the audit-envelope bats (44 files) green; per-path results identical to the per-call results on the live chains and on tampered / broken-link / missing / empty fixtures and under the store-mutation schedule above; `loa-status.sh` mean falls by ≥ 100 ms; no chain is mutated — `verify-chains` runs against a read-only chain tree and the sha256 of every chain file is identical before and after; a missing path is reported FAILED (`loa-status.sh` keeps pre-filtering existing files, so its valid-by-absence count is unchanged); zero arguments is a usage error.
- [ ] If (b): a `proposed` decision row with the alternatives and the measured cost, and the bead re-labelled `deferred-cycle-137`.
**Dependencies:** FR-1; FR-3 (same file, ordered after it).

> Sources: `.claude/adapters/loa_cheval/audit_envelope.py:414-440, 500-540, 580-600, 710-730`, `.claude/scripts/loa-status.sh:420-435`, `tests/security/test_audit_trust_policy.py:147-165`; `~/.cache/loa/eso-loop/pass-12/REPORT.md`

### FR-8: Ship — one PR, Bridgebuilder, merge, record, archive, publish v2.0.0-rc.9
**Priority:** Must Have
**Description:** After both sprints are `COMPLETED`: CHANGELOG `[Unreleased]` content moves under `## [2.0.0-rc.9] — <date> — Performance follow-ups (release candidate)` with the version markers the post-merge pipeline expects (the rc.8 precedent); `.loa-version.json` `framework_version` and the README install pin bumped; PR from `feature/cycle-137-performance` (title classifies `cycle`); Bridgebuilder ≤ 2 rounds non-degraded; admin merge only when every required check — Template Protection, Validate Framework Files, Lint Markdown, Lint YAML, Shell Tests, Cross-Platform Compatibility — is `success` on the exact head and nothing is pending or red; `record-branch.sh --cycle 137 --prev origin/record/cycle-136-bridgebuilder-followups`; archive via `archive-cycle.sh` on a `chore/cycle-137-archive` branch (housekeeping merge); the post-merge pipeline's candidate published with `post-merge-orchestrator.sh --publish <candidate> --approve-sha256 <digest>` from a non-shallow clone; tag `v2.0.0-rc.9` reachable from `main`; GitHub release created.
**Acceptance Criteria:**
- [ ] PR body lists both sprints, the beads, the DEC rows, the gates' verdicts and the Bridgebuilder outcome per head sha.
- [ ] Every check run on the final head completed and the six required checks `success`; CI mirror (full unit suite) from the final head shows only the KF-034 reds.
- [ ] Merge commit on `origin/main`; record stage 1 pushed; archive merge classifies `housekeeping`; `v2.0.0-rc.9` tag object = the merge commit's descendant per the pipeline, release page present, `[Unreleased]` empty.
- [ ] `.run/*.cycle-137.jacked-out.json` parked; ledger cycle archived; follow-up beads closed or deferred.
- [ ] Publish summary stage before `--publish`: `grimoires/loa/a2a/sprint-282/publish-summary.md` records the candidate path, its digest as printed by the pipeline AND as recomputed by the lead from the fetched candidate bytes (they must match), the candidate's `merge_sha` (must equal the merge commit on `origin/main`), the tag, the CHANGELOG heading, and every line of § Release predicate ticked true; publish runs only after that file exists.
- [ ] Post-publish install smoke test: from a scratch directory `git clone --depth 1 --branch v2.0.0-rc.9`, run `bash .claude/scripts/check-loa.sh` and the kf-surface SessionStart hook; both succeed.
- [ ] Every performance number in the PR body and the e2e files carries the host identifier, the hyperfine command line and the run count.
- [ ] The ship scripts are copied to `grimoires/loa/a2a/sprint-282/ship/` with their sha256 listed in `e2e.md` (they otherwise live outside version control).
- [ ] Bridgebuilder degraded or exhausted after two rounds: proceed with a `proposed` decision row recording the degraded state and the lead's reading of the diff; never a third round.
- [ ] Rollback is written down before publishing: revert the merge commit on `main` (regenerating manifests), mark the GitHub release as a withdrawn pre-release and leave the tag (never deleted), reopen the beads, and record the decision row; a published candidate is never silently replaced.
**Dependencies:** FR-1 … FR-7 landed or deferred per § Release predicate.

> Sources: `~/.cache/loa/cycle-135/ship/*.sh` (the recipe that worked); `~/.claude/projects/-home-merlin-Documents-thj-code-loa/memory/reference_release_process.md`; cycle-133 rc.8 publish notes; DEC-0960, DEC-1057, DEC-1060

---

## Non-Functional Requirements

### Performance
Every change either removes work with byte-identical output (FR-3/4/5) or shortens tests without changing assertions (FR-6). Benchmark protocol for every number in this cycle: `hyperfine -N -i --warmup 3 --runs 10` (mean ± σ reported), old and new mirrors measured in the same session on the idle ship host, caches in the stated state (cold = `.run/perf-cache` entry absent; warm = one prior run), the baseline revision named, the host identifier and command line recorded next to the number. Mirrors live in REAL directories (the symlinked-mirror `..` escape of pass 18 is a known trap). No change may add spawns to a hot path: `perf-spawn-budget.bats` guards six paths and gains a karpathy target in FR-4.

### Security
Hooks keep their documented fail-open / fail-closed semantics; untrusted bodies (KF, decisions, handoffs, notes) stay sanitised at surfacing; the audit chain is never mutated outside `audit_emit`; the trust-store TOCTOU defence is kept exactly or the bead is deferred; the `.run/perf-cache` writes use tmp+mv, umask 077 and symlink refusal; no new eval or source of data.

### Reliability
Red-first tests for every behaviour change; the covering bats suites and the full unit suite green on the landed head; rollback is a single-commit revert per bead; the loop commits stay as landed (no squash) so each pass reverts alone.

### Compliance
System Zone writes under the bounded marker with `checksums.json` and REPO-MAP regenerated in the same commit (DEC-0824); decision rows for every judgment call, `proposed` until the operator confirms; the CHANGELOG names every behaviour-visible change (the rc heading carries the loop block).

### Authorization basis and refusal list
Operator instruction of 2026-10-28 (verbatim in the brief: "do formal gates and then release when ready"). Unattended merge and unattended publish are both authorised by it; the safeguards are mechanical, not a pause: the merge requires every check run complete and the six required checks `success` on the exact head plus a non-degraded Bridgebuilder verdict with no open blocking finding; the publish requires the publish-summary stage (FR-8) with the digest independently recomputed by the lead from the fetched candidate bytes and equal to the pipeline's printed digest, and the candidate's `merge_sha` equal to the merge commit. Refused regardless of instruction: writing `main` outside the merge, force-pushing, deleting tags or branches, merging with a red or pending required check, publishing a candidate whose digest was not re-canonicalised and approved, touching credentials or the live push configuration in tests, changing `br` contract calls, quarantining a test.

> Sources: `grimoires/loa/context/cycle-137-brief.md` § Constraints; DEC-0824; `.claude/loa/CLAUDE.loa.md` § Agent-Network Primitives; `~/.cache/loa/eso-loop/REVIEW.md` § 6 (security checklist)

---

## User Experience

### Key User Flows
Session start → identical KF table, faster. Edit → identical gate decisions, fewer spawns. `/loa` → identical status. CI → same results sooner. Release consumer → `--tag v2.0.0-rc.9`.

### Interaction Patterns
No new messages on the hot paths; the only new operator-visible text is the CHANGELOG release section and the PR body.

### Accessibility Requirements
Plain text; no colour-only signals (`agent-ergonomics-color-guard.bats` stays green).

> Sources: `.claude/settings.json` (hook wiring); `tests/unit/agent-ergonomics-color-guard.bats`

---

## Technical Considerations

### Architecture (for the SDD)
C-1 Sprint 281 gate pass (reviewer.md, review, audit, fix commits); C-2 KF parser alignment (two awk programs, one regex change each, `cur` reset); C-3 loa-status single-yq ceiling read + agy node memo in the shared lib; C-4 profile-lib knob caching; C-5 grimoire-index decisions cache + jq folds; C-6 test-time injectable waits and corpus-once fixture; C-7 verify-chain batching design (implement or defer); C-8 ship and rc.9 publish.

### System Zone authorization (explicit, cycle-level)
This PRD authorises writes under `.claude/hooks/loa-kf-surface.sh`, `.claude/scripts/grimoire-index.sh`, `.claude/scripts/loa-status.sh`, `.claude/scripts/lib/agy-gate-lib.sh`, `.claude/scripts/lib/profile-lib.sh`, `.claude/data/profiles.yaml`, `.claude/scripts/audit-envelope.sh` and `.claude/adapters/loa_cheval/audit_envelope.py` (only under FR-7(a)), `.claude/checksums.json`, `grimoires/loa/REPO-MAP.md` + `.checksum`, `tests/unit/**`, `CHANGELOG.md`, `README.md`, `.loa-version.json` — each with the manifests regenerated in the same commit. Sprint 281 gate fixes are authorised only on the 18 System Zone files the loop changed (`git diff --stat main..c0d41f5e3 -- .claude/`): `adapters/loa_cheval/providers/__init__.py`, `hooks/compliance/implement-gate.sh`, `hooks/loa-kf-surface.sh`, `hooks/quality/karpathy-surgical-diff-check.sh`, `hooks/safety/notes-size-guard.sh`, `hooks/session-start/loa-run-state-surface.sh`, `scripts/archetype-resolver.sh`, `scripts/cache-manager.sh`, `scripts/compat-lib.sh`, `scripts/grimoire-index.sh`, `scripts/lib/dx-utils.sh`, `scripts/lib/push-notify-lib.sh`, `scripts/lib/repo_map.py`, `scripts/loa-status.sh`, `scripts/red-team-retention.sh`, `scripts/repo-map-gen.sh`, `scripts/run-checkpoint.sh`, `scripts/upgrade-health-check.sh` (plus `checksums.json`), and on the loop's non-System-Zone files (`tests/unit/perf-spawn-budget.bats`, three bats helper files, `grimoires/loa/reports/perf/eso-loop-2026-10-27.md`, `.skill-loop-progress.md`, `CHANGELOG.md`).

### Integrations
GitHub (PR, checks, merge, release) through `gh`; the post-merge pipeline (`post-merge.yml`, `post-merge-orchestrator.sh`); Bridgebuilder with `BRIDGEBUILDER_MODEL=codex-headless` as in cycle-135.

### Dependencies
None new.

### Technical Constraints
`SKILL.md` budgets untouched (no skill prose changes planned); NOTES.md at 190 KiB must be rotated before the sprint logs push it past the 200 KiB guard; mikefarah `yq` v4 remains optional on the decisions family (the skip NOTE stays); busybox and BWK awk compatibility holds for the KF regex change (no gawk-only syntax).

> Sources: DEC-0824; `.claude/hooks/safety/notes-size-guard.sh`; `.claude/scripts/grimoire-index.sh:216-221`; `~/.cache/loa/eso-loop/pass-4/review/VERDICT.md` (busybox awk evidence)

---

## Scope & Prioritization

### In Scope (MVP — this cycle)
FR-1, FR-8 (Must); FR-2 … FR-6 (Should); FR-7 (Could — implement or defer by decision row).

### In Scope (Future Iterations)
`yaml.CSafeLoader` for cheval config loading (error-text risk); a single-pass `ast.NodeVisitor` in `repo_map.py` (def-order risk); the `grep -q push_command` pre-check in `push-notify-lib.sh` (needs an alias fixture); the remaining `loa-status` `breaker_cli` Python start (58 ms).

### Explicitly Out of Scope
New optimisation targets beyond the six beads; `br`/`br doctor` contract calls; the Flatline, Bridgebuilder and adapter wire contracts; quarantining any test; squashing the loop commits.

### Priority order under time pressure
FR-1 → FR-8 → FR-2 → FR-3 → FR-5 → FR-4 → FR-6 → FR-7.

### Release predicate (authoritative — every other statement about releasing defers to this one)
`v2.0.0-rc.9` is published when and only when all of R-1 … R-8 hold; nothing else blocks or permits it.

- R-1 Gates: Sprint 281 and Sprint 282 each carry review `All good` and audit `APPROVED` produced on their final head sha (`reviewed_head` in the verdict files equals the sha the PR merges), `verdict-derive.sh` CONSISTENT, `COMPLETED` written, ledger status `completed`.
- R-2 Scope and deferral: FR-1 and FR-8 are Must and cannot be deferred. Each of FR-2 … FR-7 is either LANDED (fix commit + red-first test or the FR-6 substitute, bead closed with the commit and test named) or DEFERRED: a `proposed` decision row written BEFORE `/review-sprint sprint-2` runs re-scopes the sprint (the AC line is marked deferred by that row's id), the bead is relabelled `deferred-cycle-137` and stays open, and G-2 counts it as deferred, not failed. A deferral never blocks the release; an FR that is neither landed nor deferred does.
- R-3 Merge: the PR is merged by the ship recipe only when every check run on the exact head has completed and the six required checks — Template Protection, Validate Framework Files, Lint Markdown, Lint YAML, Shell Tests, Cross-Platform Compatibility — are `success`, Bridgebuilder is non-degraded with no open blocking finding, and the merge commit's tree equals the final reviewed head's tree (`git diff --quiet <head> <merge>` — the ship-only files `CHANGELOG.md`, `README.md`, `.loa-version.json` are part of the reviewed head because they are committed before the final gate re-run).
- R-4 Suite: on the ship host the full `tests/unit` TAP of the final head fails ONLY tests in the allowed-failure list, and `main` under the same host condition (same `git config tag.gpgsign`) fails exactly the same ones. Allowed-failure list (KF-034, host `tag.gpgsign=true`): `semver evidence: unknown squash subject refuses silent patch`, `semver evidence: classification records its source and matching commit`, `semver evidence: breaking body retains the classifying commit identity`. No other test may fail; CMP-37 is not on the list — a CMP-37 failure in a full run is load-diagnostic only if the whole companion file then passes serially on an idle host and the full run is recorded as having overlapped another bats job.
- R-5 CI on main: the push-to-main `BATS Tests` and `CI` workflow runs on the merge commit are `success` (CI runners do not carry KF-034).
- R-6 Candidate binding: the pipeline's prepared candidate names `merge_sha` equal to the merge commit on `origin/main`; its digest recomputed by the lead from the fetched bytes equals the printed digest; `--approve-sha256` receives that digest.
- R-7 Records: every `proposed` decision row of the cycle is written (dec-batch), the record branch stage 1 is pushed, `publish-summary.md` exists with R-1 … R-6 ticked.
- R-8 Post-publish: tag `v2.0.0-rc.9` is an ancestor-descendant of the merge commit per the pipeline (`git merge-base --is-ancestor`), the release page exists, the install smoke test passes; failure here triggers the FR-8 rollback, not a silent retry.

> Sources: `grimoires/loa/context/cycle-137-brief.md` § Scope, § Non-goals; `grimoires/loa/reports/perf/eso-loop-2026-10-27.md` § Follow-ups

---

## Success Criteria

### Launch Criteria
G-1 … G-6 as measured in `a2a/sprint-281/e2e.md` and `a2a/sprint-282/e2e.md`: the two gate verdicts, the beads' commits and tests, the re-baseline table, the full-suite TAP, the PR checks, the record/archive shas, the tag and release URLs.

### Post-Launch Success (30 days)
Owner: the primary maintainer (deep-name). Evidence: `grimoires/loa/known-failures.md` (no KF entry attributes a regression to a loop or Sprint 282 commit), the `BATS Tests` history on `main` (`perf-spawn-budget.bats` never trips), downstream mount reports (no hook behaviour change). Response: a spawn-budget trip or an attributed regression opens a `/bug` micro-sprint against the single commit (each pass and each bead is one revertable commit).

### Long-term Success (90 days)
Owner: the primary maintainer. Evidence: each hook change on `main` updates `perf-spawn-budget.bats` deliberately in the same commit (the test's own history), keeping the per-tool-call chains at or below the cycle-137 numbers. Response: a budget raised without a reason line in the commit is a review finding.

> Sources: § Goals & Success Metrics

---

## Risks & Mitigation

| Risk | Mitigation |
|---|---|
| The formal review finds a parity gap the per-pass reviews missed | fix red-first; re-run the pass's harness; a non-fixable finding reverts that single commit (each pass is one commit) |
| A cache (FR-4, FR-5) serves stale values | content-keyed (sha256 + version), atomic write, corrupt/missing/symlink → today's path; invalidation fixtures in bats |
| Injectable test waits change what the companion tests prove | defaults equal today's values; only `setup` overrides them; pass/fail set compared per test name before and after |
| FR-7 weakens the fail-closed trust-store check | the subprocess snapshot stays; `test_audit_trust_policy.py` pins it; otherwise defer by decision row |
| The rc.9 publish path regresses (KF-034, KF-063 history) | follow the rc.8 recipe: non-shallow clone, candidate digest re-canonicalised, `--approve-sha256`; verify the tag is reachable from `main` |
| NOTES.md crosses the size guard mid-cycle | rotate before Sprint 281 logging starts |
| Load-sensitive tests (CMP-37) fail in a loaded CI run | FR-6 shortens the file; acceptance evidence is a serial whole-file run on an idle host (R-4); CMP-37 itself is out of scope for determinism |
| Rollback of the shipped collection (loop + six beads + manifests + caches + release assets) | each pass and each bead is one commit; the merge commit reverts as one unit with manifests regenerated; `.run/perf-cache` entries are keyed and simply become misses; the published release is withdrawn per FR-8 (tag kept, release marked withdrawn pre-release) |
| A verdict is produced on one head and the PR merges another | `reviewed_head` in every verdict; R-1 and R-3 compare shas and trees; a later code commit re-runs the gate |

> Sources: § Functional Requirements; KF-034, KF-063 in `grimoires/loa/known-failures.md`; `~/.cache/loa/eso-loop/bats-final/unit.tap`

---

## Timeline & Milestones

Two sprints: Sprint 1 (global 281) rotate NOTES → reviewer.md → review → audit → COMPLETED (verdicts bound to the head sha); Sprint 2 (global 282) implement the six beads → ship files (CHANGELOG heading, README pin, `.loa-version.json`) → review → audit → COMPLETED on the final head; then PR → Bridgebuilder (fixes re-run the audit as a verify-only pass) → merge (R-3) → record → publish summary (R-6, R-7) → publish rc.9 → smoke test (R-8) → archive. Unattended, 2026-10-28.

> Sources: `grimoires/loa/context/cycle-137-brief.md`

---

## Appendix A — Goals

G-1 gates on the loop; G-2 six beads; G-3 gains hold + guard green; G-4 suite green modulo KF-034; G-5 PR/BB/merge/record/archive; G-6 rc.9 published.

> Sources: § Goals & Success Metrics

---

## Appendix B — Grounding reads

`.skill-loop-progress.md` (LOOP 2, 22 entries); `grimoires/loa/reports/perf/eso-loop-2026-10-27.md`; `~/.cache/loa/eso-loop/{final-table.tsv, baseline/*.json, final/*.json, pass-*/REPORT.md, pass-*/review/VERDICT.md, bats-final/unit.tap}`; `.claude/hooks/loa-kf-surface.sh`; `.claude/scripts/grimoire-index.sh`; `.claude/scripts/loa-status.sh:848-870`; `.claude/scripts/lib/agy-gate-lib.sh`; `.claude/scripts/lib/profile-lib.sh`; `.claude/data/profiles.yaml`; `.claude/adapters/loa_cheval/audit_envelope.py`; `tests/unit/adversarial-review-companion.bats`; `tests/unit/block-destructive-bash.bats`; `grimoires/loa/ledger.json` (cycle-137 active, next sprint 281); `grimoires/loa/archive/cycle-136-bridgebuilder-followups/prd.md` (format precedent); `~/.cache/loa/cycle-135/ship/*.sh`.

> Sources: the files named in this appendix

---

## Appendix C — Flatline PRD review dispositions

Review: `flatline-orchestrator.sh --doc grimoires/loa/prd.md --phase prd --budget 300` on PRD 1.0 (commit 7625d1554): 6 blockers, 47 medium items (`~/.cache/loa/cycle-137/logs/flatline-prd.out`). Every blocker is adopted; medium items are adopted unless listed under "declined" with the reason.

| # | Finding (location) | Disposition in 1.1 |
|---|---|---|
| B1 | FR-7 snapshot consistency and revocation semantics undefined | FR-7 rewritten: per-path semantics equal per-call semantics via the untouched `_check_trust_store` cache; store-mutation schedule test (replace with revocation, tamper, delete) is the equivalence proof; fail-closed on missing records; defer if the test cannot pass |
| B2 | No single release predicate; deferral effects undefined | § Scope → Release predicate R-1 … R-8 is the one authority; R-2 defines LANDED / DEFERRED, the pre-review decision row, the bead label and G-2's counting |
| B3 | Evidence not bound to SHAs; no re-gate rule | § Constraints (evidence binds to SHAs; re-gate rule; docs-only exception); FR-1 AC; R-1, R-3, R-6 compare shas and trees |
| B4 | agy memo reuse unbounded | FR-3: parent-shell wrapper with a shell-variable result, key `<cfg>|dev:ino:size:mtime`, invalidation on any change / `stat` failure / path switch; fixtures true→false same-size rewrite, `mv` replacement, deletion, path switch, `$(...)` caller |
| B5 | No "ready to publish" predicate; no pre-publish stage | R-5 (CI on the merge commit), R-6 (candidate binding, lead-recomputed digest), R-7 (publish-summary.md); NFR Authorization records unattended merge/publish as authorised with these mechanical safeguards |
| B6 | Allowed failures and equivalent conditions unspecified | R-4 names the three KF-034 tests, requires the same failures on `main` under the same host condition, and states when a CMP-37 isolation run is diagnostic |
| M1, M27 | completion policy for deferred FRs | R-2 |
| M2, M31, M42 | FR-4 approach, migration, second option | FR-4 description (cached_keys only; older cache → live fallback; migration fixtures) |
| M3, M46, M47 | companion synchronisation states, knob scope, negative control | FR-6 description and AC |
| M4 | corpus-once under parallel / `-f` selection, status capture | FR-6 description |
| M5 | verify-chains freshness, ordering, exit precedence, missing paths | FR-7 description and AC |
| M6, M7 | release digest authority; archive head / candidate acceptance | NFR Authorization; R-6, R-8 |
| M8 | rollback of the shipped collection | FR-8 AC; § Risks row |
| M9 | owners for 30/90-day criteria | § Success Criteria |
| M10 | verdicts name the reviewed commit | § Constraints; FR-1 AC; R-1 |
| M11 | reconcile green suite with KF-034 / CMP-37 | R-4; G-4 |
| M12, M30 | durable evidence storage | FR-1 AC (evidence copied to `a2a/sprint-281/evidence/`) |
| M13, M38 | benchmark protocol; host/command/run count | NFR Performance; FR-8 AC |
| M14, M15, M16, M43, M44, M45 | decisions cache: yq absence, payload integrity, concurrency, trust model, cold bound | FR-5 description and AC |
| M17, M29 | agy memo freshness; all callers covered | FR-3 description and AC |
| M18 | six-line protocol fixtures | FR-3 AC |
| M19 | 19 vs 20 productive passes | FR-1 AC corrected to 20 (passes 1–11, 13, 14, 16–22) |
| M20 | red-first for test-only bd-wctli | G-2 and § Constraints: TAP-set parity plus the negative control substitute |
| M21 | CMP-37 explicit | FR-6: not made deterministic; R-4 isolation rule |
| M22 | revert path as an AC | FR-1 AC (with the later-pass dependency check) |
| M23 | G-3 direction-specific | G-3: no touched command above 110 % of its final-table mean |
| M24 | enumerate System Zone files | § System Zone authorization lists the 18 files + `checksums.json` and bounds Sprint 281 fixes to them |
| M25 | Bridgebuilder degraded fallback | FR-8 AC |
| M26 | post-publish install smoke test | FR-8 AC; R-8 |
| M28 | NOTES rotation explicit | FR-1 dependency (Task 1.0 prerequisite) |
| M32 | parser drift guard | FR-2 AC |
| M33 | "impossible by construction" | FR-7 AC: read-only tree + sha256 before/after |
| M34 | `--no-cache` CLI surface | FR-5: env knob `LOA_GRIMOIRE_INDEX_NO_CACHE=1`, `--help` unchanged |
| M35 | write-mode normalisation | FR-5: none needed (no timestamp in the index) |
| M36 | `.run/perf-cache` leaves `git status` clean | FR-5 AC (`git check-ignore`) |
| M37 | "no timing-based tests" wording | § Constraints: no NEW timing-based tests; grandfathered test named |
| M39 | `## KF-abc:` diagnostic | FR-2 AC: silent reset |
| M40 | halt / park criteria | § Constraints: ≤ 3 fix→re-review iterations, ≤ 2 Bridgebuilder rounds, then HALT |
| M41 | loa-status threshold | KPI aligned to the FR-3 AC (≥ 40 ms vs the same-session old mirror) |
| Declined | — | none: every item is adopted (the ones above) or absorbed by R-1 … R-8 |

> Sources: `~/.cache/loa/cycle-137/logs/flatline-prd.out`; this document's sections as amended
