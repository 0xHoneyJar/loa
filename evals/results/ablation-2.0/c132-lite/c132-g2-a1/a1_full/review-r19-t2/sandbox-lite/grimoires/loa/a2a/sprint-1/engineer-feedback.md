# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description `pr/PR.md`)

---

## Overall Assessment

The change (sprint-255: guard register with origin and yield, pre-registered control arms on a record corpus, task kinds, path-scoped rule files) is well built. The 81 files are coherent, every new script carries a bats suite at its declared seam, inputs are validated at the trust boundaries (hook commands are parsed against one canonical schema, ids are pattern-checked, no command text or cwd reaches any generated output, the seed script redacts secret shapes and runs the no-secrets scanner over everything it writes), and the control-arm harness refuses to compare across skewed models or sources.

I ran the PR's suites in a scratch root assembled from this workspace's framework plus the PR head files (the repository's `tools/`, `evals/fixtures/review-prs/` corpus, `sandbox.sh`, `grade.sh` and `no-secrets.sh` are not part of the change and were absent, so EA-8/EA-9, SC-1…SC-5, RG-16/RG-17, BF-4 and SEAMS-9 could not be exercised here). Everything else passed: GO-1…GO-15 except GO-9, GY-1…GY-11, KINDS-1…KINDS-11, CR-1…CR-6, RP-1…RP-6, LSG-1…LSG-3, SEAMS-1…SEAMS-12 except SEAMS-9, AT-1…AT-11, AR-1…AR-7, EA-1…EA-7, EA-10…EA-12, BF-1…BF-3, BF-5…BF-13, RG-1…RG-15, RG-18…RG-28, PB-9, PB-10.

One finding blocks the merge: the tracked structural register that the new CI drift gate compares against is not in the change, so the gate (and GO-9) fail on the PR as submitted. Two medium findings concern a control-arm toggle that can silently run as its baseline and a `source` of an external library that can end `guard-yield.sh` with exit 0 before it writes anything. The rest are low.

The implementation report is the PR title only: there is no `## AC Verification` walkthrough. Under this skill that alone forces CHANGES_REQUIRED; it is not counted as a code finding below.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. CI gate / missing tracked artefact

- **HIGH** (confidence: high) `head/.github/workflows/bats-tests.yml:159` — the new step `bash .claude/scripts/guard-yield.sh --check` fails on this PR as submitted: the register it compares against, `grimoires/loa/guards.md`, is not part of the change and `.gitignore` does not ignore it (`git check-ignore` returns nothing), so `--check` exits 1 at `head/.claude/scripts/guard-yield.sh:422` (`[[ ! -f "$OUT" ]]` → "drift: grimoires/loa/guards.md differs from the generated register"). `head/tests/unit/guard-origins.bats:120` (GO-9, `run bash "$GY" --check`) fails identically.
**File:** `head/.github/workflows/bats-tests.yml:159`, `head/.claude/scripts/guard-yield.sh:422`, `head/tests/unit/guard-origins.bats:120`
**Issue:** `guard-yield.sh` describes `grimoires/loa/guards.md` as "tracked, STRUCTURAL ONLY … --check gates it" (header, lines 19-20) and `hooks-reference.md:168` points readers at it, but the file is absent from the 81-file change. Reproduced in a scratch root built from this workspace's framework plus the PR head: `--check` → exit 1 before generation; after `guard-yield.sh --hooks-table` it writes a 95-guard register, `--check` → exit 0 ("in sync (95 guards)") and `git status` lists `grimoires/` as untracked, confirming the file must be committed.
**Why This Matters:** The PR turns the drift gate on in CI and the gate is red on the PR's own tree. Every downstream consumer of the register (`/loa`'s Guards line reads the file, `hooks-reference.md` links it) sees "no register" until someone regenerates and commits it.
**Required Fix:** Run `.claude/scripts/guard-yield.sh --hooks-table` on the PR tree and commit `grimoires/loa/guards.md`. Add it to the tracked-state list that `validate-gitignore-state.sh` checks (and an explicit `!grimoires/loa/guards.md` next to the other tracked `grimoires/loa/` exceptions if a future pattern could swallow it). Re-run `tests/unit/guard-origins.bats` to confirm GO-9 passes.

