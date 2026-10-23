# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (carries pr/PR.md)

---

## Overall Assessment

The change (sprint-258: mount integrity #1267, spend caps, the ablation suite and arms, the container pipeline executor, rows and took-effect evidence) is large, carefully documented and well tested in intent. The mount-integrity pieces (`tools/gen-checksums.sh`, `tools/check-manifest-paths.sh`, the `check-loa.sh` three-outcome classification, `spend.sh`) pass their new bats suites in this environment (26 of 26 across `spend.bats`, `gen-checksums.bats`, `check-manifest-paths.bats`, `check-loa-mount-scope.bats`). The pipeline executor is well structured and its secret-handling (env-shim, name-only `docker -e`, `<set>` masking) is sound.

The change cannot merge as is. The executor and the row builder use the jq keyword `label` as a `--arg` variable and as a shorthand object key, which is a syntax error on jq 1.6 (Debian bookworm, Ubuntu 22.04, and this container): every real `pipeline-run.sh` run dies in `run_phase` with `infrastructure_error`, and `ablation-row.sh` emits no row. Independently, the fixture run directories that `took-effect.bats` and `ablation-row.bats` copy in `setup()` are not part of the change, so the CI step the PR adds (`bats evals/tests/`) fails on checkout. A third high finding, raised by the companion dissent voice and confirmed by me, is that the new `not-mounted` outcome in `check-loa.sh` lets a deleted hook or rule symlink in a submodule mount pass integrity as informational.

Observed test results on a scratch copy of the head tree (exec bits restored per the diff's `100755` modes, `TMPDIR` off the noexec `/tmp`):

| Suite | Result |
|-------|--------|
| spend.bats, gen-checksums.bats, check-manifest-paths.bats, check-loa-mount-scope.bats | 26 / 26 pass |
| pipeline-run.bats | 13 pass, 39 fail (all `run_phase` cases; jq 1.6 keyword error) |
| took-effect.bats + ablation-row.bats | setup fails: `fixtures/ablation-runs/runs/` absent; after `regen.sh` the runs are themselves broken by the jq error |
| arm-toggles.bats, run-arms.bats, validate-suite.bats, freeze.bats | not run here (depend on `evals/fixtures/review-prs`, `evals/tests/fixtures/claude-stub.sh` and the smoke tasks, which are outside the change set) |

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Portability: jq keyword `label` used as a variable and shorthand key

- **HIGH** (confidence: high) `head/evals/harness/pipeline-run.sh:708` — `--arg label "$label"` with `$label` in the program is a jq 1.6 syntax error (`unexpected label, expecting IDENT or __loc__`); the argv capture fails under `set -e`, `on_exit` writes `status: infrastructure_error, reason: driver aborted (rc 3)`, and no phase ever runs.
**File:** `head/evals/harness/pipeline-run.sh:708` (also `:826` and `:882`, the phase record and the skip record use `$label` the same way)
**Issue:** `label` is a reserved word in jq. jq 1.6 rejects `$label` as a variable reference and `{name, label}` as a shorthand key; jq 1.7 relaxed this, which is why the author's host passed. Repro: `jq -n --arg label x '{label: $label}'` fails on jq 1.6 and `jq -n --arg lbl x '{label: $lbl}'` works. In this environment (jq-1.6) 39 of 52 `pipeline-run.bats` cases fail on exactly this message, and `regen.sh` produces fixture runs whose `pipeline.json` reads `"reason":"driver aborted (rc 3)","phases":[]`.
**Why This Matters:** The executor is the sprint's central deliverable; on a stock Debian/Ubuntu-22.04 host it cannot complete a single phase. The PR's own `Dockerfile.ablation` pins bookworm (jq 1.6) as the project's reference toolchain, and the repository's other scripts stay jq-1.6-clean.
**Required Fix:** Rename the jq variable (e.g. `--arg lbl "$label"` / `$lbl`) at `:703`, `:708`, `:816`, `:826`, `:881`, `:882`, and quote the key in the shorthand (`"label": .label`) at `head/evals/harness/ablation-row.sh:285`. Add a `jq -n '{label: 1}'`-style guard or a CI matrix entry on jq 1.6, so the harness is exercised on the toolchain its own image ships.

- **HIGH** (confidence: high) `head/evals/harness/ablation-row.sh:285` — `{name, label, session_id, …}` shorthand with the keyword `label` is a jq 1.6 syntax error (`unexpected '}', expecting ':'`); the `ROW=$(jq …)` assignment fails and no row is written for any run, so a batch under jq 1.6 has an empty `runs.jsonl`.
**File:** `head/evals/harness/ablation-row.sh:285`
**Issue:** Same root cause as above; confirmed by every `ablation-row.bats` row-building case failing here while the usage case passes.
**Required Fix:** Write the key explicitly: `"label": .label`.

### 2. Testing: fixture run directories missing from the change

- **HIGH** (confidence: high) `head/evals/tests/took-effect.bats:18` — `cp -a "$FX/runs" "$T/runs"` in `setup()` targets `evals/tests/fixtures/ablation-runs/runs/`, which no file of this change creates (`head.diff` has no `ablation-runs/runs/` entry; `regen.sh:86-89` describes them as tracked); every test in the file errors in `setup`.
**File:** `head/evals/tests/took-effect.bats:18`, `head/evals/tests/ablation-row.bats:19`, `head/.github/workflows/bats-tests.yml:212-223`
**Issue:** Both suites depend on ten committed run directories (`a0-build` … `refused-a4-review`) that `regen.sh` generates. They are referenced by `MANIFEST.json` (`arm_map`) and by the tests, but the change does not carry them. The new CI step `bats --print-output-on-failure evals/tests/` therefore fails on a fresh checkout: 21 + 18 cases error before any assertion.
**Why This Matters:** The took-effect rules and the §3.1 row schema are the sprint's evidence layer; without the fixtures none of their tests run, and the CI gate the PR adds is red on merge.
**Required Fix:** Commit `evals/tests/fixtures/ablation-runs/runs/` (after the jq fix above, regenerated with `regen.sh` on jq 1.6 so the fixtures are valid), or make `setup()` call `regen.sh` when `runs/` is absent. Verify `bats evals/tests/` passes from a clean clone.

### 3. Security: submodule-mount `not-mounted` outcome hides deleted links

- **HIGH** (confidence: medium) `head/.claude/scripts/check-loa.sh:71-72` — in a submodule mount, a manifest path absent from `.claude/` but present under `.loa/<path>` is counted as informational `not-mounted`; removing the symlink `.claude/hooks/safety/block-destructive-bash.sh` (or any rule or gate script) therefore leaves `check-loa.sh` printing `Integrity verified` with exit 0.
**File:** `head/.claude/scripts/check-loa.sh:71-72` (test `head/tests/unit/check-loa-mount-scope.bats:253-261` pins this behaviour)
**Issue:** The check cannot distinguish "never linked by design" from "linked, then deleted": both read as "exists upstream, absent locally". Deletion of a fence script via Bash is exactly the class of tampering the integrity check exists to surface (the Bash path is an accepted fence gap per CLAUDE.loa.md, so the detector is the only control). Raised independently by the companion dissent voice (DISS-C-001) and verified against the code.
**Why This Matters:** CWE-354 (improper validation of integrity check value): the integrity self-check reports clean after a security control is removed, in the mount mode #1267 is meant to make trustworthy.
**Required Fix:** Record what the mount linked (mount-submodule.sh already knows the set; write it beside the manifest or derive it from `.loa/.claude` paths that have a sibling link), and treat only paths outside that set as `not-mounted`; a path the mount linked that is now absent stays `Missing`. At minimum, fail when a path under `.claude/hooks/`, `.claude/rules/` or `.claude/scripts/` is absent, whatever the mount did.

---

## Observations

### 1. Correctness and robustness

- **MEDIUM** (confidence: high) `head/evals/harness/Dockerfile.ablation:82-84` — the comment says the materialiser writes the beads opt-out marker because `br` is absent from the image, but `init_sandbox_beads` runs on the HOST (`head/evals/harness/pipeline-run.sh:489`, `head/evals/harness/lib/sandbox-mount.sh:505-509`) and takes the host's `br` when on PATH: the sandbox gets a `.beads/` database and `beads=br` evidence while the container has no `br` binary.
**Suggestion:** In container mode set `LOA_EVAL_BR_BIN` to a non-existent path (or pass the executor mode into `init_sandbox_beads`) so the opt-out marker is written as the Dockerfile assumes.
**Benefit:** The recorded environment matches what the agent actually sees; no host-version leak into the sandbox.

- **MEDIUM** (confidence: medium) `head/.claude/scripts/preflight.sh:190` — `ACTUAL_COUNT` now counts `git ls-files` entries, which still list a tracked file deleted from the working tree, so preflight's count check no longer notices a deleted `.claude/` script (dissent DISS-001). `check-loa.sh` still catches it as `Missing`, so this is a loss of a secondary signal, not of the integrity check.
**Suggestion:** Filter the listing with `[[ -f ]]` (as `tools/gen-checksums.sh:96` does) before counting.

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-row.sh:224-228` — every input (both envelopes, the whole MODELINV ledger wrapped with line numbers, pipeline.json) is passed by `--argjson`; a single argv string is capped at 128 KiB on Linux, and a full review+audit run with two voices and repairs can exceed it, so `jq` fails with E2BIG and the largest runs lose their row (dissent DISS-C-004).
**Suggestion:** Pass files with `--slurpfile` / `--rawfile`.

- **MEDIUM** (confidence: medium) `head/evals/harness/pipeline-run.sh:857` — exit 137 with `timed_out=false` is classified `interrupted` (exit 4), which the suite's `exclusion.statuses` drops pairwise; under `--memory 4g` an OOM-killed phase also exits 137 and is the agent's account, so OOM runs vanish from the analysis instead of counting as `agent_error`.
**Suggestion:** In container mode read the container's `OOMKilled` state (`docker inspect` before `--rm` removes it, or drop `--rm` and remove explicitly) and classify OOM as `agent_error`.

- **MEDIUM** (confidence: medium) `head/evals/harness/lib/sandbox-mount.sh:513` — `init_sandbox_beads` executes the sandbox's own `.claude/scripts/beads/update-beads-state.sh` on the host (with `PROJECT_ROOT=$ws`), which contradicts the trust-boundary statements at `:75` and `:97-99` ("no harness script sources .claude/ code") and runs code from the tree under evaluation outside the container.
**Suggestion:** Write the opt-out marker JSON directly from the library (it is a small fixed document), or run the script inside the container as part of the first phase.

- **MEDIUM** (confidence: high) `head/evals/harness/pipeline-run.sh:687` — `--tmpfs /tmp:rw,size=1g` mounts `/tmp` with docker's defaults `nosuid,nodev,noexec` (confirmed in this container: `findmnt /tmp` → `rw,nosuid,nodev,noexec`); anything in the sandbox that executes a file under `/tmp` (a bats run started without `TMPDIR`, a test fixture that writes a helper script to `/tmp`) fails with `Permission denied`. The driver's `TMPDIR=/workspace/.eval/tmp` mitigates the common path but not hard-coded `/tmp`.
**Suggestion:** Add `exec` to the tmpfs options (`--tmpfs /tmp:rw,exec,size=1g`) or document the constraint for task authors.

- **MEDIUM** (confidence: medium) `head/evals/tests/pipeline-run.bats:68` — the executor is exercised only with the stub mount library; no test drives `pipeline-run.sh` against the real `lib/sandbox-mount.sh`, so the integration contract (evidence routed to `ARM_EVIDENCE_FILE`, `write_sandbox_grimoire`'s review-catch `PR.md` lookup, `regen_sandbox_manifest`'s inline path when `.claude/` is git-excluded) is unverified end to end. GOAL-DRIVEN: one smoke case with the real library would catch a contract drift.

### 2. Minor

- **LOW** (confidence: high) `head/evals/harness/pipeline-run.sh:50` — the header says `snapshots/index.json` carries `{IMPLEMENT|FIX1|FIX2: commit}`; the code at `:788` lowercases the keys (`implement`, `fix1`) and `ablation-row.sh:324` reads them lowercase. Fix the comment.
- **LOW** (confidence: medium) `head/evals/harness/pipeline-run.sh:840` — after `gate_recovered` resets `rc=0` (`:805`), the record keeps `is_error: true` from `$result.is_error` while `exit: 0`; readers that key on `is_error` see a failed phase in a completed run. Set `is_error` from the recovered state.
- **LOW** (confidence: high) `head/evals/harness/pipeline-run.sh:586` — pricing executes `.claude/adapters/loa_cheval/metering/pricing.py` from the harness root, which the header's "No .claude/ code is sourced" (`:125`) and the trust-boundary test (`pipeline-run.bats:257`, which only greps `source`) do not cover. It is the harness's own trusted copy, so the exposure is small; say so in the comment or move the CLI under `evals/`.
- **LOW** (confidence: medium) `head/evals/harness/pipeline-run.sh:506` — the arm-id leak grep scans the whole mounted `.claude/` tree and `.loa.config.yaml`; any future framework file that mentions an arm id refuses every run of that arm as `infrastructure_error`. Today the source tree has no hit. Consider scoping the scan to the fixture and grimoire paths, or excluding `.claude/`.
- **LOW** (confidence: high) `head/evals/harness/fingerprint.sh:54` — a per-operator path (`$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats`) is hard-coded as the bats fallback; and `:62` folds stderr into the version line, so update nags change the fingerprint (dissent DISS-C-006). Drop the personal path and capture stdout only.
- **LOW** (confidence: medium) `head/.claude/defaults/model-config.yaml:140-146` — `gpt-6.1-sol` pricing is a copied placeholder but MODELINV rows record `pricing_source: config` like a confirmed rate (dissent DISS-C-003). The bead at sprint close covers it; a `price_date`/`placeholder: true` marker would make the rows honest meanwhile.
- **LOW** (confidence: low) `head/evals/harness/validate-suite.sh:295` — `review_catch.fixture` must resolve under `evals/fixtures/`, while `pipeline-run.sh:441` also accepts task-dir and suite-root relative paths (the bats fixture `rc-01` uses `prs/pr-x`). The two readers disagree on where a review-catch fixture may live; the safe direction (validator stricter) holds, but a suite author will be surprised.

### 3. Complexity

`run_phase` in `head/evals/harness/pipeline-run.sh:634-868` is 235 lines with argv assembly, launch, watchdog, record and accounting in one function; it is readable because of the section comments, but splitting the record step (`:753-849`) out would make the jq failure above a one-line fix site. No duplicate blocks beyond the two `plan_phases` copies (`pipeline-run.sh:215-227` and `took-effect.sh:96-106`), which are intentionally parallel. SIMPLICITY: Lean already apart from that. Ship after the fixes.

---

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and the named sidecar `adversarial-rejected-review.jsonl` has zero rows.

## Cross-Model Observations

Two voices completed (primary `gpt-5.5-pro` via `codex-headless`, companion `claude-headless`, `counted_as: independent_voice`), 7 findings:

- DISS-001 (preflight count) — real, counted above as MEDIUM (secondary signal only).
- DISS-C-001 (not-mounted hides deletions) — real, counted above as HIGH.
- DISS-C-002 (`return 0` in `check_integrity`) — not a defect: `fail` increments `FAILURES` (`head/.claude/scripts/check-loa.sh:36`) and `main` exits 1 on a non-zero counter (`:604-605`); verified by `check-loa-mount-scope.bats` CM-2/CM-3 passing here.
- DISS-C-003 (placeholder pricing) — LOW above.
- DISS-C-004 (`--argjson` E2BIG) — MEDIUM above.
- DISS-C-005 (`ms(ts)` fragility) — not counted: `started`/`finished` are always written by the driver in `%Y-%m-%dT%H:%M:%SZ` and `wall_clock_ms` guards null.
- DISS-C-006 (fingerprint stderr noise, hard-coded path) — LOW above.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Report each defect with file and line | Done | See Changes Required and Observations |
| Merge verdict | CHANGES_REQUIRED | Three high findings |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (AWS_BEARER_TOKEN_BEDROCK travels by env/name only; `<set>` in captures — verified `pipeline-run.sh:631-632, 694, 705-706`)
- [x] Input validation at trust boundaries (arm id regex, task id regex, sprint label regex, fixture path rule, leak guards)
- [ ] Integrity check soundness — see Changes Required §3
- [x] No injection paths found (no `eval`, no variable `source` lines; `python3 -I` for every embedded script)
- [x] Error messages do not leak the bearer token (tested by `pipeline-run.bats:703-730`)

---

## Code Quality Summary

**Strengths:**
- Secret handling through the env shim and `docker -e NAME` is careful and tested.
- Every new script has a usage header, exit-code table and a bats file; refusals are explicit and recorded.
- `tools/gen-checksums.sh` and `check-manifest-paths.sh` are small, NUL-safe and pass all cases.

**Areas for Improvement:**
- Run the harness tests on the toolchain the project's own image pins (jq 1.6) before merge.
- Commit generated fixtures the tests depend on, or generate them in `setup()`.
- Keep the trust-boundary claims in headers true to the code (`.claude/` scripts executed by the host).

---

## Next Steps

1. Fix the jq keyword usages in `pipeline-run.sh` and `ablation-row.sh`; run `bats evals/tests/pipeline-run.bats` on jq 1.6.
2. Regenerate and commit `evals/tests/fixtures/ablation-runs/runs/`; run `bats evals/tests/` from a clean clone.
3. Decide the `not-mounted` semantics for linked-then-deleted paths in `check-loa.sh` and update CM-1.
4. Update `grimoires/loa/a2a/sprint-1/reviewer.md` and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":7,"low":7},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-23T03:35:00Z"} -->
