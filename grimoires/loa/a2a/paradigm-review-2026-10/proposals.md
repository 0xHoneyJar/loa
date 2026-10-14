# Proposals: what Loa should take from the Van Clief review, and what it should not

**Date**: 2026-10-14. Companion to `comparison.md` (same cite tags: `D:`, `TR/`, `W:`, `S:inv`, `S:ow`, `S:yield`, `L:`). Planning only; nothing here was implemented.

**Ranking rule**: expected value to the sanctioned path (plan, implement, review, audit, run) divided by effort, with the gate-risk column as a veto. Nothing below may make `/review-sprint` or `/audit-sprint` bypassable, weaken the LOA-VERDICT one-way rule, the dissent artefact gate, the deny list, fence FR-1.2b or the System-Zone fence, or let a knob reach those. That set is called **the floor** below.

**Effort**: **S** at most half a sprint, prose and config; **M** one sprint with scripts and tests; **L** multi-sprint.

**Each item** carries: what is imported, the Loa surface, the test, gate risk, effort, and an adversarial pass (the strongest reason it is wrong, and what answers it).

---

## ADOPT (import nearly as-is)

### A1. Guard provenance and yield: "Audits are earned, not invented"
- **Import**: "A stage's Audit table contains checks from real failures in real runs, not imagination"; tables of "3-6 entries"; "New workspaces start minimal and expand based on observed issues" (`W:§4`, unmerged principles branch). Loa already has the raw material: the KF ledger with recurrence counts, the fence corpus `why` fields, and `.run/audit.jsonl` rows with `pattern_id`, `action`, `ts`, `cwd`.
- **Loa surface**: a generated guard register, `grimoires/loa/guards.md` (tracked, like `known-failures.md`), one row per hook, fence pattern id, validator rule and gate: `class` (HARNESS / SCRIPT / PROSE), `origin` (KF id, issue, review finding, cycle), `knob`, `blocks_30d`, `likely_fp_30d`, `last_real_catch`. Writer: `.claude/scripts/guard-yield.sh` reading the hook registry and `.run/audit.jsonl`, excluding bats-replay rows by `cwd` (the KF-033 class, 395 of 500 rows on this host, `S:inv` E4). It replaces the hand-maintained registration table in `hooks-reference.md`, which lists 18 rows and omits six hooks (`S:inv` totals). `/loa` prints one line: guards, guards without origin, real blocks and likely false positives in 30 days.
- **Test**: bats over a fixture audit log with replay rows; a CI lint that fails when a fence pattern id or a registered hook has no `origin`.
- **Gate risk**: none; reporting only. The register never disables anything.
- **Effort**: M.
- **Adversarial pass**: "No catch in 30 days" is not "no value": the deny list and FR-1.2b are tail insurance, and prose rules deter attempts the block log cannot see. Answer: the register reports, the operator decides, and A2 measures deterrence; the lint demands an origin, not a recent catch. One host's log is thin; fleet counts can arrive later through `cross-repo-status-lib.sh` or the mailbox.

