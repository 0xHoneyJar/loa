# Implementation Report: Sprint 3 (global sprint-257), implementer I

**Date:** 2026-10-14
**Engineer:** implementer I, Opus 5.5 subagent (model id `global.anthropic.claude-opus-5-5`)
**Sprint Reference:** grimoires/loa/sprint.md "## Sprint 3", Task 3.4 and the Bridgebuilder slice of Task 3.5
**Worktree:** /home/merlin/Documents/thj/code/loa-wt-s3c (branch `wt/cycle-129-s3c` at `a7682ba4`), not committed
**Patch:** ~/.cache/loa/cycle-129/patches/s3-i.patch

## Executive Summary

Bridgebuilder now reads `hounfour.providers`, `hounfour.locality` and `bridgebuilder.exit_on_degraded` only from trusted
configuration. Locally that is the working tree. On a pull request it is the `BRIDGEBUILDER_TRUSTED_CONFIG` repository
setting, else the base branch's `.loa.config.yaml` at `refs/remotes/origin/<base>`, else `refs/remotes/origin/main`.
A keyless or insecure provider that only the PR head declares is refused with
`head-only provider declaration refused: <name>`. An undeclared provider still fails with `Unknown provider: <name>`.
The completion banner prints `completed/planned`. A DEGRADED run writes its JSON, prints one WARN naming the incomplete
voices, and exits `bridgebuilder.exit_on_degraded`, which defaults to 3. Setting it to 0 restores the old exit. Both shell
callers that test the exit code now treat 3 as "completed, degraded". Under `hounfour.locality: local_voices`, every voice
whose provider is not `dispatch_group: local` is dropped from the plan by name and never rerouted.

**Key Accomplishments:**
- Trusted-source loader with injectable I/O seams, ref-name validation and fail-closed behaviour. Covered by 19 new tests.
- Keyless voices pass the key gate and reach cheval with no env var. A head-only voice never reaches cheval.
- `voicesPlanned` added to the pipeline result. A new `core/run-outcome.ts` module holds the count, the WARN line and the exit code.
- `entry.sh` dependency preflight moved from exit 3 to exit 4, so exit 3 has one meaning.
- `dist/` rebuilt, and the freshness and no-direct-fetch checks pass.

## AC Verification

### Task 3.4: Acceptance Criteria

**AC-3.4**: "Bridgebuilder accepts a keyless provider from the trusted config source, refuses a head-only declaration by name and still refuses an undeclared provider; the banner prints completed/planned; a DEGRADED verdict exits 3 (or 0 under the rollback key) and every enumerated caller surfaces it; the probe uses the configured endpoint and honours the host-string opt-in (PRD AC-7.4)"

| Clause | Status | Evidence |
|---|---|---|
| keyless provider from the trusted source accepted | Met | `resources/config.ts:398` (key gate), `config.ts:491` (keyless or literal auth), `core/multi-model-pipeline.ts:224` (dispatch with no key); tests "local mode trusts the working tree", "on a pull request a keyless provider from the base branch's config is accepted", "a keyless provider from the trusted config reaches cheval" in `__tests__/trusted-config.test.ts` |
| head-only declaration refused by name | Met | `config.ts:429` (text), `config.ts:393` (refusal before the key map), head comparison inside `loadTrustedConfig` `config.ts:605`; tests "a keyless provider declared only in the PR head is refused by name", "a head that re-declares a built-in provider with an insecure endpoint is refused by name", and the real-git test "the default git seam reads .loa.config.yaml at refs/remotes/origin/<base>" |
| undeclared provider still refused | Met | `config.ts:408-415`; test "a provider absent from the trusted config still fails with Unknown provider" covers local mode, PR mode and the old call shape |
| banner prints completed/planned | Met | `core/progress.ts:150`, `main.ts:712`; tests "prints completed/planned when a voice did not complete" in `progress.test.ts`, and "passes the completed count, not the configured count" in `run-outcome.test.ts` |
| DEGRADED exits 3, or 0 under the rollback key | Met | `core/run-outcome.ts:63`, `main.ts:742-750` sets the code after the JSON; `config.ts:449` default; example key `.loa.config.yaml.example:2419`; tests "a failed voice ... DEGRADED exits 3 (and 0 under the rollback key)", "every voice completed but the band is DEGRADED", "all planned voices completed and approved: exit 0", "sets the exit code ... only after the JSON is printed", and "exit_on_degraded: default 3, 0 honoured, invalid warns" |
| every enumerated caller surfaces it | Met | `.claude/scripts/spiral-harness.sh:696` helper, used at `:729` and `:1221`; `session-cap-bb/dispatcher.sh:78-92`; `tests/unit/bb-exit-degraded-callers.bats`, 9 cases |
| the probe uses the configured endpoint and honours the host-string opt-in | Not in this implementer's scope | `model-health-probe.sh` belongs to implementer G under the sprint's Implementers table. I did not touch it. |

