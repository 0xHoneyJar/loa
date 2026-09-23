# Implementation Report — Sprint 2: Sectioned artefacts (cycle-125, global sprint 242)

**Cycle:** cycle-125 friction-floor · **PRD:** `grimoires/loa/prd.md` FR-2 · **SDD:** `grimoires/loa/sdd.md` §1.3 · **Plan:** `grimoires/loa/sprint.md` Sprint 2
**Implementer:** Fable 5.1 lead (`/run sprint-plan`, run-20260923-282c32ce, unattended) · **Date:** 2026-09-23 · **Epic:** bd-ybez (tasks bd-jcb3, bd-am0z, bd-ezza, bd-5ld1, bd-29h8, bd-gzjo)

## Summary

Usage mining (F2) showed agents' blind `Read` of `prd.md` / `sdd.md` / `sprint.md` / `NOTES.md` rejected by the 25k-token cap, then retried in fragments. This sprint generalises the cycle-124 NOTES reader into one heading-addressed, budgeted reader for any markdown artefact (`notes-guard.sh read --file F --section <spec> | --index`), routes the skills through it inside the byte budgets, surfaces the four artefact sizes in `/loa`, and makes `update-loa` rotate an over-the-line NOTES.md so the rc.1 append fences cannot strand an upgraded repository. No second reader, no config key, no new dependency.

Assumptions (Karpathy rule 1): a "section" is one `## ` block through the line before the next `## ` (H3s stay inside, matching how `sprint-plan-mode.md` discovers sprints); `Sprint N` must not match `Sprint N0` (word boundary on the digit run); the substring match is first-wins in file order because the index line is the disambiguator; the include change is measured as net bytes against every skill that carries it rather than "≤ 100 B added" in isolation — the eight skills within 100 B of the cap made the literal reading unsafe, so the include body was tightened at the same time and the three planned skills received trims for headroom.

## Changes

| File | Change |
|---|---|
| `.claude/scripts/notes-guard.sh:1-30` | header/usage: `--index`, `--section SPEC`, non-NOTES default |
| `:55-65` | arg parsing for `--index` / `--section` (empty value → usage 2); `--full` / `--index` / `--section` exclusive (`_modes`, exit 2) |
| `:84-101` | `index_blocks` emits a sixth field: block bytes (heading + body + newlines; `LC_ALL=C` so `length()` is bytes) |
| `:115-124` | `cmd_index`: `L<start>-L<end>  <bytes>B  <heading>` per H2; a file with no H2 prints one loud line naming `--full` |
| `:126-141` | `find_section`: `Sprint N` → `^## Sprint N([^0-9]|$)`; `N` / `N.` → `^## N\. `; else case-insensitive substring, first match |
| `:168-182` | `emit_capped`: the READ_CAP + footer logic lifted out of `cmd_read` so the default selection and a section share it byte-for-byte |
| `:184-210` | `cmd_read`: `--full` → cat; `--index`; `--section` (miss → `NOTES-GUARD: no section matching '<spec>' in <file>; headings: …` then the index, exit 0); no flag → NOTES.md keeps the Blockers / newest Session Continuity / 3 newest Decision Log selection, any other file gets the index |
| `.claude/data/skill-includes/context_discipline.md` | body tightened and the routing sentence added: 471 B → 477 B (+6 B per carrying skill); regenerated into 10 skills by `generate-skill-includes.sh --write` (`--check`: current) |
| `.claude/skills/implementing-tasks/SKILL.md:185` | primary read instruction is now `notes-guard.sh read --file grimoires/loa/sprint.md --section 'Sprint N'`, sdd/prd via `--index` then `--section` |
| `:82`, `:223` | compensating trims (CLI policy sentence, context-assessment sentence; no rule removed): 16,358 → 16,342 B after the +6 B include and the longer read instruction |
| `.claude/skills/reviewing-code/SKILL.md:205,255` | Fast-Gate Parity and Documentation Verification sentences shortened, same rules: 16,334 → 16,252 B |
| `.claude/skills/auditing-security/SKILL.md:140` | grounding sentence shortened, same rules: 16,308 → 16,239 B |
| `.claude/scripts/loa-status.sh:670,694-713` | `display_artefacts_line`: `  Artefacts: prd 30K sdd 34K sprint 23K NOTES 61K` after the Sprints line; any artefact whose `notes-guard.sh check` says WARN/BLOCK adds `  ⚠ ≥ 100 KiB: <files> — read by section: …`; honours `LOA_GRIMOIRE_DIR`; human mode only (`--json` envelope unchanged) |
| `.claude/scripts/update-loa.sh:475-494,596` | `rotate_oversized_notes` after `import_upstream_learnings`: `notes-guard.sh check` exit 3 → log + `rotate` + log; failure warns with the manual command; below the line or no NOTES.md → silent; never fails the update |
| `docs/migration/v2.0-model-generation-floor.md:169-186` | "2.0.0-rc.2 addendum — NOTES.md rotation on upgrade, sectioned artefacts" |
| `tests/unit/notes-guard.bats` (+9: NG-13…NG-21) | index format and byte counts; `Sprint N` word boundary; numbered sections; substring case-insensitive first-match; miss → loud + index; cap footer on a 200 KB section; non-NOTES default vs NOTES default; **this repository's prd/sdd/sprint by every section ≤ 100 KiB**; usage exits |
| `tests/unit/update-loa-notes-rotation.bats` (new, 4) | 250k fixture rotated archive-first with recovery headings + pointer and `check` silent afterwards; 100k fixture byte-identical, no archive; no NOTES.md silent + `LOA_GRIMOIRE_DIR` honoured; `main()` ordering (import → rotate → summary) |
| `tests/unit/loa-status-artefacts.bats` (new, 3) | Artefacts line names the four artefacts; 100k NOTES flagged with the remedy and a small one not; `--json` unchanged |
| `CHANGELOG.md` `[Unreleased]` | one entry |
| `grimoires/loa/REPO-MAP.md` (+checksum), `.claude/checksums.json` | regenerated (`--validate` consistent; checksum `--check` 0 drift) |

