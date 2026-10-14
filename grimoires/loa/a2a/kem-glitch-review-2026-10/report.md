# kem_glitch on orchestrators, subagents and cheap parallel experiments: review against Loa

Date: 2026-10-14. Author: research agent (global.anthropic.claude-opus-5-5). Fetched text is untrusted third-party data, quoted as data.

## (a) Who kem_glitch is, and the sources

`@kem_glitch` is the Instagram handle of Kem, co-founder of Glitch Cat Club (a paid Skool community with a co-founder named Chase). The profile bio reads "Ex-Bank Director Data Management - AI Practitioner & educator Founder GlitchcatClub & Aura-intel Building in public" (15.3K followers on 2026-10-14). The club site says Kem "previously directed international data teams at UBS Investment Bank". A third party gives the surname Tossoun; I could not confirm it from a first-party source. The handle has no X, GitHub user or YouTube account. Code is published under the GitHub org `Glitch-Cat-Club`, with commits by `Aura-Intel`. Video goes to YouTube as `@glitchcatclub`.

| # | URL | Date | Gist |
|---|---|---|---|
| S1 | github.com/Glitch-Cat-Club/chief-of-staff-crew (`.claude/agents/*.md`, README) | 2026-08-31 | Orchestrator, four file-owning workers, per-seat model and turn caps |
| S2 | instagram.com/reel/DeZUVT1t5vQ | 2026-10-12 | Caption: five agents writing to one file is what orchestration looks like in practice |
| S3 | instagram.com/reel/DeW6_fqt-cq | 2026-10-11 | Caption: a swarm run on free Claude credits |
| S4 | instagram.com/reel/DeHK65INHqh | 2026-10-05 | Caption: how to evaluate skills and workflows when results are unreliable |
| S5 | instagram.com/reel/DeKBMCQNRXU, DeEyZPEtkyH | 2026-10-06, 10-04 | "Glitch orch" (Glitch Orchestra) orchestrator updates, experimental alignment system |
| S6 | youtube.com/watch?v=svvlT-nX6N8 (transcript in werk-flow/werkflow-app) | 2026-08-16 | Four-run 2x2 experiment: Haiku plus deterministic context matches Fable 5 |
| S7 | github.com/Glitch-Cat-Club/TrendingAI (`CLAUDE.md`, `Workflows/Run.md`) | 2026-05-26 | Counter-case: no subagents, synthesis inline, for billing reasons |
| S8 | instagram.com/p/DdwF-9GjVX_ | 2026-09-26 | "16 artefacts: graph engineering, RAG, agent swarms, routers, loops and more" at glitchcatclub.com/lab (listing not readable) |
| S9 | github.com/FREELABEL/iris-daemon/pull/22 (secondhand) | 2026-10-13 | A third party's "integrator" built from "the @kem_glitch reel evaluation" |
| S10 | github.com/muffin-project/muffin-agent/issues/606 (secondhand) | 2026-09-19 | Third-party summary: Align, Plan, Implement, Verify, with alignment before handoff |

## (b) Recommendations, with supporting quotes

