# Sprint 4 Implementation Report — Memory gate (FR-10) — cycle-124 "model-generation floor" (global sprint-238)

**Implementer:** Fable 5.1 lead (run mode, `/run sprint-plan`)
**Date:** 2026-09-22
**Sprint Reference:** grimoires/loa/sprint.md §Sprint 4 (tasks 4.1–4.3, 4.E2E)
**Base:** `51d18251` (Sprint 3 close) · **Epic:** bd-ianm · tasks bd-m2ml (4.1), bd-yml9 (4.2), bd-4q6k (4.3)

## Summary

Session memory is now bounded. `.claude/scripts/notes-guard.sh` gives NOTES.md a size gate (`check`, 100 KiB warn / 200 KiB block, direction-aware `--delta`), a heading-based default read (`read`: every `## Blockers`, the newest `## Session Continuity`, the 3 newest `## Decision Log` blocks by heading date, ≤ 69,632 B, loud drift fallback, never empty) and a tested rotation (`rotate`: archive fsynced before the live rewrite, existing target refused, tmp + mv, never stashes). Three fences call the gate: `notes-size-guard.sh` (PreToolUse Write/Edit/MultiEdit; denies only a growing write at/over the line), `FR-NOTES` in `block-destructive-bash.sh` (`>>` appends) and the writer gate in `update-notes-learnings.sh`. The recovery recipes and the two live readers go through `read`; the docs carry the thresholds and the accepted bypass classes; the memory-tool question is decided in writing (keep NOTES.md; no `memory_20250818`). Every task started with a failing test; 73 new/extended bats cases are green and the 216-case fence suite is unchanged apart from the three FR-NOTES additions.

Assumptions recorded (NOTES.md Decision Log, 2026-09-22 "Sprint 4 … implementation readings"): the `--delta` rule (block iff delta > 0 and size + delta ≥ 204,800), undated-block ordering, the retained-content shape of `rotate`, stderr + exit 2 as the hook's denial shape, and reusing `LOA_GRIMOIRE_DIR` (no new knob) for the learnings writer.

## Deliverables (sprint.md §Sprint 4)

| Deliverable | Where |
|---|---|
| `notes-guard.sh` (`check \| read [--full] \| rotate`) | `.claude/scripts/notes-guard.sh` (`cmd_check` :62, `cmd_read` :124, `cmd_rotate` :150; literals :33-35) |
| `tests/fixtures/notes/make-large-notes.sh` | generates `under/100k/200k/250k/750k/<bytes>` fixtures at test time; fixed shape (two Blockers blocks, dated SC/DL blocks in mixed order, the oversized block last) |
| `notes-size-guard.sh` + `settings.json` entry | `.claude/hooks/safety/notes-size-guard.sh`; `.claude/settings.json:580` and `.claude/hooks/settings.hooks.json:102` (5th entry of the Write\|Edit\|MultiEdit\|NotebookEdit array, behind `hook-guard.sh`) |
| `FR-NOTES` pattern | `.claude/hooks/safety/block-destructive-bash.sh:1277-1299` (pre-filter `*NOTES.md*`; match `>>[[:space:]]*[^;&|]*grimoires/loa/NOTES\.md($\|[^A-Za-z0-9._-])`; blocks only when `check` exits 3) |
| `update-notes-learnings.sh` writer gate | `.claude/scripts/update-notes-learnings.sh:24` (`LOA_GRIMOIRE_DIR`), `:148-157` (`notes_size_gate`, exit 3), `:175` (called before any write) |
| Readers/docs | `session-continuity.md:96,98,102,112`; `ride-translation.md:34`; `translating-for-executives/SKILL.md:180`; `structured-memory.md:28,30`; `context-engineering.md:15`; `hooks-reference.md:155-160,180` |
| Memo | `grimoires/loa/reports/2026-09-17-notes-vs-memory-tool.md` |
| Tests | `tests/unit/notes-guard.bats` (NG-1..NG-12), `tests/unit/notes-size-guard.bats` (NSG-1..NSG-10), `tests/unit/block-destructive-bash.bats:1489-1525` (FR-NOTES ×3), `tests/unit/notes-template.bats:254-272` (FR-10 ×3) |