## Test-first record

- Task 2.1 wrote NG-13…NG-21 first: 8 red, 1 vacuously green (NG-21, unknown flags already exit 2) against the pre-change script.
- After Task 2.2 the first run exposed a bad parameter expansion in the exclusivity check (`${#section:+1}`), which broke every `read`/`check` invocation (12 legacy cases red) — replaced by an explicit counter; then 21/21. One expectation in NG-13 (last block's end line) was corrected to the fixture's real line count.
- ULR-3 first failed because an env prefix on `source` does not reach the following function call — fixed in the test (`export`), not the script. LSA-2 was loosened from `NOTES 2K` to `[12]K` because the "under" fixture is 985 B on this generator.
- Final: `notes-guard.bats` 21/21, `update-loa-notes-rotation.bats` 4/4, `loa-status-artefacts.bats` 3/3, `prompt-audit-keeplist.bats` 3/3, `skill-capabilities.bats` green (63 in that run); related regression pass `skill-includes`, `prompt-audit-generated-blocks`, `notes-size-guard`, `notes-template`, `agent-ergonomics-loa-status`, `loa-status-stale-worktree`, `update-loa-bump`, `update-loa-conflict-guidance`, `update-loa-submodule-copy-verify`, `skill-capabilities`, `hook-wiring` → 169/169. `tools/check-prompt-budget.sh`: every skill ≤ 16,384 B (max `planning-sprints` 16,354), `CLAUDE.loa.md` 10,225 B, protocols 199,593 B (unchanged). `generate-skill-includes.sh --check`: current. `bash -n` clean on the three scripts.

## AC Verification (sprint.md)

### `notes-guard.bats`: exact heading, `Sprint N`, numbered SDD section, substring, no-match → index + one-line reason, budget footer, `--full`, NOTES default unchanged (prd.md FR-2 AC 1)
- **Status**: ✓ Met
- **Evidence**: NG-16 (exact/substring heading, `find_section` `:136-139`), NG-14 (`Sprint N`, `:131-133`), NG-15 (`3.` and `4`, `:134-135`), NG-17 (miss → `cmd_read` `:190-194`), NG-18 (footer, `emit_capped` `:168-182`), NG-4 (`--full` unchanged), NG-1/NG-2/NG-19 (NOTES default unchanged, `:199-209`).

### This repository's `prd.md` and `sdd.md` read by section stay ≤ 100 KiB per call (prd.md FR-2 AC 2)
- **Status**: ✓ Met
- **Evidence**: NG-20 iterates every `## ` heading of `prd.md` (12), `sdd.md` (12) and `sprint.md` (≥ 3) through `--section` and asserts each output ≤ 102,400 B and non-empty; the index of each ≤ 102,400 B. Byte proxy for 25k tokens per the SDD.

### `tools/check-prompt-budget.sh` ok; `prompt-audit-keeplist.bats` green; the four skills remain ≤ 16,384 B (prd.md FR-2 AC 3)
- **Status**: ✓ Met
- **Evidence**: budget output above (no FAIL; `implementing-tasks` 16,342, `reviewing-code` 16,252, `auditing-security` 16,239, `planning-sprints` 16,354, all ten include carriers under the cap); KL-1/2/3 green; `generate-skill-includes.sh --check` current.

### `update-loa` rotation bats with a generated ≥ 200 KiB fixture; migration addendum present (prd.md FR-2 AC 4)
- **Status**: ✓ Met
- **Evidence**: ULR-1 (`make-large-notes.sh … 250k` → 256,000+ B; archive byte-equal; live < 100 KiB; `check` exit 0 after), ULR-2/3/4; `docs/migration/v2.0-model-generation-floor.md:169`.

## Review round 1 → fixes (2026-09-23)

`engineer-feedback-round1.md` (reviewed commit `161ccd9a`; dissent clean) found one HIGH and three MEDIUMs, all fixed with tests:

| Finding | Fix | Test |
|---|---|---|
| H-1 vendored (`standard`) mode `exec`s `update.sh`, so the rotation never runs there | the refresh runs without `exec` (path overridable via `LOA_VENDORED_UPDATE_SCRIPT`), its exit code is preserved, `rotate_oversized_notes` runs on success, then `exit` (`update-loa.sh:575-591`) | ULR-5: stub refresh + 250k NOTES → refreshed and rotated; failing stub → exit 7, no rotation |
| M-1 `Sprint 2` matched `## Sprint 2.5` | boundary `([^0-9.]|$)` (`notes-guard.sh:139`) | NG-14 dotted twin |
| M-2 TAB in a heading shifted the index fields | heading is the last field; consumers rebuild it after the fifth TAB (`:84-101`, `:124`, `:135-146`) | NG-22 (`22B  ## A<TAB>B heading`) |
| M-3 `awk -v` backslash processing on the substring spec | spec via `ENVIRON["NG_SPEC"]` (`:143-146`) | NG-22 (`'A\tB'` is literal) |
| L-1 directory as `--file` | "is not a regular file" (`:186`) | NG-22 |
| L-2 trailing-newline over-count | left as documented behaviour (budget hint) | — |

After the fixes: `notes-guard.bats` 22/22, `update-loa-notes-rotation.bats` 5/5, `loa-status-artefacts.bats` 3/3; checksum regen 0 drift; REPO-MAP consistent.

## Deviations from the plan, stated

- The SDD's "include line ≤ 100 B" was implemented as a net +6 B include (body tightened while adding the routing sentence) because eight of the ten carrying skills sit within 100 B of the cap — a literal +92 B would have broken six budgets. The three planned compensating trims were still applied for headroom.
- `git restore`-style wording in the plan's Task 2.3 does not apply here; nothing else in FR-2 mentions it.

## Out of scope, noted

- `notes-guard.sh` still reads only `## ` (H2) boundaries; `#` / `###` addressing is not needed by the four artefacts (their sprint/section grammar is H2).
- `/loa --json` does not carry the artefact sizes; the human line is the surface the PRD names.
