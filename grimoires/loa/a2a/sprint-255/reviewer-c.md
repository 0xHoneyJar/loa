# Implementation Report: Sprint 255 (cycle-129 Sprint 1), implementer C

**Date:** 2026-10-14
**Engineer:** Sprint Task Implementer Agent, implementer C (Claude Opus 5.5, model id `global.anthropic.claude-opus-5-5`)
**Sprint Reference:** grimoires/loa/sprint.md (## Sprint 1, Tasks 1.7, 1.8, 1.9)
**Worktree:** /home/merlin/Documents/thj/code/loa-wt-s1c (branch `wt/cycle-129-s1c` at `ffd25258`, uncommitted)
**Patch:** ~/.cache/loa/cycle-129/patches/s1-c.patch (`git add -A && git diff --cached --binary`)

---

## Executive Summary

Task kinds are now a validator rule, a template line, a review-axis sentence, five glossary entries and a release-notes tool. `validate-artifact.sh --type sprint` requires one trailing `kind: mechanical|judgment|operator` token on every task line of plans dated from 2026-10-14 and WARNs before that date. This cycle's plan passes; the archived cycle-128 plan only WARNs. `tools/cycle-ratio.sh` prints the kind counts and the volume line with the host-scope provenance.

The two always-loaded rule files carry `paths:` frontmatter in the list form the other rule files use, with lifecycle fields that also clear two pre-existing `validate-rule-lifecycle.sh` errors. The FR-1.2b block message ends with the rule-file pointer and the fence corpus result is byte-identical. The prompt-budget workflow comment states the tool's constants and a bats case pins them. The `implementing-tasks` app-zone permission now agrees with its prose.

**Key Accomplishments:**
- `kind:` rule with dated fixtures (11 cases), and the existing Seams fixture updated so its 2026-10-14 plan stays valid
- `tools/cycle-ratio.sh` with a fixture-repository suite (6 cases)
- `paths:` frontmatter with a glob lint (6 cases), and the hazard crosswalk below
- Workflow comment pinned to `check-prompt-budget.sh` constants (PB-10, red on the old comment)

---

## AC Verification

### Sprint 1 — Acceptance Criteria owned by implementer C

**AC-1.9**: "A dated plan with an untagged task fails `--type sprint`; this plan passes; the spec-axis lines exist in `reviewing-code/SKILL.md` within budget and an eval fixture for a `mechanical` task shipped as prose is added under `evals/tasks/review-recall/` (not run in CI); `cycle-ratio.sh` prints both lines on a fixture (PRD AC-10.1 … AC-10.3)"
- Status: `✓ Met`
- Evidence: `.claude/scripts/validate-artifact.sh:961-964` — `# @guard validator:sprint.kinds`, `KINDS_REQUIRED_FROM="2026-10-14"`, `validate_sprint_kinds()`; called at `.claude/scripts/validate-artifact.sh:319`. `.claude/skills/reviewing-code/SKILL.md:218` — the `**Task kinds**:` sentence; file is 16,367 B of 16,384 B. `evals/tasks/review-recall/review-kind-01.yml` with `evals/fixtures/review-kinds/kind-01/`. `tools/cycle-ratio.sh` prints `kinds:` and `volume:` lines.
- Test: `tests/unit/validate-artifact-sprint-kinds.bats:36` KINDS-1 (untagged task on a dated plan fails), `:129` KINDS-9 (this plan passes), `:137` KINDS-10 (cycle-128 plan only WARNs); `tests/unit/cycle-ratio.bats` CR-1 (both lines on a fixture repository); `tests/unit/prompt-budget.bats` PB-9 (budget); `bash evals/harness/validate-task.sh evals/tasks/review-recall/review-kind-01.yml` → valid.

**AC-1.10**: "The two rule files carry `paths:` frontmatter and each glob matches at least one tracked file of the intended kind (lint); the hazard crosswalk is in the sprint report with the unmechanised hazards named; the harness observation is recorded; `no-history-in-rule-text.bats` and `check-prompt-budget.sh` stay green (PRD AC-3.1)"
- Status: `⚠ Partial` — the harness observation is the lead's step by instruction (not attempted here); every other clause is met.
- Evidence: `.claude/rules/stash-safety.md:1-10` and `.claude/rules/skill-invariants.md:1-10` (frontmatter, `paths:` at line 2); crosswalk in §Hazard crosswalk below.
- Test: `tests/unit/rule-paths.bats` RP-1 … RP-6 (6/6); `tests/unit/no-history-in-rule-text.bats` 3/3; `bash tools/check-prompt-budget.sh` exit 0.

**AC-1.13**: "Every existing bats, pytest, vitest and fence-corpus suite is green on the sprint's final tree; the toolchain readiness check is recorded"
- Status: `⚠ Partial` — the final tree is the lead's integrated tree. On this worktree every suite I ran is green (table in §Testing Summary) and the fence corpus is unchanged; I did not run the full repository bats, pytest or vitest sweep, and the toolchain readiness check is Task 1.0 (lead).
- Evidence: §Testing Summary.

**AC-1.11**: "The workflow comment states 160,000 / 114,688 B; `implementing-tasks/SKILL.md:28` agrees with `:76`"
- Status: `✓ Met`
- Evidence: `.github/workflows/check-prompt-budget.yml:5` — `protocols total ≤ 160,000 B (warn > 114,688 B)`; `.claude/skills/implementing-tasks/SKILL.md:28` — `permission: read-write`, matching `:76` "**Read/Write**".
- Test: `tests/unit/prompt-budget.bats` PB-10 (fails on the HEAD comment with "does not state 160,000 B", passes now); `bash .claude/scripts/validate-skill-capabilities.sh --skill implementing-tasks --strict` → PASS, 0 warnings.

---

## Tasks Completed

### Task 1.7: `kind:` rule, template, review axis, cycle-ratio, glossary

| File | Action | Description |
|------|--------|-------------|
| `.claude/scripts/validate-artifact.sh` | Modified | header comment, usage text, `validate_sprint_kinds` call, the rule block with `# @guard validator:sprint.kinds` |
| `tests/unit/validate-artifact-sprint-kinds.bats` | Created | KINDS-1 … KINDS-11 |
| `tests/fixtures/sprint-kinds/cycle-128-sprint.md` | Created | verbatim copy of the gitignored archived cycle-128 plan |
| `tests/unit/sprint-seams.bats` | Modified | fixture task line gains ` · kind: mechanical` |
| `.claude/skills/planning-sprints/resources/templates/sprint-template.md` | Modified | kind token on the example task lines plus a two-line comment |
| `.claude/skills/reviewing-code/SKILL.md` | Modified | spec-axis sentence; two prose cuts for budget |
| `evals/tasks/review-recall/review-kind-01.yml` | Created | task, not in any suite |
| `evals/fixtures/review-kinds/kind-01/*` | Created | fixture.yaml, REVIEW-INSTRUCTIONS.md, PR.md, sprint.md, head.diff, base/ and head/ |
| `.claude/loa/GLOSSARY.md` | Modified | Judgment, Kind counts, Mechanical, Operator, Volume ratio |
| `tools/cycle-ratio.sh` | Created | the two lines and `--json` |
| `tests/unit/cycle-ratio.bats` | Created | CR-1 … CR-6 |

### Task 1.8: path-scoping and crosswalk

| File | Action | Description |
|------|--------|-------------|
| `.claude/rules/stash-safety.md` | Modified | frontmatter only |
| `.claude/rules/skill-invariants.md` | Modified | frontmatter only |
| `.claude/hooks/safety/block-destructive-bash.sh` | Modified | FR-1.2b message tail only (one string) |
| `tests/unit/rule-paths.bats` | Created | RP-1 … RP-6 |

### Task 1.9: doc fixes

| File | Action | Description |
|------|--------|-------------|
| `.github/workflows/check-prompt-budget.yml` | Modified | line 5 numbers |
| `tests/unit/prompt-budget.bats` | Modified | header comment numbers; PB-10 |
| `.claude/skills/implementing-tasks/SKILL.md` | Modified | line 28 `read` → `read-write` |

---

## Technical Highlights

- **Parser.** Inline code spans are stripped before tokens are counted, so the live plan's Task 1.7 text "Add the `kind:` rule" is not a second token. The end-of-line test runs on the raw line, so a backticked tag or trailing code does not pass. Four violation shapes are reported separately: no token, several tokens, text after the value, unknown value.
- **Scope.** Top-level checkbox lines under `### Technical Tasks`, and `- [ ] Task …` lines under `### Task N.E2E`, inside `## Sprint N` blocks, with `lib/md-fence.awk` fence tracking. The template's E2E `**Acceptance Criteria:**` checkboxes are not tasks.
- **Dates.** Same header-date parse and live-plan rule as the Seams gate; older and undated plans get one aggregated WARN.
- **Portability.** Both new awk programs pass their suites under mawk and busybox awk.
- **cycle-ratio.** Committer timestamps bound an inclusive window; MODELINV rows are read with `fromjson?` so a malformed line is skipped; renames are detected and binaries skipped; git runs with `--no-ext-diff --no-textconv --no-color` so user config does not change the counts.

---

## Testing Summary

Run with `LOA_HARNESS_CHECK=0 LOA_AUDIT_REPLAY=1` and the bats binary from `~/.cache/loa/cycle-128/bats-path` (Bats 1.13.0).

| Suite | Pass / total |
|-------|--------------|
| tests/unit/validate-artifact-sprint-kinds.bats | 11 / 11 |
| tests/unit/cycle-ratio.bats | 6 / 6 |
| tests/unit/rule-paths.bats | 6 / 6 |
| tests/unit/prompt-budget.bats | 10 / 10 |
| tests/unit/validate-artifact.bats | 66 / 66 |
| tests/unit/skill-capabilities.bats | 36 / 36 |
| tests/unit/no-history-in-rule-text.bats | 3 / 3 |
| tests/unit/glossary-terms.bats | 34 / 34 |
| tests/unit/sprint-seams.bats | 12 / 12 |
| tests/unit/charting-lint.bats | 28 / 28 |
| tests/unit/glossary-validator.bats | 27 / 27 |
| tests/unit/stash-safety.bats | 12 / 12 |
| tests/unit/block-destructive-bash.bats | 291 / 291 |
| tests/unit/block-destructive-bash-limitations.bats | 6 / 6 |
| tests/unit/rule-lifecycle.bats | 4 / 4 |
| tests/unit/validation-skill-contracts.bats | 5 / 5 |
| tests/unit/skill-capabilities-role-lint.bats | 11 / 11 |
| tests/unit/effort-dispatch.bats | 10 / 10 |
| tests/unit/red-test-check.bats | 27 / 27 |
| tests/unit/adversarial-review-companion.bats | 284 / 284 |
| tests/unit/hook-guard.bats | 8 / 8 |
| tests/unit/agent-teams-hooks.bats | 8 / 8 |
| tests/unit/symlink-manifest-glossary.bats | 5 / 5 |
| tests/unit/zones-schema.bats | 6 / 6 |
| tests/integration/test_skill_metadata.bats | 2 / 5; HEAD is 1 / 5. The three failures assert hard-coded counts (25 skills, 3 rule files) that the tree outgrew before this cycle; "both validators run together with zero errors" now passes because the lifecycle validator is green |
| fence corpus `run-corpus.sh` | benign 78/78, dangerous 100/100, residual 0/5; identical before and after the string change |
| `.claude/scripts/test-safety-hooks.sh` | 67 / 67 |

Script checks, all exit 0: `tools/check-prompt-budget.sh`, `tools/check-glossary-terms.sh`, `.claude/scripts/validate-skill-capabilities.sh` (37 skills, 0 errors), `tools/check-no-raw-sha256sum.sh` (the prompt names `.claude/scripts/check-no-raw-sha256sum.sh`, which does not exist; the tool lives in `tools/`), `.claude/scripts/validate-artifact.sh --type sprint --file grimoires/loa/sprint.md`, `.claude/scripts/validate-artifact.sh --type glossary --file .claude/loa/GLOSSARY.md`, `.claude/scripts/generate-skill-includes.sh --check`, `.claude/scripts/validate-rule-lifecycle.sh` (5/5, was 3/5), `evals/harness/validate-task.sh` on the new task.

---

## Known Limitations

- The live plan draws one judgment WARN, on Task 1.5 ("generate fixtures"). That is the heuristic working as specified; the tag was not changed because `sprint.md` is not mine to edit.
- The judgment heuristic sees file tokens only by a fixed extension list (sh py ts js md yaml yml json tsv bats txt toml).
- The eval task is not wired anywhere; a later cycle must run it with `evals/harness/run-eval.sh --task review-kind-01`.
- `model calls` counts only this host's MODELINV log.
- The harness observation for path-scoping (does a rule load on a matching turn and not on a non-matching one) is the lead's.

---

## Verification Steps

```bash
cd /home/merlin/Documents/thj/code/loa-wt-s1c
export LOA_HARNESS_CHECK=0 LOA_AUDIT_REPLAY=1; B=$(cat ~/.cache/loa/cycle-128/bats-path)
$B tests/unit/validate-artifact-sprint-kinds.bats tests/unit/cycle-ratio.bats tests/unit/rule-paths.bats tests/unit/prompt-budget.bats tests/unit/sprint-seams.bats
bash .claude/scripts/validate-artifact.sh --type sprint --file grimoires/loa/sprint.md
bash tools/cycle-ratio.sh --from 864069f2 --to HEAD
bash tests/fixtures/fence-corpus/run-corpus.sh
bash tools/check-prompt-budget.sh
```

---

## Hazard crosswalk (Task 1.8, D-3.1)

| Rule file | Hazard named in the rule | Mechanism | Proof (corpus or bats row) |
|-----------|--------------------------|-----------|----------------------------|
| stash-safety.md | Output-swallowing (`\| tail`, `\| head`, `\|\| true`, `2>/dev/null`, `>/dev/null 2>&1`) around `git stash push/pop/apply` | fence `FR-1.2b`, `block-destructive-bash.sh:736-749` | `.claude/scripts/test-safety-hooks.sh:100-103` block rows and `:150-152` allow rows (67/67); `tests/unit/stash-safety.bats:190`, `:198`, `:206` grep `.claude/scripts/` for the shapes. The fence corpus `corpus.jsonl` has no stash row. |
| stash-safety.md | An outer stash shifted by the hook's internal `--keep-index`, so `pop` lands on the wrong entry or a stash is dropped or added | `stash_with_guard` count-delta in `.claude/scripts/stash-safety.sh` (only when the helper is used) | `tests/unit/stash-safety.bats:98` (dropped stash), `:118` (extra stash), `:144` (no-op push) |
| stash-safety.md | Output hidden or exit masked inside a guarded stash | `stash_with_guard` surfaces output and propagates exit | `tests/unit/stash-safety.bats:53`, `:158` |
| stash-safety.md | `git stash -k` combined with pre-commit-wrapped operations | **none**: the internal `--keep-index` is invisible to a command-string fence | — (the `no_rule_files` arm measures it) |
| stash-safety.md | `git gc` run before `git fsck --unreachable` during recovery | **none**: advice. FR-1.2 blocks `git stash drop` and `git stash clear`, a neighbouring loss path, not this rule | `tests/unit/block-destructive-bash.bats:104`, `:110` cover only drop and clear |
| skill-invariants.md | A write-capable skill dispatched through a read-only `agent:` type | `validate-skill-capabilities.sh` exit 1 | `tests/unit/skill-capabilities.bats:288`, `:317`, `:426`, `:461` fail; `:346`, `:373`, `:399` pass |
| skill-invariants.md | Agent-type allowlist drift, or a missing or unparsable `agent-types.yaml` | data-file loader with `general-purpose` fallback | `tests/unit/skill-capabilities.bats:848`, `:872`, `:884`, `:896` |
| skill-invariants.md | A `role: review` skill with `write_files: true` that keeps `Write` outside `REVIEW_WRITE_EXCEPTIONS` | validator WARN only (FR-4(b) in Sprint 2 adds the four pure-review lines) | `tests/unit/skill-capabilities.bats:574`, `:598`, `:635` |
| skill-invariants.md | Sprint review and audit skills keep `Write`/`Edit` and drop `NotebookEdit` | frontmatter pinned by tests | `tests/unit/skill-capabilities.bats:626`; `tests/unit/validation-skill-contracts.bats:50-77` |
| skill-invariants.md | Report-authoring review skills drop `git add/commit/push` | harness-enforced by their own `disallowed-tools`; **no lint pins the list** | `tests/unit/skill-capabilities.bats:635` only checks the two skills validate clean |
| skill-invariants.md | `disallowed-tools` is tool-granular, so it cannot allow `grimoires/` writes while refusing `src/` writes | zones: `implement-gate.sh`, `zone-write-guard.sh` for Write/Edit; **Bash-path writes unmechanised** (accepted gap) | `tests/unit/zone-write-guard.bats` |

**Hazards with no mechanical check:** the `stash -k` under pre-commit rule; the `fsck` before `gc` recovery advice; the git-mutation list of the report-authoring review skills (enforced at run time, not linted); and Bash-path App-Zone writes under `disallowed-tools`.

---

## Text removed from `reviewing-code/SKILL.md`

The SDD names the duplicated sentence of the `@skill-include trajectory_logging` block as the byte source. That block is generated by `.claude/scripts/generate-skill-includes.sh` with a hash, and the sentence occurs only once in the skill, so editing it would drift the include check. The bytes came from the skill's own prose instead.

Removed from `<zone_constraints>` (replaced by `Zones per the frontmatter `zones:` and CLAUDE.loa.md: the app zone is **Read-only**.`):

```
Three-Zone Model per CLAUDE.loa.md: `.claude/` system = never edit; `grimoires/loa/`, `.beads/` state = read/write; app zone (`src/`, `lib/`, `app/`) = **Read-only**.
```

Removed from `<checklists>` (the list repeats `resources/REFERENCE.md` §Red Flags):

```
 (private keys, SQL concatenation, unvalidated input, empty catch blocks, missing tests, N+1 queries)
```

Size: 16,306 B before, 16,367 B after (limit 16,384 B).

---

## Assumptions

- [ASSUMPTION fact] The `trajectory_logging` block in `reviewing-code/SKILL.md` is rendered from `.claude/data/skill-includes/trajectory_logging.md` and hash-checked; the skill has no second copy of the log-path sentence, so D-10.2's byte source does not exist as described.
- [ASSUMPTION decision] The removed bytes are the zone sentence (repeats the frontmatter `zones:` block and the kernel's Three-Zone table) and the Red Flags parenthetical (repeats `resources/REFERENCE.md` §Red Flags).
- [ASSUMPTION decision] The axis sentence sits in Phase 2 after the "check the acceptance criteria" paragraph, prefixed `**Task kinds**:`, with the prompt's sentence verbatim.
- [ASSUMPTION decision] Only top-level checkbox lines are task lines; in a `### Task N.E2E` block only `- [ ] Task …` lines count, so acceptance checkboxes there are not tasks.
- [ASSUMPTION decision] Inline code spans are not tokens: they are stripped before counting, and a tag inside backticks does not satisfy the rule.
- [ASSUMPTION decision] The `kind` keyword and its value are lower case only.
- [ASSUMPTION decision] A pre-date or undated non-live plan gets one aggregated WARN; a live undated plan gets one violation and the rule stops, as the Seams gate does.
- [ASSUMPTION decision] The judgment WARN fires when at least one recognised file token is present and all are `.sh`/`.py`/`.ts`, or when `script`, `lint` or `generate` appears as a whole word outside inline code.
- [ASSUMPTION fact] The archived cycle-128 plan lives only in the main checkout (`grimoires/loa/archive/` is gitignored), so it is copied verbatim to `tests/fixtures/sprint-kinds/cycle-128-sprint.md`, following the cycle-127 Seams fixture.
- [ASSUMPTION decision] The Seams suite's fixture task line gains ` · kind: mechanical`; without it SEAMS-12's 2026-10-14 plan fails the new rule.
- [ASSUMPTION decision] The template tags its Sprint 1 and Sprint 2 example task lines, with the two-line kind explanation as an HTML comment beside the existing annotation comments.
- [ASSUMPTION decision] The eval task uses the `.yml` extension so `evals/suites/review-recall.yaml` (include `tasks/review-recall/**/*.yaml`) does not pick it up; `run-eval.sh --task` still finds it.
- [ASSUMPTION decision] The eval grader is `pattern-match.sh` with `[*][*]MEDIUM[*][*].*[Mm]echanical`, because `validate-task.sh` refuses `|` and `\` in grader args and the recall grader needs a manifest in B's corpus.
- [ASSUMPTION decision] The fixture lives under `evals/fixtures/review-kinds/`, outside B's `review-prs/` corpus and its `SHA256SUMS`.
- [ASSUMPTION decision] `cycle-ratio.sh` uses committer timestamps with both ends inclusive; prose bytes are the byte length of each added or removed `.md` line with its newline; renames detected; binaries skipped; git runs in the current directory's repository.
- [ASSUMPTION decision] `cycle-ratio.sh` reports untagged task lines in `--json` and on stderr, not in the `kinds:` line, which keeps the specified three counts.
- [ASSUMPTION decision] Only rows with `primitive_id` MODELINV and a parseable `ts_utc` are counted.
- [ASSUMPTION decision] Exit 2 also covers outside a repository, an unreadable plan and missing jq; a SHA starting with `-` is exit 3.
- [ASSUMPTION fact] Before this change, `shell-conventions.md`, `zone-state.md` and `zone-system.md` carried `paths:` frontmatter as a YAML list with `origin`, `version` and `enacted_by`; `stash-safety.md` and `skill-invariants.md` carried none and failed `validate-rule-lifecycle.sh`.
- [ASSUMPTION decision] The new frontmatter uses the same list form with `origin: enacted`, `version: 1`, `enacted_by: cycle-083`, taken from the introducing commits `d74b2886` and `d1e548d5`.
- [ASSUMPTION fact] Under git's `:(glob)` semantics `shell-conventions.md`'s `"*.sh"` and `"*.bats"` match no tracked file, and `zone-state.md`'s `.beads/**` and `.ck/**` match none by design. `rule-paths.bats` therefore lints only the two files in scope; the lead's harness observation may show whether Claude Code matches `*.sh` at any depth.
- [ASSUMPTION decision] The FR-1.2b message already ended `Rules: .claude/rules/stash-safety.md`; that tail became `; see .claude/rules/stash-safety.md`.
- [ASSUMPTION decision] The `implementing-tasks` app-zone value is `read-write`, from the vocabulary `none | read | read-write` in use; `run-bridge` uses `read-write` for its app zone; the only test pinning app `read` covers the review and audit skills.
- [ASSUMPTION decision] The stale protocol numbers in `prompt-budget.bats`'s header comment were corrected with the workflow comment; they are the same drift.
- [ASSUMPTION fact] Hunks shared with implementer A in `validate-artifact.sh`: the header comment, the usage text, one call line after `validate_sprint_seams` in `validate_sprint`, and a new block after `validate_sprint_seams`'s closing brace. A marker of A's placed at either of those spots will need a hand merge.
- [ASSUMPTION fact] The prompt's `.claude/scripts/check-no-raw-sha256sum.sh` does not exist; `tools/check-no-raw-sha256sum.sh` was run.
