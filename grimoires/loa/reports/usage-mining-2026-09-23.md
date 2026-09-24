# Usage mining — what six months of real Loa sessions say about the framework (2026-09-23)

**Purpose:** ground the next framework cycle in observed behaviour rather than the backlog. Every number below was computed from local artefacts on the maintainer's workstation; the raw aggregates and the scripts that produced them are kept out of git under `.run/usage-mining/` (`mine-sessions.py`, `mine-attrib.py`, `loa-state-inventory.py` and their JSON outputs). Repositories other than Loa itself are referred to by rank, not name.

## 1. Corpus

| Source | Size |
|---|---|
| Claude Code transcripts (`~/.claude/projects/*/*.jsonl`, incl. subagents) | 4.9 GB · 462 project histories · 2026-01-29 → 2026-09-23 |
| Sessions | 9,981 (7,833 subagent, ~2,150 human) |
| Human prompts / tool results / tool errors | 49,967 / 514,974 / 18,972 |
| Loa mounts inspected | 40 (30 in one fleet, all submodule mode with the copied `.claude/` set; versions 1.101 → 2.0.0-rc.1) |
| Per-mount state read | `.run/` ledgers and run states, provider circuit breakers, `grimoires/loa/` ledgers, a2a records, NOTES.md, `.loa.config.yaml` |

Method: one streaming pass per transcript counted tool uses, slash commands, `Skill` invocations, Loa script invocations, hook blocks (by rule id), tool-error classes, failure signatures and compactions; a second pass attributed hook blocks and tool errors to the command or file path that triggered them and bucketed signals by month. Signatures were scanned only in tool results, so the session-start known-failures table (an `attachment` line) does not inflate them.

## 2. What the fleet actually runs

| Surface | Count | Note |
|---|---|---|
| `implement` / `review-sprint` / `audit-sprint` / `bug` (Skill) | 753 / 521 / 483 / 421 | the truename cycle is the workflow |
| `run` + `run-sprint-plan` / `simstim` | 306 / 69 | plus 2,210 `simstim-orchestrator.sh` calls |
| Golden-path aliases `/plan` `/build` `/ship` `/loa` | 50 / 6 / 3 / 18 | barely used by the primary operator |
| `/run-resume` | 142 | the most-used Loa command after the harness ones (`/clear`, `/model`, `/loop`, `/effort`, `/exit`) |
| Commands shipped vs ever invoked by name | 54 vs 27 | never: audit-deployment, autonomous, compound, constructs, deploy-production, enhance, eval, loa-aleph, loa-eject, loa-setup, mount, oracle, oracle-analyze, permission-audit, post-pr-validation, propose-learning, reality, retrospective, retrospective-batch, rtfm, run-halt, run-status, skill-audit, toggle-gpt-review, translate, translate-ride, validate |
| Skills shipped vs ever invoked by name | 36 vs 14 | never: autonomous-agent, browsing-constructs, butterfreezone-gen, continuous-learning, cost-budget-enforcer, cross-repo-status-reader, deploying-infrastructure, enhancing-prompts, eval-running, flatline-knowledge, graduated-trust, hitl-jury-panel, managing-credentials, red-teaming, rtfm-testing, scheduled-cycle-template, soul-identity-doc, structured-handoff, translating-for-executives, validating-construct-manifest |
| Most-invoked Loa scripts | `adversarial-review.sh` 2,779 · `simstim-orchestrator.sh` 2,210 · `flatline-orchestrator.sh` 1,803 · `run-mode-ice.sh` 1,537 · `verdict-derive.sh` 765 | |
| Trajectory logs on disk | 1,480 files · 17 MB | readers: `batch-retrospective.sh` (never invoked), `bridge-triage-stats.sh` (bridge files only) |

## 3. Findings, ranked by evidence

### F1 — Destructive-command fences fire mostly on harmless commands

About 1,180 hook blocks across ~2,150 human sessions; per 1,000 tool results the rate rose from 1.4 (March) to 12.7 (September) as rules were added.

| Rule | Blocks | What the attributed commands were |
|---|---|---|
| `FR-2-AMBIGUOUS` + the older `BLOCKED: rm` form | ~370 | `rm -rf dist`, `rm -rf coverage`, `rm -rf /tmp/<name>`, `rm -rf .terraform`; the accepted spelling is `./name/`; several matched text inside `ssh … 'rm -rf …'` strings |
| `FR-1.4` DROP, `FR-1.5` TRUNCATE, `FR-1.6` DELETE | ~220 | overwhelmingly heredocs writing test files, feedback markdown or commit bodies that *mention* the keyword; a minority were real statements against local test databases |
| `FR-1.1` branch -D, `FR-1.3` checkout -- | 57 / 72 | deleting squash-merged branches whose remote is gone (`-d` refuses them); restoring build-generated files |
| `P2/P2b` force-push, `P3` reset --hard, `FR-SZ2-*` System Zone | 33 / 36 / ~40 | legitimate catches, including one `git push --force origin main` |
| Agent-team guards (`team-role-guard*`, `team-skill-guard`) | 85 | teams mode only |

