# PRD brief: earned guards and open voices

**Status**: brief for `/plan-and-analyze` input; not a PRD; no cycle opened. **Date**: 2026-10-14. **Source**: `comparison.md` and `proposals.md` in this directory (Van Clief paradigm review against v2.0.0-rc.4). Drop a copy into `grimoires/loa/context/` to seed Phase 0.

## Problem

Loa's heavy end has fresh evidence of earning its cost on frontier models: every cycle-128 sprint failed a first review or audit round, the audit caught HIGHs the review approved, and Bridgebuilder caught HIGHs after both. Loa's light end does not: about 20 KB of prose loads every turn and 7.3 KB of it restates checks that already run mechanically; the fence produced 105 real blocks in four weeks and no catch; the implement gate never blocks and was inert from cycle-050 to rc.3; the run-mode circuit breaker's counters were never updated across five changes-required rounds; team guards are no-ops without an env var the lead never sets; input guardrails caught nothing in 82 events; six golden skills all sit within one percent of their byte cap. No guard carries an origin or a yield number, so the framework cannot tell an earned guard from an invented one, and it has never run the control (the same work, gate off) that its own eval harness can run. Separately, the cheval substrate can reach a local OpenAI-compatible server by configuration, but every mechanism that makes a voice count (family independence, companion chain, Bridgebuilder key map, schema enforcement, repair chain, quorum arithmetic) is Anthropic or OpenAI shaped, there is no local posture, and the model-generation floor refuses nothing while the defaults assume hosted frontier models.

## Goals

Make every guard carry its origin and its measured yield; thin what the model no longer needs and retire or repair what does not run; make files, not model-written JSON, the authority for run position; let open-weight and local models serve as advisory voices with an honest local posture; give operators one profile knob that cannot reach the gate floor. Keep the floor exactly as gated today.

## Functional requirements

- **FR-1 Guard register and yield.** A generated, tracked `grimoires/loa/guards.md` listing every hook, fence pattern id, validator rule and gate with class (harness / script / prose), origin (KF, issue, finding, cycle), knob, 30-day real blocks, likely false positives and last real catch, computed by `guard-yield.sh` from the hook registry and `.run/audit.jsonl` with bats-replay rows excluded by `cwd`. A CI lint fails when a guard has no origin. `/loa` prints the summary line. The hooks-reference registration table is generated from it.
- **FR-2 Control arms.** `evals/suites/review-recall.yaml` and `audit-recall.yaml` gain pre-registered arms: with and without the companion voice, the Karpathy block, the two always-loaded rule files, and the audit's "look for what the review did not" instruction. The corpus is seeded with the round-1 states of sprints 247 to 254 and their accepted findings as labels. Recall, refuted share and tokens per call are recorded; comparison across model versions is refused.
- **FR-3 Prose diet.** `stash-safety.md` and `skill-invariants.md` become path-scoped; CLAUDE.loa.md rows that describe a mechanism shrink to a pointer; prose-only rows gain a mechanism or move to a protocol; the kernel cap is lowered to the post-diet size; the KF session table stays behind its knob. No deletion ships before its FR-2 arm shows no recall loss.
- **FR-4 Retire or repair inert controls.** The implement gate either denies in a RUNNING state with file-presence authority or is demoted to telemetry and undocumented as a fence; `disallowed-tools` on pure-review skills strips Write and Edit or the invariant doc is corrected; the surgical-diff hook resets per task or is removed; input guardrails and danger level default off downstream; team guards are armed from the lead's spawn path or their rows leave CLAUDE.loa.md; the circuit-breaker counters are computed by `run-checkpoint.sh`.
- **FR-5 File-authoritative run position.** `.run/sprint-plan-state.json` and `.run/circuit-breaker.json` become derived caches recomputed from COMPLETED markers, LOA-VERDICT trailers, the ledger and the latest implementation commit; `/loa`, `run-resume` and the implement gate read the derivation; a drift reproduction test passes.
- **FR-6 Fence false positives.** Heredocs consumed by an interpreter are scanned as today; heredocs redirected to a file or a non-executing tool are scanned for command tokens at line start only. Every existing corpus D-row stays; new B-rows cover the recorded prose cases.
- **FR-7 Advisory open-weight voices.** The Azure example loads; `openai_compat` with a literal auth, `secret_env_allowlist`, declared `context_window`, streaming deadlines and a local dispatch group are documented; an explicit per-provider opt-in admits `http` and loopback; the chat-completions body carries `response_format: json_schema` for `structured_json` entries and `schema_enforced` reflects the body sent; `reasoning_content` and `<think>` blocks are stripped before qualification; operators declare `family` and `lineage` per model and `_adv_family_of` reads the merged config; a `counted_as: advisory_voice` keeps findings, tags them and contributes no verdict-quality envelope; promotion to a counted voice requires a distinct declared lineage and an FR-2 recall result above a maintainer-set threshold; the Bridgebuilder key map and the health probe derive from the merged config; hosted open-weight prices enter the catalog and the dissent budget gate reads catalog prices.
- **FR-8 Local posture.** `hounfour.locality: local_voices` pins the KF-004 repair chain to the answering voice, disables the `tiny` and `claude-headless` fallbacks, refuses hosted hops at plan time with a named reason, records locality in MODELINV, and states in config and output that with one local family every security audit is DEGRADED.
- **FR-9 Profile knob.** `loa.profile: lean | standard | full` sets the defaults of the optional surfaces as a set; `standard` equals today; the schema exposes no floor key under `profile`; a test asserts `lean` leaves review, audit, verdict-derive, the dissent artefact gate, the deny list, FR-1.2b, the System-Zone rules and FR-8 unchanged; `/loa` prints the effective profile.
- **FR-10 Task kinds.** Sprint tasks carry `kind: mechanical | judgment | operator`; the validator requires it from a dated migration; the review's spec axis flags mechanical tasks shipped as prose and operator tasks completed unattended; release notes report the per-cycle script / prose / model-call ratio.

