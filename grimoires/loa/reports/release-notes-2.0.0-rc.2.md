# v2.0.0-rc.2 — Friction floor (release candidate)

**Pre-release.** Second candidate of the 2.0 line. It carries everything in `v2.0.0-rc.1` (model-generation floor, mechanical gates, Aleph opt-in, prepare-then-publish release engineering) plus the cycle-125 "friction floor". Stable users can stay on `v1.202.1`; rc.1 users upgrade in place (`/update-loa` or re-mount at the tag). The rc exit criteria are unchanged from rc.1.

## What changed

Five fixes for the friction the fleet's own sessions showed most often (4.9 GB of local transcripts across 40 mounts, `grimoires/loa/reports/usage-mining-2026-09-23.md`). Nothing here adds a configuration key.

| Area | What you get | Proof |
|---|---|---|
| Destructive-command fence | `rm -rf` on named cache/build dirs, on bare names after a statement-initial `cd /tmp/…`, strictly below temp roots, on `$TMPDIR/<name>` with a real temp `TMPDIR`, and on a variable bound exactly once to `$(mktemp -d)` is no longer blocked; `git branch -D` on an ancestor of main, `git checkout -- <generated path>`, and SQL DROP/TRUNCATE/DELETE only with a runner or inline interpreter present. Catastrophic paths, `..` escapes, remote payloads and the hook's own `$PWD` are unchanged. New `git-branch-prune.sh` for merged/squash-merged/gone branches. | corpus `tests/fixtures/fence-corpus/` 49 benign / 60 dangerous / 5 residual, gated (benign ≥ 80 %, dangerous 100 %, runtime ≤ 1.5×); `block-destructive-bash.bats` 281 |
| Planning artefacts | `notes-guard.sh read --file <prd\|sdd\|sprint\|NOTES>.md --section 'Sprint N' \| 4. \| <substring>` returns one H2 block under 68 KiB; `--index` lists every H2; `/implement` reads its sprint by section; `/loa` prints `Artefacts:` sizes; `update-loa` rotates a NOTES.md over the 200 KiB line (archive first). | `notes-guard.bats` 22, rotation 5, status 3; skill budgets green |
| Runs | `run-preflight.sh` (P1 permission mode … P8 branch) at the entry of `/run`, `/run sprint-plan`, `run-bridge`, `/run-resume`, failing loud with the fix named; `run-checkpoint.sh` task checkpoints (schema v2, locked atomic writes, beads-validated read); SessionStart `Run: <state> (<age>) → /run-resume` line, mirrored in `/loa`. | `run-preflight.bats` 14, `run-checkpoint.bats` 7, `run-state-surface.bats` 7, `implement-reentry.bats` (real `br`) |
| Providers | `/loa` `Providers` block: credential *presence* (never the value, source named), CLI hop on PATH, every breaker with state, age and probe timing; `python3 -m loa_cheval.routing.breaker_cli --list [--json] \| --reset P[:AUTH]`, `cheval --reset-breaker` (journal-first); an OPEN bucket walks to the CLI hop without calling the provider; `known-failures.md` seeded on mount. | pytest 13 + 2, `loa-status-providers.bats` 4, `known-failures-seed.bats` 5 |
| Cost accounting | `find_pricing` exact → dated → alias → CLI hop with `pricing_resolution` on the row; adapters record `transport` and `resolved_model`; `cost_estimated`; `cost-report.sh --include-legacy` / `--migrate-legacy` (validated writer, receipt, idempotent) and `Unpriced rows: N (S %)`; the L2 budget enforcer refuses `allow` while the unpriced share exceeds 5 % (`halt-uncertainty`, reason `unpriced_share`). | pytest 14 + 4, `cost-report.bats` 7, `cost-budget-enforcer-unpriced.bats` 5 |

## What you may notice after upgrading

- **Fewer fence blocks, same catches.** If a command you rely on is still blocked, the block message names the rule; add the shape as a corpus row in a PR rather than editing the hook.
- **A run may refuse to start.** `run-preflight.sh` prints the failing predicate and its fix (permission mode, allow rules, review voices, breakers, NOTES size, a stale run, beads, branch). Run it by hand to see your own checklist; nothing to configure.
- **A new SessionStart line** (`Run: …`) appears only when a resumable run exists. The hook is wrapped by `hook-guard.sh` and is present in both settings files.
- **`known-failures.md` warning.** Repositories mounted before rc.2 have none; `cp .claude/templates/known-failures.md.template grimoires/loa/known-failures.md` (or re-run the mount) silences `check-loa.sh`.
- **Budget enforcer users only** (`cost_budget_enforcer` configured): the enforcer now halts on uncertainty when more than 5 % of the ledger rows are unpriced. `cost-report.sh` shows the share; `--migrate-legacy` folds pre-2.0 history in once; historical CLI rows recorded at cost 0 stay unpriced until the explicit re-pricing pass tracked as bead `bd-ypbg` lands (on the Loa repository itself the share is 74 %, so the enforcer halts there by design until then). Mounts without the L2 enforcer are unaffected.
- **A NOTES.md over 200 KiB is rotated by `update-loa`** on the first refresh after upgrading: archived whole under `grimoires/loa/archive/notes/`, then the recovery sections are kept live. Below the line nothing happens.

Migration guide: `docs/migration/v2.0-model-generation-floor.md` (rc.2 addendum). Decisions: `docs/architecture/ADR-004-model-generation-floor.md`.

## Breaking

No configuration key is added, removed or renamed in rc.2. Behaviour changes are listed above; each has a hand-run equivalent and none needs a switch. Every rc.1 switch (`LOA_CHEVAL_LEGACY_WIRE=1`, `aleph.enabled`, `LOA_COST_LEDGER_PATH`, …) still works.

## Operator steps

1. Merge PR #1269 (title keeps `cycle-125`); the pipeline prepares `v2.0.0-rc.2` with `prerelease: true` (rc increment, no CHANGELOG action needed beyond the `[2.0.0-rc.2]` heading already in place).
2. Inspect the candidate per `grimoires/loa/runbooks/post-merge-candidates.md`, publish with `--publish … --approve-sha256`, confirm **Pre-release** on GitHub.
3. `gh release edit v2.0.0-rc.2 --notes-file grimoires/loa/reports/release-notes-2.0.0-rc.2.md`.

## Soak and exit criteria

Unchanged from rc.1 (`grimoires/loa/reports/release-notes-2.0.0-rc.1.md`): two weeks minimum, ≥ 2 downstream mounts through the migration guide, no CRITICAL/HIGH rc issue open for 14 consecutive days, a recorded `live-floor-check.yml` pass, `check-loa.sh` green on a fresh mount with Aleph absent. Issues labelled `2.0.0-rc`.

## Follow-ups (beads, label `cycle-125-followup`)

- `bd-ypbg` — explicit, opt-in re-pricing pass for historical unpriced rows (marks rows `repriced_at`, never re-prices history silently).
- `bd-n7v3` — `check-permissions.sh` should merge `settings.local.json` and `~/.claude/settings.json` and honour `deny` rules (preflight P1/P2 scope).
