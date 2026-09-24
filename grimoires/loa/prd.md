# Product Requirements Document: Loa Friction Floor (cycle-125)

**Version:** 1.0
**Date:** 2026-09-23
**Author:** PRD Architect Agent (unattended run; operator authorisation "proceed as you suggest with all the most impactful things to work on", 2026-09-23)
**Status:** Draft

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Goals & Success Metrics](#goals--success-metrics)
4. [User Personas & Use Cases](#user-personas--use-cases)
5. [Functional Requirements](#functional-requirements)
6. [Non-Functional Requirements](#non-functional-requirements)
7. [User Experience](#user-experience)
8. [Technical Considerations](#technical-considerations)
9. [Scope & Prioritization](#scope--prioritization)
10. [Success Criteria](#success-criteria)
11. [Risks & Mitigation](#risks--mitigation)
12. [Timeline & Milestones](#timeline--milestones)
13. [Appendix](#appendix)

> Sources: .claude/skills/discovering-requirements/resources/templates/prd-template.md (section order)

---

## Executive Summary

Six months of real sessions show that Loa's biggest remaining cost is not missing features but friction inside sessions: safety fences that block harmless commands about once every two sessions, planning artefacts too large for the Read and Edit tools, unattended runs that stop and wait for a human, cross-model review degraded to a single voice, and a cost meter that reads zero in every repository. This cycle removes those five sources of friction with the same discipline as the mechanical floor (ADR-003) and the model-generation floor (ADR-004): mechanical, tested, fail-loud, no new configuration surface unless strictly required.

The work is grounded in a usage-mining pass over 4.9 GB of local Claude Code transcripts (about 2,150 human and 7,800 subagent sessions) and the state of 40 Loa mounts. Each requirement below carries the number that justifies it and the acceptance test that proves it. The cycle ships on `feature/cycle-125-friction-floor` as a draft PR to `main`; under the pre-release mechanism shipped in 2.0.0-rc.1 the merge is prepared as `2.0.0-rc.2`.

> Sources: grimoires/loa/reports/usage-mining-2026-09-23.md §1–§3; grimoires/loa/context/cycle-125-brief.md §1–§2; docs/architecture/ADR-003-mechanical-floor.md; docs/architecture/ADR-004-model-generation-floor.md

---

## Problem Statement

### The Problem

The framework's guards, artefacts and orchestration were each added for a real reason, but in aggregate they now interrupt the agent more often than they protect the operator, and several signals the operator relies on (verdict quality, spend, run state) are silently wrong.

### User Pain Points

- **Fences block routine work.** About 1,180 hook blocks in ~2,150 sessions; the `rm -rf` ambiguity rule alone fired ~370 times, overwhelmingly on `rm -rf dist`, `coverage`, `/tmp/<name>`; the SQL rules fired ~220 times, mostly on heredocs that *write* test files or feedback markdown containing the keyword; `git branch -D` on squash-merged branches and `git checkout --` on generated files add ~130 more. The block rate per 1,000 tool results rose from 1.4 in March to 12.7 in September. (`block-destructive-bash.sh:1271`, `:698`, `:715`, `:747`, `:593`, `:668`)
- **Artefacts exceed the tools.** `sdd.md`, `prd.md`, `sprint.md` and `NOTES.md` are the files most often rejected by the Read tool for size (35 / 24 / 18 / 20 times) and the files where Edit anchors most often fail; three fleet repositories carry a NOTES.md over the 200 KiB block line that 2.0.0-rc.1 introduced.
- **Unattended runs stop.** `/run-resume` is the most used Loa command after the harness ones (142); ~1,570 permission denials cluster in headless populations ("auto-denied, prompts unavailable"); session-limit hits recur (57 hard hits); thirteen worktrees of one repository sit `interrupted` at implementation.
- **The second opinion is missing.** The Anthropic HTTP circuit breaker is OPEN or HALF_OPEN in seven mounts and the headless one in three; `adversarial-review.sh` emitted `malformed_response` 170 times and `api_failure` 122 times; only four of forty mounts have a `known-failures.md` to record any of it.
- **Cost has gone blind since the ledger moved.** Legacy ledgers were priced (≈ $59 across 16 repositories), but 539 of 679 rows at the current path carry `pricing_source: unknown` with cost 0 because dated OpenAI ids, `gemini-2.5-pro` and CLI hop names recorded as the model do not resolve in catalog pricing; `cost-report.sh` reads only the new path, so pre-move history is invisible; `cost-budget-enforcer` has never been invoked.

### Current State

Operators reword blocked commands, page through oversized files with offset/limit, restart runs by hand, discover degraded reviews after the fact, and cannot budget model spend at all.

### Desired State

Fences fire only on genuinely destructive commands; the four planning artefacts are read and edited by section under a budget; a run refuses to start unless it can finish unattended and resumes itself from the last task; provider health is one glance in `/loa`; every model call has a price.

> Sources: grimoires/loa/reports/usage-mining-2026-09-23.md §3 F1–F5, §4; .claude/hooks/safety/block-destructive-bash.sh:593,668,698,715,747,1271; .claude/scripts/notes-guard.sh:35,124-140

---

## Goals & Success Metrics

### Primary Goals

| ID | Goal | Measurement | Validation Method |
|----|------|-------------|-------------------|
| G-1 | Fences stop blocking harmless commands without losing a single genuine catch | Replay of an attributed fixture corpus: benign pass rate, dangerous block rate | `tests/unit/block-destructive-bash.bats` over `tests/fixtures/fence-corpus/` |
| G-2 | Planning artefacts are readable and editable by section within tool limits | Section reads of this repo's `prd.md` and `sdd.md` stay under the Read cap; skills consume sections | bats for the reader; `tools/check-prompt-budget.sh` green |
| G-3 | Unattended runs fail loud before the first task or resume themselves at the last task | Preflight predicates covered by fixtures; a simulated interruption resumes at the recorded task | bats; run-mode integration test |
| G-4 | Provider health is visible and self-healing | `/loa` shows breaker/credential/hop per provider; open HTTP breaker re-routes to the CLI hop; breakers expire | bats with breaker fixtures; status snapshot |
| G-5 | The ids the fleet actually calls are priced | Unpriced share on the fixture reproducing the fleet's ids; legacy ledgers readable and migratable | bats over fixture rows; `cost-report.sh` totals and unpriced share |

### Key Performance Indicators (KPIs)

| Metric | Current Baseline | Target | Timeline | Goal ID |
|--------|------------------|--------|----------|---------|
| Benign fence-corpus commands that pass | 0 % (all were blocked) | ≥ 80 % | Sprint 1 | G-1 |
| Dangerous fence-corpus commands blocked | 100 % | 100 % | Sprint 1 | G-1 |
| Read-cap rejections on prd/sdd/sprint/NOTES per session (fleet) | ~0.05 | measurable only post-release; proxy: section reads of the two largest artefacts ≤ 25k tokens | Sprint 2 | G-2 |
| Fleet NOTES.md over the block line after upgrade | 3 | 0 (rotated by `update-loa`) | Sprint 2 | G-2 |
| Preflight predicates with fixtures | 0 | ≥ 5 (permission mode, credentials, breaker, NOTES size, state consistency) | Sprint 3 | G-3 |
| Resume granularity | per sprint | per task | Sprint 3 | G-3 |
| Providers reported in `/loa` | 0 | every configured provider | Sprint 4 | G-4 |
| Mounts seeded with `known-failures.md` | 4 of 40 (fleet) | every new mount | Sprint 4 | G-4 |
| Unpriced rows (`pricing_source: unknown`) at the current ledger path | 539 of 679 (79 %) in the fleet sample | < 5 % on the fixture reproducing those ids | Sprint 4 | G-5 |

### Constraints

- Prompt byte budgets: protocols at 199,593 B of 200,000 (any protocol prose change net-zero or negative); skills ≤ 16,384 B including unconditionally-read resources.
- No new `.loa.config.yaml` keys unless strictly required; prefer conventions (gitattributes, path shapes, existing env vars).
- Never weaken a fence's genuine catches; Aleph stays opt-in and untouched.
- Every change test-first; review and audit with cross-model dissent per sprint.

> Sources: grimoires/loa/context/cycle-125-brief.md §2 acceptance lines, §3; grimoires/loa/reports/usage-mining-2026-09-23.md §3 (baselines); tools/check-prompt-budget.sh

---

## User Personas & Use Cases

### Primary Persona: The maintainer-operator

**Demographics:**
- Role: creator and sole maintainer of Loa; runs a fleet of ~30 mounted repositories from one workstation
- Technical Proficiency: expert; drives the truename cycle (`/implement`, `/review-sprint`, `/audit-sprint`, `/bug`) and unattended runs (`/run`, `/simstim`) rather than the golden-path aliases
- Goals: ship through the gates without babysitting; trust the signals the framework prints

**Behaviors:**
- Long sessions (p90 of 13–47 hours in the heaviest repositories) with compactions and resumes
- Upgrades mounts in bursts (three moved to 2.0.0-rc.1 within hours of publication)

**Pain Points:**
- Rewording blocked commands; paging through oversized artefacts; restarting runs; discovering degraded reviews late; no spend visibility

### Secondary Persona: The unattended run agent

**Demographics:**
- Role: Claude executing `/run sprint-plan`, `/run-sprint-plan` or a scheduled loop with nobody watching
- Technical Proficiency: bound by the harness permission mode and the fences; cannot answer prompts
- Goals: finish the sprint plan or stop with a precise, resumable state

### Tertiary Persona: A downstream fleet operator

**Demographics:**
- Role: developer on a repository that mounts Loa as a submodule with the copied `.claude/` set
- Goals: upgrade without a surprise (NOTES rotation, legacy ledger), see why a review was degraded

### Use Cases

#### UC-1: Clean a build directory during implementation
**Actor:** unattended run agent
**Preconditions:** `dist/` exists from a previous build
**Flow:**
1. Agent runs `rm -rf dist && npm run build`.
2. Fence classifies `dist` as a bare, visible, relative directory and allows it.
3. Build proceeds.
**Postconditions:** no block, no rewording
**Acceptance Criteria:**
- [ ] `rm -rf dist`, `rm -rf coverage`, `rm -rf /tmp/<name>` and `rm -rf "$(mktemp -d)"` pass
- [ ] `rm -rf /`, `rm -rf ~`, `rm -rf *`, `rm -rf .`, `rm -rf .git` still block

#### UC-2: Write a test file that mentions TRUNCATE
**Actor:** unattended run agent
**Preconditions:** none
**Flow:**
1. Agent writes `cat > tests/lease.test.ts <<'EOF' … TRUNCATE … EOF`.
2. Fence sees the keyword only inside a heredoc whose sink is a file, not a SQL runner, and allows it.
**Postconditions:** file written
**Acceptance Criteria:**
- [ ] heredoc into a file, `echo`, `git commit -m` bodies containing DROP/TRUNCATE/DELETE pass
- [ ] `psql … -c 'DROP TABLE x'`, `psql <<SQL TRUNCATE … SQL`, `mysql -e 'DELETE FROM t'` still block

#### UC-3: Implement sprint 3 of a five-sprint plan
**Actor:** unattended run agent
**Preconditions:** `grimoires/loa/sprint.md` is 60 KB
**Flow:**
1. `/implement sprint-3` reads only the `## Sprint 3` block through the artefact reader.
2. Review and audit read the same block plus its acceptance criteria.
**Postconditions:** no Read-cap rejection; edits anchor within the block
**Acceptance Criteria:**
- [ ] the reader returns exactly the requested heading block, budgeted, never empty
- [ ] `--full` returns the whole file on explicit request

#### UC-4: Start an overnight run on a laptop with a restrictive permission mode
**Actor:** maintainer-operator
**Preconditions:** `.claude/settings.local.json` lacks the allow rules the run needs
**Flow:**
1. `/run sprint-plan` invokes the preflight.
2. Preflight reports the unmet predicate (permission mode) and stops before the first task.
3. Operator fixes the mode; the run starts; state is checkpointed after each task.
4. The session hits its limit at task 2.3; the next session's `/loa` names `/run-resume` as the single next step and resumes at task 2.3.
**Postconditions:** no silent stall, no lost work
**Acceptance Criteria:**
- [ ] each preflight predicate has a passing and a failing fixture
- [ ] resume restarts at the recorded task, not the sprint

#### UC-5: Read the spend for last week
**Actor:** maintainer-operator
**Preconditions:** ledger rows written by HTTP and CLI hops
**Flow:**
1. `cost-report.sh --days 7` prices every row from the catalog snapshot (CLI rows estimated and flagged).
2. `--include-legacy` folds in the pre-2.0 ledger.
**Postconditions:** a non-zero total with an estimate share
**Acceptance Criteria:**
- [ ] zero null-cost rows for known models
- [ ] `cost_estimated: true` on estimated rows

> Sources: grimoires/loa/reports/usage-mining-2026-09-23.md §2, §3 F1–F5; grimoires/loa/context/cycle-125-brief.md §2

---

## Functional Requirements

### FR-1: Fence precision in `block-destructive-bash.sh`
**Priority:** Must Have
**Description:** Reclassify the four false-positive classes without weakening any genuine catch. (a) `rm -rf` passes for: a build-artefact or cache directory named by its last path segment at any relative depth (`dist`, `build`, `out`, `coverage`, `target`, `node_modules`, `tmp`, `__pycache__`, `.next`, `.turbo`, `.terraform`, `.venv`, `.tox`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `*.egg-info`); any bare relative name when the hook's working directory is itself under a temp root; `/tmp/<name>`, `/var/tmp/<name>`, `/private/tmp/<name>`; `$TMPDIR/<name>` only when the hook's own `$TMPDIR` resolves under a temp root; a variable operand only when the same command assigns it once from `mktemp -d`. Arbitrary bare project directories (`rm -rf src`) stay blocked and keep the explicit `./name/` spelling as the escape; hidden directories outside the cache vocabulary stay blocked; quoted payloads of `ssh`/`docker exec`/`kubectl exec` keep today's scanning (no scrub — a Flatline skeptic showed the scrub would remove protection that exists today). (b) The DROP/TRUNCATE/DELETE rules apply only when the command contains a SQL runner (`psql`, `mysql`, `sqlite3`, `prisma db execute`, `-c`/`--command` on one of them, a heredoc piped into one), never to text written by `cat > file <<EOF`, `echo`, or a commit body; execution through a language driver remains the documented residual it is today. (c) `git branch -D` passes when the branch is an ancestor of `origin/main`/`main` (offline check only — the hook makes no network call); squash-merged branches are deleted through the sanctioned `git-branch-prune.sh`, which may consult `gh` with a timeout, and the block message names it. (d) `git checkout -- <path>` / `git restore <path>` passes only when every path operand is generated (`git check-attr linguist-generated`, or under `dist/`, `build/`, `coverage/`, `**/_generated/`, or a lockfile).
**Acceptance Criteria:**
- [ ] `tests/fixtures/fence-corpus/` holds ≥ 40 previously-blocked benign commands and ≥ 15 dangerous ones, derived from the attributed samples; a corpus lint (bats) rejects hostnames, URLs, IPs, `@`-credentials, key shapes and bucket names, so the sanitisation is reproducible
- [ ] ≥ 80 % of the benign set passes; 100 % of the dangerous set blocks; the existing `block-destructive-bash.bats` stays green
- [ ] each relaxation has a negative test (the dangerous twin of the benign command), including `rm -rf src`, `rm -rf ./.git/`, `rm -rf "$TMPDIR"` with an unsafe `TMPDIR`, a re-assigned mktemp variable, and `ssh host 'rm -rf /'`
- [ ] the hook adds no network call; its runtime over the corpus stays within 1.5× of the pre-change measurement (the hook runs under the fail-open `hook-guard.sh`, so latency is a safety property)
**Dependencies:** `.run/usage-mining/mine-attrib.json` (sample seed, untracked)

### FR-2: Sectioned planning artefacts
**Priority:** Must Have
**Description:** Generalise `notes-guard.sh read` into one heading-addressed, budgeted artefact reader for `prd.md`, `sdd.md`, `sprint.md` and `NOTES.md` (`--file`, `--section <heading or Sprint N>`, `--full`), and route the skills through it: `/implement sprint-N` reads its own sprint block; `/review-sprint` and `/audit-sprint` read the sprint block and acceptance criteria; `/architect` reads the PRD by section. `/loa` surfaces size warnings at 100 KiB for the four artefacts. `update-loa` rotates NOTES.md when it is at or over the block line, so the 2.0.0 upgrade cannot strand a repository.
**Acceptance Criteria:**
- [ ] reader bats: heading selection (exact and `Sprint N`), budget cap with footer, loud fallback when the template drifts, never empty
- [ ] this repository's `prd.md` (101 KB) and `sdd.md` (69 KB) read by section under 25k tokens
- [ ] `implementing-tasks`, `reviewing-code`, `auditing-security`, `designing-architecture` SKILL.md files reference the reader and remain ≤ 16,384 B each
- [ ] `update-loa.sh` rotates a NOTES.md at/over 200 KiB (bats with a generated fixture); migration guide gains an rc.2 addendum
**Dependencies:** `notes-guard.sh` (cycle-124 FR-10)

### FR-3: Run preflight, task checkpoints and resume surfacing
**Priority:** Must Have
**Description:** `run-preflight.sh` runs at the entry of `/run`, `/run-sprint-plan` and `run-mode`, and fails loud with a checklist when: the harness permission mode cannot grant the run's tool set unattended (settings files + `LOA_RUN_MODE`), a required model credential or CLI hop is absent (reusing the cheval preflight), a provider breaker is OPEN for a required voice, NOTES.md is at the block line, or the run/ledger state files are inconsistent. The run state is checkpointed after every task. On session start, a stale `RUNNING` / `INTERRUPTED` state is surfaced with the exact resume command by `loa-status.sh` and the SessionStart line; in autonomous mode `/loa` offers resume as the single next step.
**Acceptance Criteria:**
- [ ] each predicate has a passing and a failing fixture in bats; the checklist names the predicate and the fix
- [ ] state is written after each task; `run-resume` restarts at the recorded task (integration fixture)
- [ ] `loa-status.sh` prints the resume line for a stale state and nothing for a clean one
- [ ] no new config key; `LOA_RUN_MODE` and existing settings are the inputs
**Dependencies:** `session-limit-capture.sh`, run-mode skill, `cheval-preflight-gate`

### FR-4: Provider health as a first-class signal
**Priority:** Must Have
**Description:** `loa-status.sh` prints one line per configured provider: breaker state and age, credential present (never the value), CLI hop available. `cheval` re-routes to the same company's CLI hop when the HTTP breaker is OPEN (if the chain resolver already does, prove it with a test and surface it in the status line); breakers expire to HALF_OPEN after a documented cooldown; `cheval --reset-breaker <provider>` exists. `mount-submodule.sh` and `mount-loa.sh` seed `grimoires/loa/known-failures.md` from the template so the KF surface hook has a ledger downstream.
**Acceptance Criteria:**
- [ ] bats with breaker-file fixtures for OPEN / HALF_OPEN / CLOSED and expiry
- [ ] status snapshot test; no credential value ever printed
- [ ] re-route proven by a test on the chain resolver
- [ ] mount tests assert the seeded ledger
**Dependencies:** `.run/circuit-breaker-*.json` writers in `loa_cheval`

### FR-5: Cost accounting that prices what the fleet actually calls
**Priority:** Must Have
**Description:** Pricing lookup resolves the model ids the CLI hops record — dated OpenAI ids (`gpt-5.2-2025-12-11`, `gpt-5.5-2026-04-23`), Google ids such as `gemini-2.5-pro`, and rows whose `model` is a hop name (`codex-headless`, `claude-headless` — the hop must record the resolved model id, or the pricing layer must normalise the hop name to it) — so `pricing_source: unknown` becomes the exception; when the CLI reports no usage, the row is priced from cheval's own token counts and marked `cost_estimated: true`. `cost-report.sh` prints the unpriced share, reads the current path and, with `--include-legacy`, the pre-2.0 path `grimoires/loa/a2a/cost-ledger.jsonl`, and offers `--migrate-legacy` (append-only move with a receipt). `cost-budget-enforcer` reads the same totals, or is retired with the decision recorded if it cannot be made truthful.
**Acceptance Criteria:**
- [ ] bats over fixture rows reproducing the fleet's unpriced ids: each resolves to a price; truly unknown ids stay `unknown` with cost 0 and are counted in the report's unpriced share
- [ ] the CLI hops record the resolved model id (or the normaliser maps the hop name) — pinned by a test per hop
- [ ] report totals match a hand computation on the fixture; legacy include and migrate covered by tests; the migrate leaves a receipt
- [ ] test harness ledger isolation preserved (KF-033)
**Dependencies:** `loa_cheval/metering/ledger.py:135-149` (`find_pricing`, cli_reported path), `loa_cheval/metering/pricing.py`, the four `*_headless_adapter.py`, `tools/check-ledger-hygiene.sh`

> Sources: grimoires/loa/context/cycle-125-brief.md §2 FR-1–FR-5; grimoires/loa/reports/usage-mining-2026-09-23.md §3; .claude/hooks/safety/block-destructive-bash.sh:302,378,498; .claude/scripts/notes-guard.sh:82-140; .claude/adapters/loa_cheval/metering/ledger.py:135-149; .claude/scripts/mount-submodule.sh:1128-1154

---

## Non-Functional Requirements

### Performance
- The fence hook's added classification must not raise its per-command latency past the existing hook-guard budget; measure with the corpus.
- Section reads complete without loading more than the selected block plus an index pass.

### Scalability
- The fence corpus and the artefact reader work on the largest fleet artefacts observed (NOTES.md 349 KiB, sprint.md 42 KB, prd.md 101 KB).

### Security
- No relaxation may admit a command that deletes outside the repository or a temp directory, executes SQL against a runner, force-pushes, or writes the System Zone; each relaxation ships with its dangerous twin as a negative test.
- Provider status never prints a credential value; preflight never logs secrets.
- Cost ledger writes keep `O_NOFOLLOW` and the resolver's refusals.

### Reliability
- Preflight is fail-loud; a predicate that cannot be evaluated is reported as unknown, not as pass.
- Resume is idempotent from any checkpoint.

### Compliance
- Prompt byte budgets hold (`tools/check-prompt-budget.sh`); REPO-MAP and checksums regenerated after every `.claude/` change; the a2a record lives on `record/cycle-125-a2a`.

> Sources: grimoires/loa/context/cycle-125-brief.md §3; grimoires/loa/reports/usage-mining-2026-09-23.md §3 F2 (artefact sizes); .claude/hooks/hook-guard.sh

---

## User Experience

### Key User Flows

#### Flow 1: A blocked command that should not be
```
agent runs rm -rf dist → fence classifies (bare visible relative dir) → allowed → build continues
```

#### Flow 2: Starting an unattended run
```
/run sprint-plan → run-preflight.sh → checklist (all green) → tasks with per-task checkpoints → session limit → next session: /loa → "resume: /run-resume" → resumes at task
```

#### Flow 3: Reading provider health
```
/loa → "anthropic: http OPEN 3d (re-routing to claude-headless) · credential: present · hop: available" → operator acts or ignores
```

### Interaction Patterns
- Every refusal names the predicate and the fix in one line (the fence message, the preflight checklist, the status line).
- Reads are budgeted and end with a footer that names how to get the rest.

### Accessibility Requirements
- Plain-text, single-line diagnostics; no colour-only signals.
- Status lines under 120 characters.

> Sources: grimoires/loa/context/cycle-125-brief.md §2 FR-3, FR-4; .claude/scripts/notes-guard.sh:139 (footer pattern)

---

## Technical Considerations

- **Fence architecture.** The hook already scrubs complete quoted `cat` heredocs (`block-destructive-bash.sh:296-378`); FR-1 extends the classification to sink-aware SQL matching and path-shape classes for `rm -rf`, with the corpus as the regression floor.
- **Artefact reader.** `notes-guard.sh` already indexes heading blocks and emits budgeted ranges (`:82-140`); FR-2 parameterises the file and heading family rather than adding a second reader.
- **Preflight inputs.** Permission mode comes from `.claude/settings.json`, `.claude/settings.local.json` and `LOA_RUN_MODE`; credentials from the cheval preflight; breakers from `.run/circuit-breaker-*.json`; NOTES size from `notes-guard.sh check --delta`.
- **Breaker semantics.** Files under `.run/` per provider and transport (`http_api`, `headless`); FR-4 documents cooldown and adds a reset entry point.
- **Pricing.** `ledger.py` already prefers a CLI-reported amount and falls back to `find_pricing` (`:135-149`); FR-5 makes the fallback cover CLI hops with cheval-counted tokens and flags estimates.
- **Records.** The a2a sprint record goes to `record/cycle-125-a2a`; CHANGELOG entries under `[Unreleased]` are finalised by the pipeline as `2.0.0-rc.2`.

> Sources: .claude/hooks/safety/block-destructive-bash.sh:296-378; .claude/scripts/notes-guard.sh:82-140; .claude/adapters/loa_cheval/metering/ledger.py:135-149; grimoires/loa/runbooks/post-merge-candidates.md §Pre-release candidates

---

## Scope & Prioritization

### In scope (this cycle)
FR-1 through FR-5, each Must Have, in four sprints.

### Out of scope (deferred, evidence recorded)
- **F6 surface diet:** 27 of 54 commands and 22 of 36 skills never invoked; trajectory logs write-only.
- **F7 fleet upgrade tooling:** version spread 1.101 → 2.0.0-rc.1; copy-set drift in three mounts; inconsistent `framework_version` formats.
- **F8 abandoned-cycle sweep:** roughly half of fleet sprint directories lack a COMPLETED marker.
- GitHub infrastructure (branch protection, environments) and Aleph.

### MVP definition
A merge that lands as `2.0.0-rc.2` with all five FRs' acceptance tests green and the fence corpus committed.

> Sources: grimoires/loa/context/cycle-125-brief.md §2 (Non-goals), §4; grimoires/loa/reports/usage-mining-2026-09-23.md §3 F6–F8

---

## Success Criteria

- Fence corpus: ≥ 80 % benign pass, 100 % dangerous block, existing suite green.
- Artefact reader in use by four skills; NOTES rotation on upgrade tested; budgets green.
- Preflight with ≥ 5 fixture-backed predicates; per-task checkpoints; resume surfaced by `/loa`.
- Provider lines in `/loa`; re-route proven; breaker reset and expiry tested; known-failures seeded on mount.
- The fleet's unpriced ids resolve to prices on the fixture; unpriced share printed; legacy include/migrate tested.
- Every sprint COMPLETED with consistent LOA-VERDICT trailers; draft PR with CI green and one Bridgebuilder pass triaged.

> Sources: grimoires/loa/context/cycle-125-brief.md §2 acceptance lines, §5

---

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| A relaxation admits a destructive command | High | every relaxation ships its dangerous twin; corpus is a regression floor; audit dissent on each sprint |
| Sink-aware SQL matching misses an execution form (e.g. `node -e` with a driver) | Medium | keep the keyword match for known runners and document the residual; the fence was never a complete SQL guard |
| Section reader changes what skills see and shifts review quality | Medium | `--full` remains; skills read the sprint block plus ACs; A/B harness from cycle-124 available for a spot check |
| Preflight blocks a run the operator wanted anyway | Low | checklist names the fix; `LOA_RUN_MODE=interactive` path unchanged |
| Cost estimates mislead | Low | estimates flagged per row; report shows the estimated share |
| Prompt budgets overflow when skills gain reader references | Medium | net-zero edits; `tools/check-prompt-budget.sh` gates every commit |
| Only one dissent voice available on this host | Medium | record the failed-run envelope per skill guidance; the OpenAI voice is functional |

> Sources: grimoires/loa/context/cycle-125-brief.md §3; grimoires/loa/known-failures.md KF-004, KF-017, KF-033, KF-034

---

## Timeline & Milestones

| Sprint | Scope | Exit |
|--------|-------|------|
| 1 | FR-1 fence precision + fixture corpus | corpus committed, ≥ 80 % / 100 %, suite green |
| 2 | FR-2 sectioned artefacts + NOTES rotation on upgrade | reader in four skills, budgets green, migration addendum |
| 3 | FR-3 preflight, per-task checkpoints, resume surfacing | fixtures per predicate, integration resume test |
| 4 | FR-4 provider health + FR-5 cost accounting + docs | status lines, re-route test, seeded KF, priced ledgers, CHANGELOG under `[Unreleased]` |

> Sources: grimoires/loa/context/cycle-125-brief.md §4

---

## Appendix

### Assumptions recorded (autonomous run)
- `[ASSUMPTION]` Cached `/ride` reality (2026-05-04) is used without a re-run; the PRD is grounded in the usage report and direct code citations instead.
- `[ASSUMPTION]` The operator's "proceed" authorises this cycle's scope as the five items ranked most impactful in the review; F6–F8 are deferred, not dropped.
- `[ASSUMPTION]` withdrawn after the Flatline PRD review (skeptic SKP-001): quoted payloads of `ssh`/`docker exec`/`kubectl exec` keep today's scanning; the residual false positives from remote payloads are accepted.
- Flatline PRD review (2026-09-23, two voices, scoring degraded): nine skeptic concerns were integrated into FR-1 (no bare project-directory allowance, real `$TMPDIR` check, single mktemp assignment, no network in the hook, corpus lint) and into the SDD (atomic checkpoint writes with schema version and beads as the recovery source; pricing-snapshot governance recorded as an open question).
- `[ASSUMPTION]` The merge of this cycle is prepared as `2.0.0-rc.2` (a merge on the rc tag increments); no CHANGELOG heading is authored.

### Evidence pointers
- `grimoires/loa/reports/usage-mining-2026-09-23.md` (tracked summary)
- `.run/usage-mining/` (raw aggregates and scripts, untracked; fence sample seed under `mine-attrib.json` → `blocks_by_rule[*].samples`)
- `grimoires/loa/context/cycle-125-brief.md` (operator brief)

### Glossary
- **Fence** — a PreToolUse hook rule in `block-destructive-bash.sh` that refuses a Bash command.
- **Breaker** — a per-provider, per-transport circuit-breaker file under `.run/`.
- **Checkpoint** — the run-mode state written after a unit of work so `run-resume` can restart there.

> Sources: grimoires/loa/reports/usage-mining-2026-09-23.md §1, §5; grimoires/loa/context/cycle-125-brief.md §1