---

## Observations

### 1. Control arms (evals harness)

- **MEDIUM** (confidence: high) `head/evals/harness/execute-agent.sh:266` — the `rule_files` toggle records `removed: none present` and returns 0 when neither `stash-safety.md` nor `skill-invariants.md` exists in the sandbox, so the `no_rule_files` arm runs as its baseline. Reproduced: a prompt tree whose `.claude/rules/` holds only `zone-state.md` → exit 0, `executor.json` `arm_evidence.rule_files = "removed: none present"`. This contradicts the contract at `head/evals/harness/execute-agent.sh:65` ("a toggle that cannot take effect is exit 2 (an arm never silently runs as its baseline)"), which the other three toggles honour (AT-9 proves it for `karpathy_block` and `audit_delta_instruction`).
**Suggestion:** After the loop, `[[ -n "$gone" ]] || { echo "ERROR: rule_files toggle: neither rule file present in the sandbox" >&2; return 2; }`, and add the case to AT-9.
**Benefit:** A renamed rule file or a prompt tree without `.claude/rules/` can no longer produce a "no recall loss" verdict for a control that was never removed.

- **LOW** (confidence: medium) `head/evals/harness/run-arms.sh:314` — `is_transport_failure` greps `5[0-9][0-9] ` over the agent's stderr and result JSON; any three-digit number from 500 to 599 followed by a space (a line count, a token figure in a message) classifies an ordinary executor failure as a transport failure, costing a `--retry-wait` sleep and a second attempt and recording `attempts: 2`. Anchor the pattern to an HTTP-status context (`(status|HTTP|error)[^0-9]{0,8}5[0-9][0-9]\b`).

### 2. Guard register and yield

- **MEDIUM** (confidence: medium) `head/.claude/scripts/guard-yield.sh:470` — `source "$HEREDOC_LIB" 2>/dev/null` runs an external library inside the `set -euo pipefail` main shell with its diagnostics discarded. The library this line is written for (the FR-6 classifier, `.claude/scripts/lib/heredoc-classifier.sh`, a later cycle-129 sprint) sources the fence hook with `BDB_LIB_ONLY=1`; the fence shipped in this PR has no lib-only guard (no `BDB_LIB_ONLY` in `head/.claude/hooks/safety/block-destructive-bash.sh`) and, sourced with an empty stdin, reaches its `exit 0` at line 177. That `exit` ends `guard-yield.sh` with status 0 after `--check` (line 419) and before the yield join and `install_file` (line 610): `guards.md`, `guard-yield.md` and `guard-yield.json` are never written and nothing is printed. Reproduced in the scratch root with that library present: GY-1…GY-4, GY-6, GY-7 and GY-10 fail with "guard-yield.json: No such file"; with the library absent (this PR's repository state) all eleven pass. The trigger is not in this change, so the confidence is medium; the hazard is this line's design.
**Suggestion:** Probe the library in a subshell before sourcing it — `( source "$HEREDOC_LIB" </dev/null && declare -F heredoc_nonexec ) >/dev/null 2>&1 || HEREDOC_LIB=""` — or call `heredoc_nonexec` through `bash -c` per row; and land the fence's `BDB_LIB_ONLY` early-return in the same change as the library.
**Benefit:** A yield run can never exit 0 having written nothing.

- **LOW** (confidence: medium) `head/.claude/scripts/guard-yield.sh:510` — `$hookid` keys hook rows by script basename (`.rel | split("/") | last`), because audit rows carry only `hook: "<basename>"`. Two registered hooks sharing a basename in different directories collapse to whichever `from_entries` keeps last and the other's blocks are misattributed. No collision exists today (30 registrations, unique basenames); a comment or a duplicate-basename check in the cross-check section would keep it that way.

- **LOW** (confidence: medium) `head/.claude/scripts/guard-yield.sh:502` — `outside_repo` compares the audit row's `cwd` (the hook's logical `$PWD`) against `pwd -P` of the root and main worktree. On a checkout reached through a symlinked path every live block classifies as "outside the repository" and therefore as a likely false positive, deflating `real_blocks_30d` to zero. Compare against both the logical and physical root, or `realpath` the row's cwd when it exists.

