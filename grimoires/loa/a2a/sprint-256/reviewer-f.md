# Sprint 256 (cycle-129 Sprint 2) — Implementation Report, implementer F

**Implementer:** F, Claude Opus 5.5 subagent (model id `global.anthropic.claude-opus-5-5`)
**Tasks:** 2.4 → 2.7 → 2.2 → 2.3 · **Worktree:** `loa-wt-s2c` (branch `wt/cycle-129-s2c` at `b6802e4f`), nothing committed
**Patch:** `~/.cache/loa/cycle-129/patches/s2-f.patch` (47 files, `git diff --cached --binary`)

## Executive Summary

All four tasks are done and tested. The guardrail defaults are off in the example, this repository keeps input guardrails on as telemetry, and danger-level enforcement is off here too. The five C-TEAM rows are gone: the generator prunes the empty Agent Teams table, the lint checks the table follows its class, and the kernel dropped from 10,225 B to 9,189 B. `profiles.yaml` and `profile-lib.sh` resolve the nine optional keys with an mtime-keyed cache. Every reader goes through `loa_knob`, a grep lint guards that, and `/loa` prints the profile line. Three pure-review skills carry the write-tool strip and the validator fails any that lack it. The surgical-diff hook keys on the checkpoint task, writes the summary, and bounds its directory.

Two findings change the picture:

- **yq's `//` reads an explicit `false` as absent.** Three of the readers (`guardrails.input.enabled`, `guardrails.danger_level.enforce`, `require_success_criteria`) could never be turned off. The D-4.4 default change would have been inert without the lib, which tests presence instead.
- **`rtfm-testing` is not pure-review.** Its Phase 4 writes a report under `grimoires/loa/a2a/rtfm/`. I reclassified it as a report author rather than strip Write (see the assumption lines).

## AC Verification

> AC-2.2 A pure-review skill without the strip fails `skill-capabilities.bats`; the four skills carry it; `skill-invariants.md` names the Bash gap (PRD AC-4.2)

**Status:** ✓ Met for three skills, with one reasoned exception. The fourth, `rtfm-testing`, is reclassified as a report author; it is not stripped of Write.
- `.claude/scripts/validate-skill-capabilities.sh:622` adds the rule. It errors by name for `role: review` + `write_files: false` without Write, Edit and NotebookEdit. `PURE_REVIEW_STRIP` sits at `:95`.
- `tests/unit/skill-capabilities.bats:944`, `:951`, `:958`, `:969`, `:998`, `:1017` and `:1030` hold the c129-D4.2 cases.
- The strip is at `.claude/skills/eval-running/SKILL.md:6`, `.claude/skills/flatline-knowledge/SKILL.md:6` and `.claude/skills/validating-construct-manifest/SKILL.md:5`.
- `.claude/skills/rtfm-testing/SKILL.md:7` strips Edit and NotebookEdit and keeps Write for its report. Its Write step is at `SKILL.md:267` (`Write to: grimoires/loa/a2a/rtfm/report-{YYYY-MM-DD}.md`) and `:396`.
- `.claude/rules/skill-invariants.md:67` holds "The Bash gap" paragraph. The rows naming the classes come just before it.

> AC-2.3 The surgical-diff counter resets when the checkpoint task changes and keys on the session id when no task is active; the summary file exists after a write; the state directory is bounded (PRD AC-4.3)

**Status:** ✓ Met.
- Key selection is at `.claude/hooks/quality/karpathy-surgical-diff-check.sh:129-138`: the task from `run-checkpoint.sh read --json`, else the sprint, else the session id.
- The legacy file is deleted at `:141`. The per-task file and its 20-file cap follow, and the summary is written at `:177`.
- `tests/unit/karpathy-surgical-diff.bats` covers it: reset on task change (KS-1), session-id key (KS-2), and sprint key while the bead is open (KS-3).
- The same suite covers the summary fields and unchanged warning (KS-4), the bound of 20 (KS-5), legacy deletion (KS-6), sanitised names (KS-7), knob off and `lean` (KS-8), no content leak (KS-9), symlinks (KS-10) and malformed payloads (KS-11).

