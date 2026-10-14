# Implementation Report: Sprint 1 (global sprint-255), implementer A — guard register and yield

**Date:** 2026-10-14
**Engineer:** Sprint Task Implementer Agent (implementer A), model id `global.anthropic.claude-opus-5-5` (Opus 5.5)
**Sprint Reference:** grimoires/loa/sprint.md, Sprint 1, Tasks 1.1, 1.2, 1.3
**Worktree:** `/home/merlin/Documents/thj/code/loa-wt-s1a` (branch `wt/cycle-129-s1a` at `ffd25258`, uncommitted; patch `~/.cache/loa/cycle-129/patches/s1-a.patch`)

---

## Executive Summary

Every guard now has a row with an origin. `.claude/data/guard-origins.yaml` holds 94 rows: 30 hook scripts, 34 fence pattern ids, 18 validator rules, 9 gates and 3 floor policies. `.claude/data/floor.yaml` is the one floor source, and its 21 floor ids equal the `floor: true` rows. `.claude/scripts/guard-yield.sh` enumerates the guards from the repository (settings.json commands parsed against the canonical schema, `# @guard fence:` markers cross-checked both ways against the fence's call sites, `# @guard validator:` markers), fails with exit 5 on any gap, writes the structural `grimoires/loa/guards.md`, the host yield `.run/guard-yield.{md,json}`, and the generated registration table in `hooks-reference.md`. `--check` is the CI drift gate and is wired into the Shell Tests job.

The fence writes `replay: true` on its audit rows when `LOA_AUDIT_REPLAY=1` is set. `/loa` prints one Guards line. Four bats suites (33 cases) cover the register, the yield join, the floor snapshot and the status line.

The host yield on this machine differs from the inventory's estimate, and the reason matters. Every one of the 501 block rows in the live log carries the repository root as its cwd, so the specified cwd fallback catches no bats replays. The replays show up instead as eleven bursts of about 31 block rows within single minutes. I added a third fallback for that shape (10 or more block rows in one UTC minute), which removes 342 rows.

**Key Accomplishments:**
- Origin map and floor file seeded; every registered hook, fence id and validator marker has a non-empty origin (zero rows without one).
- `guard-yield.sh` with `--hooks-table`, `--check`, `--json`, exit codes 0/1/2/3/5 as specified, privacy enforced by construction and by test.
- The hand registration table (18 rows, six hooks missing) replaced by a generated 30-row table between markers.
- `/loa` Guards line with bats-gated seams; `LOA_AUDIT_REPLAY` honoured by the fence and exported by the corpus runner and the new suites.

---

## AC Verification

**AC-1.1**: "`guard-origins.bats` fails on a fixture hook without an origin and passes on the seeded map; every enumerated hook script and fence id has a row (PRD AC-1.1)"
- Status: `✓ Met`
- Evidence: `.claude/scripts/guard-yield.sh:316` — `"guard \(.) has no origin row in \($map)"` for every enumerated hook, fence or validator id absent from the map, exit 5; `:317-319` rows that resolve to nothing; `:216` the canonical-schema failure naming the command.
- Test: `tests/unit/guard-origins.bats:134` GO-11 (fixture registration of `stop-input-probe.sh` without a row fails by name); `:62` GO-3 and `:72` GO-4 (independent enumeration of hook scripts and fence ids, set-equal to the map, non-empty origins); `:82` GO-5 (validator markers); `:100` GO-7 (`floor: true` set equals `floor.yaml`); `:119` GO-9 (seeded map passes).

**AC-1.2**: "`guard-yield.bats`: replay rows (cwd under the temp dir or `/bats-run-`) are excluded and counted in the header; a rotated segment is read; heredoc, scratch-path and prose-class blocks classify as likely false positives; `last_real_catch` is day-granular (PRD AC-1.2)"
- Status: `✓ Met`
- Evidence: `.claude/scripts/guard-yield.sh:499-501` `replay($burst)` (flag, cwd under `${TMPDIR:-/tmp}/`, `/bats-run-`, `/bats.`, `/evals/results/`, `/sandbox/`, burst minute); `:443` reads `audit.jsonl` and `audit.jsonl.*`; `:502-507` `outside_repo`, `destructive_start`, `heredoc`, `likely_fp`; `:543` `last_real_catch` via `strftime("%Y-%m-%d")`.
- Test: `tests/unit/guard-yield.bats:62` GY-1 (13 replays excluded: flag 1, cwd 2, burst 10; header counts); `:76` GY-2 (segment-only P3 catch counted, `last_real_catch` 2026-10-10); `:82` GY-3 (heredoc, outside-repo scratch path and SP-1 prose class are likely FP; FR-2-AMBIGUOUS with `rm` at statement start is real); `:92` GY-4 (day granularity).

**AC-1.3**: "`guards.md` on this host carries `scope: host`, the window, status per row and the per-guard snapshot, with no command text, cwd, hostname or model name; `.run/guard-yield.json` carries the live yield; `guard-yield.sh --check` exits 0 after generation, 1 after an origin edit, and 0 after a yield-only change (PRD AC-1.3, AC-1.4)"
- Status: `⚠ Partial` as worded, `✓ Met` against DEC-0162. The AC text predates DEC-0162 (SDD D-1.4): the tracked `guards.md` is structural only, so `scope: host`, the window and the per-guard yield snapshot are in `.run/guard-yield.md` and `.run/guard-yield.json`, not in `guards.md`. I followed the SDD and the lead's prompt. The lead should confirm the AC wording is read through DEC-0162.
- Evidence: `.claude/scripts/guard-yield.sh:359` the structural header; `:552` `scope: "host"` in the yield; `:419-439` `--check` compares `guards.md` and the hooks table byte for byte and never reads the audit log.
- Test: `tests/unit/guard-yield.bats:104` GY-5 (no command text, cwd, hostname or model name in any of the outputs); `:117` GY-6 (structural, no timestamp, identical across audit logs); `:134` GY-7 (`--check` 0, then 0 after a yield-only change, then 1 after an origin edit with the regenerate hint, then 1 after a purpose edit); `:172` GY-9 (`--json` shape).

**AC-1.4**: "`hooks-reference.md`'s table is the generated one and lists all registered hooks, including the six omitted before, with their registrations and status (PRD AC-1.4)"
- Status: `✓ Met`
- Evidence: `.claude/loa/reference/hooks-reference.md:170-204` the generated block (30 registration rows: Event, Matcher, Script, Status, Knob, Purpose), now including zone-write-guard, spiral-dispatch-guard, spiral-skill-sentinel, adversarial-review-gate, the Karpathy check, Setup and PermissionRequest; `.claude/scripts/guard-yield.sh:387` `render_hooks_ref`.
- Test: `tests/unit/guard-yield.bats:159` GY-8 (one row per registration, the omitted hooks present, matcher pipes escaped).

**AC-1.5**: "`/loa` prints the Guards line from `.run/guard-yield.json` or the regenerate hint; `.claude/settings.json` hook registrations and the fence pattern-id list are byte-identical before and after the sprint (the register disables nothing); `floor-snapshot.bats` passes; `dormant` rows are excluded from the inert-controls KPI (PRD AC-1.5)"
- Status: `✓ Met` for the line, the byte-identity and the snapshot. `⚠ Partial` for the KPI clause: no inert-controls KPI is computed anywhere in my scope. The register marks the three team guards `dormant` with `knob: LOA_TEAM_MEMBER`, and the yield JSON carries `status` per row and `totals.dormant`, so a KPI can exclude them by `status`. The KPI itself belongs to whoever defines it (Sprint 2 FR-4 or the lead).
- Evidence: `.claude/scripts/loa-status.sh:938` `display_guards_line`, called at `:694` after the Providers block.
- Test: `tests/unit/loa-status-guards.bats:26` LSG-1, `:33` LSG-2, `:41` LSG-3; `tests/unit/floor-snapshot.bats:44` FS-3 (settings.json `.hooks` identical to origin/main), `:48` FS-4 (fence pattern-id call-site list identical), `:25` FS-1, `:36` FS-2.

**AC-1.13**: "Every existing bats, pytest, vitest and fence-corpus suite is green on the sprint's final tree; the toolchain readiness check is recorded"
- Status: `⚠ Partial` (sprint-level; the final tree is the lead's merge). On my tree every suite touching a file I changed is green (table below), and the fence corpus is identical before and after my edits. I did not run the full `tests/unit/` sweep or vitest. The toolchain readiness check is Task 1.0, the lead's.

---

## Tasks Completed

### Task 1.1: Seed the origin map and create floor.yaml

**Status:** Complete

**Implementation approach:** Origins came from the control-surface inventory's cites, issue numbers in file headers and commit subjects, and `git log --follow --diff-filter=A` for the rest. The floor file follows D-9.2 and the prompt's list, plus a `floor_corpus` block naming the corpus rules.

| File | Action | Description |
|------|--------|-------------|
| `.claude/data/guard-origins.yaml` | Created | 94 rows; schema documented in the header |
| `.claude/data/floor.yaml` | Created | `floor_guards` (21), `floor_keys` (6), `floor_files` (4), `floor_corpus` |

### Task 1.2: guard-yield.sh, the markers, the yield join

**Status:** Complete

| File | Action | Description |
|------|--------|-------------|
| `.claude/scripts/guard-yield.sh` | Created | enumeration, cross-checks, register, yield, hooks table, `--check`, `--json` |
| `.claude/hooks/safety/block-destructive-bash.sh` | Modified | 44 `# @guard fence:<id>` marker lines (one per site); `replay: true` on the four audit-row jq calls when `LOA_AUDIT_REPLAY=1` |
| `.claude/scripts/validate-artifact.sh` | Modified | 18 `# @guard validator:<id>` marker lines, comment-only |
| `grimoires/loa/guards.md` | Created (generated) | structural register |
| `tests/unit/guard-yield.bats` | Created | 11 cases |
| `tests/fixtures/fence-corpus/run-corpus.sh` | Modified | `export LOA_AUDIT_REPLAY=1` |

### Task 1.3: lint suites, hooks table, `/loa` line, CI step

**Status:** Complete

| File | Action | Description |
|------|--------|-------------|
| `tests/unit/guard-origins.bats` | Created | 15 cases, sha256 pin of `floor.yaml` |
| `tests/unit/floor-snapshot.bats` | Created | 4 cases, skipped with a message when origin/main is unreachable |
| `tests/unit/loa-status-guards.bats` | Created | 3 cases |
| `.claude/loa/reference/hooks-reference.md` | Modified | hand table replaced by the markers and the generated rows; the unregistered stop-input-probe moved to a sentence below the block |
| `.claude/scripts/loa-status.sh` | Modified | `display_guards_line` with `LOA_STATUS_GUARDS_FILE` and `LOA_STATUS_GUARD_YIELD_FILE` seams |
| `.github/workflows/bats-tests.yml` | Modified | "Guard register drift gate" step after the yq install, before the test steps |

---

## Measured facts

| Measure | Value |
|---|---|
| Hook commands registered in `.claude/settings.json` | 30 |
| Of those wrapped in `hook-guard.sh` | 13 |
| Unique hook scripts (rows) | 30 (29 scripts plus `hook-guard.sh` itself) |
| Fence pattern ids (rows) | 34 (32 `emit_block` ids plus the `FR-SZ` and `FR-SZ2` audit constants) |
| Fence marker lines / sites | 44 / 44 (41 `emit_block` calls, 3 `pattern_id:` constants) |
| Validator markers (rows) | 18 |
| Gates / policies | 9 / 3 |
| Register total / floor / dormant / without origin | 94 / 21 / 3 / 0 |

This host's 30-day yield header (`.run/guard-yield.json`, generated from the main checkout's `.run/audit.jsonl`):

| Field | Value |
|---|---|
| generated_at | 2026-10-13 (UTC day) |
| window_days / scope | 30 / host |
| audit_segments | 1 |
| audit_rows_considered | 501 |
| replay_rows_excluded | 342 (flag 0, cwd 0, burst 342) |
| blocks_30d / real / likely FP / telemetry | 159 / 87 / 72 / 0 |

Hooks with no recorded origin in the inventory, the KF ledger or a header, and what I wrote (all `kind: design`, from the commit that added the file):

| Row | Origin written |
|---|---|
| `hook:scripts/upgrade-health-check.sh` | `design v1.5.0 692aa617` |
| `hook:scripts/check-updates.sh` | `design v0.14.0 1f448140` |
| `hook:pre-compact-marker.sh`, `hook:post-compact-reminder.sh` | `design v1.28.0 dd8f6bf4 (#181)` |
| `hook:scripts/cleanup-context.sh`, `hook:scripts/permission-audit.sh` | `design v0.19.0 b10450fa` |
| `hook:safety/spiral-skill-sentinel.sh` | `design cycle-072 598a88ee` |
| `fence:LEGACY` | `design cycle-111 sprint-164 check_and_block back-compat` |
| `gate:prompt-budget` | `design 00a6ce1e 2026-09-20` |

---

## Technical Highlights

- **Independent lint.** `guard-origins.bats` enumerates hooks, fence ids and markers with its own grep and jq, so a bug in `guard-yield.sh`'s enumeration cannot hide a gap.
- **Two-way fence cross-check.** Every `emit_block "<ID>"` site and every literal `pattern_id: "<ID>"` constant needs a same-id marker within the 8 lines above. Every marker needs a site within the 8 lines below. A non-literal `emit_block` first argument is an error.
- **Canonical hook schema.** It is parsed in jq. Arguments are limited to `[A-Za-z0-9._=-]` tokens, and `..`, `.` and empty path segments are refused. A symlinked script is resolved once and must stay under `.claude/`.
- **Privacy by construction.** No output path reads `command`, `cwd`, `model` or a hostname into a written field. Table cells are control-stripped and pipe-escaped.
- **Performance.** The join is a single jq pass. The live 10,591-row log takes under 0.4 s, and GY-11 bounds a 10,000-row log at 10 s.
- **FP heuristic.** The prompt's `destructive_verb_at_statement_start` list is used verbatim. The heredoc classifier hook point is `.claude/scripts/lib/heredoc-classifier.sh` defining `heredoc_nonexec <command>`, exit 0 when non-executing. The fallback is `<<` presence, which is what runs today.

---

## Testing Summary

| Command | Result |
|---|---|
| `bats tests/unit/guard-origins.bats tests/unit/guard-yield.bats tests/unit/floor-snapshot.bats tests/unit/loa-status-guards.bats` | 33/33 ok |
| `bats tests/unit/prompt-budget.bats tests/unit/skill-capabilities.bats` | 45/45 ok |
| 19 related suites (block-destructive-bash, -limitations, stash-safety, hook-guard, implement-gate, validate-artifact, validate-artifact-bsd, sprint-seams, glossary-terms, glossary-validator, symlink-manifest-glossary, no-history-in-rule-text, settings-permissions, user-invoked-commands, user-invoked-harness, loa-status-artefacts, loa-status-providers, loa-status-stale-worktree, agent-ergonomics-loa-status) | 607/607 ok |
| `pytest tests/unit/test_hook_issue_regressions.py tests/unit/test_hook_limit_assessments.py` | 38 passed, 412 subtests |
| `bash tests/fixtures/fence-corpus/run-corpus.sh` | benign 78/78, dangerous 100/100, residual 0/5; identical JSON to the unmodified hook |
| `bash tools/check-prompt-budget.sh` | exit 0 |
| `bash tools/check-no-raw-sha256sum.sh` | OK (the prompt's `.claude/scripts/` path does not exist; the scanner lives in `tools/`) |
| `bash .claude/scripts/validate-skill-capabilities.sh` | exit 0 |
| `bash .claude/scripts/guard-yield.sh --check` | in sync (94 guards) |

All bats runs used `LOA_HARNESS_CHECK=0 LOA_AUDIT_REPLAY=1`.

---

## Known Limitations

- **Residual replay leakage.** 54 identical P2 rows (`git push --force origin main`, in pairs from 2026-09-22 to 2026-10-13) are probably test leakage that no fallback rule catches. They count as real catches on this host. The `replay` flag at the source fixes this going forward, provided every suite exports `LOA_AUDIT_REPLAY=1`.
- **No shared bats setup helper.** There is none, and `tests/run-bats.sh` named in SDD D-1.3 does not exist. `LOA_AUDIT_REPLAY=1` is exported by `run-corpus.sh` and my four suites only. Suites that drive the fence against the live log still need it: `block-destructive-bash.bats`, `block-destructive-bash-limitations.bats` and `stash-safety.bats` at least. The CI job could also set it in its `env:` block.
- **Floor corpus rows.** `floor_corpus` names FR-1.2b and FR-SZ*, but `tests/fixtures/fence-corpus/corpus.jsonl` has no rows with those rules today (its rules are FR-1.1, 1.3–1.6, FR-2, P2, P3, SP-1). FS-2 compares empty sets. Their behavioural pins live in `stash-safety.bats` and `block-destructive-bash.bats`.
- **Implement-gate rows.** Today's implement-gate audit rows (`event: compliance.*`, no `hook` field) are not counted. The join counts `hook == "implement-gate"` rows, which Sprint 2's D-4.1 adds.
- **C's `sprint.kinds` marker.** When implementer C's `# @guard validator:sprint.kinds` marker lands, `guard-yield.sh` exits 5 until this row is added after `validator:sprint.beads-crosscheck` in `.claude/data/guard-origins.yaml`, followed by a rerun of `.claude/scripts/guard-yield.sh --hooks-table`:

```yaml
  - id: validator:sprint.kinds
    kind: validator
    class: script
    status: active
    origin: {kind: cycle, ref: "cycle-129 D-10.1"}
    knob: none
    floor: false
    registrations: []
    note: "validate-artifact.sh --type sprint: task lines carry kind: (plans dated from 2026-10-14)"
```

- **Generated files.** REPO-MAP and `checksums.json` were not regenerated (lead-owned). `guards.md` and `hooks-reference.md` are in the patch, regenerated on this tree.

---

## Verification Steps

```bash
cd /home/merlin/Documents/thj/code/loa-wt-s1a
bash .claude/scripts/guard-yield.sh --check
bash .claude/scripts/guard-yield.sh --audit-log /home/merlin/Documents/thj/code/loa/.run/audit.jsonl
jq 'del(.guards)' .run/guard-yield.json
LOA_HARNESS_CHECK=0 LOA_AUDIT_REPLAY=1 "$(cat ~/.cache/loa/cycle-128/bats-path)" tests/unit/guard-origins.bats tests/unit/guard-yield.bats tests/unit/floor-snapshot.bats tests/unit/loa-status-guards.bats
bash tests/fixtures/fence-corpus/run-corpus.sh
```

---

## Assumptions

- [ASSUMPTION decision] `hook-guard.sh` gets its own row (`hook:hook-guard.sh`, origin #1180) with the four unique registrations it wraps, so the register has 30 hook rows where the SDD counted 29.
- [ASSUMPTION decision] Hook ids for scripts outside `.claude/hooks/` are `hook:scripts/<name>`, keeping them distinct from hooks-dir root files such as `hook:loa-kf-surface.sh`.
- [ASSUMPTION decision] A registration with no matcher is written as the bare event (`SessionStart`), not `SessionStart:`.
- [ASSUMPTION decision] The fence register has 34 ids: the 32 `emit_block` ids plus `FR-SZ` (override bypass row) and `FR-SZ2` (bounded-marker allow row), which exist only as literal `pattern_id:` audit constants. Both are `floor: true`, per "every `fence:FR-SZ*` and `fence:FR-SZ2*` id".
- [ASSUMPTION decision] The FR-1.2b marker sits above the `if` that guards the call, 4 lines above `emit_block`, not directly above it. This keeps my hunk away from line 749, the message string implementer C edits, so the 3-way apply does not see adjacent changes.
- [ASSUMPTION decision] The `replay: true` field is added to all four fence audit-row writers (block, FR-MERGE-2 override, FR-SZ bypass, FR-SZ2 marker), not only `emit_block`. Rows are byte-identical when the variable is unset.
- [ASSUMPTION decision] A burst fallback is added to the replay rule: a UTC minute holding 10 or more block rows is a replay. The SDD's cwd fallback caught zero of this host's replays because every row's cwd is the repository root.
- [ASSUMPTION decision] `outside_repo` treats both this checkout and its main worktree (from `git rev-parse --git-common-dir`) as inside the repository. Other worktrees count as outside, which matches the inventory's "scratch or worktree path" FP class.
- [ASSUMPTION decision] Gate and policy rows carry an extra `script:` field naming the implementing file, so the lint can check that each gate's script exists. `gate:success-criteria` points at `implementing-tasks/SKILL.md` (class prose). `gate:dissent-budget` points at `adversarial-review.sh`, knob `flatline_protocol.code_review.budget_cents`. `gate:kinds` points at `validate-artifact.sh` ahead of C's rule.
- [ASSUMPTION decision] Hook rows carry `registrations` in the map, and the script fails (exit 5) when they differ from settings.json. A new registration therefore needs a map edit, which is the lint's purpose.
- [ASSUMPTION decision] Status calls: the mutation loggers, `permission-audit.sh` and the Karpathy diff check are `telemetry`. The three team guards are `dormant` with `LOA_TEAM_MEMBER`. `implement-gate.sh` is `active` with `implement_gate.mode`. `fence:LEGACY` is `active` with a note that `check_and_block` has no caller (there is no `unreachable` status).
- [ASSUMPTION decision] Class calls follow the inventory: blocking or asking hooks are `harness`; session-start surfaces, reminders and loggers are `script`; the Karpathy check is `harness` with `telemetry` status.
- [ASSUMPTION decision] The hook rows for `block-destructive-bash.sh` and `adversarial-review-gate.sh` are `floor: false`; the floor is carried by the fence-id rows and `gate:adversarial-review-gate`, exactly as `floor.yaml` lists.
- [ASSUMPTION decision] Validator rule ids beyond the prompt's minimum list are `sprint.goal-ids`, `sprint.deferred`, `bug-triage.schema`, `translation.citations`, `map.schema`, `map.beads`, `spike.sections` and `glossary.entries`. The `map.*`, `spike.*` and `glossary.*` families became concrete ids because `*` is not in the id pattern. WARN-only rules such as SDD framework versions and the final-sprint E2E warning got no marker.
- [ASSUMPTION decision] `--json` writes the files and prints the yield JSON on stdout, with the summary on stderr. `--check` never reads the audit log, so CI needs none.
- [ASSUMPTION decision] Extra flags `--settings`, `--fence`, `--validator`, `--hooks-ref` and `--now` exist for fixture tests and reproducible runs.
- [ASSUMPTION decision] The hooks table's "## All Hook Registrations" intro now names `.claude/settings.json` and the generator. The unregistered `stop-input-probe.sh` row became a sentence below the generated block.
- [ASSUMPTION decision] The CI step sits after the yq install, because the script needs yq, and before the first test step.
- [ASSUMPTION fact] `implement-gate.sh` origin is written `cycle-050 FR-7` from the SDD §3.1 example. Its first commit is `e0dac338` (2026-03-18, "sprint-104 … ADVISORY compliance hook prototype").
- [ASSUMPTION fact] `adversarial-review-gate.sh` origin `#552` comes from its first commit subject ("enforce Phase 2.5 at COMPLETED marker write (#552)"). That number may be the PR rather than an issue.
- [ASSUMPTION fact] FR-SZ* origin `#1044` comes from the fence comment "sprint-bug-213 / #1044". FR-SZ2* origin `cycle-122`, FR-MERGE-2 `cycle-122 C-MERGE-002`, SP-1 `cycle-128 D-5.4` and FR-NOTES `cycle-124 FR-10` come from the fence's section headers. P2–P4 `cycle-011` come from the hook's first commit `d432b6a1`. FR-1.x and FR-2-* `cycle-111` come from the header's DCG-port note.
- [ASSUMPTION fact] Validator origins: `cycle-119` for the families added in `531f8fb7`; `cycle-120 C-D5` for translation; `cycle-128` D-ids for the families added in `8dc4a49d`, `cea919ca` and `efacf754`.
- [ASSUMPTION fact] The live audit log's 501 block rows all have cwd equal to the main checkout root, and 342 of them fall in eleven one-minute bursts of 31 or 32 rows.
- [ASSUMPTION fact] `check-no-raw-sha256sum.sh` lives at `tools/`, not `.claude/scripts/`.
- [ASSUMPTION fact] GNU `parallel` is absent on this host, so bats `-j` cannot run; all suites ran serially.