- **LOW** (confidence: high) `head/.claude/scripts/guard-yield.sh:519` — the burst rule drops every block row in any UTC minute holding ten or more, whatever its cwd. A live session that trips the fence ten times in a minute (a retry loop on a blocked command) vanishes from the yield as "replay". The header documents the heuristic; noting it here because `replay_rows_by_rule.burst` is the only trace.

- **LOW** (confidence: low) `head/.claude/data/floor.yaml:46` — (from the cross-model dissent, DISS-C-001, triaged as a design note, not a defect) sixteen of the twenty-one floor guards are fence rows, and their behaviour is pinned by `floor_corpus` rows (FS-2), the settings registration (FS-3) and the ordered call-site list (FS-4), not by the hook's bytes. A regex relaxation inside the fence that keeps every call site and corpus row passes FS-1…FS-4; the corpus pin only bites if `tests/fixtures/fence-corpus/run-corpus.sh` runs in CI, which this change does not show. Either add the corpus runner to `bats-tests.yml` or state in `floor.yaml` that fence rows are behaviour-pinned, not byte-pinned.

- **LOW** (confidence: medium) `head/.claude/data/floor.yaml:41` — (dissent DISS-C-003, triaged) `floor_keys` lists `destructive_command_guard.*`, but nothing in this change reads that namespace (the head fence has no such key) and the fence row in `guard-origins.yaml:162` says `knob: none`. The key is a forward reference to a later sprint's knob; until it lands, the Sprint 2 `profile-floor.bats` guards a phantom. A one-line comment naming the sprint that introduces the key would keep the two tracked files from reading as a contradiction.

- **LOW** (confidence: medium) `head/tests/unit/floor-snapshot.bats:25` — FS-1…FS-4 compare the floor files to `origin/main`. By construction any PR that deliberately changes `verdict-derive.sh`, `adversarial-review-gate.sh`, `settings.deny.json` or the hook registrations is red until merged, and the suite passes vacuously on `main`. The suite needs a documented path for an intended floor change (an env override checked alongside the `FLOOR_SHA256` pin, or a skip when the PR carries a DEC row), otherwise the first legitimate floor edit will be made with the test deleted.

### 3. Task kinds

- **LOW** (confidence: medium) `head/.claude/scripts/validate-artifact.sh:1023` vs `head/tools/cycle-ratio.sh:100` — the two parsers of the `kind:` token disagree: the validator strips inline code spans before counting tokens (so `` `kind: mechanical` `` at the end of a line is "no kind: token", KINDS-8 pins it) while `cycle-ratio.sh` matches the raw line, so the same line counts as `mechanical` in the release notes. Extract the token rule into one awk function both scripts source (the `md-fence.awk` pattern already exists), or add the code-span strip to `cycle-ratio.sh`.

### 4. Rules, skills, documentation

- **LOW** (confidence: low) `head/.claude/rules/stash-safety.md:3` — (dissent DISS-C-002, triaged) path-scoping the rule to `**/*.sh`, `**/*.bats`, `.claude/scripts/**`, `.claude/hooks/**` means a session that edits only Markdown or YAML and runs `git stash push/pop` through Bash no longer loads the prose guard; the mechanical floor (`fence:FR-1.2b`) covers only the output-swallowing form. RP-2 pins these globs to the SDD, so this is the SDD's decision; recording it so the trade-off is visible when the no_rule_files arm reports.

- **LOW** (confidence: medium) `head/.claude/skills/implementing-tasks/SKILL.md:28` — SURGICAL: the app zone permission flips `read` → `read-write` in a sprint about guards, with no mention in the PR description. The change is coherent (implementing-tasks is the one skill that writes app code, and `reviewing-code/SKILL.md:135` now defers to the frontmatter), but a permission widening in a skill manifest should be named in the description and CHANGELOG, and `validate-skill-capabilities.sh` should keep asserting that every other skill stays `read`.

