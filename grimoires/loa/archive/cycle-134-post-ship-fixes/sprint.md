# Sprint Plan: Post-ship fixes (cycle-134)

**Version:** 1.1
**Date:** 2026-10-25
**Author:** Sprint Planner Agent (Claude Fable 5.1, unattended)
**PRD Reference:** `grimoires/loa/prd.md` (1.2, FR-1 … FR-10, G-1 … G-5)
**SDD Reference:** `grimoires/loa/sdd.md` (1.2, C-1 … C-10, D-1.1 … D-4.3)
**Ledger:** cycle `cycle-134-post-ship-fixes`, sprint global 276 (local sprint-1)
**Execution:** `/run sprint-plan` with one PR per sprint (DEC-0960: `consolidate_pr: false` for this run / `--no-consolidate`); Opus 5.5 implementers A–D in linked worktrees returning `git diff --cached --binary` patches with a "Judgment calls" section; the lead lands A → B → C → D, reviews and audits (dissent ≤ 3), ships.
**Task kinds:** every task carries `kind: mechanical | judgment` (DEC-0144); the lead's tasks are `judgment`; no `operator` task exists — the operator's instruction of 2026-10-25 authorises the cycle end to end (brief § The operator's instruction).
**Spend:** USD 20 cap (DEC-0969): Bridgebuilder round(s) on the sprint PR; Flatline and dissent on subscription routes at USD 0; the Q-1 one-turn session (cents) is the lead's; implementers make no live model calls.
**Flatline:** `grimoires/loa/a2a/flatline/cycle-134-sprint-review.json` (codex-headless + claude-headless, cross-scoring degraded — KF-041 shape; 9 skeptic blockers and 38 medium items, every one read and dispositioned in the Appendix; 1.1 integrates the accepted ones)
**System Zone authorization:** DEC-0824 carries over — `.claude/` and `.github/` writes (Task 1.6, 1.7) under the bounded zone marker (scope framework, reason, expiry ≤ 2 h, re-issued per write session) with `checksums.json` and REPO-MAP regenerated in the landing commit.

---

## Executive Summary

One sprint closes the nine defects the cycle-133 Bridgebuilder round and the rc.8 ship surfaced: the home-scope validator's two clause (g) gaps and its driver-trusted integrity record (FR-1, FR-2, FR-4), the over-broad mount rewrite rules (FR-5), the proxy pid limit, the supervisor's reclaim identity and the seeder's unfetched blobs (FR-6 … FR-8), the publish orchestrator's exit-code contract and float policy (FR-9), and the red post-merge run on the publisher's own ledger push (FR-3, KF-063). Four Opus implementers work in parallel on disjoint files; the lead lands, reviews, audits and ships one PR shaped for a non-degraded Bridgebuilder verdict; no release is cut (DEC-0967).

**Total Sprints:** 1
**Sprint Duration:** 1 day
**Estimated Completion:** 2026-10-26

> Sources: prd.md § Executive Summary, § Scope & Prioritization; sdd.md § 8

---

## Sprint Overview

| Sprint | Global | Theme | Key Deliverables | Dependencies |
|--------|--------|-------|------------------|--------------|
| 1 | 276 | The nine fixes and the ship | C-1 … C-9 with tests; CHANGELOG `[Unreleased]`; the host-local regression against D-4.3; one PR → Bridgebuilder → merge → record → archive | None |

> Sources: sdd.md § 1.4, § 8

---

## Sprint 1: The nine fixes and the ship (global 276)

**Duration:** 1 day
**Dates:** 2026-10-25 – 2026-10-26

### Sprint Goal

Fix every in-scope defect with a test that fails before and passes after, keep the recorded smoke evidence's verdicts as pre-registered, and ship the sprint as one PR with a non-degraded Bridgebuilder verdict — no release.

### Deliverables

- [x] C-1, C-2, C-3: `took-effect.sh` hook rule (group identity + equation), transcript completeness (JSONL policy), integrity cross-check against the pin; `evals/tests/took-effect-{hooks,transcripts,integrity}.bats` → **[G-2]**
- [x] C-4: R3/R5 corpus table (sdd.md § 11.F) and narrowed rules, `sandbox-mount-rules.bats`; `cmd_hooks` emits `home_hook_groups`; the bead correction on the verify claim → **[G-1]**
- [x] C-5, C-6, C-7: proxy pid limit with the pair-pinning test; `.jobs/<name>.ident` and identity-checked reclaim; seeder fix-diff blobs in the bounded fetch with a `file://` fixture → **[G-1]**
- [x] C-8: classifier trailing-`(#NNN)` extraction, empty number → other, cycle job guarded on `pr_number`; classifier and workflow-guard bats → **[G-3]**
- [x] C-9: both tag identity checks pre-write (exit 2), race → 1, integer domain at generate and publish, unreachable remote → 2; `post-merge-publication.bats` → **[G-1]**
- [x] CHANGELOG `[Unreleased]` entries; the host-local regression report against D-4.3; nine beads closed with commit and test → **[G-1, G-2]**
- [ ] One PR, Bridgebuilder verdict with no `degraded_reason`, CI green, admin merge, record branch stage, archive; no tag → **[G-4, G-5]**

### Acceptance Criteria

- [ ] PRD FR-1 AC 1–4 (fixture passes with 2 Bash invocations and 1 configured hook; k = 0 passes; unknown group fails; non-multiple fails; k above triggers fails; grammar confirmed on a real event; regression verdicts per D-4.3)
- [ ] PRD FR-2 AC 1–3 (JSONL policy fixtures both ways; the s274 REVIEW capture yields the pre-registered (g) entry)
- [ ] PRD FR-3 AC 1–5 (ledger-commit subject → other; `(#345)` trailer anchoring; guard text asserted; lookup failure distinguished; change confined to post-merge.yml and the classifier)
- [ ] PRD FR-4 AC 1–2 → `took-effect-integrity.bats`; FR-5 AC 1–3 → `sandbox-mount-rules.bats` + the § 11.F table + `sandbox-mount-home-scope.bats`; FR-6 AC 1–2 → `egress-proxy.bats`; FR-7 AC 1–2 → `batch-supervisor.bats`; FR-8 AC 1–2 → `seed-corpus-from-external.bats` (`file://` fixture); FR-9 AC 1–3 → `post-merge-publication.bats`; completion policy: all nine land in this sprint — a Should Have that slips is re-filed on its bead with a current status, named in `reviewer.md`, and G-1 is reported partial (the Must Haves FR-1, FR-2, FR-3 and the ship cannot slip)
- [ ] PRD FR-10 AC 1–3 (non-degraded Bridgebuilder summary; record branch and archive; no `v2.0.0-rc.9`)
- [ ] Review APPROVED and audit APPROVED on the PR head before the merge; `npx --no-install bats` suites and the harness bats green locally; CI green on the head → **[G-5]**

### Technical Tasks

<!-- → **[G-n]** names the PRD goal; ⇐ names the blocking task(s) (edge-or-none); every line ends with · kind: … -->

- [x] Task 1.1: Validator hook rule (A) — `evals/harness/took-effect.sh`: parse `hook_name` as `<event>[:<matcher>]`; build the pinned group set from the HOME copy's user settings (groups with the same key merged); read `home_hook_groups` (hex ids per sdd.md § 3.2) with the `home_hook_counts` fallback as event-level aggregates; the equation c = k·n, 0 ≤ k ≤ triggers with the § 11.H derivation table (`triggers: n/a` otherwise); evidence line `hooks: … c= n= k= triggers=`; header comment updated; `evals/tests/took-effect-hooks.bats` per sdd.md § 7.3 (k = 0 passes; unknown group fails; non-multiple fails; k above triggers fails; merged groups; hex round-trip of a matcher with colons and pipes; legacy aggregate) (bd-bex39); the `home_hook_groups` grammar is pinned by the shared fixture `evals/tests/fixtures/home_hook_groups.sample` (B emits it, A parses it); the `hooks:` evidence line records the Claude Code version from the transcript's `init` event; A implements against the documented event shape and finalises the parser on Task 1.4's real fixtures → **[G-2]** ⇐ none · kind: mechanical
- [x] Task 1.2: Validator transcript completeness (A, after 1.1 on the same file) — `labels_run` from `meta/pipeline.json` non-skipped phases; per label the JSONL policy (regular non-symlink non-empty file; every non-empty line a JSON object; exactly one `result` as the final non-empty line; ≥ 1 `init` before it; shared `session_id`; oversize lines complete and counted); failures `transcript <label>: <reason> (line N)`; unlabelled transcripts reported; `evals/tests/took-effect-transcripts.bats` (missing / no init / no result / malformed interior line / result not last / init after result / foreign session_id → fail; complete → pass) (bd-k3dia); `meta/pipeline.json` must list every phase the suite declares for the arm, and a skipped phase must carry a `skipped_reason`, else (g) fails `phases: incomplete record`; 'oversize' means longer than `EVENT_CAP` bytes (the constant at the top of took-effect.sh) and the count is the `skipped_for_size=` field of the `transcripts:` evidence → **[G-2]** ⇐ Task 1.1 · kind: mechanical
- [x] Task 1.3: Validator integrity cross-check (A, after 1.2) — under home-scope derive the pin's manifest digest from `.claude/checksums.json` at the pinned commit (SHA-256 of the blob bytes; entry count = its `files` map size), require `record.manifest_sha256` = `arm_evidence.manifest_sha256` = that digest, `record.files` = the count, `tampered` = `missing` = 0; walk a retained `<run>/home/.claude` when present (regular files only, symlink = fail, extra files reported) and bind it by the digest; evidence names `independent walk` or `record cross-checked against the pin (HOME deleted at exit)`; `evals/tests/took-effect-integrity.bats` (digest mismatch, count mismatch, tampered retained copy → fail; clean → pass with the mode) (bd-htzy2); the pin is the commit named by the operator's `--suite-file` (not the run's own record), compared against `meta/pipeline.json`'s recorded pin (a mismatch fails), with the objects read from `--source-repo`; the retained-HOME walk policy (regular files only; symlinked directories, special files, unreadable paths and traversal errors refuse by name; extra files reported) each has a fixture → **[G-2]** ⇐ Task 1.2 · kind: mechanical
- [x] Task 1.4: Q-1 hook-name grammar and the regression baseline (lead) — one-turn `claude -p --setting-sources user --output-format stream-json --verbose` on the lead host under a settings file with a matcher-less PreToolUse group and a regex group (`Write|Edit`), the real `hook_started` events handed to A as fixtures (or the recorded fact that tool hooks emit no events in `-p` mode, on bd-bex39); `took-effect.sh --run-dir … --suite-file …` over the two retained batches before the change (the D-4.3 baseline lines into `a2a/sprint-276/regression.md`); first source at zero cost: grep the retained transcripts under `evals/results/ablation-2.0/smoke-c133-s274{,-r2}/` for `hook_started` shapes (today: only `SessionStart:startup`); if the one-turn session emits no tool-hook events either, the grammar stays unconfirmed for tool hooks and the shipping decision is recorded as a DEC row (A ships the two-form parser with k = 0; fixtures synthesised from the SDK message types, marked as such) → **[G-2]** ⇐ none · kind: judgment
- [x] Task 1.5: Mount rules corpus table, narrowing and the hook-group emitter (B) — `evals/harness/lib/sandbox-mount.sh`: run the transform over the pinned framework, list every R3/R5 hit by context class into sdd.md § 11.F with keep/drop per the narrowing criterion, narrow the regexes to the kept contexts, diff the rewritten corpus before and after with every difference explained in the report; `cmd_hooks` prints the `home_hook_groups` line (sdd.md § 3.2) after the existing one; `evals/tests/sandbox-mount-rules.bats` (one case per table row; a planted un-rewritten literal fails `verify`; `hooks` output round-trips a matcher with colons and pipes); `evals/tests/sandbox-mount-home-scope.bats` and the negative control stay green; comment on bd-kgfh5 correcting the verify claim (verify round-trips R5 via `R5_REV`); the § 11.F keep/drop table goes to the lead before the regex change lands (Task 1.11 reviews each drop against the narrowing criterion) → **[G-1]** ⇐ none · kind: judgment
- [x] Task 1.6: Classify guard (C, System Zone) — `.claude/scripts/classify-merge-pr.sh`: PR number from the subject's trailing `(#NNN)` validated as a positive decimal, else empty; `pr_type=other` when empty with the stderr note `no associated PR: a push, not a merge`; `--pr-number` honoured; `.github/workflows/post-merge.yml` full-pipeline `if:` gains `&& needs.classify.outputs.pr_number != ''`; `tests/unit/classify-merge-pr.bats` (ledger subject → other; cycle subject without trailer → other; `fix: … closes #12 (#345)` → 345; `(#0)`/`(#12a)` → empty; explicit `--pr-number` → cycle; gh failure with a trailer → subject classification kept); `tests/unit/post-merge-workflow-guards.bats` (both job guards name `pr_number`); the other workflows that run on a push to `main` listed in the report as unchanged; KF-063 status line and attempt row (bd-hyx0n); the two guarded jobs and their exact expressions: `simple-release` keeps `if: needs.classify.outputs.pr_type != 'cycle' && needs.classify.outputs.pr_number != ''`, `full-pipeline` becomes `if: needs.classify.outputs.pr_type == 'cycle' && needs.classify.outputs.pr_number != ''`; the bats comments carry a table of representative classifier outputs (ordinary push, cycle merge, non-cycle merge, classification failure) and the expected routing → **[G-3]** ⇐ none · kind: mechanical
- [x] Task 1.7: Publish contract (C, System Zone) — `.claude/scripts/post-merge-orchestrator.sh`: `validate_candidate_v2` runs the local and remote tag identity checks with `tag_identity_matches` (lightweight tag = refusal; `ls-remote` failure = `remote unreachable, identity unverified`), all exit 2 before `PUBLISHING`; `phase_tag` re-checks before the push, returns 1 on the race, skips the push on an identical identity; `--generate` walks `prepared_state` and refuses a non-integer number (no fraction, no exponent, |n| ≤ 2^53−1, −0) with exit 2 and the JSON path before canonicalisation; `validate_candidate_v2` enforces the same domain at publish (exit 2); header exit-code table updated; `tests/unit/post-merge-publication.bats` per sdd.md § 7.3 incl. the real rc.8 candidate as a passing fixture (bd-4pv1j); the numeric check scans number tokens in the serialised JSON text before any parser normalises them (`1.0`, `1e3`, `-0` are refusals; `9007199254740991` passes, `9007199254740992` and its negative refuse); 'pre-write' means every exit-2 fixture asserts the state file, the progress file, local refs, remote refs and the ledger patch unchanged → **[G-1]** ⇐ none · kind: mechanical
- [x] Task 1.8: Proxy pid limit (D) — `evals/harness/lib/egress-proxy.sh:205` `--pids-limit 256`; `evals/harness/Dockerfile.proxy:45` run line follows; `evals/tests/egress-proxy.bats` asserts pid limit ≥ `MaxClients` + the base task allowance read from both files, the allowance observed once in a running proxy (`pids.current` at idle) and pinned as a commented constant (bd-1br0v); the lead observes `pids.current` on the Docker host and the constant's comment records the observed value and date; the derivation (MaxClients + main/log threads + margin) is written beside it — a concurrent-load test is out of scope and noted → **[G-1]** ⇐ none · kind: mechanical
- [x] Task 1.9: Supervisor job identity (D) — `evals/harness/lib/batch-supervisor.sh`: write `.jobs/<name>.ident` (`<start_ticks>:<sha256 of cmdline>`) before `.pgid`; `reclaim` compares both before `kill_group`, re-reads before TERM and KILL, treats records without `.ident` as stale with a one-time warning listing them (pgid, name) and removes stale records; header documents the residual numeric-pgid window; `evals/tests/batch-supervisor.bats` cases per sdd.md § 7.3 (bd-ruo5b); the identity belongs to the group leader (pgid = leader pid): when the leader has exited but members remain, the record is 'leaderless' — not signalled, logged with the live member pids for the operator, removed; a landing precondition (Task 1.11): no live `.jobs` records on the host → **[G-1]** ⇐ none · kind: mechanical
- [x] Task 1.10: Seeder fix-diff blobs (D) — `evals/harness/seed-corpus-from-external.sh`: `changed(FIX_PARENT, FIX_LAST)` from trees (`--no-renames`, NUL-safe) adds both sides' blob ids to the want set, deduplicated and charged once against `--max-files`/`--max-bytes`; out-of-bounds refuses `fix diff needs N blob(s) outside the fetch bounds: <paths>`; the diff is computed after the fetch under `GIT_NO_LAZY_FETCH=1`; any enumeration or fetch failure refuses; `evals/tests/seed-corpus-from-external.bats` gains a `file://` fixture repository exercising the fetch, the refusal and the no-partial-diff guarantee (bd-kdk3l); phases spelled out: (1) the blobless fetch already brings the commits and trees of FIX_PARENT and FIX_LAST (no blob), (2) `changed()` over those trees, (3) both sides' blob ids join the want set and are charged, (4) the one bounded batch fetch, (5) the diffs — any failure in (1)–(4) refuses before (5) → **[G-1]** ⇐ none · kind: mechanical
- [x] Task 1.11: Sprint close (lead) — land A (1.1 → 1.3), then B, C, D; after A and B the home-scope bats and a `hooks` → `took-effect.sh` round trip; checksums and REPO-MAP regenerated under the zone marker in the landing commit of C; CHANGELOG `[Unreleased]` entries per fix; DEC rows from every "Judgment calls" section; the host-local regression after the change against D-4.3 (any unexplained difference → DEC row and bead before merge); beads bd-bex39 bd-k3dia bd-hyx0n bd-htzy2 bd-kgfh5 bd-1br0v bd-ruo5b bd-kdk3l bd-4pv1j closed with commit and test; `npx --no-install bats tests/unit evals/tests` green; `reviewer.md`; 'fails before, passes after' is verified per patch: the new bats files are applied first and run against the pre-patch tree, the failing case ids recorded in `reviewer.md`, then the patch; the dissent runs (≤ 3, `adversarial-review.sh --type review` on each implementer's code-only diff, envelopes under `a2a/sprint-276/`) are a named step whose CRITICAL/HIGH findings block the review; an unexplained regression difference is resolved before merge — the expected table (D-4.3) is amended by a DEC row with the explanation, or the change is fixed — never merely recorded → **[G-1, G-2, G-5]** ⇐ Task 1.1, Task 1.2, Task 1.3, Task 1.4, Task 1.5, Task 1.6, Task 1.7, Task 1.8, Task 1.9, Task 1.10 · kind: judgment
- [ ] Task 1.12: Ship (lead) — after review and audit APPROVED: PR from `feature/cycle-134-post-ship-fixes` (code and tests only; evidence stays out), Bridgebuilder round(s) from the merged skill (≤ 2 rounds, plateau rule; a coverage cut → split along A/B/C/D per prd.md FR-10), required checks bound to the final head, admin merge with a merge commit, `record-branch.sh --cycle 134 --head <merge> --prev origin/record/cycle-133-follow-through --stage "stage 1"` + ICE push, `archive-cycle.sh --cycle 134 --retention 50` on a chore branch → PR → merge, run state JACKED_OUT; no tag, the post-merge candidate left unpublished (DEC-0967); **pre-merge gate** (the E2E's G-1, G-2, G-4 and the budget read happen here, before `gh pr merge`): fixtures green, the regression per D-4.3, the Bridgebuilder summary with no `degraded_reason` and a verdict of APPROVE or COMMENT with no blocking finding (a blocking finding is fixed or DEC'd within the ≤ 2 rounds), the cost ledger read before each round with a stop when the remaining budget is below one round's worst case (USD 8, the cycle-133 per-round cost); review, audit, the Bridgebuilder verdict and the required checks all reference the same final head — any commit after APPROVED re-runs review and audit (and dissent if an implementer's diff changed) and, when it touches `.claude/` or `.github/`, runs under a fresh zone marker with `checksums.json` and REPO-MAP regenerated; the secret scan (detect-secrets + the repository scanners) runs before the push and its result is recorded in `reviewer.md`; the PR carries code, tests, CHANGELOG `[Unreleased]`, `sdd.md` § 11.F, `decisions.yaml`, KF-063's status line, `checksums.json` and REPO-MAP — `reviewer.md`, `regression.md`, `e2e.md` and the envelopes ride the record branch; split fallback cost rule: at most two split PRs (A+B, C+D) with one Bridgebuilder round each, anything beyond is an operator decision; recovery: red merge-triggered CI → fix PR before the record stage; failed record push → re-run `record-branch.sh` (CAS); failed archive PR → fix and re-run; JACKED_OUT only after all three → **[G-4, G-5]** ⇐ Task 1.11 · kind: judgment
- [ ] Task 1.E2E: Sprint 1 goal validation — G-1 (nine beads closed with commit and test), G-2 (fixtures both ways; the D-4.3 regression lines), G-3 (classifier and guard fixtures; the live confirmation deferred to the next publish, on KF-063), G-4 (the Bridgebuilder summary with no `degraded_reason`), G-5 (CI check-runs; the cost ledger rows of the cycle ≤ USD 20) → `a2a/sprint-276/e2e.md`; post-merge verification: merge-triggered CI green on `main`, the record branch pushed, the archive PR merged, and the live observation that `post-merge.yml` classified the sprint merge itself as `cycle` with its `(#NNN)` and prepared (did not publish) a candidate → **[G-1, G-2, G-3, G-4, G-5]** ⇐ Task 1.12 · kind: judgment

### Patch contract (per-implementer path allowlist)

| Implementer | May change | Must not touch |
|---|---|---|
| A | `evals/harness/took-effect.sh`, `evals/tests/took-effect-*.bats`, `evals/tests/fixtures/took-effect/**`, `evals/tests/fixtures/home_hook_groups.sample` (read) | `sandbox-mount.sh`, `.claude/`, `.github/` |
| B | `evals/harness/lib/sandbox-mount.sh`, `evals/tests/sandbox-mount-rules.bats`, `evals/tests/fixtures/home_hook_groups.sample`, `grimoires/loa/sdd.md` § 11.F only | `took-effect.sh`, `.claude/`, `.github/` |
| C | `.claude/scripts/classify-merge-pr.sh`, `.claude/scripts/post-merge-orchestrator.sh`, `.github/workflows/post-merge.yml`, `tests/unit/classify-merge-pr.bats`, `tests/unit/post-merge-workflow-guards.bats`, `tests/unit/post-merge-publication.bats`, `grimoires/loa/known-failures.md` (KF-063 lines) | `evals/`, `checksums.json`/REPO-MAP (the lead regenerates) |
| D | `evals/harness/lib/egress-proxy.sh`, `evals/harness/Dockerfile.proxy`, `evals/harness/lib/batch-supervisor.sh`, `evals/harness/seed-corpus-from-external.sh`, their bats and fixtures | `took-effect.sh`, `sandbox-mount.sh`, `.claude/`, `.github/` |

A patch outside its allowlist is returned, not landed.

### Seams Under Test

| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `took-effect.sh` over a fixture run dir (transcripts, ps, arm-evidence, pipeline.json) | hook-group identity and equation errors; transcript policy errors; integrity binding errors | a `hook_name` grammar Claude Code changes later | `evals/tests/took-effect*.bats` (cycle-133) |
| `sandbox-mount.sh transform` / `verify` / `hooks` over the pinned tree | an over-broad or missing rewrite; a verify gap; evidence grammar | runtime behaviour of rewritten commands (the smoke) | `evals/tests/sandbox-mount-home-scope.bats` |
| `classify-merge-pr.sh` + the workflow `if:` text | mis-routed pushes; wrong PR number | GitHub's expression evaluation (not executed in tests) | `tests/unit/classify-merge-pr.bats` |
| `post-merge-orchestrator.sh --generate` / `--publish` in a fixture repo with a fake remote | exit-code contract; identity rules; numeric domain | a real GitHub remote's failure modes | `tests/unit/post-merge-publication.bats` |
| `egress-proxy.sh` + `Dockerfile.proxy` read as files | pid/MaxClients drift | tinyproxy's actual thread count under load | `evals/tests/egress-proxy.bats` |
| `batch-supervisor.sh reclaim` with planted `.jobs` records | signalling an unverified group; legacy handling | the residual check-then-signal window | `evals/tests/batch-supervisor.bats` |
| `seed-corpus-from-external.sh` against a `file://` fixture repository | unfetched blobs in the fix diff; bounds | GitHub API behaviour | `evals/tests/seed-corpus-from-external.bats` |

### Dependencies

- None external. `npx --no-install bats` on this host; Docker 26.1 only for the egress bats that already require it; the retained smoke batches under `evals/results/ablation-2.0/smoke-c133-s274{,-r2}/` for the host-local regression.
- Internal: Task 1.2 after 1.1 and 1.3 after 1.2 (one file, implementer A); Task 1.11 after 1.1 … 1.10; Task 1.12 after 1.11; Task 1.E2E after 1.12.

### Security Considerations

- Validators fail closed (unknown hook group, damaged transcript, unbindable integrity record); the supervisor never signals an unverified group; the seeder keeps `GIT_NO_LAZY_FETCH=1` as its provenance boundary; the proxy keeps a pid limit on a `NET_ADMIN` container.
- System Zone writes (Tasks 1.6, 1.7) under the bounded zone marker with `checksums.json` and REPO-MAP regenerated in the landing commit; secret scan (detect-secrets and the repository scanners) before the push; the operator's dotfile keys are never read, echoed or committed.
- The publish path's exit-2 contract is what the runbook relies on; every pre-write refusal path has a fixture.

### Risks & Mitigation

- Risk: the `hook_name` grammar for tool hooks is not what the parser expects → Task 1.4 confirms it on a real event before A's patch lands; k = 0 keeps un-emitting groups legal.
- Risk: narrowing R3/R5 removes a rewrite the mount needs → the corpus table with every difference explained; home-scope bats and the negative control gate it.
- Risk: the regression shows a difference beyond the pre-registered one → shipping gate: DEC row and bead before merge (D-4.3).
- Risk: the Bridgebuilder round degrades on the sprint PR → the PR is code and tests (well under the file cap); if coverage is cut, split along A/B/C/D (FR-10).
- Risk: dissent voices time out on the full diff → code-only diff per implementer; ≤ 3 runs.

### Success Metrics

- G-1: 9 of 9 beads closed with commit and test.
- G-2: the took-effect fixtures pass in both directions; the regression reproduces D-4.3 exactly.
- G-3: the classifier and guard fixtures pass; the next publish's ledger push is green (recorded afterwards on KF-063).
- G-4: the Bridgebuilder summary on the PR carries no `degraded_reason` and its verdict equals the consensus block's.
- G-5: CI green on the merged head; cycle spend ≤ USD 20 in the cost ledger.

> Sources: prd.md § Functional Requirements, § Success Criteria; sdd.md § 1.4, § 7.3, § 8, § 11.D

---

## MVP Definition

The sprint is the MVP: FR-1, FR-2, FR-3 and FR-10 are the merge gate; FR-4 … FR-9 land in the same sprint and, if one slips, are re-filed on their bead with a current status and named in the report (G-1 partial).

> Sources: prd.md § Scope & Prioritization

## Risk Assessment

Low: nine local changes with fixtures, no model spend to build or test, one PR. The one open question with schedule risk is Q-1 (the hook-name grammar), resolved by the lead's one-turn session on day one.

> Sources: sdd.md § 9, § 10


---

## Appendix

### Goals (from prd.md § Goals & Success Metrics)

| Goal | Statement | Evidence at sprint close |
|------|-----------|--------------------------|
| G-1 | Every in-scope bead closed with evidence | 9 beads closed, each close reason naming the commit and the test; `reviewer.md` |
| G-2 | The validator is right in both directions | the FR-1/FR-2/FR-4 fixtures; the D-4.3 regression lines in `a2a/sprint-276/regression.md` |
| G-3 | The post-merge pipeline is green on a push without a PR | the classifier and workflow-guard fixtures; the next publish's ledger push (recorded on KF-063 afterwards) |
| G-4 | One PR, one non-degraded Bridgebuilder verdict | the PR's Bridgebuilder summary (no `degraded_reason`; verdict = consensus block) |
| G-5 | Green suites at no model spend | CI check-runs on the merged head; the cycle's cost-ledger rows ≤ USD 20 |

> Sources: prd.md § Goals & Success Metrics, § Success Criteria

### Flatline sprint review dispositions (1.0 → 1.1)

| Item | Concern (short) | Disposition |
|---|---|---|
| SKP-012, opus IMP-020 | an unexplained regression difference only gets a DEC + bead | **Accepted:** resolved before merge (table amended by DEC with the explanation, or fixed) — Task 1.11 |
| SKP-003, gpt IMP-002, opus IMP-001/002 | Q-1 negative case; Task 1.1 ↔ 1.4 ordering | **Accepted:** Task 1.1 ⇐ Task 1.4; zero-cost first source; the negative outcome is a recorded shipping decision — Tasks 1.1, 1.4 |
| SKP-006, SKP-005 | check-then-signal window; leaderless groups | **Accepted in part:** leaderless records are stale and logged; the residual window is documented (no pgid atomicity exists) — Task 1.9 |
| SKP-001 (gpt), opus IMP-017 | where the validator gets the pin | **Accepted:** the operator's `--suite-file` names it; the run record must agree; objects from `--source-repo` — Task 1.3 |
| SKP-015, gpt IMP-005 | E2E after the merge | **Accepted:** the pre-merge gate in Task 1.12; post-merge verification in 1.E2E |
| SKP-008, gpt IMP-010, opus IMP-016 | lexical forms normalised by the parser | **Accepted:** number-token scan of the serialised text; fixtures for `1.0`, `1e3`, `-0`, both 2^53 boundaries — Task 1.7 |
| SKP-002 | pipeline.json completeness | **Accepted:** every declared phase present; skipped phases carry a reason — Task 1.2 |
| SKP-001 (opus) | record cross-check is not content proof | **Accepted, already stated** (sdd.md D-1.3, § 11.G) |
| gpt IMP-001 | baseline before changes land | **Accepted** (Task 1.4 first; Task 1.1 ⇐ 1.4) |
| gpt IMP-003 | one completion policy | **Accepted** (Acceptance Criteria) |
| gpt IMP-004, opus IMP-006 | same final head; re-review after a post-approval commit | **Accepted** (Task 1.12) |
| gpt IMP-006 | recovery for red CI / failed record / failed archive | **Accepted** (Task 1.12) |
| gpt IMP-007, opus IMP-007 | split procedure and cost | **Accepted:** at most two split PRs, one round each; beyond → operator (Task 1.12) |
| gpt IMP-008, opus IMP-005 | which files ride the PR | **Accepted** (Task 1.12) |
| gpt IMP-009 | executable guard validation | **Partially accepted:** representative-outputs table in the test; no expression evaluator (Task 1.6) |
| gpt IMP-011 | define pre-write | **Accepted** (Task 1.7) |
| gpt IMP-012 | concurrent-load proxy check | **Noted:** out of scope; the derivation is documented (Task 1.8) |
| gpt IMP-013 | retained-HOME walk policy fixtures | **Accepted** (Task 1.3) |
| gpt IMP-014 | budget reservation per round | **Accepted** (Task 1.12) |
| opus IMP-003 | verify fails-before | **Accepted** (Task 1.11) |
| opus IMP-004 | shared grammar fixture | **Accepted** (`evals/tests/fixtures/home_hook_groups.sample`) |
| opus IMP-008 | live observation of the merge's own classification | **Accepted** (1.E2E) |
| opus IMP-009 | fetch phases | **Accepted** (Task 1.10) |
| opus IMP-010 | landing precondition for 1.9 | **Accepted** (Task 1.9 / 1.11) |
| opus IMP-011 | lead approval of the keep/drop table | **Accepted** (Tasks 1.5, 1.11) |
| opus IMP-012 | AC mapping for FR-4 … FR-9 | **Accepted** (Acceptance Criteria) |
| opus IMP-013 | per-implementer path allowlist | **Accepted** (Patch contract table) |
| opus IMP-014 | who observes `pids.current` | **Accepted** (Task 1.8: the lead) |
| opus IMP-015 | exact `if:` expressions | **Accepted** (Task 1.6) |
| opus IMP-018, IMP-019 | dissent and secret-scan steps | **Accepted** (Tasks 1.11, 1.12) |
| opus IMP-021 | acceptable Bridgebuilder verdict | **Accepted** (Task 1.12) |
| opus IMP-022, IMP-023 | oversize definition; Claude Code version on the evidence line | **Accepted** (Tasks 1.2, 1.1) |
| opus IMP-024 | fresh marker for post-landing System Zone commits | **Accepted** (Task 1.12) |
| remaining items | restatements or wording | **Noted** |

> Sources: `grimoires/loa/a2a/flatline/cycle-134-sprint-review.json`