### F2 — Planning artefacts have outgrown the tools

| Signal | Top files (count) |
|---|---|
| Read tool "exceeds maximum allowed tokens" | `sdd.md` 35 · `prd.md` 24 · `NOTES.md` 20 · `sprint.md` 18 · `known-failures.md` 8 · `CHANGELOG.md` 7 · `ledger.json` 6 |
| Edit "String to replace not found" | `sdd.md` 26 · `NOTES.md` 20 · `prd.md` 17 · `sprint.md` 8 |
| Edit "modified since read" | `NOTES.md` 26 · `sprint.md` 13 · `prd.md` 10 · `sdd.md` 8 |
| NOTES.md size across 43 mounts | 3 at or over 200 KiB (349, 217, 217) · 4 between 100 and 200 KiB · 36 under 100 KiB |

The 2.0.0-rc.1 `notes-guard` block line (200 KiB) will refuse appends in three fleet repos on upgrade; the migration guide says rotate, nothing does it for them.

### F3 — Unattended runs stop and wait for a human

| Signal | Count |
|---|---|
| `/run-resume` invocations | 142 |
| "hit your session limit" (hard hits / mentions) | 57 / 211 (peaks: July 92, September 77) |
| Permission "auto-denied (prompts unavailable)" + "requires approval" + "denied" | ~1,570 (one headless population shows auto-denial in 162 of 419 sessions) |
| `AskUserQuestion` calls | 2,268 |
| Run states on disk | 13 worktrees of one repo `interrupted` at implementation; `HALTED` ×3 at operator gates; `RUNNING` states from April in three repos; compactions 402 |
| Session length p90 in the heaviest fleet repos | 13 to 47 hours |

### F4 — Cross-model review is running on one voice

| Signal | Count |
|---|---|
| Provider circuit breakers on disk | `anthropic-http_api` OPEN in 6 mounts + HALF_OPEN in 1 · `anthropic-headless` OPEN in 3 · google OPEN in 2 · codex-headless OPEN in 1 |
| Emitted directly by `adversarial-review.sh` | `malformed_response` 170 · `api_failure` 122 |
| DEGRADED mentions (all sources / direct script emissions) | 3,410 / ~80 |
| `known-failures.md` present | 4 of 40 mounts |

### F5 — Cost accounting has gone blind since the ledger moved (corrected)

An earlier draft of this section read the wrong field (`cost_usd`; the writer records `cost_micro_usd`) and concluded every ledger was zero. Re-read with the real field:

| Ledger | Rows | Priced (`pricing_source: config`/`cli_reported`) | Unpriced (`unknown`, cost 0) | USD recorded |
|---|---|---|---|---|
| pre-2.0 path `grimoires/loa/a2a/cost-ledger.jsonl` (16 mounts) | ~1,960 | ~1,740 | ~220 | ≈ $59 |
| `.run/cost-ledger.jsonl` (4 mounts, the current default) | 679 | 140 | 539 | ≈ $26 |

The legacy ledgers were priced; the current-path rows are mostly not: 205 of 214 rows in one fleet repo and 309 of 410 in another carry `pricing_source: unknown` because their model ids do not resolve in the catalog pricing — dated OpenAI ids (`gpt-5.2-2025-12-11`, `gpt-5.5-2026-04-23`), `gemini-2.5-pro`, and hop names recorded as the model (`codex-headless`, `claude-fable-5-1` via the CLI hop). `cost-report.sh` reads only the new path by default, so a repository's history before the move is invisible; `cost-budget-enforcer` has never been invoked.

### F6 — Surface that is never used (see §2)

Half the commands and three fifths of the skills are dormant in real use; trajectory logs are write-only.

### F7 — Fleet drift and copy-set drift

30 fleet mounts span 1.101 → 2.0.0-rc.1 (three moved to the rc within hours of publication). In three mounts the copied `.claude/hooks` or `settings.json` differ from the repo's own `.loa` submodule (20, 7 and 1 files). `framework_version` values mix `1.180.0`, `v1.180.1`, `v1.189.1-8-g5faa3e97` and bare SHAs.

### F8 — Abandoned cycles

Across the fleet's a2a records roughly half to two thirds of sprint directories carry a `COMPLETED` marker (largest repos: 149/210, 87/148, 107/131, 84/92, 34/94); the rest are partial cycles still in ledgers.

## 4. What already worked

Write-before-read rejections fell from 9.0 per 1,000 tool results in June to 0.1–1.0 since August (the ALWAYS rule plus its hook). Beads failures are now rare (87 migration, 27 flush, 26 not-initialised in the whole corpus).

## 5. Caveats

DEGRADED counts include re-reads of artefacts that contain the word; the Loa repository's own dogfooding inflates several error classes; 6,312 raw "Exit code N" errors are mostly ordinary test failures; the corpus is one workstation, one operator, one fleet.