- **LOW** (confidence: medium) `head/evals/README.md:504` — the new section and `pr/PR.md` are the only prose for this sprint; there is no CHANGELOG entry for the register, the kinds rule, the control arms or the path-scoped rules, and no note that `grimoires/loa/guards.md` becomes a tracked artefact operators must regenerate after editing `guard-origins.yaml`. If the release pipeline owns CHANGELOG, the regenerate rule still belongs in `hooks-reference.md` or the guard-origins header (it is in the header; a line in `CLAUDE.loa.md`'s scripts reference would help).

---

## Rejected dissent payloads

- none: `adversarial-review.json` `metadata.rejected_summary` is `[]` and there is no `adversarial-rejected-review*.jsonl` sidecar beside it.

## Cross-Model Observations

Dissent status `clean`; primary `gpt-5.5-pro` returned no findings, companion `claude-headless` (independent voice) returned three ADVISORY findings. All three are triaged above as LOW observations (DISS-C-001 → floor.yaml:46, DISS-C-002 → stash-safety.md:3, DISS-C-003 → floor.yaml:41); none is counted.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | `grimoires/loa/guards.md` (the tracked register the new CI gate and GO-9 compare against) is not in the change |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Guard register with origin and yield (`guard-yield.sh`, `guard-origins.yaml`, `floor.yaml`) | Fail | Script, map, floor and both bats suites are sound (GO-1…8, GO-10…15, GY-1…11 pass); the generated register itself is missing, so the CI gate and GO-9 fail |
| Pre-registered control arms on a record corpus (`execute-agent.sh`, `run-arms.sh`, `arms-report.py`, `seed-corpus-from-record.sh`, suites) | Pass | AT-1…11, AR-1…7, BF-10…13, RG-28, EA-11/12 pass; `rule_files` toggle gap noted (MEDIUM) |
| Task kinds (`validate-artifact.sh` kinds rule, `cycle-ratio.sh`, template, glossary) | Pass | KINDS-1…11 and CR-1…6 pass; the cycle-128 fixture WARNs as intended; glossary validates |
| Path-scoped rule files (`stash-safety.md`, `skill-invariants.md`) | Pass | RP-1…6 pass; `validate-rule-lifecycle.sh --json` reports 0 errors |
| `/loa` Guards line (`loa-status.sh`) | Pass | LSG-1…3 pass |
| Fast-gate parity | Not verifiable | No CI run or formatter/type-check evidence in the report; shell/python only, bats suites run as above |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (seed script redacts secret shapes; the only key-shaped string is assembled at test time in SC-2)
- [x] Input validation and sanitization present (hook commands parsed against one schema with control-character rejection; ids pattern-checked; `--now`, `--window-days`, arm ids, fixture ids, SHAs validated; table cells sanitised)
- [x] Authentication/authorization correct (N/A; executor strips parent-session coupling and credentials, EA-10/EA-11)
- [x] No SQL/XSS injection vulnerabilities (N/A; `--by` is pattern-restricted, SC-4 proves `x;$(id)` is refused)
- [x] Dependencies secure (stdlib Python under `-I`, jq, yq v4 pinned by sha256 in CI)
- [x] Error messages don't leak sensitive data (yield outputs carry no command text, cwd, host or model; GY-5)

---

## Code Quality Summary

**Strengths:**
- Every mechanical rule has a runnable check that fails when it breaks; fixture suites prove the failure modes (GO-10…14, AT-9/10, SC-4…6, CR-4/5).
- The register is a pure function of the repository and the yield is host-local and untracked; the privacy boundary is tested.
- The control-arm harness refuses skewed comparisons (model, source, arm id) and never edits the source tree.

**Areas for Improvement:**
- Generated artefacts that CI gates on must ship with the gate.
- "Cannot take effect is exit 2" must hold for every toggle, not three of four.
- Sourcing a hook-sized library into a `set -e` main shell needs a subshell probe.

Complexity: `validate_sprint_kinds` (≈75 lines) and the yield `jq` program (≈100 lines) exceed the 50-line guideline but are single-purpose, commented and pinned by tests; no circular dependency, no duplicate blocks beyond the shared `kind:` awk (flagged above). Lean already. Ship, once the register lands.

---

## Next Steps

1. Generate and commit `grimoires/loa/guards.md`; confirm `guard-yield.sh --check` and GO-9 pass on the PR tree.
2. Make the `rule_files` toggle fail closed; probe the heredoc library in a subshell.
3. Add an `## AC Verification` walkthrough to the implementation report.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":11},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T07:40:00Z"} -->
