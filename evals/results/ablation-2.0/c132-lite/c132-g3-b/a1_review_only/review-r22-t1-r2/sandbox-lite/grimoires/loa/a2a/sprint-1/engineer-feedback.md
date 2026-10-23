# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (carries `pr/PR.md`)

---

## Overall Assessment

The change under review is `pr/head.diff` (72 files, ~7,000 added lines): the cycle-130 Sprint 258 work — the tracked-tree integrity manifest and its CI gate (#1267), the submodule-mount scope in `check-loa.sh`, the spend cap and screening mode in `run-arms.sh`, the ablation-2.0 suite, the shared sandbox mount library, the container pipeline executor, `took-effect.sh`, `ablation-row.sh`, `spend.sh`, `validate-suite.sh`, `freeze.sh`, and their bats suites.

The engineering is careful: the executor's environment allowlist, secret handling (bearer token by name only, `<set>` in captures), descriptor hygiene, two-mount container launch, leak guards, and the evidence-first `took-effect.sh` rules are well designed and well tested. I ran the suites this environment could execute (see Test Evidence): `spend.bats` 6/6, `gen-checksums.bats` 7/7, `check-loa-mount-scope.bats` 6/6, `check-manifest-paths.bats` 7/7, and 45 of 52 `pipeline-run.bats` cases pass.

Three defects block merge. Two break CI as shipped: `took-effect.bats` and `ablation-row.bats` depend on fixture run directories that are not in the change, and the new integrity-manifest gate requires a regenerated `.claude/checksums.json` that the change does not include while it edits several manifest-covered files. The third is a regression in `preflight.sh` (the adversarial dissent's blocking finding): counting `git ls-files` entries instead of files present means a deleted System Zone file no longer trips the count check.

Process note: `reviewer.md` carries the PR description only and has no `## AC Verification` section; in this evaluation layout that is expected, but under the skill's rules it is an automatic CHANGES_REQUIRED on its own. The counts below decide the verdict regardless.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Testing — fixture run directories are missing from the change

- **HIGH** (confidence: high) `head/evals/tests/took-effect.bats:18` — `setup()` runs `cp -a "$FX/runs" "$T/runs"`, but `evals/tests/fixtures/ablation-runs/runs/` does not exist anywhere in the change; every one of the 21 tests fails in setup.
**File:** `head/evals/tests/took-effect.bats:18`, `head/evals/tests/ablation-row.bats:19`, `head/.github/workflows/bats-tests.yml:212`
**Issue:** `head/evals/tests/fixtures/ablation-runs/regen.sh` generates ten run directories under `runs/` and both test files copy that directory in `setup()`. The change ships `regen.sh`, `MANIFEST.json`, `suite.yaml`, `tasks/` and `prs/`, but no `runs/`. Reproduced here against the head tree: all 21 `took-effect.bats` and all 18 `ablation-row.bats` cases fail with `cp: cannot stat '.../fixtures/ablation-runs/runs': No such file or directory`. The new workflow step at line 212 runs `bats evals/tests/`, so CI goes red on this PR.
**Why This Matters:** `took-effect.sh` and `ablation-row.sh` (two of the sprint's deliverables) have zero executed test coverage, and the CI step added in the same change fails.
**Required Fix:** Run `evals/tests/fixtures/ablation-runs/regen.sh` and commit the resulting `runs/` tree (ten directories, `.git` and `*.bundle` removed as regen.sh does). If the directory was intentionally left out, make the tests regenerate it in `setup_file()` instead. Confirm `.gitignore` does not exclude it.

### 2. CI / Integrity — the manifest gate is added without regenerating the manifest

- **HIGH** (confidence: medium) `head/.github/workflows/bats-tests.yml:178` — `bash tools/gen-checksums.sh --check` is now a required step, but the change edits tracked `.claude/` files (`check-loa.sh`, `preflight.sh`, `generated-model-maps.sh`, `defaults/model-config.yaml`, `loa/CLAUDE.loa.md`, the bridgebuilder `dist/` files) without touching `.claude/checksums.json`; the check reports DRIFT and exits 1.
**File:** `head/.github/workflows/bats-tests.yml:175-178`, `head/tools/gen-checksums.sh:164-168`
**Issue:** `gen-checksums.sh --check` hashes the working-tree content of every tracked `.claude/` path and compares the `files` map with the committed manifest. The committed manifest (the framework mount here lists 1,973 entries, including `check-loa.sh`, `preflight.sh` and `model-config.yaml`) necessarily disagrees with the edited files unless regenerated in the same commit. Only `model-config.yaml.checksum` was refreshed. The companion dissent voice reached the same conclusion (DISS-C-005) and adds the downstream effect: `check-loa.sh` reports `Tampered:` on each of these paths on a fresh mount of this commit.
**Why This Matters:** The gate this sprint introduces fails on the sprint's own commit, and every downstream integrity check is red until the manifest is regenerated.
**Required Fix:** Run `bash tools/gen-checksums.sh` and commit the regenerated `.claude/checksums.json` with this change (and add that step to the release checklist the header of `gen-checksums.sh` describes). Verify with `bash tools/check-manifest-paths.sh && bash tools/gen-checksums.sh --check`.

### 3. Security — preflight's integrity count no longer notices deleted System Zone files

- **HIGH** (confidence: high) `head/.claude/scripts/preflight.sh:190` — `ACTUAL_COUNT` is now `git ls-files -- .claude | …| wc -l`; `git ls-files` lists index entries, which still include a tracked file deleted from the working tree, so deleting any managed file leaves the count equal to the manifest's and the "file count mismatch" warning never fires.
**File:** `head/.claude/scripts/preflight.sh:177-196`
**Issue:** Verified on a scratch repository: after deleting one tracked file, `git ls-files` still reports both entries while `find` reports one and `git ls-files --deleted` reports one. The previous `find`-based count caught the deletion; the new count only falls back to `find` when the tracked count is zero. This is the adversarial dissent's blocking finding (DISS-001, gpt-5.5-pro voice).
**Why This Matters:** Preflight is the cheap first-line System Zone check; an incomplete or tampered-by-deletion installation now passes it silently. The full hash walk in `check-loa.sh` still catches deletions, but preflight's own promise ("compare file count") is broken, and the function's purpose is integrity. CWE-354 (Improper Validation of Integrity Check Value).
**Required Fix:** Count tracked paths that are present: filter the `ls-files` output with `[[ -f "$MANIFEST_TREE/$p" ]]`, or subtract `git ls-files --deleted -- .claude | wc -l`. Add a unit case that deletes one tracked `.claude/` file and expects the mismatch warning.

---

## Observations

### 1. Portability — the executor needs jq 1.7 semantics but only checks that jq exists

- **MEDIUM** (confidence: high) `head/evals/harness/pipeline-run.sh:167` — the tool check tests presence only; on jq 1.6 (Debian bookworm, Ubuntu 22.04 runners) every run dies at the first phase with `jq: error: syntax error, unexpected label` because `$label` (a jq keyword used as a variable name at lines 702/708, 816/826 and 881/882) is rejected by jq 1.6.
**File:** `head/evals/harness/pipeline-run.sh:167`, `:702-708`, `:816-826`, `:881-882`, `head/evals/harness/ablation-row.sh:285`
**Suggestion:** Reproduced here with jq 1.6: `{label: $label}` is a compile error, and the `{name, label, …}` shorthand at `ablation-row.sh:285` fails the same way. A second jq-1.6 difference hides behind the first: jq 1.6 `-Rs` drops a trailing NUL (`printf 'a\0b\0' | jq -Rs length` is 3), so the argv/env captures at lines 704-707 (`split("\u0000") | .[:-1]`) silently lose their last element. With `$label` renamed on a jq 1.6 host, `phase-*.argv.json` lacks `--resume <id>`, `--effort <v>` and `LOA_ADVERSARIAL_REVIEW_ENFORCE`, which is exactly what `took-effect.sh` reads (`effort_flag_medium`, `enforce_env_false`, `implementer_single_session`). Either require `jq >= 1.7` in the tool check (also in `ablation-row.sh`/`took-effect.sh`) or rename the variable and build the arrays without relying on the trailing separator (for example `--args` or `rtrimstr("\u0000")`).
**Benefit:** A loud, early refusal instead of a phase-1 crash, and captures that cannot silently lose evidence.

### 2. Integrity — the not-mounted rule masks tampering by deletion in submodule mounts

- **MEDIUM** (confidence: high) `head/.claude/scripts/check-loa.sh:75-76` — any manifest path absent locally but present under `.loa/<path>` is informational; in a submodule mount, deleting a linked hook or script (`.claude/hooks/...`, `.claude/scripts/preflight.sh`) now yields "Integrity verified" plus a count line.
**File:** `head/.claude/scripts/check-loa.sh:67-83`
**Suggestion:** This is the accepted trade-off of SDD §5.3 (#1267 false positives), and the companion dissent flags it independently (DISS-C-001). The gate is only `-d .loa/.claude`; nothing distinguishes "never linked by design" from "link removed". Compare against what `mount-submodule.sh` intended to link (a link list or the set of symlinks it created) and report a removed link as Missing; keep not-mounted for paths outside that set.
**Benefit:** Restores deletion detection where the integrity check is most relied on.

### 3. Executor — host `br` initialises beads the container cannot run

- **MEDIUM** (confidence: medium) `head/evals/harness/pipeline-run.sh:489` — `init_sandbox_beads` runs on the host and uses host `br` when present (`head/evals/harness/lib/sandbox-mount.sh:505`), so the sandbox gets a `.beads/` initialised with a binary the image does not carry; `head/evals/harness/Dockerfile.ablation:82` asserts the opt-out marker is written, which is only true on a host without `br`.
**File:** `head/evals/harness/pipeline-run.sh:489`, `head/evals/harness/lib/sandbox-mount.sh:500-520`, `head/evals/harness/Dockerfile.ablation:82-84`
**Suggestion:** In container mode pass `LOA_EVAL_BR_BIN=/nonexistent` (or an explicit opt-out flag) so every arm gets the same `beads=opt-out` state regardless of the operator's host; record the chosen mode in `arm_evidence`.
**Benefit:** Arms are comparable across hosts, as the Dockerfile comment promises.

### 4. Validity — the BARE arm's prompt carries information the Loa arms' brief does not

- **MEDIUM** (confidence: medium) `head/evals/harness/pipeline-run.sh:544` — the A0 contract says `Test command: …; run the tests; stop when they pass`, while the Loa arms' `task-brief.md` (`head/evals/harness/lib/sandbox-mount.sh:472-473`) is criterion + TASK.md only. SPECULATION: unless every TASK.md repeats the test command, A0 gets a stronger stopping signal than A1, confounding the H1 comparison the suite pre-registers.
**File:** `head/evals/harness/pipeline-run.sh:541-544`, `head/evals/harness/lib/sandbox-mount.sh:471-474`
**Suggestion:** Put the test command in the task brief for every arm (or in none) so the arms differ only in the component under ablation.
**Benefit:** Keeps the ablation's primary comparison clean.

### 5. Trust boundary / watchdog — pricing runs `.claude/adapters` code and fails silent

- **MEDIUM** (confidence: medium) `head/evals/harness/pipeline-run.sh:586` — `price_for` executes `$REPO_ROOT/.claude/adapters/loa_cheval/metering/pricing.py` although the header (line 125) says no `.claude/` code runs; when that file is absent (the eval workflow's trusted-copy layout) the lookup returns `null`, the watchdog is quietly disabled (`priced: false`) and the cap is enforced only after each phase completes.
**File:** `head/evals/harness/pipeline-run.sh:125-126`, `:576-597`, `:731`
**Suggestion:** Either document pricing.py as the one sanctioned `.claude/` dependency and warn on stderr when a model is unpriced, or fail the run when the watchdog cannot price a phase and no `LOA_EVAL_PRICING_JSON` is given.
**Benefit:** The per-run cap (D-4.10) is enforced mid-phase as designed, or its absence is visible.

### 6. Complexity

- **MEDIUM** (confidence: high) `head/evals/harness/pipeline-run.sh:634-868` — `run_phase()` is 235 lines with argv construction, env assembly, container launch, watchdog loop, result parsing, snapshotting, verdict reading and accounting in one body; `apply_arm_toggles()` at `head/evals/harness/lib/sandbox-mount.sh:255-371` is 117 lines, and the validator's Python block at `head/evals/harness/validate-suite.sh:107-360` is 250 lines of straight-line checks.
**Suggestion:** `SIMPLICITY[shrink]`: split `run_phase` into `build_launcher`, `watch_phase`, `record_phase`, `account_phase`; split the toggle `case` into one function per toggle; move the validator into `lib/validate-suite.py` where it can have functions and its own tests. Function length over 50 lines is above the skill's threshold; no justification is recorded.
**Benefit:** Each piece becomes testable on its own; the jq-portability fix above touches three places inside `run_phase` today. Over-engineering pass otherwise: Lean already. Ship.

### 7. Dockerfile — dead build stage and stale version notes

- **MEDIUM** (confidence: medium) `head/evals/harness/Dockerfile.ablation:19-20` — the `brbuild` stage installs `beads_rust` that line 82 says is not on crates.io; nothing references the stage. BuildKit prunes it, but the classic builder (or `DOCKER_BUILDKIT=0`) runs it and the build fails on both `cargo install` attempts.
**File:** `head/evals/harness/Dockerfile.ablation:19-20`, `head/evals/harness/pipeline-run.sh:85`
**Suggestion:** Delete the stage. Also align the version notes: the Dockerfile pins codex 0.162.1 while `pipeline-run.sh:85` says 0.137.0.
**Benefit:** Reproducible image build on every builder; accurate provenance comments.

### 8. Lower-severity items

- **LOW** (confidence: high) `head/evals/harness/ablation-row.sh:230` — `ms(ts)` only strips a `.NNNZ` suffix; a `+00:00` offset or empty string makes `fromdateiso8601` raise and the whole row build exits 5 instead of degrading (verified: jq rejects `2026-10-15T00:00:00+00:00`). Dissent DISS-C-002.
**Suggestion:** Guard with `try (…) catch null` and fall back to the summed phase durations.
- **LOW** (confidence: high) `head/evals/harness/fingerprint.sh:86` — the digest needs `python3` while the header promises a missing tool only changes the fingerprint; line 54 also bakes an operator-specific `~/.local/dotfiles/...` bats path into a shipped script. Dissent DISS-C-004.
**Suggestion:** Use `sha256_portable`-equivalent fallback or require python3 explicitly; drop the private default path.
- **LOW** (confidence: medium) `head/.claude/defaults/model-config.yaml:144-148` — the gpt-6.1-sol rate card is a documented placeholder, but MODELINV rows and `runs.jsonl` cost figures priced through it carry no marker. Dissent DISS-C-003.
**Suggestion:** Add a `pricing_note`/`placeholder: true` field the ledger writer can surface, and a bead to replace it.
- **LOW** (confidence: medium) `head/evals/harness/pipeline-run.sh:570` — the codex `auth.json` copy under `meta/home/` is removed on EXIT/TERM/INT/HUP only; a SIGKILLed driver leaves an OAuth credential inside the run directory that batch tooling may archive.
**Suggestion:** Sweep `meta/home/` at the start of `ablation-row.sh`/the batch runner, or mount a tmpfs for HOME.
- **LOW** (confidence: high) `head/tests/unit/check-manifest-paths.bats:99-102`, `head/tests/unit/gen-checksums.bats:87-91` — the "outside a git repository" cases create their fixture under `$BATS_TEST_TMPDIR`; when TMPDIR lives inside a git work tree (as here) they fail. Both pass with `TMPDIR=/tmp`.
**Suggestion:** `git init` a parent and remove `.git`, or set `GIT_CEILING_DIRECTORIES`.
- **LOW** (confidence: high) `head/tests/unit/gen-checksums.bats:9` — the header refers to a `GC-8` live-manifest case that does not exist in the file.
- **LOW** (confidence: high) `head/evals/harness/pipeline-run.sh:491` — the `.run/zone-guard-authorization.json` check follows `mkdir -p "$WS/.run"` on line 490 and the fixture path rule already refuses a top-level `.run`; the condition cannot be true.
- **LOW** (confidence: medium) `head/evals/harness/lib/sandbox-mount.sh:131` — the whole-tree mount copies `.claude/overrides/` and any `settings.local.json` from the operator's source tree into every sandbox, so operator customisations become part of the treatment.
**Suggestion:** Exclude `overrides/` and local settings from the copy (the manifest already skips `overrides/`).
- **LOW** (confidence: low) `head/evals/tests/fixtures/ablation/suite-lib.bash:10` — five tests (`arm-toggles.bats:442,464`, `validate-suite.bats:32`, `freeze.bats:99`) read `grimoires/loa/evals/ablation-2.0/smoke/smoke-{build,review}-01`, which the change does not add; confirm they exist on the base branch, otherwise this is the same class as Changes Required §1.
- **LOW** (confidence: high) `head/evals/suites/ablation-2.0.yaml:25` — `source_commit: "<sprint-258-commit>"` is a placeholder nothing validates; `validate-suite.sh` could refuse a non-hex value before a freeze.

---

## Rejected dissent payloads

None. The envelope's `metadata.rejected_summary` is empty and the sidecar `adversarial-rejected-review.jsonl` beside it holds zero rows.

---

## Cross-Model Observations

Adversarial review ran with `--diff-file pr/head.diff`: primary gpt-5.5-pro (answered via codex-headless), companion claude-headless, 2/2 voices, consensus. Triage:

| Finding | Voice | Disposition |
|---------|-------|-------------|
| DISS-001 preflight counts index entries, not files | primary (BLOCKING) | Confirmed; Changes Required §3 |
| DISS-C-001 not-mounted masks deletion in submodule mounts | companion | Confirmed; Observations §2 |
| DISS-C-002 `ms(ts)` strict timestamp parsing | companion | Confirmed; Observations §8 |
| DISS-C-003 placeholder gpt-6.1-sol pricing unmarked | companion | Accepted; Observations §8 |
| DISS-C-004 fingerprint.sh python3 dependency / private path | companion | Confirmed; Observations §8 |
| DISS-C-005 `.claude/checksums.json` not regenerated | companion | Confirmed; Changes Required §2 |

---

## Test Evidence

Run from a scratch copy of `pr/head` (scripts restored to the 100755 mode the diff records; `/tmp` is `noexec` here, so an executable TMPDIR was used; jq is 1.6 on this host).

| Suite | Result | Note |
|-------|--------|------|
| `evals/tests/spend.bats` | 6/6 pass | |
| `tests/unit/gen-checksums.bats` | 7/7 pass | GC-7 needs TMPDIR outside a git tree (Observations §8) |
| `tests/unit/check-manifest-paths.bats` | 7/7 pass | MP-6 needs the real repository manifest; MP-7 as GC-7 |
| `tests/unit/check-loa-mount-scope.bats` | 6/6 pass | against the PR's `check-loa.sh` |
| `evals/tests/took-effect.bats` | 0/21 | setup: `fixtures/ablation-runs/runs` missing (Changes Required §1) |
| `evals/tests/ablation-row.bats` | 0/18 | same cause |
| `evals/tests/pipeline-run.bats` | 48/52 pass after renaming `$label` for jq 1.6 in the scratch copy (45 in the full run, 3 more on re-run once the scratch patch had settled) | the 4 remaining failures are the jq 1.6 trailing-NUL capture loss (Observations §1); unpatched, every phase-running case fails on `$label` |
| `run-arms.bats`, `arm-toggles.bats`, `freeze.bats`, `validate-suite.bats` | not run | need base-branch fixtures (`claude-stub.sh`, `review-prs/`, smoke tasks) absent from this snapshot |

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | fixture `runs/` tree; regenerated `.claude/checksums.json`; preflight count fix |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict" (sprint.md) | Pass | every finding above is cited as `head/<path>:<line>`; verdict below |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the bearer token travels by name; the codex auth copy is a scoped, deleted-at-exit file — see Observations §8 for the SIGKILL gap)
- [x] Input validation and sanitization present (arm ids, sprint labels, task ids, USD amounts, phase names are regex-checked; prompt substitution guards `&`)
- [x] Authentication/authorization correct (container runs as host uid, read-only root, two mounts, no `~/.claude` credential copy)
- [x] No SQL/XSS injection vulnerabilities (n/a; no `eval`, no variable `source`)
- [ ] Integrity checks: preflight count regression (Changes Required §3) and not-mounted masking (Observations §2)
- [x] Error messages don't leak sensitive data (`<set>` in captures; leak guards for `hidden`, defect keys, arm ids)

---

## Code Quality Summary

**Strengths:**
- Environment allowlist with an `execvpe` shim and descriptor closing; secrets never on argv; verified by tests that grep for the token across the run directory.
- Evidence-first design: every arm claim is checked from artefacts (`took-effect.sh`), the arm id lives only under `meta/`, and the sandbox manifest is regenerated after toggles so in-sandbox integrity stays green.
- Thorough bats coverage with realistic stubs (stream-json CLI, docker launcher, mount library) and the trust-boundary self-test.

**Areas for Improvement:**
- Ship the generated fixtures and the regenerated manifest with the code that depends on them.
- Pin or check minimum tool versions (jq 1.7) where the scripts rely on them.
- Keep integrity heuristics strictly monotone: a change that silences false positives must not also silence deletions.

---

## Next Steps

1. Commit `evals/tests/fixtures/ablation-runs/runs/` (via `regen.sh`) and the regenerated `.claude/checksums.json`; re-run `bats evals/tests/ tests/unit/` and `tools/gen-checksums.sh --check`.
2. Fix the preflight count (present tracked files only) with a deletion test case.
3. Address the jq 1.7 dependency and the other observations at your discretion.
4. Update `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` walkthrough and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":7,"low":10},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-23T05:20:00Z"} -->