> AC-2.4 The example reads `false` for both guardrail keys; this repository reads `guardrails.input.enabled: true` and `danger_level.enforce: false`; the orchestrator tests pass with the knob on; the CHANGELOG carries the migration notes (PRD AC-4.4)

**Status:** ✓ Met for my part. The CHANGELOG note is Task 2.9, the lead's.
- The example sets `false` at `.loa.config.yaml.example:1313` and `:1359`, with the evidence comment above the block.
- This repository sets `true` and `false` at `.loa.config.yaml:625-629`, a new `guardrails:` block. Nothing else in that file changed.
- `tests/unit/guardrails-orchestrator-file-input.bats` passes 4/4 against this repository's config, which has the knob on.
- `tests/unit/profile-lib.bats` PL-15 drives the orchestrator and the enforcer with the knob both on and off.
- Migration lines for the lead's CHANGELOG:
  - The example now ships `guardrails.input.enabled: false` and `guardrails.danger_level.enforce: false`. Set them `true` to restore the old behaviour.
  - An explicit `false` is now honoured. Before this change both keys read `true` whatever they were set to.

> AC-2.5 `constraints.json` has no C-TEAM rows; the kernel regenerates without the Agent Teams table; the reference states the rules and the arming variable; the three team hooks are `dormant` in the register (PRD AC-4.5)

**Status:** ✓ Met.
- `.claude/data/constraints.json` loses its C-TEAM rows in a pure deletion of 105 lines.
- `.claude/scripts/generate-constraints.sh:41` defines `OPTIONAL_TABLES`, and `prune_optional_table` is at `:167`.
- `.claude/loa/CLAUDE.loa.md` was regenerated with no `## Agent Teams` table.
- `.claude/loa/reference/agent-teams-reference.md:32` adds "## Rules and arming", with the five rules and their rationales verbatim. The arming note is at `:44`.
- `.claude/data/guard-origins.yaml` already lists the three team hooks as `dormant` with knob `LOA_TEAM_MEMBER` (Sprint 1).
- Tests: `tests/unit/lint-invariants.bats` LI-1 to LI-9, and `.claude/scripts/lint-invariants.sh:229` (`check_optional_constraint_tables`).

> AC-2.9 `profile-lib.bats`: explicit key beats profile beats fallback; `standard` equals the post-cycle example defaults listed in `profiles.yaml`; `profile-floor.bats` passes under `lean`; `/loa` prints the profile and overrides (PRD AC-9.1 … AC-9.3)

**Status:** ✓ Met.
- `tests/unit/profile-lib.bats` covers precedence (PL-5, PL-6) and checks `standard` against the oracle and the example (PL-3, PL-4).
- It also covers the unknown profile (PL-7), cache rebuilds (PL-8, PL-9, PL-10), overrides (PL-11), floor keys refused (PL-12), malformed paths (PL-13), the `/loa` line (PL-14), readers (PL-15, PL-16) and the grep lint (PL-17).
- `tests/unit/profile-floor.bats` PF-1 to PF-7 pass.
- `/loa` prints the line from `.claude/scripts/loa-status.sh:942` (`display_profile_line`), called at `:694`.

> AC-2.12 After each patch apply the fence corpus and the hook bats were run before the next tool call relied on them, recorded in the report; every existing bats, pytest, vitest and fence-corpus suite is green on the sprint's final tree

**Status:** ⏸ The apply-time smoke run is the lead's step, after applying this patch. For my part:
- A 57-file sweep of every bats file touching what I changed gave 908 ok and 15 not ok.
- IG-11 was mine (my example comment named `implement_gate`). I fixed it and it now passes 23/23.
- The other 14 failures reproduce identically on a pristine `b6802e4f` worktree. They are listed under Known Limitations.
- The two pytest files that read the example config pass 60/60.

