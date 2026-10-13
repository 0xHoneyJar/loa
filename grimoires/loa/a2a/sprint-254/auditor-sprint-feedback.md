# Security & Quality Audit Report — Sprint 254 (cycle-128 Sprint 3), round 2

**Auditor:** Paranoid Cypherpunk Auditor (Claude Fable 5.1)
**Date:** 2026-10-13T07:59:58Z
**Scope:** commits efacf754 (implementation), 3b0f8bf3 (review round r254-1 and docs) and befd511d (audit round r254-2) on feature/cycle-128-decision-surfaces: the glossaries and their gate, the Seams rule, `red-test-check.sh`, the review-skill grant and text, the mount manifest, the docs, the regenerated REPO-MAP and checksums, and the tests.
**Methodology:** Round 1 (auditor-sprint-feedback-r1.md): every changed script read, sources and sinks walked, two-voice audit dissent (`adversarial-audit.json`: gpt-5.5-pro via codex-headless + claude-headless, consensus, 9 findings, 0 schema-rejected) triaged payload by payload. Round 2: every hunk of befd511d re-read against the round-1 Required Fix text; a shell test command refused live on a throwaway repository (exit 2, the message names the config key); the 23-suite run on the final tree; the static lints re-run; no second dissent (each fix is the one the payload asked for and each is pinned by a test).
**Previous round:** CHANGES_REQUIRED (0 critical, 1 high, 3 medium, 3 low).

---

## Executive Summary

befd511d gives `red-test-check.sh` the boundary the probe got in r253-2, and then some. The test command and `--setup` must start with a listed runner (bats, pytest, `python -m pytest`, `npm`/`pnpm`/`yarn` `test`/`run`, `cargo test`, `go test`, `make`, `mix test`, `bundle exec rspec`, or a `./`/`tests/` script the operator names in `.loa.config.yaml` `red_test.allowed_runners`; the exact `red_test.command`/`red_test.setup` strings); shells, `env`, `eval`, `exec`, inline-code interpreters and the listed runners' inline-code flags are refused with exit 2. Every run starts from `env -i` with a filtered PATH, a per-run HOME and TMPDIR under the scratch, no git config, no prompt, a failing askpass and ssh transport, plus `--env-pass NAME` for one caller variable with credential-shaped and contract names refused. The test runs red, green, then red again, so a stateful decoy reads DECOY. The output tails are control-stripped (C0, C1, U+2028/9), capped per line and fenced as untrusted content with the verdict line printed last. Every git call runs hook-free and without fsmonitor, and a snapshot of refs, HEAD, the config files and the hooks directory is compared after each phase; a write to the shared `.git` exits 2 with the entries. The review skill takes only the red commit SHA from `reviewer.md`, the test command from `sprint.md` or `red_test.command`, prefers `--json`, treats the tails as data, and its `execute_commands` grant is explicit. The Seams rule tracks fences through `lib/md-fence.awk` and a live plan without a parseable header Date fails (the archive and fixtures keep the WARN; one Sprint 2 fixture gained a Date for that reason). The glossary validator caps aliases globally at 40 and WARNs on non-ASCII names; the checker's report lists resolution-only and unreferenced entries; the symlink manifest links the glossary only when the pinned framework ships it and prints one notice otherwise (five manifest tests).

Verification on the final tree: 23 suites, 760 ok and 2 failures on an undated Sprint 2 fixture that the new Date rule caught; the fixture dated and the three affected suites re-run 100/100 (762/762 in total); prompt budgets exit 0 (reviewing-code 16,306 of 16,384); skill capabilities 37/37; AGENTS.md consistent at 51 commands; swallowed-jq and raw-sha256sum lints clean; `sync-fixtures.sh --check` current; `repo-map-gen.sh --validate` exit 0; `bash -n` on every changed script; shell-compat greps clean; the glossary gate PASS on the live kernel; both glossaries, the sprint plan, the PRD and the SDD validate. Nothing is carried.

**Verdict:** APPROVED - LET'S FUCKING GO

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Notes |
|---|---|---|
| Security | 9/10 | The review role's execution path is bounded to listed runners under a scrubbed environment with a `.git` snapshot; the remaining point is that the gate is lint-grade over tracked files by design (documented) |
| Architecture | 9/10 | One pattern (runner allowlist, `env -i`, snapshot, fenced output) now shared by the probe and the red-test check |
| Code Quality | 9/10 | `g()` wrapper for every git call; `build_env`; `tail_file`/`fence_tail`; per-run env directories |
| DevOps | 9/10 | 762 tests across 23 suites; RTC-19…26 pin each refusal and boundary; SMG-1…5 pin the manifest |
| Blockchain | n/a | |

