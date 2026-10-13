# Sprint 254 (cycle-128 Sprint 3), implementer H: docs, release surfaces, SDD backfill and the E2E draft

Scope: Task 3.6, the SDD §10 DEC backfill and the Task 3.E2E draft. The worktree is `loa-wt-s3c-docs`, detached at `efacf754`. Nothing was committed. The patch is at `~/.cache/loa/cycle-128/patch-s3-h.patch`, and `git apply --check` passes on the main checkout.

## Files changed

| File | Change |
|------|--------|
| `CHANGELOG.md` | The `[Unreleased]` section is rewritten as one release note for sprints 252–254, grouped into Added, Changed, Fixed, Security and Migration. Each bullet names its surface and FR. The review-round and audit-round fixes are folded into the entries they correct, so no bullet is labelled by round any more. The Sprint 3 entries cover the glossaries, the glossary validator and checker with their CI workflow, Seams Under Test, `red-test-check.sh` and the micro-sprint two-commit rule. The heading stays `[Unreleased]`. |
| `README.md` | A "Unreleased — decision surfaces" block above rc.2. It has seven bullets and an upgrade line pointing at the Migration notes. The command count is unchanged at 51. |
| `.claude/loa/reference/hooks-reference.md` | A SessionStart row in All Hook Registrations, and a new "Decision surfaces (cycle-128)" table. The table covers the decisions surface, the ICE spike rule, SP-1, the FR-1.1 decided-spike unlock, the `chart-guard.sh` gate and the FR-8 lint, each with its accepted bypasses and tests. A "cycle-128 additions" pointer sits in the block-destructive-bash section. |
| `.claude/loa/reference/scripts-reference.md` | A "Decision Surfaces (cycle-128)" table with one row per new script: contract and exit codes. A line below it lists the new validator types. |
| `.claude/loa/reference/protocols-summary.md` | The `karpathy-principles.md` row names the new unattended decision-recording rule, because that protocol changed in Sprint 1. |
| `grimoires/loa/REPO-MAP.md`, `REPO-MAP.md.checksum` | Regenerated with `repo-map-gen.sh`; `--validate` exits 0. |
| `.claude/checksums.json` | Tracked entries refreshed (see the decision below): 41 hashes changed and 16 new files added. |
| `evals/fixtures/loa-skill-dir/.claude/scripts/{golden-path.sh,mount-loa.sh}` | `sync-fixtures.sh` re-copied two fixture copies that had drifted with the Sprint 2 and Sprint 3 code. `--check` failed on `efacf754` before this change. |
| `grimoires/loa/sdd.md` | §10 Open Questions table only: each "pending seed, Task 1.6" is replaced by DEC ids. |

Gitignored, so not in the patch: `grimoires/loa/a2a/sprint-254/e2e.md` (the E2E draft), this file, and the lead's evidence files copied in from the main checkout.

## SDD §10 backfill

| Row | Resolved by | DEC |
|-----|-------------|-----|
| 1–6 | D1…D6 | DEC-0001…DEC-0006 |
| 7 | D7 amended by D10 | DEC-0007, DEC-0010 |
| 8, 9 | D8, D9 | DEC-0008, DEC-0009 |
| 10–15 | D11…D16 | DEC-0011…DEC-0016 |
| 16 | A5 | DEC-0025 |
| 17 | A10 | DEC-0030 |
| 18 | D-8.4 (no A-ref) | DEC-0049 (A29) |
| 19 | A33 | DEC-0053 |
| 20 | A31 | DEC-0051 |

Before the change, `validate-artifact.sh --type sdd --file grimoires/loa/sdd.md` printed 20 WARNs ("an Open Questions row is Resolved without a DEC id"). After it, the validator exits 0 with no output.

## Check results (worktree, final tree)

