# Product Requirements Document: Performance follow-ups (cycle-137)

**Version:** 1.0
**Date:** 2026-10-28
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

> Sources: this document's sections

---

## Executive Summary

On 2026-10-27/28 a 22-pass `extreme-software-optimization` skill loop produced 20 commits (395795939 … c0d41f5e3) that cut the framework's own overhead: the repo-map generator 4658 → 1219 ms, grimoire-index 1819 → 826 ms, the known-failures SessionStart hook 488 → 15 ms, the Write/Edit PreToolUse chain about 78 → 62 ms, the Stop guard 24 → 14 ms, and a deterministic spawn-budget guard. Every pass was profiled first, proven byte-identical old-vs-new on golden and adversarial fixtures, reviewed by a fresh Opus 5.5 agent and verified by the orchestrator — but the loop ran outside `/implement`, so the formal `/review-sprint` and `/audit-sprint` gates never ran, the branch is unpublished, and the loop left six follow-up beads.

This cycle lands the loop through the formal gates as Sprint 1 (global 281, review and audit fixes only), closes the six beads as Sprint 2 (global 282: a latent KF field-parsing defect, four further spawn reductions with byte-identical output, two slow test files, and a security-sensitive batching design that may end as a documented deferral), and ships one PR through a Bridgebuilder round, the record branch, the archive and the `v2.0.0-rc.9` release candidate.

> Sources: `grimoires/loa/context/cycle-137-brief.md`; `.skill-loop-progress.md` § LOOP 2; `grimoires/loa/reports/perf/eso-loop-2026-10-27.md`; beads bd-atk7q, bd-gv5jf, bd-h5tcn, bd-1mfm7, bd-wctli, bd-09z1i (`br show`)

---

## Problem Statement

### The Problem

1. **Unreviewed by the framework's own gates.** The 20 loop commits touch 15 System Zone files (hooks on the per-tool-call path, `compat-lib.sh` sourced by about 78 scripts, the cheval provider registry, the repo-map engine). CLAUDE.md requires every code change to pass `/review-sprint` and `/audit-sprint`; the loop's per-pass Opus reviews are evidence, not the gate.
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
- G-2: Sprint 282 — beads bd-atk7q, bd-gv5jf, bd-h5tcn, bd-1mfm7, bd-wctli closed with a commit and a red-first test each; bd-09z1i closed by implementation or by a decision row that names the security reason for deferral.
- G-3: the loop's gains hold on the shipped head: the re-baseline of the sixteen loop commands stays within 10 % of `final-table.tsv`, and `tests/unit/perf-spawn-budget.bats` is green on every landed commit.
- G-4: the full `tests/unit` suite on the final head shows no failure beyond the pre-existing `semver-evidence` reds (KF-034); CMP-37 passes in isolation.
- G-5: one PR from `feature/cycle-137-performance`, Bridgebuilder ≤ 2 rounds non-degraded, merged when every required check is green on the exact head, record branch and archive as every cycle.
- G-6: `v2.0.0-rc.9` published from the post-merge candidate with the CHANGELOG heading and version markers in place.

### Key Performance Indicators (KPIs)

- Measured, hyperfine on the ship host: `loa-status.sh` ≤ 760 ms (from 818) after FR-3; karpathy hook trace shows no `yq` on the warm-cache path after FR-4; `grimoire-index.sh` warm run ≤ 650 ms (from 826) after FR-5; `adversarial-review-companion.bats` ≤ 300 s and the three `block-destructive-bash.bats` corpus tests sharing one corpus run after FR-6.
- Parity: every FR-3/4/5 change byte-identical old-vs-new on the live inputs and the named fixtures (stdout, stderr, rc, written files).
- Cycle meter spend ≤ USD 30 (Flatline reviews, dissent runs, Bridgebuilder rounds on subscription routes; real charges ≈ 0).

### Constraints

