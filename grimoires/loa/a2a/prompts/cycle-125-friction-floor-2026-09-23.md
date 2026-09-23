# Operator prompt — cycle-125 "Friction floor" (2026-09-23)

**Issued by:** Jani (Loa creator/maintainer), after the usage-mining review of 2026-09-23: *"proceed as you suggest with all the most impactful things to work on."* Unattended run on branch `feature/cycle-125-friction-floor` (from `origin/main` `867cbc37`, the merge of the 2.0.0-rc.1 PR). Deliverable: a draft PR to `main` whose title contains `cycle-125`. Do not merge, tag or publish; the merge will be prepared by the pipeline as `2.0.0-rc.2` (a merge on the rc tag increments).

## 1. Why (evidence, do not re-derive)

`grimoires/loa/reports/usage-mining-2026-09-23.md` (tracked) summarises 4.9 GB of local Claude Code transcripts (≈2,150 human + 7,800 subagent sessions, Mar–Sep 2026) and the state of 40 Loa mounts. Raw aggregates and the mining scripts are under `.run/usage-mining/` (untracked). The five findings this cycle addresses, with the numbers that justify them, are F1–F5 there. F6–F8 (surface diet, fleet update tooling, abandoned-cycle sweep) are explicitly deferred.

## 2. Scope — five functional requirements

