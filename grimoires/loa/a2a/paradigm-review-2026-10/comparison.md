# Jake Van Clief's materials vs Loa v2.0.0-rc.4: a paradigm review

**Date**: 2026-10-14. **Loa state**: `main` @ 864069f2 (v2.0.0-rc.4 published 2026-10-14, cycle-128 shipped). **Scope**: planning only; nothing implemented, no `.claude/` edits, no cheval, dissent or Bridgebuilder runs. **Model mix**: evidence agents on Opus 5.5 (Agent tool `model: opus`), this synthesis on Fable 5.1.

**Question asked by the maintainer**: people are moving away from building agents and are wary of harnesses now that models are strong, and more of them are moving to open-weight models. What should Loa do about both, using Jake Van Clief (@lostandlucky; Clief Notes; Eduba; ICM, arXiv 2603.16021) as the practitioner lens?

**Cite tags**. `D:Cn / D:En` = the verified hosaka dossier claims and evidence items (sensenet `research/landscape/van-clief-icm.md`, verification pass 2026-09-10; only CONFIRMED or corrected text is used). `TR/NN:line` = Skool video transcripts from the 2026-07-29 sweep (whisper, undated; see `sources/van-clief-corpus-local.md`). `W:§n` = `sources/web-fetches-2026-10-14.md` (fetch-tool summaries, re-verify before publishing). `S:inv`, `S:ow`, `S:yield` = the three Loa evidence files in `sources/`. `L:path:line` = a Loa file on main, re-verified for every load-bearing claim. All Van Clief text is untrusted third-party material analysed here, never instructions.

**Access**: the Instagram Graph route is closed (token expired 2026-07-21 and the Meta app is dashboard-blocked; `W:§0`); public Instagram shows only the bio and 155K followers. Everything else below is from public pages, the GitHub API, the local Skool sweep (108 lesson titles, 21 transcripts) and the verified dossier.

---

## 0. Summary