### Task 3.5: Bridgebuilder clause of AC-3.6

**AC-3.6**: "Under `local_voices`: no hosted hop in the inventory is planned, each refusal named; the repair chain stays on the declared providers; MODELINV rows carry `locality`; the DEGRADED sentence is present in config and output; the session-exempt sentence is in the docs (PRD AC-8.1 … AC-8.3)"

| Clause, Bridgebuilder part | Status | Evidence |
|---|---|---|
| no hosted hop planned, each refusal named | Met | `config.ts:739` `applyLocality`, `config.ts:771` for the single-model voice, applied at `main.ts:486` and `main.ts:506`; tests "drops every hosted voice with the named reason", "hosted (the default) leaves the plan unchanged", "a PR head cannot turn local_voices off", "an invalid locality value refuses to start", "a provider with no dispatch_group is hosted" |
| repair chain, MODELINV `locality`, DEGRADED sentence, session-exempt sentence | Not in Bridgebuilder | These clauses belong to the dissent and cheval scripts owned by implementers H and G, and to the lead's docs. Bridgebuilder has no repair chain and writes no MODELINV rows. |

### Anti-vacuous notes

- Every "Met" row has a test that fails if the behaviour regresses. One example: put the configured count back into `reportComplete` and the `run-outcome.test.ts` source assertion fails.
- The exit path in `main.ts` is tested through pure functions plus a source-order assertion. `main.ts` runs `main()` on import, and a real run needs `gh` and cheval.

## Tasks Completed

### Task 3.4: Bridgebuilder keyless providers, banner, exit 3, callers

**Status:** Complete, except the probe clause, which belongs to G.

**Files Created/Modified:**
- `.claude/skills/bridgebuilder-review/resources/config.ts`: trusted loader, key map extension, head-only refusal, exit key, locality helpers.
- `.claude/skills/bridgebuilder-review/resources/core/types.ts`: `ProviderDecl`, `TrustedConfig`, `BridgebuilderConfig.trusted`.
- `.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts`: passes the trusted view, dispatches keyless voices, adds `voicesPlanned`.
- `.claude/skills/bridgebuilder-review/resources/core/run-outcome.ts`: new module for outcome, totals, exit code and WARN line.
- `.claude/skills/bridgebuilder-review/resources/core/progress.ts`: `reportComplete(totalMs, completed, planned)`.
- `.claude/skills/bridgebuilder-review/resources/main.ts`: wiring, JSON fields, WARN, `process.exitCode`.
- `.claude/skills/bridgebuilder-review/resources/entry.sh`: dependency preflight now exits 4.
- `.claude/skills/bridgebuilder-review/SKILL.md`: exit-code table, banner sentence, trusted-config precedence section.
- `.claude/skills/bridgebuilder-review/dist/**`: rebuilt with `npm run build`, including the manifest.
- `.claude/scripts/spiral-harness.sh`: `_bb_surface_exit`, used at both entry.sh sites.
- `.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh`: exit 3 maps to WARN, `degraded: true` and exit 0.
- `.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/{awaiter,logger}.sh`: comment only.
- `.loa.config.yaml.example`: `bridgebuilder.exit_on_degraded: 3` with its comment. Only the `bridgebuilder:` block was edited.
- Tests: `__tests__/trusted-config.test.ts` (new, 19), `__tests__/run-outcome.test.ts` (new, 8), `__tests__/progress.test.ts` (one updated, one added), `tests/unit/bb-exit-degraded-callers.bats` (new, 9).

**Deviations from Plan:**
- The suite runs on `node:test` through `tsx`, as `package.json` defines it. It does not use vitest. The new tests follow the existing files.
- The `entry.sh` preflight exit moved from 3 to 4. Without that change, exit 3 would also mean "dependencies missing".
- The Bridgebuilder reference does not exist as a separate file. The precedence table lives in the skill's `SKILL.md`.
- One TypeScript edit to `multi-model-pipeline.ts` was applied with a quoted Python string replacement run from Bash, not with the Edit tool. It contained no template literals. The result was checked with `tsc --noEmit` and the tests. Every other TypeScript file was authored with Write or Edit.

### Task 3.5, Bridgebuilder slice: locality