- System Zone writes carry `checksums.json` and `REPO-MAP.md` regenerated in the same commit (DEC-0824); red-first tests; no timing-based tests (the spawn-budget guard is the deterministic form); `br` contract calls untouched.
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
- [ ] `reviewer.md` carries an `## AC Verification` walkthrough: for each of the 19 productive passes the parity evidence (what was compared, on which inputs), the covering bats files and counts, the before/after measurement, the review verdict and the commit hash; passes 12 and 15 with their floors.
- [ ] Review ends `All good`; audit ends `APPROVED`; `verdict-derive.sh --gate review|audit` CONSISTENT; the `COMPLETED` marker is written; the ledger marks sprint 281 completed.
- [ ] Every fix commit from the gates is red-first where it changes behaviour, and byte-identical old-vs-new where it changes a loop file's implementation.
- [ ] `tests/unit/perf-spawn-budget.bats` 6/6 on the final Sprint 281 head; `check-loa.sh` passes; `repo-map-gen.sh --validate` passes.
**Dependencies:** none.

> Sources: `.skill-loop-progress.md` § LOOP 2 (passes 1–22); `~/.cache/loa/eso-loop/pass-*/REPORT.md` and `review/VERDICT.md`; `.claude/skills/reviewing-code/SKILL.md` § Phase 4; `.claude/skills/auditing-security/SKILL.md`

### FR-2: KF field-variant parsing and heading reset (bd-atk7q)
**Priority:** Should Have
**Description:** In both KF parsers (`loa-kf-surface.sh` `fieldval`, `grimoire-index.sh` `emit_kf` `fieldval`) a field line of the form `**Label (qualifier)**: value` (colon outside the bold) is parsed exactly like `**Label**: value` and `**Label (qualifier):** value`; a `## KF-<non-digits>:` heading resets the current entry (`cur = ""`) so its field lines are attributed to no entry. The two parsers stay textually aligned (the comment at `grimoire-index.sh:93-99` promises "both field variants").
**Acceptance Criteria:**
- [ ] bats, red first: a fixture with `**Symptom (short)**: s` yields symptom `s` in both the hook's table and the index TSV; `**Symptom (short):** s` still yields `s`; a `## KF-abc:` entry followed by `**Symptom**: x` leaves the previous entry's symptom unchanged and emits no row for `KF-abc`.
- [ ] On the live `known-failures.md` (0 variant entries, 63 numeric headings) the hook's stdout and `grimoire-index.sh --tsv/--json/write` outputs are byte-identical to the pre-change outputs.
- [ ] `perf-spawn-budget.bats` kf-surface and grimoire-index counts stay within budget.
**Dependencies:** FR-1 (lands after the gates).

> Sources: `.claude/hooks/loa-kf-surface.sh:96-125`, `.claude/scripts/grimoire-index.sh:93-128`; `~/.cache/loa/eso-loop/pass-6/review/VERDICT.md` (fixtures fx_e, fx_all); `grep -c '^## KF-[0-9]+:' grimoires/loa/known-failures.md` = 63, variant count 0

### FR-3: loa-status config reads (bd-gv5jf)
**Priority:** Should Have
**Description:** `_anthropic_ceiling_json` reads the alias and five model fields with one `yq` invocation emitting one value per line (the same `//` defaults; a line count other than six or a `yq` failure falls back to the current per-field reads); `agy_gate_warn_once` in `agy-gate-lib.sh` reuses the opt-in node already read by `agy_opted_in` in the same process when available (a process-local memo of the node text keyed by config path), so the node is read once per process. Output bytes of `loa-status.sh` (human and `--json`) are unchanged.
**Acceptance Criteria:**
- [ ] Old-vs-new mirror parity (stdout with ages normalised, stderr, rc) on the live config, `--json`, `--help`, an unknown flag, a `PATH` without `yq`, and a config whose `aliases.opus` is absent, whose model lacks `effective_input_ceiling`, and whose `agy_opt_in` is true / false / the string "true" / absent.
- [ ] bats green: `loa-status-providers.bats`, `agy-gate-conformance.bats`, `flatline-tertiary-agy-opt-in.bats`, every `loa-status*.bats`.
- [ ] hyperfine (`-N -i`, 10 runs): `loa-status.sh` mean falls by ≥ 40 ms against the same-session old mirror; the `yq` count in a `bash -x` trace of `_anthropic_ceiling_json` is 1.
**Dependencies:** FR-1.