### FR-1 Fence precision (`.claude/hooks/safety/block-destructive-bash.sh`)
About 1,180 blocks in ~2,150 sessions, ~80 % on harmless commands. Keep every genuine catch (force-push, reset --hard, System-Zone writes, stash drop, `rm -rf` of roots/globs/home) green while removing the false-positive classes:
- `rm -rf` on a bare relative **visible** directory (`dist`, `coverage`, `build`, `.venv`? — hidden stays blocked unless spelled `./.name/`), on `/tmp/<name>` and `$TMPDIR`/`mktemp` paths, and on text that is a quoted payload of `ssh`/`docker exec`/`kubectl exec` (runs elsewhere; out of the local fence's scope — record the decision).
- SQL rules (`FR-1.4/1.5/1.6`) only when the statement is *executed* by a SQL runner (`psql`, `mysql`, `sqlite3`, `prisma db execute`, `-c`/`--command`, a heredoc piped into one of them), never when it is merely text written by `cat > file <<EOF`, a commit message or an `echo`.
- `git branch -D`: allow when the branch is provably merged (a merged PR for that head via `gh`, or `git branch --merged` against the upstream base) — the squash-merge case where `-d` refuses; otherwise keep the block and point at the helper.
- `git checkout -- <path>` / `git restore <path>`: allow for paths git itself marks generated (`git check-attr linguist-generated`) or under `dist/`, `coverage/`, `**/_generated/`; otherwise keep the block.
Acceptance: a fixture corpus under `tests/fixtures/fence-corpus/` derived from the attributed samples (≥ 40 previously-blocked benign commands, ≥ 15 dangerous ones; scrub hostnames, credentials, bucket names, DB URLs before committing), driven by `block-destructive-bash.bats`: ≥ 80 % of the benign set passes, 100 % of the dangerous set still blocks; the existing suite stays green.

### FR-2 Sectioned planning artefacts
`sdd.md`, `prd.md`, `sprint.md` are the top files that exceed the Read tool's token cap and where Edit anchors fail; NOTES.md is over the 200 KiB block line in three fleet repos. Generalise the `notes-guard.sh` approach into one artefact reader (`artifact-read.sh` or `notes-guard.sh read --file <artefact> --section <heading>`; heading-addressed, budgeted, never empty, `--full` on request) and use it where the skills read these files: `/implement sprint-N` reads its own `## Sprint N` block, review/audit read the sprint block plus the ACs, `/architect` reads the PRD by section. Size budgets (warn at 100 KiB) surfaced by `/loa`. `update-loa` (and the migration guide) rotate NOTES.md automatically when it is at or over the block line. Acceptance: bats for the reader (heading selection, budget, fallback), a check that `grimoires/loa/prd.md` (101 KB) and `sdd.md` (69 KB) of this repo read by section under 25k tokens, skill byte budgets still met (`tools/check-prompt-budget.sh`).

### FR-3 Run preflight and resume
`/run-resume` is the most used Loa command (142); ~1,570 permission denials cluster in headless populations; session-limit hits recur; run states sit `interrupted`/`RUNNING` for months. Build `run-preflight.sh`, invoked by `/run`, `/run-sprint-plan` and `run-mode`'s entry, that fails loud before the first task when: the harness permission mode cannot grant the run's tool set unattended (read `.claude/settings*.json` / `LOA_RUN_MODE`), the model credentials/CLI hops the configured voices need are absent (reuse `cheval-preflight-gate`), a provider breaker is OPEN for a required voice, NOTES.md is at the block line, or the ledger/state files are inconsistent. Checkpoint the run state after every task (not only per sprint) so `run-resume` restarts at the task; on session start, surface a stale `RUNNING`/`INTERRUPTED` state with the exact resume command (`loa-status.sh` + the SessionStart hook line), and in autonomous mode (`LOA_RUN_MODE=autonomous`) let `/loa` offer resume as the single next step. Acceptance: bats for each preflight predicate with fixtures; a simulated interrupted state resumes at the recorded task; no new config key.

### FR-4 Provider health as a first-class signal
Anthropic HTTP breaker OPEN in 7 mounts, headless in 3; dissent degrades silently; only 4 of 40 mounts have a `known-failures.md`. `loa-status.sh` (`/loa`) prints one line per configured provider: breaker state and age, credential present (never the value), CLI hop available; `cheval` re-routes to the CLI hop of the same company when the HTTP breaker is OPEN (if the chain resolver already does, prove it with a test and surface it), breakers expire to HALF_OPEN after a documented cooldown and `cheval --reset-breaker <provider>` exists; `mount-submodule.sh`/`mount-loa.sh` seed `grimoires/loa/known-failures.md` from the template so the KF surface hook has something to surface downstream. Acceptance: bats with breaker-file fixtures; status snapshot test; mount test asserts the seed.

### FR-5 Cost accounting that produces numbers
Every ledger in the fleet totals $0. Price every `cost-ledger.jsonl` row from the catalog pricing snapshot using the row's token counts — CLI hops included (when the CLI JSON carries usage, price it; when it does not, estimate from the tokens cheval counted and mark `cost_estimated: true`); `cost-report.sh` reads the new path and, with `--include-legacy`, the pre-2.0 path `grimoires/loa/a2a/cost-ledger.jsonl`, and offers `--migrate-legacy` (append-only move with a receipt); `cost-budget-enforcer` reads the same totals (or is retired if the enforcer cannot be made truthful — record the decision). Acceptance: bats over fixture rows for every catalog family: zero null costs for known models; report totals match by hand; ledger isolation of the test harness preserved (KF-033).

## 3. Constraints (all in force)
- Smallest diff; failing test first for every code change; `// loa:shortcut:` markers where taken; no new `.loa.config.yaml` keys unless strictly required (prefer conventions: gitattributes, path shapes, existing env vars).
- Never weaken a fence's genuine catches; never touch Aleph-managed files; Aleph stays opt-in.
- Prompt byte budgets: protocols are at 199,593 B of 200,000 — any protocol prose change must be net-zero or negative; skills ≤ 16,384 B incl. unconditionally-read resources; `tools/check-prompt-budget.sh` must pass.
- `.claude/` edits under the framework marker (`.run/zone-guard-authorization.json`, armed, expires 2026-09-30T00:00Z); regenerate `grimoires/loa/REPO-MAP.md` and `.claude/checksums.json` after every `.claude/` change; delete the marker at cycle end.
- Every sprint: implement → `/review-sprint` → `/audit-sprint` with cross-model dissent (`adversarial-review.sh`; the OpenAI voice is the one that works on this host; write the failed-run record when a voice is unavailable); COMPLETED marker; ledger + beads updated.
- The per-sprint a2a record goes to the never-merged branch `record/cycle-125-a2a`; Template Protection forbids new `grimoires/loa/a2a/sprint-*` files on `main`.
- CHANGELOG entries under `## [Unreleased]` (the pipeline finalises them under `## [2.0.0-rc.2]` at merge); migration guide gets a short "rc.2" addendum for FR-2's NOTES rotation and FR-5's legacy ledger.
- Push only via `.claude/scripts/run-mode-ice.sh push origin feature/cycle-125-friction-floor`; keep the PR under 300 files; run one Bridgebuilder pass at the end and triage it.
- Autonomous: do not stop to ask; record chosen readings in NOTES.md Decision Log; stop only on an operator-only blocker.

## 4. Suggested sprint shape
1. FR-1 fence precision + fixture corpus.
2. FR-2 sectioned artefacts + NOTES rotation on upgrade.
3. FR-3 run preflight, task checkpoints, resume surfacing.
4. FR-4 provider health + FR-5 cost accounting + docs (CHANGELOG, migration addendum, README line).

## 5. Stop conditions
All sprints COMPLETED with consistent LOA-VERDICT trailers; draft PR open with CI green and the Bridgebuilder pass triaged; NOTES.md Decision Log and the session memory updated; zone marker deleted.
