# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (carries pr/PR.md)

---

## Overall Assessment

The change under review is the sprint-258 PR (72 files): mount-integrity tooling for #1267 (`tools/gen-checksums.sh`, `tools/check-manifest-paths.sh`, `tools/fresh-mount-proof.sh`, the `check-loa.sh` / `preflight.sh` edits and a new CI gate), the `gpt-6.1-sol` catalog entry (KF-044), and the cycle-130 ablation harness (`pipeline-run.sh`, `lib/sandbox-mount.sh`, `ablation-row.sh`, `took-effect.sh`, `validate-suite.sh`, `freeze.sh`, `spend.sh`, `fingerprint.sh`, `run-arms.sh` spend cap and screen, `Dockerfile.ablation`, the suite file, fixtures and bats).

The ablation harness is careful work: the executor's environment allowlist and descriptor shim, the secret-by-name docker forwarding, the leak guards, the arm-evidence trail and the fixture-driven bats are all verified by reading the code against the tests (I could not execute the bats here: the workspace holds only the PR's touched files). `model-config.yaml.checksum` matches the new catalog bytes (sha256 verified). `CLAUDE.loa.md`'s unchanged header hash is correct (the hash covers the body only).

Two findings block the merge, both in the FR-1 integrity work:

1. The PR edits 16 tracked `.claude/` paths but does not regenerate `.claude/checksums.json`, and simultaneously adds a CI step that runs `tools/gen-checksums.sh --check` against that committed manifest. The gate the PR introduces fails on the PR's own head, and `check-loa.sh` will report every edited path as Tampered on a fresh clone.
2. `check-loa.sh` now treats any manifest path that is absent from `.claude/` but present under `.loa/` as informational "not-mounted" and exits 0. Because mount-submodule.sh links whole directories and copies hooks, deleting a linked directory symlink or a copied hook is now invisible to the integrity check.

The adversarial dissent (gpt-5.5-pro primary, claude-headless companion, both completed) independently raised finding 1 (DISS-C-004), finding 2 (DISS-C-001) and two `preflight.sh` regressions (DISS-001 BLOCKING, DISS-C-002) which I confirmed in the code and record below.

Process note: the implementation report (pr/PR.md) is a title line only; it carries no `## AC Verification` walkthrough, which the review protocol lists as an automatic CHANGES_REQUIRED on its own.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Integrity manifest not regenerated; the new CI gate fails on this head

- **HIGH** (confidence: high) `head/.github/workflows/bats-tests.yml:178` — the new step runs `bash tools/gen-checksums.sh --check`, which regenerates the manifest from the tracked `.claude/` tree and exits 1 on any drift against the committed `.claude/checksums.json`; this PR changes the bytes of 16 tracked `.claude/` paths (`head/.claude/defaults/model-config.yaml:122`, `head/.claude/defaults/model-config.yaml.checksum:1`, `head/.claude/scripts/check-loa.sh:56`, `head/.claude/scripts/preflight.sh:182`, `head/.claude/scripts/generated-model-maps.sh:16`, `head/.claude/loa/CLAUDE.loa.md:1`, the ten `bridgebuilder-review/dist` and `resources` generated files) and `.claude/checksums.json` is not in the diff.
**File:** `head/.github/workflows/bats-tests.yml:175-178`
**Issue:** `tests/unit/check-manifest-paths.bats` MP-6 ("the committed manifest of this repository passes") establishes that the manifest is committed. A committed manifest cannot match both the base and the head bytes of `model-config.yaml`, so after this merge `gen-checksums.sh --check` prints `DRIFT` for every edited path (exit 1) and the CI job is red. Downstream, `check-loa.sh` `check_integrity` compares the same manifest and reports `Tampered:` for each of those paths on a clean checkout, setting drift and exit 1. The companion dissent raised the same scenario (DISS-C-004).
**Why This Matters:** The PR's stated goal is to make fresh mounts pass integrity (#1267). As landed it does the opposite for every mount of this commit, and the gate added to prevent exactly this class of drift fails on the commit that adds it. `tools/fresh-mount-proof.sh --worktree` (which the PR ships) would have shown this.
**Required Fix:** Run `bash tools/gen-checksums.sh` and commit the regenerated `.claude/checksums.json` in this PR; run `tools/fresh-mount-proof.sh --worktree` and paste its summary line into the report. Add the missing test the bats header already names (`head/tests/unit/gen-checksums.bats:9` refers to "GC-8" reading the live manifest, but no GC-8 exists): `gen-checksums.sh --check` on `$ROOT` exits 0.
**Reference:** CWE-354 (Improper Validation of Integrity Check Value); SDD §5.1/§5.2 as cited in the tool headers.

