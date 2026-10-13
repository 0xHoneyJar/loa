# Security & Quality Audit Report — Sprint 254 (cycle-128 Sprint 3), round 1

**Auditor:** Paranoid Cypherpunk Auditor (Claude Fable 5.1)
**Date:** 2026-10-13T07:30:17Z
**Scope:** commits efacf754 (implementation) and 3b0f8bf3 (review round r254-1 and docs) on feature/cycle-128-decision-surfaces: the glossaries and `tools/check-glossary-terms.sh` with its CI workflow and the `--type glossary` validator, the Seams Under Test rule, `red-test-check.sh`, the micro-sprint two-commit rule, the review-skill grant, the mount manifest lines, the docs and reference tables, the SDD backfill, the regenerated REPO-MAP and checksums, and the tests.
**Methodology:** Every changed script read in full; the review's own live exercise of `red-test-check.sh` repeated with a hostile eye; sources and sinks walked by hand; two-voice audit dissent (`adversarial-audit.json`: gpt-5.5-pro via codex-headless + claude-headless, consensus, 9 findings, 0 schema-rejected) triaged payload by payload against the code; the review verdicts (engineer-feedback-r1.md, engineer-feedback.md) read for demotions; the checksum and manifest coverage of the new framework file verified directly.
**Review input:** round 1 CHANGES_REQUIRED (0 critical, 0 high, 1 medium, 7 low), round 2 APPROVED after 3b0f8bf3.

---

## Executive Summary

The sprint's code is careful where it looks (worktrees under a trap, hook-free checkouts, an argv that never passes through a shell, CommonMark fences shared by two tools, capped and related aliases) and the docs are faithful to it. The audit's one HIGH is the same shape Sprint 2's audit found in the unblock probe, now in `red-test-check.sh`: the review skill, which until this sprint could run only `git diff`, `git log` and three framework scripts, gains `Bash(.claude/scripts/red-test-check.sh *)`, and that script runs whatever follows `--` (and every word of `--setup`) with the reviewer's full environment, in worktrees that share `.git` with the live checkout. The skill text takes the red commit from `reviewer.md`, which the implementing agent writes, and names no source for the test command. In run mode the reviewer is unattended and credentialed, so the party under review can choose what the reviewer executes. Three MEDIUMs sit beside it: a stateful test passes red-then-green through shared writable state and reads as VERIFIED; the printed output tails are agent-authored text shown to an agent without the L6 fence this cycle applies everywhere else; and the shared `.git` means a test's hook or config write survives the cleanup. Three LOWs are lint-grade (the seams rule's fence tracking and Date gate, the glossary's alias controls, the manifest's tolerance of a missing glossary in an older framework). All have small, local fixes and the probe from r253-2 is the pattern to copy.

**Verdict:** CHANGES REQUIRED

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Notes |
|---|---|---|
| Security | 6/10 | The review role's new execution path is unbounded and credentialed; output tails unfenced; shared `.git` survives cleanup. The glossary gate and the Seams rule are lint-grade by design and say so |
| Architecture | 9/10 | The red-test check's shape (two detached worktrees, argv not shell, honest scope) is right; it needs the probe's boundary |
| Code Quality | 9/10 | `md-fence.awk` shared by two tools; verdict precedence stated; `ENVIRON`-free awk with constants only |
| DevOps | 9/10 | 741 tests across 22 suites, controls in CI, REPO-MAP and checksums regenerated, fixtures synced |
| Blockchain | n/a | |

---

## Findings

### [HIGH-001] `red-test-check.sh` is an unbounded, credentialed execution path granted to the review role