## Tasks Completed

- **Task 2.4.**
  - The oracle `tests/fixtures/profiles/standard-oracle.json` was captured first, from each reader's own yq expression against the example, this repository's config and an empty config.
  - Guardrail defaults changed in the example and in this repository.
  - The C-TEAM rows were removed. The generator prunes the optional table; `agent_teams_constraints` is registered in `generate-constraints.sh` and `validate-constraints.sh`.
  - The lint invariant and its self-test cases were added. The reference section was added and the kernel regenerated.
  - Keeplist K-07 was retargeted to the reference heading, and IDR-3 now finds the C-TEAM rationales in the reference.
- **Task 2.7.**
  - Added `.claude/data/profiles.yaml` and `.claude/scripts/lib/profile-lib.sh`, which is also a CLI: `profile`, `source`, `knob`, `overrides`, `json`.
  - Rerouted readers: `loa-kf-surface.sh`, `loa-decisions-surface.sh`, `loa-l6-surface-handoffs.sh`, `loa-l7-surface-soul.sh`, `guardrails-orchestrator.sh` and `danger-level-enforcer.sh`.
  - Rerouted prose readers: the `implementing-tasks` gate line, the `retrospective_postlude` and `input_guardrails` includes (regenerated), and the two continuous-learning resources.
  - Added `tools/check-knob-readers.sh`, the `loa:` block in the example, and the `/loa` Profile line.
- **Task 2.2.**
  - The grep result is recorded under AC-2.2.
  - The strip went on three skills, with the validator rule, the bats cases and the skill-invariants rows plus the Bash gap paragraph.
  - Three effort-test fixtures in `skill-capabilities.bats` were pure-review-shaped, so they now carry the strip.
- **Task 2.3.**
  - Rewrote the hook.
  - Migrated `karpathy-surgical-diff-hook.bats` and `karpathy-trajectory-event.bats` to the new seams.
  - Added `karpathy-surgical-diff.bats` and the SURGICAL line in `reviewing-code`.

## Technical Highlights

- **Presence-tested reads.** `loa_knob` resolves through `getpath` and tests for null, never `//`. PL-6 pins that an explicit `false` beats `full`.
- **Floor unreachable.** Profile keys matching `floor.yaml` `floor_keys` are dropped with a WARN. A `*` matches one or more characters, and an ancestor such as `flatline_protocol` also counts. PF-2 and PL-12 pin this, and PF-1 reads the pin constant from `guard-origins.bats`.
- **Cache.** `.run/effective-config.json` is keyed on the three paths plus `stat` mtime (nanoseconds) and size. The warm path is one stat and one jq, and the write is temp-file plus `mv`. A seam config writes no cache unless `LOA_PROFILE_CACHE_FILE` is set, so tests never touch the repository cache.
- **Path safety.** Key paths must match `^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$` before reaching yq (PL-13).
- **Hook simplification.** Per-task state files are small and rotated, so the hook drops the earlier config-token and state-aggregate caches. It went from 848 lines to about 220.

Measured cost per hook call:

| Path | Cost |
|---|---|
| Hook, production path, no run state, cached profile | about 43 ms |
| Hook, with checkpoint read and `br show` | about 107 ms |
| `loa_knob` warm, via the CLI | about 15 ms |

## Testing Summary