## Test-first record

| Task | Failing first | Green after |
|---|---|---|
| 4.1 | `notes-guard.bats` 11/12 red (NG-10 vacuous until the script existed) with the fixture generator in place | 12/12 |
| 4.2 | `notes-size-guard.bats` 10/10 red; `block-destructive-bash.bats` 214–216 red (213 existing cases green, untouched) | 10/10; 216/216 |
| 4.3 | `notes-template.bats` 71–73 red (thresholds undocumented; `head -50` / `cat` readers live) | 73/73 |
| wiring | `hook-wiring.bats` W4 and `lint-invariants.sh --hooks-wiring-only` failed once the hook was wired only in `settings.json` — the hooks template needed the same entry (`settings.hooks.json:102`); both green after |

Two test-side corrections during the red→green pass, both recorded: NG-6's crossing case used a delta too large for the generator's ±63 B landing zone; the size-guard payloads (256 KB) exceeded the 128 KiB single-argument limit, so they now travel by file and stdin exactly as real hook input does.

## AC Verification

### AC-10.1 — `notes-guard.bats` with generated fixtures; read/check/hook/FR-NOTES/rotate/writer behaviours
- **Status**: ✓ Met
- **Evidence**:
  - 750 KB fixture (`make-large-notes.sh … 750k`, oversized Decision Log last): `read` ≤ 69,632 B and ≤ 20,000 tokens at `bytes*10/35`, non-empty, contains `## Blockers`, `## Session Continuity`, `## Decision Log`, names `read --full` — NG-1 (`notes-guard.bats:30-43`; cap logic `notes-guard.sh:138-142`).
  - Selection: both Blockers blocks, only `NEWEST-CONTINUITY-0910` (the mid-file, newest-dated block), only D-0905/D-0904/D-0903, Blockers before SC before the Decision Logs newest-first — NG-2 (`:45-69`; `select_ranges` `notes-guard.sh:103-112`).
  - Template drift: `NOTES-GUARD: no known sections …` then the head; empty file still non-empty output — NG-3 (`:71-81`; `notes-guard.sh:129-133`).
  - `read --full` byte-identical — NG-4 (`cmp`).
  - `check`: silent < 100 KiB; `NOTES-WARN` + exit 0 at 100 KiB; `NOTES-BLOCK` naming `notes-guard.sh rotate` + exit 3 at 200 KiB; missing file exit 0 — NG-5 (`notes-guard.sh:62-78`).
  - `--delta` direction-aware and crossing-aware — NG-6.
  - Hook: growing Write denied (exit 2, remedy), shrinking allowed — NSG-1/NSG-10; Edit growing/shrinking — NSG-2; `replace_all` × occurrences crosses the line, single edit does not — NSG-3; MultiEdit sums — NSG-4; other path / missing file / unparseable payload exit 0 — NSG-5; symlink, relative path (cwd = grimoire dir) and a different `LOA_GRIMOIRE_DIR` reach the same decisions — NSG-6; below 200 KiB allowed — NSG-7; fail-open under `hook-guard.sh` — NSG-8; wired behind `hook-guard.sh` — NSG-9 (`notes-size-guard.sh:43-44,70,74-75,83-84,95-98`).
  - `FR-NOTES`: `>> grimoires/loa/NOTES.md`, `>> "${PROJECT_ROOT}/grimoires/loa/NOTES.md"` and a heredoc `cat >> …/NOTES.md` blocked at 200 KiB with `rotate` in the message; allowed at 100 KiB and below; reads, `notes-guard.sh rotate`, `NOTES.md.bak`, other files and a missing NOTES.md never blocked — `block-destructive-bash.bats:1489-1525`; existing 213 cases green unmodified.
  - `rotate` not blocked at 200 KiB and `check` silent afterwards — NG-9.
  - `update-notes-learnings.sh` exits 3 with `NOTES-BLOCK` on stderr and the file byte-identical at 200 KiB; appends below the line — NG-11 (`update-notes-learnings.sh:148-157,175`).