> Sources: `.claude/scripts/loa-status.sh:848-870, 818-830, 895-900`, `.claude/scripts/lib/agy-gate-lib.sh:122-139, 203-215, 300-320`; `.skill-loop-progress.md` pass 14 and pass 20 hotspot tables

### FR-4: Profile-lib serves the karpathy threshold knob from the cache (bd-h5tcn)
**Priority:** Should Have
**Description:** `karpathy_principles.diff_lines_per_task` becomes a cached knob: either it is added to the profile knob set the cache is built from (`profiles.yaml` and the cache builder in `profile-lib.sh:120-160`) so `loa_knob` hits `.run/effective-config.json`, or `loa_knob` learns a documented per-process memo for live-path misses. The value semantics (`.loa.config.yaml` override, profile default, hard default 100, non-integer fallback) and the stale-cache / missing-cache / missing-`yq` paths are unchanged.
**Acceptance Criteria:**
- [ ] bats red first in `profile-lib.bats` (or `karpathy-config-schema.bats`): with a warm cache the knob resolves without spawning `yq` (trace assertion), and the resolved value equals the live-path value for an override, a profile default and the hard default.
- [ ] The karpathy hook's state JSONL and summary are byte-identical old-vs-new across the pass-19 fixture matrix (session-id shapes × checkpoint shapes); `karpathy-*.bats` green; `profile-lib.bats` green.
- [ ] `perf-spawn-budget.bats` gains a karpathy target with a fixed fixture and cache, measured and budgeted in the same commit.
**Dependencies:** FR-1.

> Sources: `.claude/scripts/lib/profile-lib.sh:28-75, 120-160, 212-260`, `.claude/data/profiles.yaml:28-48`, `.claude/hooks/quality/karpathy-surgical-diff-check.sh:36-50`; `~/.cache/loa/eso-loop/pass-19/REPORT.md` § Hotspot

### FR-5: grimoire-index decisions family cache and write-mode folds (bd-1mfm7)
**Priority:** Should Have
**Description:** The decisions family rows (the TSV `emit_decisions` produces) are cached under `.run/perf-cache/` keyed on the sha256 of `decisions.yaml` and the script version; a hit skips `yq`; a miss, a key mismatch, a missing or unparsable cache, or `--no-cache` takes today's path and rewrites the cache atomically (tmp + mv, umask 077, symlink refusal — the pass-6/7 `.run/perf-cache` conventions of the 2026-07 loop). The write-mode `bad` check and final `.total` read fold into `to_json`'s single jq output. `--validate`, `--tsv` and `--json` output bytes are unchanged.
**Acceptance Criteria:**
- [ ] Old-vs-new parity on the live grimoire for `--tsv`, `--json`, `--validate` (stdout, stderr, rc) and write mode (stdout, stderr, `INDEX.md`, `grimoire-index.json`), cold and warm; a fixture with an edited `decisions.yaml` row invalidates the cache (the new row appears); a corrupt cache file, a symlinked cache file and a read-only `.run` all give today's output and exit codes.
- [ ] bats red first in `grimoire-index.bats`: cache hit skips `yq` (trace assertion), cache miss rebuilds, invalidation on content change, corrupt cache ignored.
- [ ] hyperfine warm run mean ≤ 650 ms (from 826) on the same host; `perf-spawn-budget.bats` grimoire-index budget updated in the same commit with the reason.
**Dependencies:** FR-1.

> Sources: `.claude/scripts/grimoire-index.sh:216-250, 296-330`; `.claude/hooks/safety/zone-write-guard.sh` (`.run/perf-cache` precedent, 2026-07 pass 6); `.skill-loop-progress.md` passes 4, 5, 20