### A2. The control run: a pre-registered gate-off arm in the eval harness
- **Import**: "same model, same questions, no folder. Then the same questions with the folder. You commit both runs, raw, and you report what actually changed" (`W:§1`, Comp #14). Loa's cycle-124 A/B (recall, false positives, tokens per call; flips only where pre-registered gates held, ADR-004 §5) is the same protocol.
- **Loa surface**: `evals/suites/review-recall.yaml` and `audit-recall.yaml` already carry an `ab:` block with a floor commit and a frozen corpus (`L:evals/suites/review-recall.yaml:3,23-26`). Add arms: review with and without the companion voice; with and without the Karpathy block; with and without the two always-loaded rule files; audit with and without "look for what the review did not". Seed the corpus with the round-1 states of sprints 247 to 254, whose accepted findings are the labels (`S:yield` §1). Record recall, refuted share and tokens per call; `advisory_on_model_skew` stays on.
- **Test**: `evals/tests/recall-baseline-freshness.bats` extended to the new arms; a test that an arm cannot be compared across model versions.
- **Gate risk**: none; measurement. Any flip remains a separate, pre-registered decision (ADR-004 open question on executor tiers).
- **Effort**: M. The harness, corpus manifest and comparison script exist.
- **Adversarial pass**: a frozen corpus of already-reviewed PRs can make a gate look useless because the easy defects are gone. Answer: the round-1 states are pre-review, and the 24 accepted HIGHs of sprint 248 are a hard label set. Second objection: the arm "without the companion" measures a Fable fresh context, not model diversity; that is the point (`S:yield` §0).

### A3. Rule / lookup / judgment tags and "the step the agent must never do" on sprint tasks
- **Import**: every step in the October teaching example is tagged `(rule)`, `(lookup)` or `(judgment)`, one step is circled as the time sink, and one is "The step AI must never do ... Lena reads every email first" (`W:§4`, lena-reminders). Principle 2's test: "Could a Python function do this reliably?" (`W:§4`).
- **Loa surface**: `sprint-template.md` tasks gain `kind: mechanical | judgment | operator`. `validate-artifact.sh --type sprint` requires it from a dated migration. The review's spec axis checks that `mechanical` tasks shipped as scripts with tests, not as prose the model re-executes (Karpathy ladder, `L:.claude/protocols/karpathy-principles.md`), and that `operator` tasks were not completed unattended (they become `decision:unblock` tickets or `/decisions` rows). The fact/decision split from cycle-128 is the interview-side twin.
- **Test**: validator bats; a review fixture with a `mechanical` task implemented as skill prose yields a MEDIUM.
- **Gate risk**: none; adds a review check.
- **Effort**: S.
- **Adversarial pass**: another required block in the sprint plan is ceremony if nobody reads it. Answer: the reviewer reads it (spec axis), and it is the one field that lets A1 and the 10/30/60 line (L1) be computed per sprint rather than per repo.

---

## ADAPT (change for Loa's mechanics)

### B1. Diet of the always-on prose
- **His mechanism**: "Plain files in a sensible order get you most of the way there" (`W:§2`); the routing table tells the agent what to read and what to skip (`TR/20:135-137`).
- **Loa mapping**: about 20 KB of prose loads every turn (`S:inv` totals): CLAUDE.loa.md 10,225 B at a 10,240 B cap, the project CLAUDE.md 2,460 B, and two rule files with no `paths:` frontmatter, 7,301 B, that restate checks already mechanized (FR-1.2b, `validate-skill-capabilities.sh`). Steps: (1) give `stash-safety.md` and `skill-invariants.md` `paths:` frontmatter so they load only when a stash command or a SKILL.md is in play; (2) in CLAUDE.loa.md, rows that describe a mechanism shrink to one line that names it, and rows that describe nothing mechanical (section F of `S:inv`: TaskCreate, `/bug` eligibility, beads creation, the Teams rows, the breaker arithmetic) either get a mechanism (B2) or move to a protocol; (3) lower the kernel cap after the diet so it holds; (4) the 5,168 B KF table at session start stays behind its knob, default off downstream.
- **Test**: `tools/check-prompt-budget.sh` with the new cap; `no-history-in-rule-text.bats`; the A2 arm "without the rule files" shows no recall loss before anything is deleted.
- **Gate risk**: none in mechanism. The deterrent value of rule text is the unknown; A2 measures it first.
- **Effort**: S for (1), (3), (4); M with (2).
- **Adversarial pass**: prompt text is cheap on cached prefixes, so why bother? Answer: 20 KB per turn across every mount is not cheap on CLI hops without caching, and the budget evidence says the cap, not need, sets skill size (`S:inv` §G). Second: path-scoped rules may fail to load when the hazard comes through an unusual path. Answer: the mechanical check (the fence) is what holds; the text is the explanation.

### B2. Retire or repair the inert controls
- **His mechanism**: "Audits are earned, not invented"; start minimal, expand on observed issues (`W:§4`).
- **Loa mapping** (the SCAFFOLD rows of `S:inv`, each with its recorded state):
  - (a) **Implement gate**: ask only, invalid output from cycle-050 to rc.3, trusts `.run/sprint-plan-state.json` that the model writes and that reads `RUNNING` after ship (`S:inv` §B, E3). Decide: deny in a RUNNING state with file-presence authority (B3), or demote to a telemetry hook and stop documenting it as a fence. Tighten-only.
  - (b) **`disallowed-tools`** on review skills strips NotebookEdit only; Write and Edit remain. Either strip them from pure-review skills, as `skill-invariants.md` already claims, or correct the claim.
  - (c) **Karpathy surgical-diff hook**: warn-only, running total 143,324 lines against a 100-line threshold, 603 KB state, stderr the model never sees. Reset per task or remove.
  - (d) **Input guardrails and danger level**: 0 catches in 82 events; all 7 blocks were on `run-mode`, `reviewing-code` and `auditing-security` themselves. Default `enabled: false` downstream; keep the code behind the knob.
  - (e) **Team guards**: no-ops because `LOA_TEAM_MEMBER` is unset in the live team session. Export it from the lead's spawn path, or delete the five Teams rows from CLAUDE.loa.md.
  - (f) **Run-mode circuit breaker**: `cycle_count.current: 0`, `history: []` after five changes-required rounds (verified 2026-10-14). Move the counters into `run-checkpoint.sh` so the trip is computed by a script (Pocock review item L6, now with evidence).
- **Test**: one bats per item; the fence corpus unchanged; `implement-gate.bats` for (a).
- **Gate risk**: (a) is the only fence change and it tightens. (d) turns off a surface that never fired; its knob already exists.
- **Effort**: M.
- **Adversarial pass**: each of these was once a reaction to a real failure. Answer: the origin goes into A1's register; the retirement is reversible; and keeping controls that do not run teaches operators that Loa's documentation is not true (the implement gate was described as a fence for a year while inert).

### B3. Files as the authority for run position
- **His mechanism**: "State management is the files on disk"; "an agent with no memory must orient, act, and report status from the files alone" (`D:C7`).
- **Loa mapping**: `.run/sprint-plan-state.json` and `.run/circuit-breaker.json` become derived caches recomputed by `run-checkpoint.sh` from what exists: `a2a/sprint-N/COMPLETED`, the LOA-VERDICT trailers, `ledger.json` status, the latest implementation commit. `/loa`, `run-resume` and the implement gate read the derivation; the autonomy counters (cycles, breaker trips) stay first-class but are written by the script, not the model. This is the June OKF/ICM analysis item #8, still open, with the drift now observed (`S:inv` E3).
- **Test**: a drift reproduction (state says RUNNING, files say complete) that the derivation resolves; run-mode recovery bats.
- **Gate risk**: run-mode recovery semantics change; mitigated by keeping the JSON as a cache with the same shape.
- **Effort**: M.
- **Adversarial pass**: file presence can be forged too (a stale `a2a/sprint-1/COMPLETED` from cycle-122 would have satisfied the gates, `S:yield` §5). Answer: the derivation checks the trailer's sprint id and the ledger row together, not a bare marker; the forgery class is already in `verdict-derive.sh`'s cross-checks.

### B4. Fence false positives: interpreter-consumed heredocs
- **His mechanism**: none directly; "Code does what is mechanical" implies the mechanism must not punish the prose.
- **Loa mapping**: 96 of 105 real-session blocks in four weeks involved a heredoc body or a scratch path; five SP-1 blocks were all prose that named a spike merge inside a heredoc (`S:inv` E4; documented false positive at `hooks-reference.md:199`). Distinguish heredocs whose consumer is an interpreter (`bash`, `sh`, `python`, `eval`, a pipe into one) from heredocs redirected to a file or a tool that does not execute them; scan the first class as today, the second for the literal command tokens only at line start. Keep every corpus D-row; add B-rows for the prose cases from NOTES.md.
- **Test**: the fence corpus (`tests/fixtures/fence-corpus/corpus.jsonl`) with new B and D rows; `run-corpus.sh` green; latency under the 80 ms budget.
- **Gate risk**: medium. This loosens a fence; it is corpus-gated and never touches FR-1.2b, the SZ rules or the deny list.
- **Effort**: S to M.
- **Adversarial pass**: `cat <<EOF > script.sh` followed by `bash script.sh` executes the body later. Answer: the second command is itself fenced; the fence is per command, and the two-step form is already how the cycle-125 relaxation reasoned about cache deletes.

### B5. Advisory open-weight voice path
- **His mechanism**: "as long as the model can read files and navigate a folder structure you can use it" (`TR/06:294`); the memory paper's cross-vendor result (`W:§4`).
- **Loa mapping** (`S:ow` §7 slices, with the gate controls that make them safe):
  - **Recipe (S)**: fix the Azure example so it loads; document `openai_compat`, a literal `auth`, `secret_env_allowlist`, declared `context_window`, `streaming_recovery` deadlines, a `local` dispatch group; an explicit opt-in for `http` and loopback that the bash endpoint validator honours only for that provider.
  - **Schema on chat (S to M)**: send `response_format: {type: json_schema}` on the chat-completions body for entries declaring `structured_json`; set `schema_enforced` from the body sent; read `reasoning_content` deltas and strip `<think>` blocks before qualification.
  - **Family and lineage (M)**: operators declare `family` and `lineage` per model in `hounfour.providers`; `_adv_family_of` reads the merged config, not only the System catalog; `companion_chain` accepts keys beyond `anthropic` and `openai`; `unknown` stays never-independent.
  - **Advisory by default**: a new `counted_as: advisory_voice` keeps the findings, tags them, and contributes no verdict-quality envelope. Promotion to a counted voice requires a declared lineage distinct from the primary's and a recall result from A2 above a threshold the maintainer sets.
  - **Bridgebuilder and probe (S to M)**: derive the key map from the merged config with a keyless option; an OpenAI-compatible health probe against the configured endpoint.
  - **Pricing (S)**: catalog prices for hosted open-weight APIs; the dissent budget gate reads the catalog price instead of fixed 10 and 30 per Mtok.
- **Test**: pytest for the chat schema body, the family resolution and the advisory accounting; bats for `adversarial-review.sh` planning an advisory companion; a fixture local server (the test suite already has an injected fetch seam pattern elsewhere); the verdict-quality tests assert an advisory voice never changes APPROVED or DEGRADED.
- **Gate risk**: independence inflation (two fine-tunes of one base) answered by declared lineage with `unknown` default; weak-voice quorum dilution answered by advisory-by-default; the 128K context default answered by requiring `context_window`; unknown pricing answered by the catalog requirement.
- **Effort**: M; L if open-weight voices must count toward two-voice verdicts.
- **Adversarial pass**: an advisory voice costs tokens and operator attention for no quorum. Answer: its value is the availability hedge (KF-037 and KF-038 made the companion single-voice for hours) and the privacy posture (B6); its findings still reach the reviewer. Second: the record shows the second vendor's unique yield was small (`S:yield` §7), so why add a third? Answer: this is not a quality claim; it is cost and locality.

### B6. Local-only posture
- **His mechanism**: "Your conversation can stay on your hardware if you keep a local model" (`TR/17:103-105`, describing OpenClaw); his DeepSeek tracking remark shows he does not equate open weights with privacy (`TR/06:296-297`).
- **Loa mapping**: `hounfour.locality: local` pins the KF-004 repair chain to the answering voice, disables the `tiny` and `claude-headless` fallbacks, refuses hosted hops at plan time with a named reason, and records `locality: local` in MODELINV. The honest consequence is stated in the config: with one local family, every security audit is `DEGRADED_SECURITY_REVIEW` until a second local family (declared lineage) exists.
- **Test**: a planning test that no hosted hop is planned under the switch; a redaction test that the repair chain never leaves the declared providers.
- **Gate risk**: none to the floor; it reports degradation rather than hiding it.
- **Effort**: S (depends on B5's family work for the two-family case).
- **Adversarial pass**: the Claude Code session itself still talks to Anthropic, so "local-only" is a misnomer. Answer: name it `locality: local_voices` and say in the docs that the orchestrator is the platform.

### B7. One profile knob for the optional set
- **His mechanism**: "Configure the factory, not the product" (`D:C8`).
- **Loa mapping**: `.loa.config.yaml.example` has 55 top-level keys over 2,916 lines (`S:inv` totals). Add `loa.profile: lean | standard | full`, read once by the config loader, that sets the defaults of the optional surfaces as a set: KF and decisions surfacing, Flatline planning phases, companion voice, Karpathy diff warning, success-criteria gate, input guardrails and danger level, invisible retrospective, interview pacing. `standard` reproduces today's defaults. `lean` cannot reach the floor: the schema has no key for the floor surfaces under `profile`, and a test asserts that `lean` leaves review, audit, verdict-derive, the dissent artefact gate, the deny list, FR-1.2b, the SZ rules and FR-8 unchanged.
- **Test**: config-loader bats for each profile; the floor-unchanged test; the example documents which keys a profile sets.
- **Gate risk**: the knob could become the downstream way to turn gates off. The floor-unchanged test and the absence of a key are the control.
- **Effort**: S to M.
- **Adversarial pass**: profiles hide what is on. Answer: `/loa` prints the effective profile and the surfaces it enabled; a per-key override still wins.

---

## LEARN (fold into prose, docs or tests; no new surface)

- **L1. The 10/30/60 line.** "the actual AI calling is maybe 10% of the system volume" (`TR/19:115-121`). Report Loa's own ratio per cycle in the release notes (script lines changed, prose bytes changed, model calls per sprint from MODELINV); with A3's tags it can be computed per sprint. A number, not a gate.
- **L2. Validator rules age.** Each new `validate-artifact.sh` rule is a dated migration (`S:inv` §D). Adopt his "3-6 entries, expand on observed issues" as a per-cycle review: a rule with no recorded catch after two cycles is proposed for retirement in the A1 register.
- **L3. The run log as a test.** His `4-test.md` records "What it asked / What I changed" per run (`W:§4`). Use the shape for spike reports (`grimoires/loa/spikes/`) and for the rounds record of a discovery interview.
- **L4. Subscription versus list price.** The cost ledger reads $1,727 list for a period billed at $0 (`S:yield` §6). Cost reports should print both columns so operators can compare a subscription hop, a metered hop and a local hop honestly.
- **L5. "Reading it is the execution."** His memory taxonomy (`TR/15:132-138`) is a clean statement of why L5/L6/L7 bodies are untrusted; cite it in the agent-network reference.
- **L6. The two human gates.** "Most workflows do not belong to AI end to end" (`W:§5`) and his U-shape (`D:E4`) match Loa's placement of humans at plan and PR. Say so in the README and have `/loa` show the pending human work: today, 124 `proposed` decision rows with `decided_by: null` (verified) await `/decisions confirm`.
- **L7. The name.** ICM and Interpretable Context Methodology are claimed as trademarks on an unmerged branch (`W:§4`). Refer to the method descriptively; make no "ICM-compatible" claim.
- **L8. The walk test.** "a fresh agent can operate from the files alone" (`W:§4`) is a sharper acceptance test for compaction recovery than "read NOTES.md"; add it to the session-continuity protocol's checklist.

---

## REJECT (with reasons)

- **R1. Agent self-audit replacing the separate review and audit passes** (`D:C4`). The record shows the audit catching HIGHs the review approved (sprint 254) and both catching defects the implementer shipped in every cycle-128 sprint (`S:yield` §1, §2). Self-audit by the working agent is the spiral guard's named antipattern (`L:.claude/loa/CLAUDE.loa.md:78`).
- **R2. A human edit at every stage boundary on the build path** (`D:C5`). His own U-shape data puts the least editing in the middle (`D:E4`); Loa already has humans at the two ends; the unattended middle is Loa's purpose.
- **R3. Folder naming conventions in place of beads and the ledger** (`TR/20:180-191`). Dependency graphs, `br ready` and cross-session recovery need a queryable store; KF-022 (recurrence 4) is a cost to fix (B3 covers the run-position half), not a reason to drop the store.
- **R4. An open-weight model as the orchestrator now.** Loa is a Claude Code framework; the session runtime is the platform; KF-019 is the executor-weakness failure class; ADR-004 tunes gates to the current generation. Voices first, advisory, measured (B5).
- **R5. Removing the fence core** because of zero in-period catches. #555 was real and the class recurred in cycle-122; the deny list costs nothing at runtime. Earn it (A1), trim its false positives (B4), keep it.
- **R6. "Pick one and build the systems for that one"** (`TR/21:540-545`) as Loa policy. Cross-vendor availability failures are a recurring class in the KF ledger (KF-002, 017, 020, 037, 038, 040); the hedge stays. The record does say the second vendor's unique yield was small in two-voice runs, which is why B5 frames open weights as insurance and cost, not quality.
- **R7. Adopting the CONTEXT.md contract as Loa's artifact format.** Loa's typed, validated artifacts are a superset; the one import worth taking is the "What must never be read, shared or changed" section, which Loa already expresses as zones and FR-8.

---

## Adversarial pass: grilling Loa by his test, and the proposals by Loa's rules

**His test on Loa ("would the next release make it a toggle?")** The subsystems with no platform substitute are the decision ledger and attribution, the separate review and audit with a verdict contract, cross-vendor dissent, Bridgebuilder, run mode's unattended loop, and beads. The subsystems the platform or the model now covers in whole or part are per-user memory (auto-memory), injection and PII refusal (the model), over-building (the model), and increasingly the permission layer itself (KF-042: the platform's classifier blocked Loa's own operations). The proposals cut only in the second group.

**Loa's rules on the proposals.** None touches the floor. B2(a) tightens a fence; B4 loosens one under corpus control; B5 adds voices that cannot change a verdict; B7 has a floor-unchanged test. A1 and A2 add nothing but measurement and are the precondition for B1 and B2's deletions.

**The strongest objections that remain.**
1. *Deterrence is invisible.* The block log cannot see the destructive command an agent never typed because the rule said not to. A2's "without the rule files" arm on the frozen round-1 corpus is the only measurement available, and it is indirect.
2. *One host, four weeks.* The false-positive and block counts are local to this machine and this maintainer's style of work. The register (A1) must say so until fleet counts exist.
3. *The reviewer is the reviewed.* The yield record credits a Fable fresh context; this synthesis is Fable. The numbers are ledger counts, and the evidence files were written by Opus agents, but a maintainer should read `S:yield` §7 with that in mind.
4. *Advisory voices are dead weight.* If no operator needs locality, B5 and B6 add surface for nothing. Answer: build the recipe and the accounting (S slices) first; the M slice waits for a declared need.
5. *Profiles invite gate-off.* The floor-unchanged test is the control; without it B7 should not ship.

---

## Carry-overs surfaced during this review (not proposals; for the maintainer)

- **Bridgebuilder banner and exit code** (fleet mailbox from ridden, 2026-10-13): `resources/main.ts:674` passes `config.multiModel.models.length` to `reportComplete`, so the banner prints configured models, not completed ones, and the process exits 0 on a DEGRADED verdict (verified on main; KF-010 recorded the same class for the posted comment). The argv-size half of the same report is KF-039, fixed in rc.3; ridden's mount is pinned at rc.1.
- **124 `proposed` decision rows** with `decided_by: null` await `/decisions confirm` (verified).
- **Doc drift**: the prompt-budget workflow comment says protocols cap at 200,000 B while the script enforces 160,000 B; the hooks-reference registration table omits six registered hooks; `implementing-tasks/SKILL.md:28` says app `permission: read` while `:76` says Read/Write; `implement_gate.mode` exists but is absent from the example config (`S:inv`).
- **KF-041 (recurrence 3)**: Flatline cross-scoring degraded on every planning run since cycle 127; structural by the ledger's own rule, so route through an upstream issue rather than another retry.
- **Meta app** dashboard block plus expired token: operator action before any Instagram read; future reads run from sensenet.

## Recommended next step

One cycle, three sprints, as `prd-brief.md`: (1) A1, A2, A3 and B1's path-scoping; (2) B2, B3, B4, B7; (3) B5's S slices and B6, with the M slice (family and lineage) only if an operator need is declared during the cycle. Subagents Opus 5.5; review and audit on Fable 5.1; dissent capped at three runs per sprint. The brief goes into `grimoires/loa/context/` as the input to `/plan-and-analyze`, the same path the Pocock review took to cycle-128.