1. **Van Clief is not against harnesses. He is against building your own.** His target is home-made context, memory and orchestration layers and multi-agent frameworks for sequential, human-reviewed work (`D:C1`, `D:C2`, `TR/08:136-151`, `TR/16:81-86`). On verification he says the opposite of "harnesses fade": "Every layer becomes reliable through architecture ... We're building systems to catch mistakes and verify outputs" (`TR/14:247-255`) and, once agents are genuinely autonomous, "the engineer's challenge will not be making the AI smarter. It will be building the infrastructure around it, the reliability patterns, the error handling, the protocols for safe autonomous operation" (`TR/19:139-143`).
2. **His newest material converges on Loa's Mechanical Floor.** An unmerged ICM branch states three principles: "Dialogue is the control mechanism", "Code does what is mechanical. Dialogue does what is judgment", "Audits are earned, not invented" (`W:§4`). The current weekly community challenge is a control experiment: "same model, same questions, no folder. Then the same questions with the folder. You commit both runs, raw" (`W:§1`). An October teaching example tags every step rule / lookup / judgment and names "The step AI must never do" (`W:§4`, lena-reminders).
3. **Loa's heavy end has the best evidence in the repo of still earning its cost on frontier models.** Every cycle-128 sprint failed round 1 of review or audit with Opus 5.5 implementers and a Fable 5.1 reviewer; the audit found HIGHs the review had approved; Bridgebuilder found HIGHs after both approved, at the lowest refuted share of any gate (10 to 19 percent) (`S:yield` §1, §2, §7). The measured effect is a fresh context of the same frontier model, not model diversity: 625 of the 629 companion-voice calls in the period were priced as Fable 5.1 (`S:yield` §0; verified against `.run/cost-ledger.jsonl`).
4. **Loa's light end is where his critique lands, and the inventory agrees with him.** About 20 KB of always-on prose per turn, of which 7.3 KB restates checks that already run mechanically; a fence with 105 real-session blocks in four weeks and no in-period catch; an implement gate that never blocks and was inert from cycle-050 to rc.3; a run-mode circuit breaker whose counters were never updated across five changes-required rounds; team guards that are no-ops without an env var the lead never set; input guardrails with zero catches in 82 events; six golden skills all within one percent of the 16 KiB cap (`S:inv` §A, §B, §G, cross-cutting E3, E4). These are "audits invented, not earned".
5. **File-as-state**: Loa agrees in its grimoires, ledgers, decisions ledger and KF ledger, and contradicts itself in `.run/*.json` (observed drift: `state: RUNNING` with all sprints completed, breaker `history: []`) and in beads (KF-022 split-brain, recurrence 4). The June 2026 OKF/ICM analysis already recommended "make file-presence authoritative for workflow position" (#8); it is still open. His filesystem-memory benchmark supports file memory on cost (97 percent fewer tokens), not on accuracy (29 of 39 correct versus 34 of 39 for long context; one significant comparison in the paper) (`W:§4`).
6. **Open weights**: he names local models as a hedge against usage limits and lock-in (`TR/06:291-298`), uses Claude Opus via a Max subscription in practice (`TR/06:16`, `TR/21:153`, `D:E4`), promised local-model videos that never appeared, and never tested portability. Loa's transport can reach a local OpenAI-compatible server today by config alone, but every mechanism that makes a voice count is Anthropic or OpenAI shaped: family independence, the companion chain, the Bridgebuilder key map, schema enforcement, the KF-004 repair chain, quorum arithmetic (`S:ow` §2, §4). The cycle-124 "model-generation floor" refuses nothing; it is pytest invariants over the Anthropic catalog (`S:ow` §3). Open weights can be advisory voices now; the orchestrator is Claude Code and stays Anthropic by construction.
7. **Recommendation**: one cycle that (a) makes every guard earn its place with provenance and a control arm, (b) thins the always-on prose and retires or repairs the inert controls, (c) opens an advisory open-weight voice path with a local-only posture, (d) adds one profile knob. The gate floor (separate review and audit, verdict trailer, dissent artefact gate, deny list, stash fence, System-Zone fence, operator-only commands) is not touched. See `proposals.md` and `prd-brief.md`.

---

## 1. Who he is in October 2026, and what changed since the September dossier

| Item | Sept dossier (2026-09-10) | Now (2026-10-14) | Register |
|---|---|---|---|
| Skool "Clief Notes" | 47.8k members, free, 40+ lessons (`D:E3`) | 52.1k members, 12 admins, 5.0 stars on 108 reviews; Premium and VIP tiers; a "Drawing Room" VIP roadmap opened about 2026-10-10 ("They're getting harder. That's intentional.") (`W:§1`) | platform, self-run |
| Weekly competitions | #12 "THE AUDITOR" (about 2026-09-03), a folder-based auditor (`D:E8`) | #14 "THE CONTROL" (about 2026-10-09, by moderator Matthew Creamer): "Build a folder. Then prove it earns its place ... run a control" for $1,000 in Eduba credits (`W:§1`) | post, not Van Clief |
| New Workflow Audit | about 2026-09-06, 127 likes (`D:E8`) | 151 likes, 64 comments; one-question-at-a-time interview about inputs, process, "where things get messy", outputs, decisions (`W:§1`) | post |
| Substack | last post 2026-08-28 | unchanged; archive confirms 12 posts, none after 2026-08-28 (`W:§2`) | blog |
| Preprint | v1 2026-03-17, v2 2026-03-18 (`D:C1`) | still v2, no v3 (`W:§3`) | preprint |
| ICM repo | 1.2k stars, 206 forks, last commit 2026-07-25 (`D:E1`) | 1,333 stars, 229 forks; main unchanged; two unmerged branches: `add-principles-and-builder-update` (2026-06-01, the three principles) and `add-trademark-notice` (2026-10-06: "Interpretable Context Methodology™ and ICM™ are trademarks of Jake Van Clief ... The MIT License ... grants no rights in the names") (`W:§4`) | repo |
| icm-architect | 1.5k stars (`D:E2`) | 1,891 stars, 262 forks; commits 2026-08-14 "Add System map form for auditing folders later agents will edit", 2026-08-25 "Take the field-tested restructure fixes; leave the invariants alone"; README adds a "walk test" and a Restructure mode that "audits an existing folder, classifies every file (catalog / contract / factory / product / dead)" (`W:§4`) | repo |
| New repos | not in dossier | `cost-of-remembering` (2026-08-03, 36 stars): filesystem memory vs long context on LongMemEval; `lecture-deck-skill` (2026-09-12); `lena-reminders` (2026-10-10): "Session 4 worked example", a six-file workspace from a live October cohort (`W:§4`) | repo / course |
| eduba.io | "We build multi-agent systems and production infrastructure" (`D:C11`) | unchanged, plus one line not in the dossier: "Most workflows do not belong to AI end to end" (`W:§5`) | marketing |
| Instagram | "IG ~130K" (July, reported) | 155K followers, verified; bio routes to Skool; clips dated Oct 2026, no captions readable (`W:§0`) | platform |

Audience: mostly non-developers and business operators (he explains VS Code, markdown and tokens from scratch, `TR/20:12-38`; "Three community members with no prior coding experience" built video workspaces, `D:E4`), with an enterprise consulting arm (KPMG UK, IAG, University of Edinburgh listed; no agent deployment described, `D:E7`). The lena example is an office manager's Monday reminder chase (`W:§4`). This is not Loa's audience; the overlap is the method layer, not the market.

---

## 2. His position in his own words, mapped to the two lenses

### 2.1 Lens 1: agents, frameworks, harnesses, and stronger models

| # | What he says | Where | What it means for Loa |
|---|---|---|---|
| 1 | "for sequential workflows where a human reviews output at each step, they introduce engineering overhead that the problem does not require" | `D:C1` (preprint) | Scoped to human-reviewed sequential work. Loa's unattended run mode is outside his scope by his own section 5.2 (`D:C6`: concurrency, tight loops and mid-pipeline branching "require ... AutoGen and similar frameworks"). |
| 2 | "one agent, reading the right files at the right moment, does the work that would otherwise require a multi-agent framework" | `D:C2` | Loa's single Claude Code session plus skills already is this. The question is what Loa's teammate topology and hook layer add on top. |
| 3 | "Rather than using really complicated workflows or infrastructures and harnesses, you can create one really good harness for a single type of model" and "the Cloud Code agent has harnesses in its own right, but that's the point, I don't need to reinvent the wheel" | `TR/12:14-17`, `TR/12:171-172` (lesson 0.1) | "One harness, bought not built." Loa is content on Claude Code's harness (hooks, permissions, skills), not a competing runtime. His critique hits Loa where Loa duplicates the platform. |
| 4 | "Anthropic and these other companies are going to build harnesses way better than anyone here will" and "the whole idea of having to build insane project memory systems and harnesses for it, I don't think you really need to" | `TR/08:136-151` (lesson Impl 3.1) | The strongest anti-harness line. Its object is memory systems and context injection, not gates or verification. |
| 5 | "Don't automate what the next model will give you for free"; invest in "the stuff that's specific to your context your domain knowledge your client relationships your data" | `TR/16:81-86` (lesson 2.4) | The cleanest test for lens 1, applied in §3.3 below: would a model or Claude Code release make a given Loa subsystem "a toggle in someone else's settings menu" (`TR/16:6-10`)? |
| 6 | "The LLMs are already smart. Or at least smart enough ... the hard part has to live somewhere else"; "You need to productionize your opinion not just your process"; "A little human judgment at the two ends saves an enormous amount of machine work in between" | `W:§2` (Substack 2026-06-14) | Capability is not the bottleneck; judgment and its placement are. The "two ends" is the U-shape (`D:E4`), which is where Loa already puts its humans (§3.4). |
| 7 | "Every layer started with unreliability. Every layer becomes reliable through architecture. AI is no different ... We're building systems to catch mistakes and verify outputs or just create redundancy" | `TR/14:247-255` (lesson 2.2) | Verification infrastructure is the durable part in his own framing. This is an argument for Loa's gates under the stronger-models lens, not against them. |
| 8 | "the actual AI calling is maybe 10% of the system volume. The orchestration ... maybe 30%. The actual data processing ... 60% ... All the bad ones seem to ignore this ratio" | `TR/19:115-121` (lesson 2.7) | Most of a working system is deterministic code. Loa's 380 shell and 104 Python scripts against 96 KB of model-executed skill prose is consistent with this; the inventory shows where prose still does a script's job (§3.2). |
| 9 | "Dialogue is the control mechanism. A person talking to one agent and editing files in output/ folders. Not orchestration code, not agent-to-agent negotiation"; "Code does what is mechanical. Dialogue does what is judgment"; "Audits are earned, not invented. A stage's Audit table contains checks from real failures in real runs, not imagination"; audit tables of "3-6 entries"; "New workspaces start minimal and expand based on observed issues" | `W:§4` (unmerged branch, 2026-06-01) | Principle 2 is Karpathy principle 2 and the Mechanical Floor in his words. Principle 3 is the test Loa's guard inventory fails in several rows (§3.2). Principle 1 is where he and Loa part: Loa's control mechanism on the build path is a gate, not a conversation. Cite as a draft; the branch is unmerged. |
| 10 | "The next model ... arrives and makes every package in the library run better. Faster reasoning under the same judgment" | `W:§2` (Substack 2026-08-28) | Structure persists across model generations; the model is swappable. Loa's ADR-004 makes the opposite bet in one place: it sizes prompts, budgets and gates for "the current Claude generation" (`L:docs/architecture/ADR-004-model-generation-floor.md:15`). |
| 11 | "over the next five years ... less and less are you going to need to build agents that navigate folders ... more and more you're going to condense your structures and processes into something that one or two agents or one really good coding agent can read" | `TR/06:314-317` | Direction of travel: fewer agents, more packaged structure. Loa's five-teammate sprint topology runs against this; its single-session golden path runs with it. |
| 12 | He warns that a popular orchestration layer is "one of anthropic announcements away from becoming a niche tool" | `TR/17:110` (lesson 2.5) | Platform absorption is his named risk for orchestration layers, including Loa. |
| 13 | "Most workflows do not belong to AI end to end" | `W:§5` (eduba.io) | Also Loa's position: the golden path has a human at plan and at PR. |

Not his words (do not cite): "the thinking that survives every update" is unverified About-page wording; "never write code for your agents" has no source; the hosaka wedge essays' "explicitly anti-swarm" overstates his section 5.2 (`sources/van-clief-corpus-local.md`, verification status).

### 2.2 Lens 2: model choice, open weights, local models

| # | What he says | Where | What it means for Loa |
|---|---|---|---|
| 1 | "you could use local coding models as long as the model can read files and navigate a folder structure ... it might not do it to the level that some models will" | `TR/06:294` (Claude Design lesson, undated) | Portability rests on "can read files and navigate a folder". Loa's floor is higher: structured dissent output, a verdict trailer, fences, two-voice quorum. |
| 2 | Named models (as transcribed): Qwen3-Coder-Next ("80 billion parameter model but it only loads certain parameters at a time"), CodeGemma, Devstral, DeepSeek ("some people argue that deep seek has some tracking that's being sent back even in their open source models") | `TR/06:295-297` | A mention list, not a benchmark. The DeepSeek remark is a trust concern about open weights, which cuts the other way from "local means private". |
| 3 | "I hit my limits I could just swap over to another model I can swap over to a local one ... I can't worry about being locked into a model"; "this can cut costs" | `TR/06:291-298`, `TR/06:317-318` | Motivated by usage limits and lock-in. This is Loa's own KF-002 / KF-017 / KF-020 / KF-037 / KF-038 pressure, and the reason cheval has within-company chains and headless hops. |
| 4 | In practice: "a single model family (Claude Opus 4.6 and Sonnet 4.6)"; "I'm on the top max plan"; "pick one and build the systems and the knowledge of how to use that one well, it will easily transfer" | `D:E4`, `TR/06:16`, `TR/21:540-545` | Single-vendor on a flat-rate subscription. The portability claim is untested in his material; the promised local-model videos are absent from the July curriculum. |
| 5 | On OpenClaw: "You can swap Claude or GPT or Lama or even run your own local model ... Your conversation can stay on your hardware"; "most people ... will always choose convenience. But developers and privacy conscious users ... are going to choose flexibility" | `TR/17:103-105, 120-122` | Privacy is a market segment in his framing, not his requirement. |
| 6 | "If you did API calls for all of this, it'd be really expensive, but with a subscription, it's not as expensive" | `TR/00:9`, `TR/06:291` | His economics assume flat-rate inference. That is what local inference competes with, and it is why Loa's cost ledger reads list-price $1,727 for a period that was billed at $0 (`S:yield` §6). |
| 7 | Filesystem memory "filed by Claude Sonnet 5 and queried by GPT-5.5" "scored identically to that model reading the full history, at 96% lower cost per query" | `W:§4` (cost-of-remembering, n=39) | The one cross-vendor portability result in his corpus is about memory files, not about a weaker model doing the work. It supports Loa's file-based state, not open-weight executors. |

### 2.3 His control and quality mechanisms, against Loa's

| Mechanism (his) | Loa's counterpart | Agree / contradict / extend |
|---|---|---|
| CONTEXT.md contract: reads / does / writes (`D:C3`) | Sprint tasks, SKILL.md frontmatter, handoffs; `validate-artifact.sh` schemas | Loa extends: typed and validated. His has no schema and no validator. |
| Stage audits the agent runs itself, "an unambiguous pass condition" (`D:C4`) | `/review-sprint` and `/audit-sprint` by a separate role, two-voice dissent, LOA-VERDICT trailer | Contradicts. Self-audit by the working agent is the class Loa's spiral guard calls "fox guarding the henhouse" (`L:.claude/loa/CLAUDE.loa.md:78`). The record favours Loa: the separate audit caught HIGHs the review approved twice in cycle-128 (`S:yield` §2). |
| "Every output is an edit surface"; human inspects and optionally edits at each boundary (`D:C5`) | Human at plan (`/decisions`, rounds) and at PR; unattended in between | Contradicts on the build path, by design. His own U-shape data says the middle needs the least editing (`D:E4`), which is where Loa removed the human. |
| "Configure the factory, not the product" (`D:C8`) | `.loa.config.yaml`: 55 top-level keys, 2,916 example lines (`S:inv` totals) | Agrees in intent; Loa's factory has too many dials. |
| "Local scripts handle the mechanical work" (`D:C1` abstract); Python added "because they needed more determinism" (`TR/12:55-57`) | Mechanical Floor (ADR-003), validators, fences, 484 scripts | Agrees. The inventory lists where Loa still asks the model to do a script's job: breaker arithmetic, ICE "MUST go through", beads creation, `/bug` eligibility (`S:inv` §F table at the end). |
| "Audits are earned, not invented" (`W:§4`) | KF ledger with recurrence counts; fence corpus `why` fields; stash-safety rule citing #555 | Partial. 16 of 72 fence pattern lines carry an incident reference; many guards show "no recent evidence found" (`S:inv`). |
| Control run: folder vs no folder, both committed raw (`W:§1`) | `evals/` with `ab:` blocks and frozen PR corpus (`L:evals/suites/review-recall.yaml:3,23-26`); the cycle-124 pre-registered A/B (ADR-004 §5) | Loa has the harness; it has not been pointed at its own guards. |
| Step tags rule / lookup / judgment and "The step AI must never do" (`W:§4`) | Fact/decision split in the interview (cycle-128); FR-8 operator-only commands | Agrees; Loa lacks the per-task tag on the build path. |
| Run log as test: "What it asked / What I changed" over three runs (`W:§4`) | KF attempts table; eval ledger | Agrees in shape. |
| "Two gates" client system (`D:C9`, second-hand) | Plan gate and PR gate | Agrees; unverifiable anecdote. |

### 2.4 What the sources cannot tell us

No Instagram captions (Graph blocked; public page captionless). No Skool text lessons (86 of 108 are titles only; "Tokens, Deepseek, & Managing Context" and "GPT 5.5 - What Actually Changed" look relevant and were never captured). Transcripts are undated whisper output; model names are mis-heard ("Lama", "B2", "VoxTroll") and must be checked against the video before publication. No controlled comparison exists in his material except the n=39 memory paper, which is underpowered on accuracy by its own account. The three principles are on an unmerged branch for four months. No open-weight model has run ICM in any source we hold, and none has run inside Loa either (`S:yield` §7).

---

## 3. Lens 1: scaffolding versus guardrails in Loa

### 3.1 What the gates caught on frontier models (the yield record)

The period 2026-09-17 to 2026-10-14 (cycles 124 to 128) is the first in which Opus 5.5 implemented and Fable 5.1 reviewed and audited for whole cycles. `S:yield` §1 and §2 give the per-sprint table and every HIGH; the shape is:

- **Every sprint from 247 to 254 except 249 needed at least one changes-required round.** Cycle-128: 252 review r1 0/0/4/1; 253 review r1 0/1/1/8 and audit r1 0/1/6/8; 254 review r1 0/0/1/7 then audit r1 0/1/3/3 after the review had approved (`S:yield` §1).
- **The audit catches what the review approves.** The sprint-254 HIGH ("`red-test-check.sh` is an unbounded, credentialed execution path granted to the review role") came from the audit, which is told to "look for what the review did not"; the review missed it and the dissent filed it as MEDIUM (`S:yield` §2, §7).
- **Bridgebuilder, after both approvals, still found real HIGHs** on #1266, #1274 and #1279 (the bash-3.2 fail-open in the implement gate; configured red-test commands bypassing the runner checks), with the lowest refuted share of any gate, 10 to 19 percent (`S:yield` §3).
- **The fresh context is the effect, not the second vendor.** In two-voice runs the companion voice raised most accepted findings (19 of 24 review HIGHs in sprint 248; every review-round finding in 254) and the OpenAI primary's BLOCKINGs were refuted in 249, 251 and 252. The companion was Fable 5.1 in 625 of 629 priced calls (`S:yield` §0, §3; verified: `.run/cost-ledger.jsonl` 519 `global.anthropic.claude-fable-5-1` + 106 `claude-fable-5-1`, all `cli_reported`).
- **Defects in Loa's own mechanical controls were found only by adversarial review, never by the implementer**: the dead `{"decision":"ask"}` (inert since cycle-050), the non-canonical path bypass, the `${rel,,}` fail-open, six fence predicate holes in sprint 241 (`S:yield` §5). A fence is only as good as the review of the fence.
- **Costs.** Sprint 248's 39-run dissent loop was 84 percent of metered spend (about $1,448 list) and ten days of wall clock; the 3-run cap followed. CLI contention (KF-037, recurrence 9) costs about an hour per run under load; the Flatline scoring stage degraded on every planning run from cycle 127 on (KF-041, recurrence 3), so its yield is unmeasured (`S:yield` §4, §6, §7).
- **What the record cannot show**: the counterfactual (no sprint shipped ungated), production severity (no finding tied to a user-facing incident), false positives of the Fable gates themselves (never independently checked), and anything about open-weight models (none ran).

### 3.2 The inventory: what earns, what is scaffold

`S:inv` classifies every control surface on the sanctioned path. Condensed:

| Verdict | Surfaces | Why |
|---|---|---|
| **EARNS** | separate review and audit passes; LOA-VERDICT trailer + `verdict-derive.sh`; two-voice dissent (on findings; costly to operate); Bridgebuilder; adversarial-review gate (here; off by default downstream); Flatline on planning (blockers became shipped decisions); `run-preflight.sh`; NOTES size guard; FR-8 `disable-model-invocation`; `hook-guard.sh`; post-compact and session-limit reminders; CI prompt budgets and skill-capabilities lint; deny list (cheap insurance, not on evidence) | Recent catches, or a recorded incident, or zero cost |
| **SCAFFOLD** | always-loaded `stash-safety.md` and `skill-invariants.md` (7,301 B per turn restating mechanized checks); implement gate (ask only, inert cycle-050 to rc.3, trusts `.run` JSON the model writes, Bash writes unseen); `disallowed-tools` on review skills (strips NotebookEdit only, Write and Edit remain); team guards (no-ops without `LOA_TEAM_MEMBER`, unset in the live team session); Karpathy surgical-diff hook (warn-only, saturated at a 143,324-line running total, 603 KB state, the model never sees stderr); input guardrails and danger level (0 catches in 82 events; all 7 blocks on the sanctioned skills themselves); invisible retrospective; goal-driven gate; SP-1 spike fence (5 real blocks, all heredoc prose); glossary CI; run-mode circuit breaker as prose (never counted a cycle); danger-level enforcer | No observed failure, or does not function as described |
| **AMBIGUOUS** | the fence core (zero in-period catches, 96 of 105 real blocks likely false positives, but #555 was real and recurred in cycle-122); zone guard (friction in self-development, protects downstream copies); KF SessionStart table (5,168 B; entries are plumbing); decision ledger (124 rows, none operator-confirmed); `/chart` (two of three cycle-128 HIGHs were in it); AC-verification script (duplicates reviewer reading); `red-test-check.sh` (new; its first review produced a HIGH against itself); ICE wrapper (mechanical, its use is prose); mutation loggers (polluted by bats replays, KF-033) | Real need, unproven or costly form |

Totals (`S:inv`): 30 registered hooks (6 PreToolUse plus 2 PostToolUse on every Write/Edit); 381 allow and 62 deny permission rules; 32 fence pattern ids over 41 block sites with a 183-row corpus; CLAUDE.loa.md 138 lines / 10,225 B against a 10,240 B cap; always-on prose about 20 KB per turn plus 5.2 KB at session start; 27 protocols at 131 KB; 380 `.sh` and 104 `.py` scripts; 9,032 bats tests; six golden skills at 96,427 B total, 20 percent of it shared include blocks, every one within one percent of its cap.

Two readings of "all six skills sit at the cap": the cap is working (it holds size down, ADR-004 §5) and the cap is the only thing deciding size (need would put them lower). Both are true; the diet proposal in `proposals.md` B1 uses the control arm (A2) to find out which text is load-bearing.

### 3.3 His test applied to Loa: what would the next release make a toggle?

"Don't automate what the next model will give you for free" (`TR/16:81-86`), subsystem by subsystem:

| Loa subsystem | Platform or model already supplies it? | Verdict |
|---|---|---|
| NOTES.md session memory, compaction markers | Claude Code auto-memory covers per-user recall; the cycle-124 memo kept NOTES for the team record and bounded it (`L:.claude/loa/reference/context-engineering.md`, "Memory size gate") | Keep the bounded team record; stop growing operator-private prose there (170 KB today against a 200 KB block) |
| Hooks and fences | Claude Code supplies the hook mechanism and now its own permission classifier, which denied four Loa operations as Self-Modification (KF-042) | Loa's content on the platform's mechanism; the collision is new and will grow |
| Karpathy prose, simplicity ladder, surgical diff | Frontier models over-build less; no cycle-128 finding is tagged SIMPLICITY or SURGICAL (`S:inv` §A) | Candidate toggle; measure with A2 before removing |
| Interview rounds, fact/decision split, decision ledger | No platform equivalent; the attribution problem (who decided) is organisational, not model capability | Keep |
| Separate review and audit, dissent, Bridgebuilder | No platform runs a second role in a fresh context with a verdict contract and a one-way rule; GitHub review bots are single-voice | Keep; the record supports it |
| Run mode, ICE, circuit breaker | The platform has no unattended sprint loop; but Loa's breaker is prose arithmetic the model did not execute | Keep the loop; move the arithmetic into a script |
| Beads | No platform equivalent for cross-session dependency graphs; KF-022 (recurrence 4) is the cost | Keep, with the file-authority fix for run position |
| Guardrails (PII, injection, relevance) | The platform and the model refuse injection better than a regex scorer; 0 catches in 82 events | Toggle off by default |
| Glossary, AGENTS.md generation, BUTTERFREEZONE | Hygiene; model-independent | Keep as CI, not as prompt |

### 3.4 File-as-state: where he and Loa agree, contradict, extend

- **Agree.** "State management is the files on disk" and "an agent with no memory must orient, act, and report status from the files alone" (`D:C7`) describe Loa's grimoires, a2a envelopes, `ledger.json`, `decisions.yaml`, the KF ledger and the generated INDEX; Loa's session recovery is file-first (`L:.claude/loa/reference/context-engineering.md`). His memory paper's cost result (5,314 tokens read per question against 184,186; build cost amortised in about seven questions) is the economics behind Loa's INDEX-first intake (`W:§4`).
- **Contradict, Loa side.** `.run/sprint-plan-state.json` reads `state: RUNNING` with all three sprints `completed` and sprint-2 `cycles: 0`; `.run/circuit-breaker.json` has `cycle_count.current: 0` and `history: []` after five changes-required rounds (`S:inv` E3; verified 2026-10-14). The position of a run lives in JSON the model is supposed to maintain, not in the files that exist. The June OKF/ICM analysis #8 named this ("make file-presence authoritative for workflow position"); it is still open. Beads is a SQLite database with a JSONL export, and its split-brain is a recurrence-4 known failure (KF-022).
- **Contradict, his side.** His stance has no validator, no schema and no verdict contract; "the human edits the file" is the integrity mechanism (`D:C5`). Loa's zone-state rule that OKF-style fail-soft consumption "MUST NOT be imported into any loa validator or decision gate" (`L:.claude/rules/zone-state.md`) is the correct boundary and should hold against ICM too.
- **Extend.** His "walk test" (a fresh agent can operate from the files alone, `W:§4`) is a sharper acceptance criterion for Loa's recovery than "read NOTES.md after compaction". His Restructure mode's file classes (catalog / contract / factory / product / dead) are a useful audit frame for grimoires: Loa's `dead` class would include the 325 un-indexed a2a directories the June analysis counted.

### 3.5 What should become optional, thinner or removable

Preview of `proposals.md`: thin the always-on prose to the rows that point at a mechanism (B1); retire or repair the inert controls listed as SCAFFOLD (B2); make files authoritative for run position (B3); trim fence false positives by distinguishing interpreter-consumed heredocs from file-consumed ones (B4); one profile knob that flips the optional set together and cannot reach the floor (B7); and, before any of that, give every guard an origin and a yield number (A1) and a control arm (A2). Nothing in the EARNS column is proposed for removal.

---

## 4. Lens 2: open-weight models

### 4.1 Where Loa stands: transport works, gates do not

`S:ow` traces a local OpenAI-compatible server through cheval on main:

- **Reachable by config alone.** `type: openai_compat` with a custom `endpoint`, a literal non-empty `auth` string, and per-model `endpoint_family: chat`, `auth_type`, `dispatch_group`, `capabilities`, `context_window`. Plain `http://127.0.0.1` is not refused on the Python path; the bash endpoint validator (no http, no loopback, no RFC1918) guards only shell callers such as the health probe (`S:ow` §2; registry verified at `L:.claude/adapters/loa_cheval/providers/__init__.py:48-59`).
- **The documented Azure example fails at load** (missing `auth_type`, `dispatch_group`, `endpoint_family`); the credential allowlist admits only `LOA_*`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `MOONSHOT_API_KEY`, `GOOGLE_API_KEY`, `GEMINI_API_KEY` unless extended (verified `L:.claude/adapters/loa_cheval/config/interpolation.py:24-31`); the health probe enum admits four providers; `model_aliases_extra` is locked to four providers and `https` (`S:ow` §2).
- **Defaults assume hosted frontier models**: context window 128,000 when undeclared (overfills an 8K or 32K model), a 30 s first-token deadline that a CPU prefill will trip, no handling of `<think>` blocks or `reasoning_content`, no pricing (ledger reads `unknown`), the dissent budget gate at fixed 10 and 30 per Mtok regardless of a zero price (`S:ow` §2, §5).
- **The chat-completions body never carries a schema** (verified `L:.claude/adapters/loa_cheval/providers/openai_adapter.py:323-341`); only the `responses` family does. A local voice always runs on the tolerant parser and the KF-004 repair loop, whose default chain is `tiny` (Anthropic Haiku) then `claude-headless` then the voice itself: a local-only posture is impossible without pinning it, and findings would otherwise leave the machine for repair (`S:ow` §4, §5).

### 4.2 The model-generation floor refuses nothing

ADR-004 moved Loa's own Claude use to Opus 5 / Sonnet 5 / Fable 5.1, sized budgets to those models, and enforced structured outputs on Anthropic hops. Enforcement is `test_anthropic_catalog_floor.py`: invariants over the live Anthropic catalog (verified `L:.claude/adapters/tests/test_anthropic_catalog_floor.py:1-8`). No loader, resolver or adapter checks a model's generation or vendor; old ids resolve by explicit pin; the Bedrock adapter builds a generic Converse URL from any id and parses `reasoningContent` generically, so `us.meta.*`, `us.deepseek.*` or `mistral.*` are not refused (Anthropic coupling remains in the thinking shapes, the remediation text, the absence of streaming and schema) (`S:ow` §3). The floor is a statement about what Loa's prompts and gates are tuned for ("Gates are only as strong as their weakest executor", `L:docs/architecture/ADR-004-model-generation-floor.md:15`), not a refusal.

### 4.3 Could an open-weight model be a voice, judge, companion or Bridgebuilder voice today?

| Role | Today | Blocker (verified) |
|---|---|---|
| Dissent primary | Yes, with caveats | Family resolves to `unknown` (`_adv_family_of` reads the System catalog and name rules only) |
| Dissent companion, counted | No | Companion families are hard-coded `anthropic` and `openai` (`L:.claude/scripts/adversarial-review.sh:2398-2410`); an `unknown` family is never independent, so the voice is `duplicate_voice` and contributes no envelope (`:3428-3445`) |
| Flatline voice and scorer | Yes | No family check; must pass content qualification; KF-041 shows a scorer can null every score silently |
| Bridgebuilder voice | No | `validateApiKeys` rejects any provider outside its key map with `Unknown provider` (`L:.claude/skills/bridgebuilder-review/resources/config.ts:384-388`) |
| Orchestrator (the Claude Code session) | No | Loa is a Claude Code framework; KF-019 (an agent confabulating that a governed path does not exist) is the failure class of a weaker or misinformed executor |

Verdict quality counts voices, not voice strength: a local voice returning schema-valid empty findings would satisfy quorum (`S:ow` §7). Two open-weight models fine-tuned from one base would count as two families unless lineage is declared. These two facts decide the proposal shape: open-weight voices enter as **advisory** (findings kept and tagged, no envelope) until an eval shows recall.

### 4.4 Cost and privacy

- Each dissent sends the secret-scanned diff to the primary and the companion provider; redaction removes secrets, not code or paths; repairs send finding JSON to the repair chain; MODELINV records ids and token counts, not prompts; no third-party telemetry exists (`S:ow` §5).
- No local-only mode exists. The "Conservative (all native, no remote calls)" config example still runs the session against Anthropic. A fully local dissent needs `companion_voice: false` (every security audit then DEGRADED), a pinned repair chain, and a local health probe (`S:ow` §5).
- Hosted open-weight APIs (OpenRouter, Together, Groq) were proposed in June as `kind: http` providers "with no local infra" (`L:grimoires/loa/proposals/headless-adapters/headless-adapter-expansion.md:29`); no runbook or proposal mentions Ollama, vLLM, llama.cpp or LM Studio (`S:ow` §7).
- The economics he assumes (flat-rate subscription) are the ones Loa's CLI hops already exploit; local inference competes with that, not with API list price. The cost ledger's $1,727 list total for a $0-billed period (`S:yield` §6) means Loa cannot yet say what an open-weight voice would save.

### 4.5 What breaks when the model is weaker than the harness assumes

The KF ledger already holds the class (`S:ow` §6): KF-004 (findings missing `id` or `failure_mode`; recurrence at least 31; the one structural entry bearing on weaker voices; its fix is wire-level schema enforcement, which cheval does not ask a chat-completions server for), KF-011 (prose-wrapped JSON), KF-023 (prose counted as a voice; the reproduction was a non-frontier secondary), KF-041 (scorer nulls every score, open), KF-002 and KF-003 (empty content; typed aborts tuned to hosted latency), KF-015 (gate passing degraded runs; fail-closed validation stays load-bearing), KF-019 (confabulated absence; argues against a weaker orchestrator). Also the 16 KiB skill prompts and the "look for what the review did not" audit instruction are tuned for Fable-class readers (ADR-004).

### 4.6 His stance against Loa's, on this lens

He treats model choice as a hedge the folder structure makes cheap, has not exercised it, and keeps a single vendor on a subscription. Loa has exercised cross-vendor dissent for a year and the record says the second vendor's unique yield in two-voice runs was small while the availability hedge was real (KF-002, 017, 020, 037, 038, 040). The honest synthesis: open weights matter to Loa first as **availability and cost insurance for voices** and as a **privacy posture some operators need**, not as a quality source. That is a config-and-accounting problem (families, lineage, schema on chat, pricing, a local posture), sized M, not an architecture change.

---

## 5. Where this review is thin, and one conflict of interest

- The fence false-positive figures are one host's `.run/audit.jsonl` over four weeks, and "no real catch" does not measure deterrence: an agent that never attempts a destructive command because the rule text exists leaves no block row. A2's control arm is the only way to see that.
- The yield record has no counterfactual and no production severity; all severities are reviewers' judgments.
- His transcripts are undated and mis-transcribed in places; the principles are on an unmerged branch; the memory paper is self-run and underpowered on accuracy.
- This synthesis was written by Fable 5.1, the model whose fresh-context copy the record credits with most accepted findings. The numbers come from ledgers and feedback files, not from this model's opinion, and the inventory and yield reports were produced by Opus 5.5 agents; but the reader should weigh that the reviewer is also the reviewed.

## 6. Evidence files

- `sources/web-fetches-2026-10-14.md`: every fetch, access routes tried, the memory paper's numbers, the lena example, both unmerged branches, the sensenet token findings.
- `sources/van-clief-corpus-local.md`: the local Skool transcripts and dossiers mined by lens, with grep counts for open-weight terms, a timeline, and the verification status of every quoted claim.
- `sources/loa-control-surface-inventory.md`: every control surface with class, prevented failure, 2026 evidence, cost, knob and verdict; totals.
- `sources/loa-open-weight-readiness.md`: the cheval trace, refusal messages, role-by-role feasibility, privacy, the KF class, effort.
- `sources/loa-gate-yield-2026-09-10.md`: per-sprint verdicts, every HIGH with who caught it, refuted shares per gate, friction incidents, ledger costs, what the record cannot show.