### 2. `check-loa.sh` integrity check is fail-open for every unlinked path in a submodule mount

- **HIGH** (confidence: medium) `head/.claude/scripts/check-loa.sh:75` — `elif [[ "$submodule_mount" == "true" && -f ".loa/${file}" ]]; then not_mounted=$((not_mounted + 1))` classifies any manifest path missing from `.claude/` as informational when `.loa/.claude` is a directory and the upstream copy exists; `rm .claude/scripts` (a directory symlink the mount creates, mount-submodule.sh `MANIFEST_DIR_SYMLINKS`) or deleting a copied hook under `.claude/hooks/` (the #842 copy set) now prints one `not-mounted: N path(s)` line and exits 0 where the base reported `Missing:` and failed.
**File:** `head/.claude/scripts/check-loa.sh:47-87`
**Issue:** The rule "absent locally, present upstream ⇒ by design" is not checked against what the mount actually declared. mount-submodule.sh owns an authoritative link manifest (`get_symlink_manifest`, directory, file, skill, command and agent symlinks, plus the hooks copy set), so the set of paths a mount deliberately does not link is knowable. Without consulting it, deletion of a linked gate, hook or script directory is indistinguishable from a deliberately unlinked path. `tests/unit/check-loa-mount-scope.bats` CM-1 codifies the permissive behaviour but no test covers the deleted-link case. The companion dissent raised this as DISS-C-001 with the same failure path.
**Why This Matters:** `check_integrity` is the mechanical fence CLAUDE.loa.md relies on (implement-gate, zone guards and hooks live under `.claude/`). The change converts a fail-closed check into fail-open for the whole class of "linked thing removed", which is precisely the tamper an integrity check exists to catch. The fix is bounded: the information needed is already produced by the mount.
**Required Fix:** Count a path as not-mounted only when it is outside the mount's declared link set (read `get_symlink_manifest` from the submodule, or a link manifest the mount writes at mount time, e.g. alongside `.loa-version.json`); a path under a declared directory link, a declared file link or the hooks copy set that is absent stays `Missing` (fail). Add a CM case: remove a linked directory symlink and assert `FAILURES` is non-zero.
**Reference:** CWE-754 (Improper Check for Unusual or Exceptional Conditions); CLAUDE.loa.md "Mechanical stack: implement-gate.sh …".

---

## Observations

### 1. `preflight.sh` count check regressions (from the dissent, confirmed)

- **MEDIUM** (confidence: high) `head/.claude/scripts/preflight.sh:190` — `ACTUAL_COUNT=$(git -C "${MANIFEST_TREE}" ls-files -- .claude …)` counts index entries, which `git ls-files` keeps listing after a tracked file is deleted from the working tree; deleting a System Zone script leaves the count equal to the manifest's and preflight no longer emits the file-count mismatch the base implementation did (dissent DISS-001, marked BLOCKING by the primary voice; I rate it medium because the preflight count is an advisory warning and `check-loa.sh` still reports the deletion as Missing).
**File:** `head/.claude/scripts/preflight.sh:188-192`
**Suggestion:** Count tracked paths that exist: pipe `git ls-files -z -- .claude` through a `test -f` filter (the same rule `gen-checksums.sh` applies when it skips a tracked path that is not a file), so a deletion lowers the count.
**Benefit:** Keeps the one signal preflight had for a damaged tree.

- **MEDIUM** (confidence: high) `head/.claude/scripts/preflight.sh:195` — `if [[ "${ACTUAL_COUNT}" -eq 0 ]]` takes the legacy `find` count only when nothing under `.claude/` is tracked; a standard-mode downstream that commits a few `.claude/` files (settings, a command or two) with the vendored tree gitignored gets a small tracked count that never equals the manifest, so every preflight prints `System Zone integrity check: file count mismatch` where the base matched (dissent DISS-C-002).
**File:** `head/.claude/scripts/preflight.sh:188-196`
**Suggestion:** Decide the counting rule by how the manifest was produced (e.g. `jq '.generator'` or the presence of a tracked `.claude/checksums.json`), not by whether the tracked count happens to be zero; or count `git ls-files` ∪ on-disk files minus the manifest/overrides exclusions.
**Benefit:** Avoids a permanent false warning that trains operators to ignore the signal.

### 2. Container image

- **MEDIUM** (confidence: medium) `head/evals/harness/Dockerfile.ablation:19-20` — `FROM rust:1-bookworm AS brbuild` / `RUN cargo install beads_rust --version 0.2.6 … || cargo install …` is a stage nothing `COPY --from`s, and the file's own comment at `head/evals/harness/Dockerfile.ablation:82` says beads_rust 0.2.6 is not on crates.io, so both `cargo install` attempts fail; under BuildKit the unreferenced stage is skipped, under the classic builder (`DOCKER_BUILDKIT=0`, older daemons) the build fails at line 20.
**File:** `head/evals/harness/Dockerfile.ablation:19-20`
**Suggestion:** SIMPLICITY[delete]: remove the `brbuild` stage (the "No beads in the image" decision at line 82 already stands).
**Benefit:** The image builds under either builder and the file stops contradicting itself.

### 3. Tests that read files this PR does not ship

- **MEDIUM** (confidence: low) `head/evals/tests/freeze.bats:99` — FZ-6 runs `freeze.sh --smoke --allow-partial --check` on the default root `grimoires/loa/evals/ablation-2.0`, and `head/evals/tests/fixtures/ablation/suite-lib.bash:10` copies every fixture task from `grimoires/loa/evals/ablation-2.0/smoke/`; `head/evals/tests/arm-toggles.bats:442` and `:464` and `head/evals/tests/validate-suite.bats:31` read the same smoke tasks and `MANIFEST.sha256`. None of those paths is in the diff. If they are not already committed on the base branch, the new CI step at `head/.github/workflows/bats-tests.yml:221` fails every freeze, validate-suite and AT-22/AT-24 case.
**File:** `head/evals/tests/freeze.bats:98-101`
**Suggestion:** State in the report where the smoke tasks and `MANIFEST.sha256` were landed (commit), or add them to this PR.
**Benefit:** The CI step the PR adds is only green if its inputs are in the tree.

### 4. Complexity

- **MEDIUM** (confidence: high) `head/evals/harness/pipeline-run.sh:634-868` — `run_phase` is about 230 lines (argv/env assembly, launcher, watchdog loop, record, snapshot, verdict, accounting and the exit decision in one body); `head/evals/harness/lib/sandbox-mount.sh:255-375` `apply_arm_toggles` is about 120 lines of case arms. SIMPLICITY[shrink]: split `run_phase` into `build_launcher`, `watch_phase`, `record_phase` and `decide_phase`; move each toggle arm into `_sm_toggle_<name>`. Over-engineering pass otherwise: the dead `brbuild` stage (2 lines), `in_container_path` at `head/evals/harness/pipeline-run.sh:618` (unused, 1 line) and `bad=0` at `head/evals/harness/ablation-row.sh:93` (never read). net: -6 lines possible.

### 5. Low

- **LOW** (confidence: high) `head/evals/harness/pipeline-run.sh:85` — header says the image runs "codex 0.137.0 by Dockerfile.ablation" while `head/evals/harness/Dockerfile.ablation:25` pins `CODEX_VERSION=0.162.1`; the fingerprint/image-digest rationale quotes the wrong version.
- **LOW** (confidence: high) `head/tests/unit/gen-checksums.bats:9` — the header names GC-8 ("the live manifest is only read by GC-8") but the file ends at GC-7; the one assertion CI relies on (the committed manifest passes `--check`) has no test. GOAL-DRIVEN: add it (see Changes Required 1).
- **LOW** (confidence: high) `head/evals/harness/took-effect.sh:112` — `rule_no_system_prompt` can never fail under `pipeline-run.sh`, which passes `--append-system-prompt-file` for no arm (the mounted arms get their prompt surface via the sandbox `CLAUDE.md`); as A0's took-effect evidence it does not discriminate A0 from A1. Consider asserting instead that A0's argv has no `--setting-sources`-visible `CLAUDE.md` (already covered by `no_dot_claude`) and drop the rule, or document that it is argv-only evidence.
- **LOW** (confidence: medium) `head/evals/harness/ablation-row.sh:220` — `select(.path | test("(^|/)\\.claude/"))` also matches writes to the user-level `/home/evaluser/.claude/…` (the per-run HOME), which is not the Loa System Zone; such a write is recorded as a `zone_violations.dot_claude_writes` entry (dissent DISS-C-003). Anchor the test to the sandbox root (`^(/workspace/|\./)?\.claude/` or the captured cwd).
- **LOW** (confidence: medium) `head/evals/harness/pipeline-run.sh:441` vs `head/evals/harness/validate-suite.sh:229` — the executor resolves `fixture` relative to the task directory first, the validator only relative to the suite root; a task declaring `fixture: fixture` runs under pipeline-run but never validates (the bats fixture `tasks/bf-01/task.yaml` uses `fixture: fx`, which only the executor accepts). Make both read the same rule.
- **LOW** (confidence: high) `head/evals/harness/validate-suite.sh:240` — `"/" in crit` flags any criterion containing "and/or", "read/write" or a fraction as "names a path or file"; restrict to a path-like token (`\S+/\S+`).
- **LOW** (confidence: high) `head/evals/harness/fingerprint.sh:54` — the fallback bats path `$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats` is one operator's dotfiles layout baked into a shipped script; fall back to `absent` and let `--bats-bin` / `LOA_EVAL_BATS_BIN` name it.
- **LOW** (confidence: medium) `head/evals/harness/pipeline-run.sh:586` — `price_for` executes `$REPO_ROOT/.claude/adapters/loa_cheval/metering/pricing.py` while the header at `head/evals/harness/pipeline-run.sh:125` says no `.claude/` code is run under the eval.yml trust boundary; the bats trust-boundary case only greps for `source`/`eval`, so this is undetected. Either exempt it explicitly in the header (it is the harness tree's own copy) or read prices from `LOA_EVAL_PRICING_JSON` / a vendored table.
- **LOW** (confidence: high) `head/.claude/defaults/model-config.yaml:144` — `gpt-6.1-sol` pricing is a copied placeholder (documented, bead at sprint close); fine as a tracked follow-up, noted so it is not forgotten.
- **LOW** (confidence: high) `head/evals/harness/spend.sh:39` — the default `--since` is the cycle-130 kickoff instant hard-coded in a shipped script; documented in the header, acceptable, but it will silently be wrong for the next cycle. Prefer reading it from the suite file (`caps.since` or similar).

---

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and the named sidecar `grimoires/loa/a2a/sprint-1/adversarial-rejected-review.jsonl` has zero rows.

## Cross-Model Observations

Dissent run: `adversarial-review.sh --type review --sprint-id sprint-1 --diff-file pr/head.diff --json`; status `reviewed`, primary gpt-5.5-pro, companion claude-headless (`independent_voice`), `verdict_quality.voices_planned` 2 / `voices_succeeded` 2. Five findings, all triaged above: DISS-001 (preflight deletion blind spot, Observations 1, confirmed; demoted from BLOCKING to medium with rationale), DISS-C-001 (check-loa fail-open, Changes Required 2, confirmed), DISS-C-002 (preflight partial tracking, Observations 1, confirmed), DISS-C-003 (dot_claude_writes regex, Observations 5, confirmed low), DISS-C-004 (manifest not regenerated, Changes Required 1, confirmed and raised to high because the PR's own CI gate fails).

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | regenerated `.claude/checksums.json`; a bounded not-mounted rule in `check-loa.sh`; an AC Verification walkthrough in the report |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict

| Criterion | Status | Notes |
|-----------|--------|-------|
| Defects reported with file and line | Pass | every finding above cites `head/<path>:<line>` |
| Merge verdict given | Pass | CHANGES_REQUIRED (two high findings) |
| `## AC Verification` present in the implementation report | Fail | pr/PR.md is a title line; no walkthrough (automatic CHANGES_REQUIRED per protocol) |

---

## Documentation Verification

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exists; verified by hand. The diff carries no CHANGELOG entry and no reference-doc update for the three new `tools/*.sh` entry points, the new CI gate, the `gpt-6.1-sol` catalog entry or the KF-044 known-failure record it cites; the shipped scripts are self-documenting in their headers. Non-blocking here (the sprint is the PR itself and the repository's CHANGELOG convention is outside the review inputs), but the report should name where KF-044 and the Sprint 258 decisions (DEC-0490 etc.) were recorded.

---

## Security Checklist

- [x] No hardcoded secrets or credentials (codex `auth.json` is copied into the per-run HOME for the run's duration, mode 0700, deleted on exit and interrupt; documented and tested)
- [x] Input validation and sanitization present (arm ids, sprint labels, task ids, USD amounts, suite paths; leak guards on prompts and sandbox)
- [x] Authentication/authorization correct (Bedrock bearer token travels by environment name only; argv capture records `<set>`; tests assert the value appears nowhere under the run dir)
- [x] No SQL/XSS injection vulnerabilities (n/a; jq/yq programs take data via `--arg`/`strenv`)
- [ ] Integrity check correctness: see Changes Required 1 and 2 (manifest drift; fail-open not-mounted class)
- [x] Error messages don't leak sensitive data

---

## Code Quality Summary

**Strengths:**
- The executor's process hygiene is unusually thorough: exact environment allowlist via a python `-I` exec shim, descriptors above 2 closed, secrets by name to docker, hermetic git for sandbox commits, and tests that prove each property (`pipeline-run.bats` env/descriptor/bedrock cases).
- Evidence-first design: arm toggles are verified after application and refused (exit 2) when they cannot take effect; `took-effect.sh` reads only artefacts the run produced; the arm id never enters the sandbox.
- `gen-checksums.sh` and `check-manifest-paths.sh` are small, NUL-safe and chunked; `fresh-mount-proof.sh` is the right proof tool for #1267.

**Areas for Improvement:**
- Ship the proof: the PR adds `fresh-mount-proof.sh` and a CI gate but does not show either passing on its own head.
- Keep the integrity check fail-closed; derive "not-mounted" from the mount's declared link set.
- `run_phase` and `apply_arm_toggles` need splitting before the next sprint grows them further.

---

## Next Steps

1. Regenerate and commit `.claude/checksums.json`; run `tools/fresh-mount-proof.sh --worktree` and `tools/gen-checksums.sh --check`; add the GC-8 test.
2. Bound `check-loa.sh`'s not-mounted rule to the mount's declared link set and add the deleted-link CM case.
3. Address the `preflight.sh` count rule (deleted tracked files; partially tracked downstreams).
4. Remove the dead `brbuild` stage; fix the codex version in the pipeline-run header.
5. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` walkthrough and the location of the smoke tasks / `MANIFEST.sha256`.
6. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":5,"low":10},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-23T07:17:01Z"} -->