| Check | Result |
|-------|--------|
| `tools/check-prompt-budget.sh` | exit 0 (CLAUDE.loa.md 10,225 of 10,240 B, untouched) |
| `agents-md-gen.sh --check` | exit 0, 51 commands; AGENTS.md not regenerated |
| `repo-map-gen.sh --validate` | exit 0 |
| `validate-gitignore-state.sh` | exit 0, no drift |
| `evals/fixtures/sync-fixtures.sh --check` | exit 0 after the sync; exit 1 with 2 drifts before it |
| `validate-artifact.sh --type sdd` on sdd.md | exit 0, no WARN |
| `agents-md-gen.bats`, `repo-map-gen.bats` | 8/8, 6/6 |
| E2E suites (`LOA_HARNESS_CHECK=0`) | red-test-check 17/17, sprint-seams 10/10, glossary-terms 20/20, glossary-validator 19/19, user-invoked-commands 13/13, user-invoked-harness 5/5 with the live case skipped, charting-lint 28/28, golden-path-charting 15/15, spike-validator 16/16, check-round-independence 18/18, run-mode-ice 52/52, unattended-prototype 6/6, dec-write-lib 47/47, loa-decisions-surface 8/8, grimoire-index 13/13, validate-artifact 60/60, charting-decisions 52/52, chart-frontier 12/12, block-destructive-bash 291/291 (load 8.7) |

## Lead attention

1. **The decisions surface is not in the shipped hook template.** `loa-decisions-surface.sh` is registered in `.claude/settings.json` but not in `.claude/hooks/settings.hooks.json`, which carries the other SessionStart hooks (run-state surface, context class). A mounted project that installs hooks from the template would never run it. This is a code fix outside H's scope, so it is not in this patch. The hooks-reference row describes the hook as registered.
2. **The brief's seed map is off by one.** It said PRD D1…D21 map to DEC-0001…DEC-0021. `seed-map.tsv` and the ledger map D1…D20 to DEC-0001…DEC-0020, and DEC-0021 is SDD A1. PRD Appendix E D21 (the `proposed_by` and `decided_by` rule) has no ledger row of its own; the closest row is DEC-0051 (A31). No Open Questions row cites D21, so the backfill is unaffected. The G-1 count is unaffected too. Whether D21 needs a seed row is the lead's call.
3. **Row 18's DEC is a judgment.** Its "Resolved by" cites only the SDD design id D-8.4. DEC-0049 (A29: the live-harness bats is opt-in and every outcome is defined) is the ledger row for that check. If the lead prefers DEC-0008 (D8), it is a one-cell change.
4. **The checksums.json refresh is surgical.** See the decision below. If the lead regenerates the file with `update.sh` in the main checkout instead, drop this patch's hunk for it.
5. **The README heading still says rc.2,** while rc.3 is published and the cycle-126 block still says "Unreleased". Both predate this cycle and were left alone.

## Assumptions

- [ASSUMPTION fact] PRD D1…D20 are DEC-0001…DEC-0020 and SDD A1…A41 are DEC-0021…DEC-0061. Both the seed map and each row's `source` field confirm this.
- [ASSUMPTION fact] The archived cycle-127 plan exits 1 because of two pre-existing required-section rules. The Seams rule adds one WARN and no violation. The tracked fixture copy is byte-identical to the archive.
- [ASSUMPTION fact] `agents-md-gen.sh --check` reports 51 commands, so AGENTS.md was not regenerated.
- [ASSUMPTION fact] `.claude/checksums.json` hashes every file under `.claude/` in the checkout that generated it, including about 1,400 untracked local files. The cycle-127 sprint commits refreshed it in place.
- [ASSUMPTION decision] `checksums.json` was refreshed for git-tracked files only: changed tracked files were re-hashed, new tracked files added, and untracked entries left byte-for-byte. Rerunning the generator from this clean worktree would delete about 1,400 entries for local-only files. Every refreshed path is in `git diff 304a2480 -- .claude`. The output is identical to jq's formatting. The script is `~/.cache/loa/cycle-128/h-checksums-update.py`.
- [ASSUMPTION decision] The fixture sync is in scope as a release surface. Without it, the required `sync-fixtures.sh --check` would fail on the cycle's own code.
- [ASSUMPTION decision] The CHANGELOG gains a `### Migration` heading, following the release-level "Migration guide" heading already in the file. The post-merge finaliser keeps every `###` heading.
- [ASSUMPTION decision] The cycle-128 surfaces in hooks-reference get one table of their own. `chart-guard.sh` and the FR-8 lint are gates rather than hooks, and the existing Event/Matcher table cannot hold them. The All Hook Registrations table still gets the SessionStart row.
- [ASSUMPTION decision] Fixed now holds only the fix to pre-existing behaviour (`validate-gitignore-state.sh`). Fixes to code that had not been released are folded into their Added or Security entry.
- [ASSUMPTION decision] The E2E rows that H ran with read-only commands are marked H. The lead's G-1 to G-4 and G-7 rows keep the lead's evidence. The G-2 live beads cross-check is left for the lead to re-run, because the worktree has no `.beads/`.