---

## Previous Feedback Status

| Round-1 item | Status | Evidence in befd511d |
|---|---|---|
| HIGH-001 unbounded, credentialed execution path | Fixed | `check_runner` (runner list, config exact strings, inline-code flags refused), `build_env` + `env -i` with `SAFE_PATH`, per-run HOME/TMPDIR, `--env-pass` validation; skill Phase 2 text and REFERENCE "Red Test Check" (SHA from reviewer.md only; command from sprint.md or `red_test.command`; `--json`); `execute_commands` args `["--red", "*"]`; `.loa.config.yaml.example` `red_test` block; RTC-19, RTC-20, RTC-21, RTC-22, RTC-23; live: `-- bash -c 'exit 1'` refused with exit 2 |
| MEDIUM-001 stateful decoy | Fixed | second red run (`run_bounded "$WT_RED" red2`), DECOY on a pass, `red_again_exit` in `--json`, header honest scope; RTC-24 |
| MEDIUM-002 unfenced tails | Fixed | `tail_file` (C0/C1/U+2028-9 stripped, 400-byte lines, `| ` prefix), `fence_tail` (L6 via `context-isolation-lib.sh`, labelled fallback), verdict line last; RTC-1, RTC-7, RTC-18, RTC-25 |
| MEDIUM-003 shared `.git` | Fixed | `g()` with `core.hooksPath=/dev/null` and `core.fsmonitor=false`, `snapshot()`/`verify_git_state` around `--setup` and the runs, header states the shared `.git` and the detector; RTC-26 |
| LOW-001 Seams fence and Date gate | Fixed | `md_fence()` in both seams awk passes; a live plan without a parseable header Date fails, archive and fixtures WARN; SEAMS-11, SEAMS-12; the Sprint 2 `charting-lint.bats` fixture dated 2026-10-01 |
| LOW-002 glossary alias controls | Fixed | `GLOSSARY_MAX_ALIASES_TOTAL=40`, non-ASCII WARN on terms and aliases, `--report`/`--json` entry-reference list; GV-25, GV-26, GV-27, GT-29, GT-30, GT-31 |
| LOW-003 manifest tolerance | Fixed | optional framework files linked only when the pinned submodule ships them, one notice otherwise; `symlink-manifest-glossary.bats` SMG-1…5 |

---

## Findings (open)

None.

---

## Observations (no change required)

1. **reviewing-code sits at 16,306 of 16,384 bytes** after the trust rules were added; the next edit to that skill should move text to `resources/REFERENCE.md` first.
2. **The glossary gate is lint-grade by design** (tracked, agent-editable kernel, glossary and allowlist); the checker's advisory WARN and its entry-reference report make the resolution paths visible to a reviewer of the diff, which is the intended control.
3. **A new Date requirement for live plans** means a plan generated by an older `/sprint-plan` without `**Date:**` now fails the validator until dated; the CHANGELOG Migration section already states the Seams gate date and the sprint template carries the header.

---

## Sources and sinks walked (round 2 delta)

- Reviewer argv → `check_runner` (list, config, flags) → `build_env` → `env -i` run in a hook-free, fsmonitor-free worktree → `tail_file`/`fence_tail` (untrusted, fenced, capped) → `verify_git_state` (refs, HEAD, config, hooks) → verdict line last; `--json` preferred by the skill.
- `reviewer.md` → the red commit SHA only; `sprint.md`/`red_test.command` → the test command; `.loa.config.yaml` changes on the branch → WARN.
- Plans → `validate_sprint_seams` with `md-fence.awk`; live plans require a header Date.
- Glossaries → per-entry and global alias caps, relatedness and non-ASCII WARNs; the checker's entry-reference report.
- Mount → the glossary linked only when present in the pinned framework.

## Severity Tally (Phase 2.5)

| Severity | Count | Items |
|---|---|---|
| CRITICAL | 0 | |
| HIGH | 0 | HIGH-001 fixed in befd511d |
| MEDIUM | 0 | MEDIUM-001 … MEDIUM-003 fixed in befd511d |
| LOW | 0 | LOW-001 … LOW-003 fixed in befd511d |

## Verdict

**APPROVED - LET'S FUCKING GO.** Sprint 254 may be marked COMPLETED; the cycle's three sprints are done.

## Rejected dissent payloads

None. The envelope lists zero rejected payloads and no sidecar files.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-254","ts":"2026-10-13T07:59:58Z"} -->