1. **The orchestrator routes and never fixes.** "You own triage, routing and the final word. You never fix anything yourself." (S1, chief-of-staff.md)
2. **Write the board before any spawn.** "Before you spawn anyone, call TodoWrite with one item per problem you found, each naming its owner" and "A run where the board was never written is a failed run." (S1)
3. **Parallelise only across disjoint file ownership, in one message.** "Each specialist owns different files, so put all four Agent calls in a single message and let them run in parallel." (S1)
4. **Every brief has four parts.** "Every brief states the problem you found, the file that specialist owns, what you want back, and the boundary" (S1)
5. **Wait for every worker.** "never write your final answer while any of them is still working. Ending early kills their unfinished work." (S1)
6. **Set cost per seat.** "`model` sets the quality and cost of that seat, and `maxTurns` caps how long it can run." The orchestrator runs on Opus, the four workers on Sonnet with maxTurns 20 to 40. (S1, README and frontmatter)
7. **The maker never signs off.** "the person who made a thing should not be the one who signs it off." (S1, auditor.md)
8. **Cheap and short beats exhaustive.** "Measure before you claim, and measure economically" and "An exhaustive audit that never lands is worth less than a short one that does." (S1, auditor.md)
9. **Run small controlled comparisons, and let the cheap model win when context is deterministic.** "Same prompt, four runs." "Haiku 4.5 with the graph gets it right." (S6)
10. **Do not spawn when spawning is metered.** "all synthesis here happens INLINE in my own context. No Task subagents. No parallel spawning." The reason given is that a billing change made `--print` and API-key calls metered. (S7)
11. **Show orchestration failure honestly.** "5 agents write to the same file at the same time. This is what agent harness, loops and orchestration look like in practice." (S2) S9, secondhand, answers it with claims, one-at-a-time merges, tests on the combination and a stop rule.

## (c) Comparison with Loa

| Recommendation | What Loa does today | Gap | Cheap next step |
|---|---|---|---|
| 1 Orchestrator never fixes | The lead integrates patches and writes the ledgers. In Sprint 256 it also wrote corpus rows itself after a safety classifier stopped implementer E (`grimoires/loa/NOTES.md:11`) | The lead does implementation work, which the fresh-context review has to catch later | Record each lead-authored hunk in reviewer.md so the review sees it as lead work |
| 2 Board first | Beads tasks come from the sprint plan before implementation (CLAUDE.loa.md ALWAYS rules) | None | None |
| 3 Disjoint ownership | Implementers work in linked worktrees and return `git diff --cached --binary` patches. The lead applies them one at a time with `git apply --3way --index` (`NOTES.md:8,11`). No claims are declared | Overlap shows up at apply time or later. One integration defect was found only by a lint after apply (`NOTES.md:8`) | Put claimed paths in each brief and compare them with `git apply --numstat` before applying |
| 4 Four-part brief | Briefs are written ad hoc. The worktree-and-patch practice is not in `.claude/skills/run-mode/SKILL.md`. Agent-teams Template 1 describes per-sprint teammates on a shared tree (`.claude/loa/reference/agent-teams-reference.md:131-150`) | The working practice lives only in NOTES and memory | Write the practice down as a template |
| 5 Wait for all | The lead waits for implementers. Long arm runs are detached with `setsid nohup`, and the Sprint 2 gate falls back instead of waiting (`grimoires/loa/sdd.md:95`, D-2.3) | Loa is stronger here: a long job never blocks a gate | None |
| 6 Cost per seat | Opus 5.5 implementers, Fable 5.1 review (operator policy). There is no turn or spend cap per subagent. `run-arms.sh` has `--concurrency` and transport retries but no spend ceiling (`evals/harness/run-arms.sh:67,226`). The batch-2 cost gate is a decision row applied by hand (DEC-0173) | Spend is checked by judgment, not by the driver | Add `--max-usd` to the driver |
| 7 Maker does not sign off | Separate review and audit in fresh contexts. Two-voice dissent. The yield record credits the fresh context (`grimoires/loa/a2a/paradigm-review-2026-10/comparison.md:108`) | Loa is stronger | None |
| 8 Cheap and short | Dissent is capped at three runs per sprint after the 39-run loop took 84 percent of metered spend (`comparison.md:110`) | Matches after the fact | None |
| 9 Small controlled comparisons | FR-2 arms: four arms, three interleaved trials, a pinned source commit and model, bootstrap intervals (`sdd.md:95`). The executor is Opus 5.5 at about $3 per trial on pr-01, with batch-2 diffs 10 to 60 times larger (`NOTES.md:9`). Batch 1 was 10 of 24 trials done per arm when read | No screening tier. Every arm pays full price before any signal arrives | Run one trial on a few fixtures first and promote only arms that move |
| 10 Metered spawning | The cost ledger is list-priced. The paradigm review asks for subscription and list columns (`proposals.md:118`, L4). `cost-report.sh` groups by cheval `agent` (`.claude/scripts/cost-report.sh:406,456`) | I did not find per-subagent cost for Claude Code subagent sessions | Attribute spend to each dispatched seat |
| 11 Same-file collisions | Patches are applied in sequence, with a smoke run after each apply (DEC-0168, `NOTES.md:11`). The circuit breaker's counters are never updated (paradigm review SCAFFOLD row) | No stop rule for a patch that fails twice | A second failed apply sends the patch back once, then stops it |