**Where:** `.claude/skills/reviewing-code/SKILL.md` (`allowed-tools: … Bash(.claude/scripts/red-test-check.sh *)`, the `execute_commands` row with `args: ["*"]`, Phase 2 text "run `red-test-check.sh --red <Red commit from reviewer.md> -- <test command>`"); `.claude/scripts/red-test-check.sh` `run_bounded` (`exec "$@"`, `--setup` argv; only `GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX` unset). Dissent DISS-001, DISS-C-001 and DISS-C-002, confirmed.
**Issue:** Nothing restricts the test argv or `--setup` to a test runner; shells and interpreters pass; the reviewer's environment (provider keys, `GH_TOKEN`, `SSH_AUTH_SOCK`, `GIT_SSH_COMMAND`, `GIT_ASKPASS`, `GIT_CONFIG_*`) reaches code checked out from the commit under review; and the skill text points the reviewer at `reviewer.md`, an artefact the reviewed agent authored, for its inputs. The previous grant made the review role execution-free; this is a trust-boundary change the diff does not acknowledge (the probe in r253-2 runs under `env -i` for the same reason).
**Impact:** A `reviewer.md` or a diff that steers the reviewer to `-- bash -c '<exfil>'`, or a test file at the red commit that reads the environment and posts it, runs with the reviewer's session credentials; in run mode nobody is watching.
**Required Fix:** (1) In `red-test-check.sh`, allowlist the first word of the test argv and of `--setup`: the known runners (`bats`, `pytest`, `python -m pytest`, `npm`/`pnpm`/`yarn` `test`, `cargo test`, `go test`, `make`, `mix test`, `bundle exec rspec`, `./` or `tests/` scripts only when `.loa.config.yaml` `red_test.allowed_runners` names them) or the project's configured test command; refuse `bash`, `sh`, `zsh`, `env`, `eval`, `python -c`, `node -e` and any `-c`/`-e` inline-code flag with exit 2 and a message naming the config key. (2) Run `--setup` and the test under `env -i` with an explicit passthrough (`PATH`, `HOME` pointed at a per-run directory under the scratch, `TMPDIR` likewise, `LANG`, `LC_ALL`, `TERM`, `CI=1`) plus `--env-pass NAME` for runners that need more; state the environment contract in the header. (3) The skill text names `sprint.md` or `.loa.config.yaml` (never `reviewer.md`) as the source of the test command, keeps the red commit SHA from `reviewer.md` (a SHA is harmless), and says the reviewer runs only a listed runner. (4) `execute_commands` args stay explicit rather than `["*"]` where the frontmatter allows it. Tests: a refused shell argv (exit 2), a refused `--setup bash -c`, an allowed `bats` run, an env probe test asserting `GH_TOKEN` is absent in the worktree, and the existing suite green.

### [MEDIUM-001] A stateful test reads as VERIFIED