### FR-6: Two slow test files (bd-wctli)
**Priority:** Should Have
**Description:** `adversarial-review-companion.bats`: the 300 s holder processes and fixed sleeps become injectable waits (an env knob read by the fixtures, default the current values so the shipped behaviour is unchanged, overridden to seconds in the test's `setup`), and polls that spin to a 30 s ceiling stop at the first observable event; no assertion changes. `block-destructive-bash.bats`: the cycle-125 corpus runs once in `setup_file` into a results file the three tests read; the latency test keeps its own measurement.
**Acceptance Criteria:**
- [ ] The pass/fail/skip set per test name is identical before and after for both files (serial runs, TAP lines compared); no assertion text, expected value or skip condition changes.
- [ ] `adversarial-review-companion.bats` serial wall time ≤ 300 s on the ship host (from > 900 s); the three corpus tests in `block-destructive-bash.bats` run the corpus once (trace or counter evidence).
- [ ] CI's `bats-tests.yml` Shell Tests job green on the PR head.
**Dependencies:** FR-1.

> Sources: `tests/unit/adversarial-review-companion.bats:182-232`, `tests/unit/block-destructive-bash.bats:812-845, 1546-1590`; `~/.cache/loa/eso-loop/pass-21/REPORT.md` § Profile

### FR-7: audit-envelope verify-chain batching (bd-09z1i)
**Priority:** Could Have
**Description:** The SDD decides between (a) one `audit-envelope.sh verify-chains <root>` entry that verifies the trust store once per process (the subprocess-over-tempdir-snapshot defence kept exactly as `_trust_store_snapshot` / `_check_trust_store` implement it, run once) and then walks every chain file `loa-status.sh` checks, with per-file results and the same exit semantics, and (b) deferral. The decision row names the TOCTOU argument either way.
**Acceptance Criteria:**
- [ ] If (a): `tests/security/test_audit_trust_policy.py` and the audit-envelope bats (44 files) green; per-file results identical to the per-call results on the live chains and on tampered / broken-link / missing fixtures; `loa-status.sh` mean falls by ≥ 100 ms; the mutation of any chain is impossible by construction (read-only paths only).
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
**Dependencies:** FR-1 … FR-7.

> Sources: `~/.cache/loa/cycle-135/ship/*.sh` (the recipe that worked); `~/.claude/projects/-home-merlin-Documents-thj-code-loa/memory/reference_release_process.md`; cycle-133 rc.8 publish notes; DEC-0960, DEC-1057, DEC-1060

---

## Non-Functional Requirements

### Performance
Every change either removes work with byte-identical output (FR-3/4/5) or shortens tests without changing assertions (FR-6). Targets are measured against a same-session old mirror in a real directory (the symlinked-mirror `..` escape of pass 18 is a known trap). No change may add spawns to a hot path: `perf-spawn-budget.bats` guards six paths and gains a karpathy target in FR-4.

### Security
Hooks keep their documented fail-open / fail-closed semantics; untrusted bodies (KF, decisions, handoffs, notes) stay sanitised at surfacing; the audit chain is never mutated outside `audit_emit`; the trust-store TOCTOU defence is kept exactly or the bead is deferred; the `.run/perf-cache` writes use tmp+mv, umask 077 and symlink refusal; no new eval or source of data.

### Reliability
Red-first tests for every behaviour change; the covering bats suites and the full unit suite green on the landed head; rollback is a single-commit revert per bead; the loop commits stay as landed (no squash) so each pass reverts alone.

### Compliance
System Zone writes under the bounded marker with `checksums.json` and REPO-MAP regenerated in the same commit (DEC-0824); decision rows for every judgment call, `proposed` until the operator confirms; the CHANGELOG names every behaviour-visible change (the rc heading carries the loop block).

### Authorization basis and refusal list
Operator instruction of 2026-10-28 (verbatim in the brief). Refused regardless of instruction: writing `main` outside the merge, force-pushing, deleting tags or branches, merging with a red or pending required check, publishing a candidate whose digest was not re-canonicalised and approved, touching credentials or the live push configuration in tests, changing `br` contract calls, quarantining a test.

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
This PRD authorises writes under `.claude/hooks/loa-kf-surface.sh`, `.claude/scripts/grimoire-index.sh`, `.claude/scripts/loa-status.sh`, `.claude/scripts/lib/agy-gate-lib.sh`, `.claude/scripts/lib/profile-lib.sh`, `.claude/data/profiles.yaml`, `.claude/scripts/audit-envelope.sh` and `.claude/adapters/loa_cheval/audit_envelope.py` (only under FR-7(a)), `.claude/checksums.json`, `grimoires/loa/REPO-MAP.md` + `.checksum`, `tests/unit/**`, `CHANGELOG.md`, `README.md`, `.loa-version.json`, and any loop file a Sprint 281 review or audit fix names — each with the manifests regenerated in the same commit.

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

### Release-blocking status
FR-1 and FR-8 block the release; a Should/Could FR that does not land is deferred with a decision row and its bead kept open.

> Sources: `grimoires/loa/context/cycle-137-brief.md` § Scope, § Non-goals; `grimoires/loa/reports/perf/eso-loop-2026-10-27.md` § Follow-ups

---

## Success Criteria

### Launch Criteria
G-1 … G-6 as measured in `a2a/sprint-281/e2e.md` and `a2a/sprint-282/e2e.md`: the two gate verdicts, the beads' commits and tests, the re-baseline table, the full-suite TAP, the PR checks, the record/archive shas, the tag and release URLs.

### Post-Launch Success (30 days)
No KF entry attributes a regression to a loop commit; `perf-spawn-budget.bats` never trips on `main`; downstream mounts report no hook behaviour change.

### Long-term Success (90 days)
The spawn budgets are updated deliberately with each hook change, keeping the per-tool-call chains at or below the cycle-137 numbers.

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
| Load-sensitive tests (CMP-37) fail in a loaded CI run | FR-6 shortens the file; the gate runs the file alone on failure and records it |

> Sources: § Functional Requirements; KF-034, KF-063 in `grimoires/loa/known-failures.md`; `~/.cache/loa/eso-loop/bats-final/unit.tap`

---

## Timeline & Milestones

Two sprints: Sprint 1 (global 281) plan → reviewer.md → review → audit → COMPLETED; Sprint 2 (global 282) implement the six beads → review → audit → COMPLETED; then PR → Bridgebuilder → merge → record → archive → publish rc.9. Unattended, 2026-10-28.

> Sources: `grimoires/loa/context/cycle-137-brief.md`

---

## Appendix A — Goals

G-1 gates on the loop; G-2 six beads; G-3 gains hold + guard green; G-4 suite green modulo KF-034; G-5 PR/BB/merge/record/archive; G-6 rc.9 published.

> Sources: § Goals & Success Metrics

---

## Appendix B — Grounding reads

`.skill-loop-progress.md` (LOOP 2, 22 entries); `grimoires/loa/reports/perf/eso-loop-2026-10-27.md`; `~/.cache/loa/eso-loop/{final-table.tsv, baseline/*.json, final/*.json, pass-*/REPORT.md, pass-*/review/VERDICT.md, bats-final/unit.tap}`; `.claude/hooks/loa-kf-surface.sh`; `.claude/scripts/grimoire-index.sh`; `.claude/scripts/loa-status.sh:848-870`; `.claude/scripts/lib/agy-gate-lib.sh`; `.claude/scripts/lib/profile-lib.sh`; `.claude/data/profiles.yaml`; `.claude/adapters/loa_cheval/audit_envelope.py`; `tests/unit/adversarial-review-companion.bats`; `tests/unit/block-destructive-bash.bats`; `grimoires/loa/ledger.json` (cycle-137 active, next sprint 281); `grimoires/loa/archive/cycle-136-bridgebuilder-followups/prd.md` (format precedent); `~/.cache/loa/cycle-135/ship/*.sh`.

> Sources: the files named in this appendix