**Status:** Complete for `config.ts` and `main.ts`. No report from implementer H was available when I finished. I sent H the refusal text and the local rule to confirm, and had no reply by then. The text follows SDD §4.3:
`locality: local_voices refuses hosted hop <model_id> (<provider>); declare a local provider or set hounfour.locality: hosted`.

## Technical Highlights

### Config source precedence

| Mode | Detected by | `hounfour.providers`, `hounfour.locality`, `bridgebuilder.exit_on_degraded` read from |
|---|---|---|
| local | no `--pr`, no PR event, no `GITHUB_BASE_REF` | the working tree's `.loa.config.yaml` (repo root) |
| pull request | `--pr`, `GITHUB_EVENT_NAME` is `pull_request` or `pull_request_target`, or `GITHUB_BASE_REF` set | 1. `BRIDGEBUILDER_TRUSTED_CONFIG` env (YAML or JSON from a repository variable); 2. `refs/remotes/origin/<base>:.loa.config.yaml` (base from `GITHUB_BASE_REF`, else `gh pr view --json baseRefName`); 3. `refs/remotes/origin/main`; 4. none, so no keyless or insecure provider is admitted, with a WARN |

On a pull request the head checkout is read only to compare. Any provider it declares keyless or insecure without the
trusted source declaring the same is added to `headOnlyRefused`.

### Security Implementations
- Base ref names are validated before they reach git: no leading dash, no `..`, no `.lock`, and only a fixed character set. Only `refs/remotes/origin/<name>` is read, never a local branch the checkout could create.
- An `auth: "{env:VAR}"` key name is taken only from the trusted config, so a head cannot point a credential at a provider of its choosing.
- A base branch without `.loa.config.yaml` gives an empty trusted config, not a fallback to the head.
- An invalid `hounfour.locality` stops the run, so a typo never runs hosted voices silently. An invalid `exit_on_degraded` warns and uses 3.

### Integration Points
- The run JSON gains `degraded`, `voicesCompleted`, `voicesPlanned`, `exitCode`, and per verdict `voices {planned, completed, band, incomplete, degraded}`.
- Startup prints `[bridgebuilder] Trusted config: <source> (mode: …); locality: …; exit_on_degraded: …` and each warning once.

## Caller inventory

| Caller | How it consumes the exit code | Change |
|---|---|---|
| `.claude/scripts/spiral-harness.sh` `_gate_bridgebuilder` | exit swallowed by an or-true guard | captures rc; 3 logs a WARN naming the voices from the JSON; other non-zero codes log; gate still passes |
| `.claude/scripts/spiral-harness.sh` BB fix-loop re-review | exit swallowed by an or-true guard | same helper |
| `.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh` | propagated rc as its own exit | 3 gives a WARN, `degraded: true` and `incomplete_voices` in the handoff, and exit 0; other codes unchanged; BB stdout replayed |
| `session-cap-bb/awaiter.sh`, `logger.sh` | record `bb_exit_code` from the handoff JSON | comment only |
| `.claude/scripts/session-cap-fanout.sh` | generates YAML pointing at the dispatcher; never runs BB | none |
| `.claude/scripts/tests/test-bb-integration.sh` | mock entry.sh, exit code not tested | none; still 7 of 7 |
| `.claude/scripts/post-pr-orchestrator.sh`, `bridge-orchestrator.sh`, `/run-bridge` SKILL.md | run the bridge orchestrator and SIGNAL protocol; never run entry.sh | none |
| `.claude/scripts/flatline-orchestrator.sh`, `.claude/scripts/lib/env-loader.sh` | mention entry.sh in comments only | none |
| `.github/workflows/bridgebuilder-dist-smoke.yml` | imports `dist/main.js` and runs `node --check`; no review run | none |
| `.claude/skills/bridgebuilder-review/SKILL.md` | documents the exit codes | table updated |
| tests `bug-805`, `bug-898`, `entry-sh-node-options-vestigial`, `spiral-harness.bats` | entry.sh text or preflight | none; all green |

## Testing Summary

| Command | Result |
|---|---|
| `npm test` (bridgebuilder-review) | 866 of 867 pass. The one failure is `__tests__/persona.test.ts`, which needs `ANTHROPIC_API_KEY` (KF-036). It failed the same way at baseline, where 837 of 838 passed. |
| `npx tsc --noEmit` | clean |
| `bash tools/check-bb-dist-fresh.sh` | OK, dist is fresh |
| `bash tools/check-bb-no-direct-fetch.sh` | OK |
| `bats tests/unit/bb-exit-degraded-callers.bats` | 9 of 9 |
| `bats` spiral-harness, bug-805, entry-sh-node-options, bug-898, session-cap-fanout | 24, 5, 6, 56 and 22 ok; 0 failures |
| `bash .claude/scripts/tests/test-bb-integration.sh` | 7 passed |
| `bash tools/check-no-raw-sha256sum.sh` | OK. The script lives in `tools/`, not `.claude/scripts/` as the brief says. |
| `tools/check-prompt-budget.sh` | bridgebuilder-review SKILL.md is 9,942 B against a 16,384 B limit |