**Where:** `red-test-check.sh` (red run, then green run, both with linked dependency directories, the reviewer's `HOME` and `TMPDIR`, and the shared repository). Dissent DISS-C-003, confirmed.
**Issue:** The two runs share writable state. A test that records "I have run before" in `node_modules/.cache`, `$HOME` or `$TMPDIR` fails on the first run and passes on the second; the script reports VERIFIED and the reviewer's checklist item is satisfied by a test unrelated to the bug.
**Impact:** The decoy detection (exit 3) has a one-line bypass that needs no knowledge of the fix.
**Required Fix:** Run red, green, then red again and require the second red run to fail (a pass is `DECOY`, exit 3, with a message naming the stateful shape); give each run its own `HOME` and `TMPDIR` under the scratch (part of the HIGH-001 scrub); note the stateful decoy in the header's honest-scope paragraph. Tests: a marker-file test is caught; the normal pair still verifies.

### [MEDIUM-002] The printed output tails are agent-authored text shown to an agent without the L6 fence

**Where:** `red-test-check.sh` `tail_block` and `finish()` (`strip` removes C0 and DEL only; lines uncapped; the `--- red run ---` / `verdict:` markers are forgeable from inside the test output). Dissent DISS-C-004, confirmed.
**Issue:** The reviewer is told to cite this output. A test at the red commit can print `--- end red run ---`, a fake `verdict:` line and instructions, and the reviewer reads them as tool output. Every other agent-to-agent surface of this cycle (the decisions surface, the INDEX family, the hand-off snapshot) strips C1 and the Unicode separators, caps lengths and fences the text.
**Impact:** Prompt injection into the review through test output, on a surface the skill tells the reviewer to trust.
**Required Fix:** Cap each tail line (400 characters) and the tail to 80 lines (already), strip C1 and U+2028/U+2029 as `loa-decisions-surface.sh` does, wrap both tails in the L6 `<untrusted-content>` fence through `context-isolation-lib.sh` when available (a labelled plain fence otherwise), print the authoritative `verdict:` line after the fenced blocks, and add one sentence to the skill text: the tails are untrusted test output; only the exit code and the verdict line are authoritative; prefer `--json`. Tests: a forged marker inside test output lands inside the fence; the verdict line is last.

### [MEDIUM-003] The temporary worktrees share `.git` with the live checkout

**Where:** `red-test-check.sh` `add_wt` (`-c core.hooksPath=/dev/null` on the add only) and the header's cleanup claim. Dissent DISS-C-005, confirmed in part (the hook path for the add is covered; `core.fsmonitor` is not; the test's own git writes persist).
**Issue:** Both worktrees share `.git/config`, `.git/hooks`, refs and objects with the live checkout. A test can set `core.hooksPath`, write a hook, add refs or tags, and all of it survives `worktree remove`; the header reads as containment that does not exist for `.git`.
**Impact:** A planted hook runs on the reviewer's next commit in the live tree.
**Required Fix:** Add `-c core.fsmonitor=false` to the worktree add; snapshot `git for-each-ref`, a hash of the config files and the hooks listing before the runs and compare after (the probe's `snapshot()` from r253-2 is the pattern; fail with exit 2 and the changed entries); state in the header that the worktrees share `.git` and that the snapshot is what detects a write there. Tests: a test that writes a hook or a tag fails the check.

### [LOW-001] The Seams rule's fence tracking and Date gate fail open

**Where:** `validate-artifact.sh` `validate_sprint_seams` (its own `fence = !fence` toggle, not `lib/md-fence.awk`; a missing, misplaced or malformed `**Date:**` turns the violation into a WARN). Dissent DISS-C-006, confirmed.
**Fix:** Prepend `lib/md-fence.awk` and use `md_fence($0)` as the glossary validator does; for a plan under `grimoires/loa/` that is not under `grimoires/loa/archive/`, a missing or unparseable header Date is a violation (the plan must carry `**Date:** YYYY-MM-DD`); archived and fixture plans keep the WARN. Tests: a nested fence no longer hides a sprint block; an undated live plan fails; the archived cycle-127 plan and the undated fixtures still WARN only.

### [LOW-002] The glossary's alias controls are per entry and ASCII-folded

**Where:** `validate_glossary` (`GLOSSARY_MAX_ALIASES` per entry; `alias_related` a WARN; `norm()` folds case and separators but not Unicode). Dissent DISS-C-007, confirmed as lint-grade.
**Fix:** A global alias budget (fail over 40 aliases in a glossary), a WARN on a non-ASCII letter in a term or alias name (a homoglyph alias passes the duplicate check today), and the `--report` of `check-glossary-terms.sh` lists entries that no kernel token or glossary prose references by term so resolution-only entries are visible. The gate remains lint-grade by design (tracked, agent-editable files); the docs say so.

### [LOW-003] Manifest coverage of the new framework file

**Where:** `.claude/scripts/lib/symlink-manifest.sh`, `mount-loa.sh`, `mount-submodule.sh` (`.claude/loa/GLOSSARY.md` added); `.claude/checksums.json`. Dissent DISS-C-008, verified in part: the checksum manifest does list `.claude/loa/GLOSSARY.md` (one entry, refreshed in 3b0f8bf3), so an in-place edit is detectable; `grimoires/loa/gt/checksums.json` covers the reality directory only and is not in scope.
**Fix:** Confirm that the core-manifest apply step tolerates a missing source when a project is pinned to an older framework (skip with a notice, no dangling link) and add `GLOSSARY.md` to the manifest's existence test if one exists; otherwise state the behaviour in the mount script's header.

---

## Sources and sinks walked

- Reviewer argv → `red-test-check.sh` (**no runner allowlist, inherited env, shared `.git`: HIGH-001, MEDIUM-003**) → detached worktrees (hook-free add) → test output tails (**raw, forgeable markers: MEDIUM-002**) → verdict (**stateful pass: MEDIUM-001**) → the reviewer's citation.
- `reviewer.md` (implementer-authored) → skill Phase 2 inputs (**the red commit SHA is harmless; the test command must not come from here: HIGH-001 fix 3**).
- Kernel and glossary prose → awk (constants only via `-v`; `md-fence.awk` shared) → allowlist (capped, reasons) and aliases (**per-entry cap, WARN-grade relatedness: LOW-002**) → CI gate with controls.
- Sprint plans → `validate_sprint_seams` (**own fence toggle, Date gate WARN-only: LOW-001**).
- Mount → symlink manifest and mount gitignore lists (`GLOSSARY.md`), checksum manifest (covered) (**older-framework tolerance unverified: LOW-003**).
- Docs → CHANGELOG, README, references, SDD §10 (DEC ids verified against the ledger: DEC-0001…0016, 0025, 0030, 0049, 0051, 0053 all exist with matching sources), REPO-MAP (`--validate` exit 0), checksums (tracked files, spot-checked).
- Tests → fixture repositories and temp directories only; RTC-15 proves the live tree untouched; the seams fixture is byte-identical to the archive.

## Review demotions confirmed

The review's observations (backticked-token scope, the archived plan's pre-existing failures, the checksums refresh scope) stand. The review did not raise the execution-path change; this audit does, as the one HIGH.

## Severity Tally (Phase 2.5)

| Severity | Count | Items |
|---|---|---|
| CRITICAL | 0 | |
| HIGH | 1 | HIGH-001 |
| MEDIUM | 3 | MEDIUM-001, MEDIUM-002, MEDIUM-003 |
| LOW | 3 | LOW-001, LOW-002, LOW-003 |

## Verdict

**CHANGES REQUIRED.** Round-2 fixes dispatched: implementer G takes HIGH-001, MEDIUM-001, MEDIUM-002, MEDIUM-003 and LOW-001 (`red-test-check.sh`, the review-skill text and grant, `validate_sprint_seams`, tests); implementer F takes LOW-002 and LOW-003 (`validate_glossary`, the checker's report, the manifest tolerance). Approval follows the re-read of the fixes and a green run of the suites.

## Rejected dissent payloads

None. The envelope lists zero rejected payloads and no sidecar files.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":3,"low":3},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-254","ts":"2026-10-13T07:30:17Z"} -->