### AC-10.2 — `rotate` invariants
- **Status**: ✓ Met
- **Evidence**: NG-7 (`notes-guard.bats:126-152`): archive bytes == original (`cmp`); archived + retained ≥ original; retained < 100 KiB with `## Session Continuity`, `## Decision Log`, `## Blockers` and `## Archive pointers` naming the archive (so `check-loa.sh check_notes_template`'s two required-heading greps still pass); archive mtime ≤ live mtime in nanoseconds (archive written and `sync -d`'d before the tmp + `mv`, `notes-guard.sh:163-175`); `git check-ignore -q grimoires/loa/archive/notes/…` true (`.gitignore:185`). NG-8: an existing target is refused with exit 4 and the live file is unchanged (the test pre-creates the target names for the current and the next second, so the collision is race-free). NG-10: no `git stash` anywhere in the script.

### AC-10.3 — memo, docs, `notes-template.bats` extensions
- **Status**: ✓ Met
- **Evidence**: memo present (`grimoires/loa/reports/2026-09-17-notes-vs-memory-tool.md`: decision, four reasons, what FR-10 delivers instead, revisit triggers); `context-engineering.md:15` "Memory size gate" row (and the stale `.gitignore:293` citation replaced); `structured-memory.md:28` threshold row + `:30` bounded default read; `session-continuity.md:96-98` tier table and `:102`/`:112` recipes; `notes-template.bats:254-272` — thresholds documented (100 KiB / 200 KiB), the unbounded-`cat`/`head` reader set under `.claude/` is empty (frozen `config/translate-ride-v{2,3,4}.md` snapshots excluded; `cat >` writers do not match), Level 1/3 recipes go through `notes-guard.sh`; the 70 pre-existing assertions untouched.

### Sprint-level rows
- `block-destructive-bash.bats` existing cases green unmodified — ✓ 216/216 (three appended cases; no existing case edited).
- `notes-template.bats` existing assertions untouched — ✓ (append-only; 73/73).
- Karpathy: thresholds as literals, no config key, no env knob (the learnings writer reuses the existing `LOA_GRIMOIRE_DIR` contract); `notes-guard.sh` is 180 lines including its header; the hook has no dependency beyond `jq`, `realpath`, `stat`.

## Task 4.E2E — End-to-End Goal Validation

| Goal | Validation action (as planned) | Result |
|---|---|---|
| G-1 | `test_anthropic_thinking.py`, `test_max_tokens_defaults.py`, `test_tool_choice_no_forced_modes.py`; `cycle-124-effort-flag.bats`; `--effort xhigh` dry-run ≥ 64,000 | 70 pytest passed; bats 9/9; `cheval --agent flatline-dissenter --model claude-opus-5 --effort xhigh --dry-run` → `max_tokens 64000`, `effort xhigh` (same for `claude-fable-5-1`) |
| G-2 | `cheval --dry-run --model opus\|fable`; drift gates | resolved ids `claude-opus-5`, `claude-fable-5-1`; `tools/regen-model-artifacts.sh --check` OK; `gen-adapter-maps.sh --check` OK; `gen-bb-registry:check` rc 0; `build:check` (BB dist fresh) rc 0 |
| G-3 | `cycle-124-cache-telemetry.bats`; eligibility table | 8/8; the eligibility table and the live-scaffold operator step are in the Sprint 1 report (`a2a/sprint-235/reviewer.md`) — unchanged |
| G-4 | corpus suites + ratio one-liner | `adversarial-review-schema-enforced.bats` + `corpus-loader.bats` 25/25, `test_corpus_loader.py` 14 passed; enforced-subset rejections in every sprint-237 sidecar: 0; ratio one-liner on the live `.run/model-invoke.jsonl` (this window): `6 adversarial-audit openai:codex-headless cli false`, `7 adversarial-review openai:codex-headless cli false` — no `claude-headless` rows in the window (every dissent ran on the codex hop, which cannot enforce; the 3/3 enforced `claude-headless` rows are in the Sprint 2 archive) |
| G-5 | `golden-path-c8-verdict-trailer.bats` | 33/33 (inconsistent trailer never reviewed) |
| G-6 | sha256 of both ledgers before/after the full local unit suite; tripwire | see the G-6 paragraph below |
| G-7 | `check-prompt-budget.sh`; `capture.sh --verify`; `compare.sh` | budget exit 0 (skills ≤ 16,384 B; protocols 199,525 B ≤ 200,000, warn line still exceeded — bd-72fq); goldens 32/32; A/B compare outputs as recorded in `a2a/sprint-237/ab/compare/` (recall/FP/tokens gates met or residual reported, environment caveat stated) |
| G-8 | `notes-guard.bats` headline case | NG-1: ≤ 69,632 B, ≤ 20k tokens, non-empty, all three headings |