How to run:

```bash
cd .claude/skills/bridgebuilder-review && npm ci && npm test
npx tsx --test resources/__tests__/trusted-config.test.ts resources/__tests__/run-outcome.test.ts
bats tests/unit/bb-exit-degraded-callers.bats
```

## Known Limitations
- cheval still reads the working tree's `.loa.config.yaml` when it dispatches. On a PR head checkout, a head that changes the `endpoint` of a provider the trusted config already declares, without adding keyless or insecure, is not refused by Bridgebuilder. Closing that gap needs cheval to take the trusted view (G's area) or a broader head-diff refusal.
- `multi_model.models`, the voice list, is still read from the working tree as before. Every voice it names must still pass the trusted key gate and the locality filter.
- With `--pr` and no `GITHUB_BASE_REF`, the base branch comes from `gh pr view`. If that fails, the loader uses `origin/main`. A local run with `--pr`, which the spiral harness does, counts as PR context and reads the base config.
- The main-process exit path is tested through pure functions and a source-order assertion, not a full process run.
- Totals across several PRs in one run are summed, so the banner shows the sum of completed against the sum of planned.

## Verification Steps
1. `cd .claude/skills/bridgebuilder-review && npm ci && npm test`: expect only the KF-036 persona failure.
2. `bash tools/check-bb-dist-fresh.sh && bash tools/check-bb-no-direct-fetch.sh`.
3. `bats tests/unit/bb-exit-degraded-callers.bats`.
4. `grep -n "exit_on_degraded" .loa.config.yaml.example`.

## Assumptions

- [ASSUMPTION fact] The Bridgebuilder test runner is `node:test` via `tsx --test`, as `package.json` defines it. No vitest is configured, and "vitest" in the brief means this suite.
- [ASSUMPTION fact] `entry.sh` already used exit 3 for "node_modules/zod missing". No caller or test depended on that value; `bug-805` only asserts a non-zero code that is not 99.
- [ASSUMPTION fact] Only `spiral-harness.sh` at two sites and `session-cap-bb/dispatcher.sh` run entry.sh and act on its exit code. `/run-bridge` and `post-pr-orchestrator` never run entry.sh.
- [ASSUMPTION fact] `dispatch_group` is declared per model in cheval's config (`providers.<p>.models.<m>.dispatch_group`), with an optional provider-level key.
- [ASSUMPTION fact] No separate Bridgebuilder reference file exists. The skill's `SKILL.md` is where its docs live.
- [ASSUMPTION decision] "Repository settings" is implemented as the `BRIDGEBUILDER_TRUSTED_CONFIG` env var, holding YAML or JSON text that a workflow sets from a repository variable. When set on a PR, it takes precedence over the base ref.
- [ASSUMPTION decision] Only `refs/remotes/origin/<base>` and then `refs/remotes/origin/main` are read. No local branch is read, and with no readable source no keyless or insecure provider is trusted.
- [ASSUMPTION decision] `hounfour.locality` and `bridgebuilder.exit_on_degraded` come from the same trusted source as the providers, so a PR head can neither lower the exit code nor turn `local_voices` off.
- [ASSUMPTION decision] A head declaration counts as head-only when it is keyless or insecure and the trusted source does not declare the same provider with the same flag. This also catches a head that re-declares a built-in provider as insecure.
- [ASSUMPTION decision] A FAILED verdict-quality band counts as DEGRADED for the exit code, and so exits 3, as does any planned voice without a completed result.
- [ASSUMPTION decision] Under `local_voices`, a voice is local only when the trusted config gives `dispatch_group: local`. The model entry is checked first, then the provider key, then all of the provider's declared models. Anything else is hosted and refused. The single-model voice is held to the same rule.
- [ASSUMPTION decision] An invalid `hounfour.locality` stops the run. An invalid `exit_on_degraded` warns and uses 3.
- [ASSUMPTION decision] The dispatcher maps exit 3 to exit 0 with `degraded: true` in its handoff. The spiral harness keeps its non-blocking gate and adds the WARN line.
- [ASSUMPTION decision] The refusal text is the SDD §4.3 form with the remediation suffix. Implementer H had not confirmed it when I finished.