| Command | Result |
|---|---|
| `bats tests/unit/profile-lib.bats` | 17/17 |
| `bats tests/unit/profile-floor.bats` | 7/7 |
| `bats tests/unit/karpathy-surgical-diff.bats karpathy-surgical-diff-hook.bats karpathy-trajectory-event.bats karpathy-config-schema.bats` | 24/24 |
| `bats tests/unit/lint-invariants.bats` | 9/9 |
| `bats tests/unit/skill-capabilities.bats validation-skill-contracts.bats skill-inputs-manifest.bats aleph-opt-in.bats agent-ergonomics-*.bats` | 74/74 |
| `bats tests/unit/implement-gate.bats` | 23/23 |
| `bats tests/unit/instruction-diet-revert.bats prompt-audit-keeplist.bats prompt-audit-generated-blocks.bats` | green |
| `bats tests/unit/prompt-budget.bats guard-origins.bats floor-snapshot.bats kf-surface.bats loa-decisions-surface.bats` | green, inside the sweep |
| 57-file sweep (log `~/.cache/loa/cycle-129/s2f/sweep1.log`) | 908 ok, 15 not ok; IG-11 fixed after; 14 pre-existing |
| `bash .claude/scripts/test-lint-invariants.sh` | 18/18 (baseline was 11/13) |
| `bash tools/check-prompt-budget.sh` | exit 0 |
| `bash tools/check-glossary-terms.sh` | PASS (one advisory WARN, unchanged class) |
| `bash .claude/scripts/validate-skill-capabilities.sh` | 37/37, 0 errors, 3 warnings |
| `bash tools/check-no-raw-sha256sum.sh` | OK |
| `bash .claude/scripts/generate-skill-includes.sh --check` | current |
| `bash .claude/scripts/validate-constraints.sh` | 0 errors, 0 warnings (was 1 orphan-marker warning) |
| `bash .claude/scripts/guard-yield.sh --check` | in sync (95 guards) |
| `bash tools/check-knob-readers.sh` | clean (9 keys) |
| `python3 -m pytest .claude/adapters/tests/test_anthropic_catalog_floor.py test_model_auth_metadata_validator.py` | 60/60 |

The skill-capabilities warnings are two baseline review-keyword warnings plus one more of the same class.

Kernel byte count:

| File | Before | After |
|---|---|---|
| `.claude/loa/CLAUDE.loa.md` | 10,225 B | 9,189 B |

The cap is unchanged; lowering it is Task 2.8.

Skill byte counts (cap 16,384):

| Skill | Before | After |
|---|---|---|
| reviewing-code | 16,367 | 16,358 |
| implementing-tasks | 16,280 | 16,275 |
| auditing-security | 16,268 | 16,267 |
| autonomous-agent | 16,328 | 16,327 |
| bug-triaging | 16,181 | 16,180 |
| deploying-infrastructure | 16,294 | 16,293 |

## Removed `reviewing-code` text

Removing the footer offsets the SURGICAL sentence; the net change is −8 B, plus −1 B from the shared include. The removed text is the end of `.claude/skills/reviewing-code/SKILL.md`:

```
## Provenance

Folded in from history: AC Verification auto-fail (cycle-057, #475), Fast-Gate Parity (#1086), YAGNI taxonomy (#1012).
```

The added sentence, appended to the Karpathy Principles line:

```
`SURGICAL:` reads `.run/karpathy-surgical-summary.json` and `.run/karpathy-surgical/<bead>.jsonl` (sprint beads) when present.
```

## Harness probe instructions for the lead (Task 2.2)

The probe checks the live harness, after the patch is applied in the main checkout.

1. Start a fresh Claude Code session in the main checkout. Skill frontmatter is read at invocation, and `disallowed-tools` needs Claude Code 2.1.152 or later.
2. Invoke the Skill tool with `skill: "flatline-knowledge"` and args `harness probe, no query`. This skill has no side effects and only Read, Grep and Glob grants.
3. While the skill is active, attempt a Write to `grimoires/loa/a2a/sprint-256/probe-disallowed-tools.txt` with content `probe`. Then attempt an Edit of the same path, and a NotebookEdit on any path.
4. Record the harness response verbatim for each of the three attempts. Enforcement shows as the tool being unavailable or refused.
5. As a control, repeat the Write in a turn with no skill active. It should succeed; delete the probe file afterwards.
6. Optionally repeat steps 2 to 4 with `eval-running`.