**G-6** — filled from `scratchpad/e2e-g6.log` when the full `tests/unit/` run completes (see the addendum at the end of this report).

## Verification matrix (PRD NFR-9)

| Command | Result |
|---|---|
| `python3 -m pytest .claude/adapters/tests -q -p no:cacheprovider` | 2276 passed, 6 skipped (live scaffolds), 175 subtests |
| `npx --no-install bats tests/unit/` | G-6 addendum |
| `bash .claude/scripts/gen-adapter-maps.sh --check`, `npm run gen-bb-registry:check` (in `.claude/skills/bridgebuilder-review`), `tools/regen-model-artifacts.sh --check`, `.claude/checksums.json` regenerated | all OK |
| `bash tools/check-ledger-hygiene.sh`, `bash tools/check-prompt-budget.sh`, `bash tools/check-no-swallowed-jq.sh` | OK / exit 0 / OK |
| `grimoires/loa/perf/skill-loop-2026-07-05/golden/capture.sh --verify` | 32/32 |
| `bash .claude/scripts/repo-map-gen.sh --validate` (after regen) | consistent |
| `bash .claude/scripts/lint-invariants.sh --hooks-wiring-only`; `hook-wiring.bats` | 1 pass, 0 error; 10/10 |
| doc-lock suites that read the edited files (12 files, 199 cases) | green except the 7 pre-existing `aleph-release-ingestion` cases (unchanged since the branch base) |

## Security considerations (sprint.md §Sprint 4)

- **Fences**: `FR-NOTES` is additive (the fence's existing 213 cases pass unmodified); the hook is behind `hook-guard.sh` (fail-open on a parse error, NSG-8) and fails open on its own parse problems; `rotate` uses `cp` + `sync -d` + tmp + `mv` — no `git stash`, no in-place edit.
- **Sensitive data**: NOTES.md stays untracked; `grimoires/loa/archive/` is gitignored (`.gitignore:185`); the memo contains no operator content; fixtures are generated, never committed.
- **Accepted bypass classes** (documented in `hooks-reference.md:155-160` and the hook header): Bash writers other than `>>` (`python -c`, `tee`, heredocs into the file) are not inspected — same class as the parent fence; the writer-side gate covers the framework's own appender.

## Follow-ups (beads)

- bd-72fq — protocol total above the 143,360 B warn line (199,525 B after the FR-10 doc lines).
- The `translate-ride-v{2,3,4}.md` snapshots keep their unbounded `cat` (frozen versions, excluded from the grep-lock) — noted for the next config-snapshot refresh; no bead (the snapshots are not loaded by any live skill).

## Sprint 4 residual and cycle close

None of the FR-10 rows is partial. Cycle-level close-out (draft PR, framework-review §9 status column, zone-marker deletion) follows the review and audit of this sprint.