## Non-goals

No change to `/review-sprint`, `/audit-sprint`, the LOA-VERDICT one-way rule, the dissent artefact gate, the deny list, fence FR-1.2b or the System-Zone fence. No open-weight model as the orchestrator. No counted open-weight voice without the FR-2 result. No removal of the fence core, beads or the ledger. No human edit gate added to the build path. No "ICM-compatible" claim or use of the ICM name beyond description. No automatic disabling of any guard from the register.

## Success criteria

- Every registered hook and fence pattern id has an origin; CI fails on a new one without it.
- The guard register shows, for this host, the 30-day block, false-positive and catch counts, with bats replays excluded (zero rows whose `cwd` is a bats temp dir).
- FR-2 arms run on the seeded corpus with three trials each and produce recall and tokens-per-call per arm; the report names which prose arms changed recall.
- Always-on prose per turn drops from about 20 KB to at most 12 KB with no FR-2 recall loss; `check-prompt-budget.sh` green at the lowered cap.
- `.run/circuit-breaker.json` shows a non-zero cycle count after a changes-required round in a fixture run; the drift reproduction resolves to the file-derived state.
- A fixture local server declared per FR-7 completes a dissent as an advisory voice: findings present and tagged, verdict quality unchanged, `schema_enforced: true` on the chat body, nothing sent to `tiny` or `claude-headless` under FR-8.
- `lean` profile: the floor-unchanged test passes; `/loa` prints the profile.
- Fence corpus green with the new rows; p95 latency under the 80 ms budget; no D-row removed.
- No regression in `implement-gate.bats`, `verdict-derive.bats`, `skill-capabilities.bats`, `adversarial-review-schema-enforced.bats`.

## Open questions for the interview

Whether the implement gate becomes a deny or a telemetry hook (maintainer). The recall threshold that promotes an advisory voice. Whether `lean` is the documented default for downstream mounts or opt-in. Whether `stash-safety.md` path-scoping should key on `git stash` in the command or on any git command. Whether to count fleet block logs now (mailbox) or later. Which open-weight hosted API, if any, gets catalog prices first.

## Shape

One cycle, three sprints: (1) FR-1, FR-2, FR-10 and the path-scoping half of FR-3; (2) FR-4, FR-5, FR-6, FR-9 and the rest of FR-3; (3) FR-7's recipe, schema and accounting slices and FR-8, with the family-and-lineage slice only if an operator need is declared during the cycle. Subagents Opus 5.5; review and audit on Fable 5.1; at most three dissent runs per sprint; every planning decision taken unattended becomes a `DEC` row.