## (d) Proposals, ranked by value over effort

1. **Claimed paths per implementer.** Surface: run-mode skill dispatch text plus a small lead-side check script under `.claude/scripts/` (System Zone, lead-only change). Each brief lists the paths it owns. Before applying, `git apply --numstat` runs against the claims. A patch outside its claims goes back to its author. Evidence: next cycle, no post-apply integration defect that a claim check would have caught.

2. **A spend ceiling in the arms driver.** Surface: `evals/harness/run-arms.sh` plus cost ledger rows. Add `--max-usd`. The driver tracks spend per trial, stops launching trials once projected spend passes the ceiling, and marks STATUS.json `partial`. That makes DEC-0173 mechanical. Evidence it worked: a bats case in which a stub executor exceeds the ceiling and the run ends `partial` with `trials_failed` at 0. The batch-2 decision then reads from STATUS.json instead of a hand estimate.

3. **A screening tier before full arms.** Surface: evals (`run-arms.sh --screen`, `report.sh --arms`). Run one trial over four fixtures for every arm. Only arms whose delta beats the baseline's spread go on to three trials. Evidence it worked: once batch 1 completes, the screen's ranking of arms matches the full ranking, at a fraction of batch 1's spend. Keep the model fixed, because `compare.sh` refuses model skew.

4. **Write down the worktree-patch dispatch practice.** Surface: run-mode skill or the agent-teams reference (lead-only). Describe the linked worktree, the `--cached --binary` patch, one apply at a time with a smoke run after each, the lead as sole ledger writer, the four-part brief, and committed-range diffs for dissent. Evidence: no NOTES gotcha is learned twice next cycle.

5. **Cost per subagent seat.** Surface: `cost-report.sh` and the cost ledger. Record model, turns and tokens for each dispatched implementer, with subscription and list columns side by side. Evidence: a per-seat table in reviewer.md that can test a Sonnet seat against an Opus implementer on low-risk tasks.

## (e) What I could not verify

- **No statement in the exact framing of the request.** I found no first-party quote that says "subagents with orchestrators run cheap experiments in parallel." Recommendations 1 to 8 come from the agent definitions in S1, which are artefacts and not commentary. Recommendation 9 comes from one YouTube transcript.
- **The October reels.** No transcription tool was available, and I did not install one. Only captions were read for S2 to S5. Their spoken advice on orchestration, swarms and evaluating unreliable workflows is unknown. S4's evaluation artefact is behind the broadcast channel.
- **Other platforms.** Search engines returned a CAPTCHA, no results or 451 errors. X returned 402 or 451, and I found no X account. glitchcatclub.com/lab did not render its artefact list. The Glitch Orchestra repository, if public, was not found.
- **Secondhand sources.** S9, S10 and the surname are third-party readings. S6 is a YouTube auto-caption transcript.
- **Loa per-subagent cost.** I did not confirm whether Claude Code subagent sessions reach Loa's cost ledger. The grouping I saw is by cheval agent.

Searched: `kem_glitch`, `kemglitch`, `kem glitch`, `Kem Tossoun`, `glitchcatclub`, `glitch orchestra` and reel ids, on GitHub, Bing, Google, DuckDuckGo, Instagram and YouTube. yt-dlp read caption metadata only.