**Fallback if the Write succeeds inside the skill.** Switch the three skills to an explicit read-only `allowed-tools` set: `Read, Grep, Glob`, plus `eval-running`'s two Bash grants. Then state in `skill-invariants.md` that `disallowed-tools` is not enforced and that `allowed-tools` is the barrier. The existing validator rule ("write_files false with Write in allowed-tools is ERROR") already backs that.

The probe must then also show that `allowed-tools` restricts and does not merely pre-approve. If it only pre-approves, neither key is a barrier. The honest statement is then that only the zones and the fence stand between these skills and a write.

## Known Limitations

- **Pre-existing failures** reproduce identically on pristine `b6802e4f`:
  - `cycle-098-cross-primitive-l7.bats` T-CHAIN-1 and T-CHAIN-3.
  - `test_process_compliance.bats` cases 6, 7, 9 and 10.
  - `hook-wiring.bats` W6.
  - `scheduled-cycle-skill-3D.bats` case 10.
  - `trust-concurrent-and-disable.bats` cases 1, 2, 3, 7, 9 and 13.
- **Guardrail sub-check defect, not fixed.** `guardrails-orchestrator.sh` `is_check_enabled` and `get_check_mode` still use `// default`. A sub-check set to `enabled: false` reads as true, including `relevance_check`, which the example documents as disabled by default. It is outside the profile set; a bead is suggested.
- **Retrospective now runs here.** This repository had no `invisible_retrospective` key, and the prose ran the scan only on an explicit true. `standard` sets it true, so the retrospective postlude now runs in this repository. I left `.loa.config.yaml` otherwise untouched as instructed. Add `invisible_retrospective: {enabled: false}` there to keep today's behaviour.
- **A copied example defeats `lean`.** An operator who copies the whole example has every profile key set explicitly, so `loa.profile: lean` has no effect until those keys are deleted. The `/loa` overrides list shows this.
- **Mid-task the hook keys on the sprint.** `run-checkpoint.sh read --json` discards a checkpoint whose task is still open in beads. During a task the key is therefore the sprint, and it is the task only after a checkpoint names a closed bead. KS-3 pins this; it follows the spec literally.
- **Lint blind spots.** `check-knob-readers.sh` misses runtime-assembled key paths and readers that index the config as nested keys in another language.
- **Hand-written copy left for D.** `run-mode/SKILL.md:26` keeps its own copy of the old guardrails skip prose. It is implementer D's file; the orchestrator now answers PROCEED with "guardrails disabled in config" whichever way that prose reads.
- **Overlap with implementer D.** `implementing-tasks/SKILL.md` carries my two regenerated include blocks and the gate line, in hunks separate from D's marker lines.
- **Profile not in JSON.** `loa-status.sh --json` does not carry the profile; I kept that hunk self-contained.
- **No floor rows in the corpus yet.** The fence corpus has no FR-1.2b or FR-SZ rows today. PF-6 compares every corpus row and adds five inline floor probes.
- **Left for the lead.** REPO-MAP, `checksums.json` and the CHANGELOG were not touched; they are Task 2.9.

## Verification Steps

```bash
git apply --index ~/.cache/loa/cycle-129/patches/s2-f.patch
BATS=$(cat ~/.cache/loa/cycle-128/bats-path)
LOA_HARNESS_CHECK=0 LOA_AUDIT_REPLAY=1 $BATS tests/unit/profile-lib.bats tests/unit/profile-floor.bats \
  tests/unit/karpathy-surgical-diff.bats tests/unit/lint-invariants.bats tests/unit/skill-capabilities.bats
bash tests/fixtures/fence-corpus/run-corpus.sh
bash tools/check-prompt-budget.sh && bash tools/check-knob-readers.sh && bash .claude/scripts/generate-skill-includes.sh --check
bash .claude/scripts/loa-status.sh | grep '^Profile:'
```

The last line should print `Profile: standard (explicit overrides: guardrails.input.enabled=true, known_failures.surface_at_session_start=true)`.

## Assumptions

- [ASSUMPTION fact] yq's `//` treats `false` as absent, so `.guardrails.input.enabled // "true"`, `.guardrails.danger_level.enforce // true` and `.karpathy_principles.require_success_criteria // true` returned true for an explicit false. `loa_knob` tests presence instead.
- [ASSUMPTION fact] `validate-skill-capabilities.sh` FR-4 reads `.capabilities.write_files // "null"`, which turns false into "null". That check only tests for true, so it is harmless there; the new rule reads without `//`.
- [ASSUMPTION fact] The guard register already had the three team hooks as `dormant` with knob `LOA_TEAM_MEMBER`, and the three `kind: policy` rows, from Sprint 1. I made no register edit.
- [ASSUMPTION fact] The fence corpus has no FR-1.2b or FR-SZ rows at `b6802e4f`.
- [ASSUMPTION fact] 14 failing bats cases in five files reproduce identically on pristine `b6802e4f`.
- [ASSUMPTION fact] This repository's `invisible_retrospective.enabled` was absent, so the scan was off. Under `standard` it is on.
- [ASSUMPTION decision] The oracle is each reader's expression evaluated over the shipped example. This repository's values and the empty-config values are recorded alongside, and the guardrail keys carry today's and the post-change values side by side.
- [ASSUMPTION decision] `rtfm-testing` is reclassified as a report-writing review skill rather than stripped, because its documented Phase 4 writes a State-Zone report. Its frontmatter is `write_files: true`, Write added to `allowed-tools`, `disallowed-tools: [Edit, NotebookEdit]`, and it is added to `REVIEW_WRITE_EXCEPTIONS`. This deviates from DEC-0142's list of four; the alternative is to strip it and drop or relocate its report.
- [ASSUMPTION decision] The generator handles the empty class with an `OPTIONAL_TABLES` prune. `agent_teams_constraints` is registered in the SECTIONS of both `generate-constraints.sh` and `validate-constraints.sh`, so restored rows render and validate.
- [ASSUMPTION decision] Keeplist K-07 now protects the reference's "Rules and arming" heading, and IDR-3 reads the C-TEAM rationales from the reference table.
- [ASSUMPTION decision] The lint self-test's two baseline failures (a good fixture that only WARNs exits 1) were fixed by asserting exit 0 or 1, as the test's own description states.
- [ASSUMPTION decision] The `reviewing-code` bytes came from removing its `## Provenance` footer. The no-history lint allows that footer but does not require it.
- [ASSUMPTION decision] The lib honours `LOA_STATUS_CONFIG_FILE` only under bats markers, as `loa-status.sh` does. `LOA_PROFILE_CONFIG_FILE` is ungated because hooks pass their own config seam through it.
- [ASSUMPTION decision] The cache key also covers file size and `floor.yaml`, not only the two mtimes.
- [ASSUMPTION decision] A floor `*` matches one or more characters including dots, and an ancestor of a floor key is forbidden too.
- [ASSUMPTION decision] The `input_guardrails` include was rerouted although the prompt's reader list omitted it. It reads `guardrails.input.enabled`, and the change is −1 B.
- [ASSUMPTION decision] The hook's perf caches are removed, and on its first run the hook deletes the two old cache files when it uses the default state directory.
- [ASSUMPTION decision] The hook always exits 0. The old exit 5 on a non-object payload is gone, consistent with its non-blocking contract.
- [ASSUMPTION decision] State entries gain a `task` field. The summary has exactly the five specified fields.
- [ASSUMPTION decision] Task keys are sanitised inside jq, so a newline in a task label cannot truncate the key, and a leading dot becomes `_` so no hidden file escapes rotation.
- [ASSUMPTION decision] The `/loa` Profile line is human output only.
- [ASSUMPTION decision] The example's `loa:` comment does not name `implement_gate` (IG-11 forbids it until implementer D documents the gate). It points at `floor.yaml` for the floor keys.
