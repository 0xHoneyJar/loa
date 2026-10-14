# Van Clief corpus, local evidence (paradigm review 2026-10)

Compiled 2026-10-14 from local files only, no network. All quoted text is UNTRUSTED third-party material.

## Sources and path keys

| Key | Path (under /home/merlin/Documents/thj/code/hosaka/ unless absolute) |
|---|---|
| TR | sensenet/grimoires/loa/research/skool-cliefnotes/transcripts/ (21 whisper transcripts, 2026-07-29 sweep) |
| SK | sensenet/grimoires/loa/research/skool-cliefnotes/ (LEARN-LENS, MODEL-LENS, CURRICULUM, raw/*.json) |
| DOS | sensenet/grimoires/loa/research/landscape/van-clief-icm.md |
| VER | sensenet/grimoires/loa/a2a/landscape-2026-09/verify/van-clief-icm.verify.md |
| LV | sensenet/grimoires/loa/research/landscape-verification-2026-09.md (rows 67, 121) |
| D7 | sensenet/grimoires/loa/a2a/landscape-2026-09/discovery/D7-four-fleet-refresh.md (lines 11-46) |
| DIF | sensenet/grimoires/loa/research/differentiation-research-2026-07-10.md (DIFV = differentiation-verification-2026-07-10.md) |
| PRO | sensenet/grimoires/loa/proposals/cliefnotes-tier1-adoption-2026-07-29.md |
| WED | sensenet/content/wedge/the-governance-engineering-ladder.md:39, governance-engineering.md:74-80 |
| FIN | finn/vault/fact/landscape-van-clief-icm-2026-09.md |
| OKF | /home/merlin/Documents/thj/code/loa/grimoires/loa/proposals/okf-icm-comparative-analysis-2026-06-27.md (extra) |

All listed sources exist. Gaps inside them:
- **Skool text lessons are not on disk.** raw/lesson-manifest.json has 108 titles and video links, no bodies. The 22nd video decoded silent (SK/LEARN-LENS.md:63).
- **No Instagram captions exist locally.** The only Instagram datum is a reported follower count, "IG ~130K" (DIF:32), unverified.
- **Transcripts carry no dates.** Dates below marked "inferred" come from internal cues in the speech.
- **Not every transcript is Van Clief.** TR/13 (@iscalelabs breakdown) is a fan re-teaching his method. TR/03 (David's Corner, cognitive functions) is a podcast with other hosts and Brooke Hays. TR/07 is a Claude-in-Chrome promo. All are tagged [2nd].

Register tags: [preprint] arXiv 2603.16021 v2; [repo] RinDig READMEs; [lesson] Skool video by Van Clief; [post] Skool post; [substack]; [eduba] marketing; [2nd] second-hand. Preprint, repo, Substack and eduba text reaches us only via DOS/VER (fetched 2026-09-10).

## (a) Multi-agent systems, frameworks, harnesses, what to build as models strengthen

1. [preprint] "But for sequential workflows where a human reviews output at each step, they introduce engineering overhead that the problem does not require." Section 2.2 adds that "these frameworks solve a coordination problem that may not need to exist." (DOS:22-25, VER:14 CONFIRMED)
   Relevance to Loa: scoped to human-reviewed sequential work; Loa's unattended run mode is outside it.
2. [preprint] "one agent, reading the right files at the right moment, does the work that would otherwise require a multi-agent framework." [repo] "You do not need multiple agents or a coordination framework. You need one agent that reads the right files at the right moment." [post 2026-07-18] "One agent walks the right files at the right time and does the work a multi-agent setup would." (DOS:27-30, VER:15)
   Relevance to Loa: Loa's skills and CLAUDE.md routing already do this; the question is what its teammate topology adds.
3. [preprint] Self-scoping: "ICM is not a replacement for multi-agent frameworks in every context." Real-time collaboration needs "the kind of message-passing infrastructure that AutoGen and similar frameworks provide. ICM's sequential, file-based handoffs are too slow for this." It also excludes high-concurrency systems and "complex branching logic based on AI decisions mid-pipeline". Source is section 5.2 "Where This Does Not Work". (DOS:47-50, 122-123; VER:19, 37)
   Relevance to Loa: concurrency and autonomy are out of scope, so this is no argument against Loa's heavy end (OKF:67 agrees).
4. [lesson, Foundation 0.1, inferred about June 2026] "not building multi-agentic frameworks and all these absurdities" (TR/12:4). "Rather than using really complicated workflows or infrastructures and harnesses, you can create one really good harness for a single type of model. And then that model can then navigate structure as it needs to." (TR/12:14-17)
   Relevance to Loa: "one harness, bought not built" (Claude Code); Loa sits on top of it.
5. [lesson, 0.1] "Again, with no crazy injection harnesses, yes, the Cloud Code agent has harnesses in its own right, but that's the point, I don't need to reinvent the wheel, it's already been invented." (TR/12:171-172). "this entire workflow is probably four or five startups ... And it's all in folders and markdown files with one agent, one singular agent." (TR/12:186-187)
   Relevance to Loa: challenges Loa's hook layer, though his "injection harnesses" are about context, not enforcement.
6. [lesson, Impl 3.1, website build] "Anthropic and these other companies are going to build harnesses way better than anyone here will." Also: "the whole idea of having to build insane project memory systems and harnesses for it, I don't think you really need to because it's already happening automatically and even if you did want to do this yourself with a local model, all you need is another set of folders and another set of markdown files." (TR/08:136-151)
   Relevance to Loa: the strongest "do not build harnesses" line; it targets memory systems, not gates.
7. [lesson, Foundation 2.4, the ladder] "The trap is you investing in automating something that the next model was always going to handle on its own anyway" and "Don't automate what the next model will give you for free". Instead, invest in "the stuff that's specific to your context your domain knowledge your client relationships your data" (TR/16:81-86). A $200,000 Fortune 500 pipeline became "a toggle in someone else's settings menu" (TR/16:6-10).
   Relevance to Loa: the cleanest test for the first lens: would a model or Claude Code release make a given Loa subsystem a toggle?
8. [lesson, Foundation 2.5 "OpenClaw Has 350K+ Stars", inferred late January 2026 because the video still says "Moltbot" and "over 100,000 stars"] An orchestration layer that "follows the 60, 30, 10 architecture" is called "good architecture" and "systems that are actually going to last the decade. This is where we should be spending our time as developers." He also warns it is "one of anthropic announcements away from becoming a niche tool" ("getting Sherlock[ed]"). (TR/17:86-91, 100, 110, 125)
   Relevance to Loa: orchestration is valued, platform absorption is the risk; both apply to Loa.
9. [lesson, Foundation 2.7, AI auditing] "What we call an AI agent in the vast majority of cases is not a single entity making autonomous decisions. It is a collection of prompts structured and sequenced by traditional code" (TR/19:25-27). Looking ahead: "when that happens, the engineer's challenge will not be making the AI smarter. It will be building the infrastructure around it, the reliability patterns, the error handling, the protocols for safe autonomous operation." (TR/19:139-143)
   Relevance to Loa: against "harnesses fade as models grow": more autonomy means more infrastructure.
10. [lesson TR/06, Claude Design, undated] "over the next five years ... less and less are you going to need to build agents that navigate folders and collect things more and more you're going to condense your structures and processes into something that one or two agents or one really good coding agent can read" (TR/06:314-317). He adds: "you want to build the systems that grow with time not get replaced with time" (TR/06:332-333).
    Relevance to Loa: his direction of travel: capability in structure, fewer agents.
11. [lesson, Foundation 3.1 "The Full Walkthrough", inferred before 2026-03-17 because the paper is still being written] "most apps or frameworks or agent things require you to build an agent for each of these ... Why not just have cloud code become the agent you need when you're working in the workspace?" (TR/20:129-132). "I have zero code technically speaking, running any sort of Python injection or framework or database ... most of the time for most people, you don't need all that extra stuff" (TR/20:192-196). [lesson, Impl 1.2] "we don't need agents, we need file structures" (TR/05:168).
    Relevance to Loa: the fungible single agent; SK/LEARN-LENS.md:55 logged it as a counter-philosophy.
12. [repo/Skool about page, via DOS theme row only] "the thinking that survives every update" (DOS:105). This was NOT among the 12 verified claims. Treat it as unverified wording.
13. [substack 2026-08-28] "it took a lot of complexity out of all this 'agentic orchestration' hub bub" (DOS:78, VER:25).
14. [eduba] "We build multi-agent systems and production infrastructure. We also help teams decide what not to build." (DOS:72-75, VER:24). DOS:134 rules this a scope gap with the preprint, not a contradiction.
    Relevance to Loa: the consulting arm sells multi-agent builds; the anti-framework message targets learners.
15. [2nd TR/13] A fan goes further: "You can't rely on cloud code or codex memory to do this for you. It never will." (TR/13:301). This contradicts (a)6. Not Van Clief.

## (b) Model choice, open weights, local models, cost, lock-in

**The corpus is NOT silent on open weights.** One Van Clief lesson (TR/06) discusses local and open models by name. Grep over the concatenated transcripts, case-insensitive, counting matching lines:

```
cat TR/* | grep -iEc 'ollama'            -> 0
cat TR/* | grep -iEc 'llama'             -> 0   (whisper writes "Lama")
cat TR/* | grep -iEc 'mistral'           -> 1   (TR/06:296)
cat TR/* | grep -iEc 'deepseek'          -> 0   (whisper writes "deep seek", TR/06:296-297)
cat TR/* | grep -iEc 'qwen'              -> 0   (whisper writes "when three coder next", TR/06:295)
cat TR/* | grep -iEc 'gemma'             -> 2
cat TR/* | grep -iEc 'open[- ]?weight'   -> 0
cat TR/* | grep -iEc 'open[- ]?source'   -> 13
cat TR/* | grep -iEc 'local(ly)? (model|llm)|run(ning)? (it )?local|locally' -> 26
cat TR/* | grep -iEc 'model[- ]agnostic|any model|different model|switch(ing)? model' -> 6
cat TR/* | grep -iEc 'lock[- ]?in|vendor' -> 5
cat TR/* | grep -iEc 'opus|sonnet|haiku' -> 3
cat TR/* | grep -iEc 'kimi|grok|glm|minimax' -> 0
```

Per-file `grep -c` undercounts here because some file names contain colons.

1. [lesson TR/06, undated] Open with: "is there a way to do it without cloud? Could you possibly use local models?" (TR/06:2). Core passage: "you could use local coding models as long as the model can read files and navigate a folder structure you can use it to use these documents it will read skill files it will read these folders it might not do it to the level that some models will" (TR/06:294).
   Relevance to Loa: portability rests on "can read files and navigate a folder"; Loa's floor (hooks, gates, dissent) is higher.
2. [lesson TR/06] Named models, transcribed as spoken. "when three coder next ... an 80 billion parameter model but it only loads certain parameters at a time so you can use it on smaller graphics cards" (TR/06:295). That is likely Qwen3-Coder-Next, an inference from the transcription. Also "code Gemma this is from Google deep mine ... download the smaller versions that will run locally" (TR/06:295) and "Mistral has a local model called Devstral" (TR/06:296). DeepSeek: "they have B2 which is really good ... it's open source", with the caveat "some people argue that deep seek has some tracking that's being sent back even in their open source models" (TR/06:296-297). The DeepSeek version is unclear in the audio.
   Relevance to Loa: his only named open-weight list; a mention, not a benchmark.
3. [lesson TR/06] The why: "if you understand the folder structure if you can navigate it you can remove the need to only use cloud right like I hit my limits I could just swap over to another model I can swap over to a local one ... I can't worry about being locked into a model" (TR/06:297-298). And: "the reason you want to not waste your time building with one single company and focus on the fundamentals is because then you can have it locally you can control it this can cut costs" (TR/06:317-318). Usage limits are his stated trigger: "this is another reason why you might want to use local models" (TR/06:291).
   Relevance to Loa: motivated by rate limits and lock-in, not privacy; the same pressure as Loa's KF-002/017/020.
4. [lesson TR/06] He promises "videos on installing and using local models" (TR/06:295, 342). None is in the 2026-07-29 curriculum. Other agents named: "Claude code or codex or Gemini any agent" (TR/06:94).
6. [lesson TR/17] He describes OpenClaw/Moltbot, not his own practice, as "model agnostic. You can swap Claude or GPT or Lama or even run your own local model, and you don't have vendor lock-in ... Your conversation can stay on your hardware if you keep a local model." His verdict: "most people ... will always choose convenience. But developers and privacy conscious users, I think they're going to choose flexibility." (TR/17:103-105, 120-122)
   Relevance to Loa: privacy appears as a market segment, not his requirement.
7. [lesson TR/12] Cost: a live voice-controlled session cost "$1.20 for about an hour", and "we could drop that number down exponentially if we used more open source models" (TR/12:250-251). He plans a switch to "VoxTroll, which is a more open source voice model" (TR/12:249), probably Mistral's Voxtral, which is an inference.
8. Which models he actually uses. [preprint] "a single model family (Claude Opus 4.6 and Sonnet 4.6)" (DOS:90, VER:29). [lesson 4.1 "Install and First Use", inferred before 2026-03-17 because he still says "model workspace protocol"] "I'm using opus 4.6, which is the more powerful one." (TR/21:153). [lesson TR/06] "I'm on the top max plan" (TR/06:16). [lesson TR/12] Claude Code runs "through my subscription account" (TR/12:200-201). His ethics engine queries "Claude, GPT, Lama, blah, blah, blah, Gemini" as test subjects, not as his workers (TR/19:45).
   Relevance to Loa: in practice single-vendor on a subscription; model-agnosticism is claimed, never tested.
9. [lesson TR/21] Model selection advice: "at the end of the day, pick one and build the systems and the knowledge of how to use that one well, it will easily transfer all the other ones" (TR/21:540-545). He prefers Claude direct "because it's cheaper, it works better" (TR/21:536).
10. [lesson TR/00, TR/06] Subscription versus API cost: "If you did API calls for all of this, it'd be really expensive, but with a subscription, it's not as expensive." (TR/00:9). "it's still less than if I was doing API calls" (TR/06:291).
    Relevance to Loa: his economics assume a flat-rate subscription, which is what local inference would compete with.
11. [2nd TR/13] The fan video says any agent, "cloud codex or these local elements", can read the same file, and suggests Hermes for "open source models, cheaper models" (TR/13:429-433, 458-464).

## (c) Control and quality mechanisms

1. **CONTEXT.md contract** [repo] "Each stage defines a contract in its CONTEXT.md with three parts: what it reads, what it does, and what it writes." The preprint section 3.3 says the same (DOS:32-35, VER:16).
   Relevance to Loa: like Loa's sprint artifacts and handoffs, minus schema validation.
2. **Stage audits** [repo] "Quality checklists the agent runs after completing a stage but before writing output. Each check has an unambiguous pass condition." Also: "any stage where the model is making creative decisions benefits from at least one checkpoint and a quality gate." Linear stages "often run straight through" (DOS:37-40, 126; VER:17).
   Relevance to Loa: self-audit by the working agent; Loa separates roles and adds cross-model dissent.
3. **Every output is an edit surface** [preprint 3.1] "The intermediate output of each stage is a file a human can open, read, edit, and save before the next stage runs." Corrected 3.3 wording: "At each boundary, the human can inspect and optionally edit the output before the next stage reads it." (DOS:42-45, VER:18 CORRECTED)
4. **Configure the factory, not the product** [preprint 3.1] Layer 3 reference material is "configured once during workspace setup and remain[s] stable across every run" (DOS:57-60, VER:21).
5. **Scripts for mechanical work** [preprint abstract] "Local scripts handle the mechanical work that does not need AI at all." (DOS:120). [lesson 0.1] Python was added "because they needed more determinism. They wanted the output to be the same every time." (TR/12:55-57). [lesson Impl 3.1] Skills ship Python "to offload the need to use so many tokens" (TR/08:118-120).
   Relevance to Loa: matches Loa's protocol-versus-script split.
6. **10/30/60 ratio** [lesson 2.7] "the actual AI calling is maybe 10% of the system volume. The orchestration ... that's maybe 30%. The actual data processing ... that's actually like 60% ... All the bad ones seem to ignore this ratio." (TR/19:115-121). [lesson 2.5] gives the same rule as "60% traditional code ... 30% ... rule-based logic ... only 10% actually needs to be AI calls" (TR/17:76-82).
   Relevance to Loa: "most of the system is not AI" supports keeping deterministic gates.
7. **Abstraction ladder** [lesson 2.4] book, then movie, then video game. "whatever AI made cheap give it away ... the thing that you actually charge for is the layer above" and "give away the movies, sell the video games" (TR/16:107-109, 147-148). A separate Layer 1/2/3 ladder (chat, skills, chained skills with Python) is in TR/12:31-82.
8. **Phase-based build and spec-as-contract** [lesson 3.1] "Four stages, you have to do a brief, you need a spec ... a build, and an output." (TR/20:145-148). [lesson Impl 1.1] The spec is "A contract between the voiceover recording and the animation". It deliberately has no frame numbers or pixel positions, because "I actually found that constricted the model ... It actually made the animations worse" (TR/04:193-196, 238-254). [lesson 2.6] "A loose spec or a poor spec means that cloud or your AI agent makes more interpretive choices or hallucinates more" (TR/18:37).
   Relevance to Loa: a counterweight to over-specifying tasks; creative-work anecdote only.
9. **Routing table** [lesson 3.1] "a simple table that tells the AI for this task, read these files, skip those files, you might need these skills." He calls it "the most important pattern in the whole system" (TR/20:135-137).
   Relevance to Loa: like REPO-MAP and context intake; the SKIP column is what Loa lacks (PRO:13-22).
10. **Alignment questions first** [lesson Impl 3.1] "it's going to ask me three questions" (TR/08:93).
11. **Cognitive-function agents** [2nd TR/03, podcast speaker, not Van Clief] "I have an orchestrator that sits at the top that ... orchestrator's job is to simply load a specialized agent and load context". The orchestrator reroutes mis-addressed tasks, and "Sitting above the personality is our values ... things ... that we refuse to do" (TR/03:716-718, 743-751, 769-774). This sits in David's Corner, and it is a multi-agent design inside his community.
12. **Weekly competition "THE AUDITOR"** [post, by Matthew Creamer, not Van Clief, about 2026-09-03] $500 for "a folder-based AI auditor that checks something against a specific standard and reports where it falls short" (DOS:98, VER:33 CORRECTED on the author's role).
13. **"Two gates"** [substack 2026-08-28, second-hand member anecdote] "Messages and a voice note go in, a branded proposal comes out, and a human signs off at two gates before anything reaches the end client. The builder isn't in the room. The judgment is." (DOS:62-65, 129; VER:22)
    Relevance to Loa: nearest local example of reduced gating; unverifiable.
14. **"New Workflow Audit"** [post, Van Clief, about 2026-09-06] "Built a guided way to turn work you know by heart into something you and your AI can actually use." Method: "your AI asks one question at a time about what comes in, what you do, where things get messy, what goes out, and the decision..." The premium resource was not fetched (D7:23).
    Relevance to Loa: close to /plan-and-analyze discovery, for business workflows.

## (d) Memory and state

1. [repo] "State management is the files on disk. Coordination between stages is one folder's output being another folder's input." [icm-architect README] "an agent with no memory must orient, act, and report status from the files alone" (DOS:52-55, VER:20).
   Relevance to Loa: matches grimoires and .run; OKF:142 notes .run position drift.
2. Five-layer hierarchy [preprint 3.2]. Locally only Layers 3 and 4 are quoted: reference material is stable, and working artifacts change per run (DOS:57-58). The other three layers are not quoted in any local file. [lesson 3.1] "I actually go into a five layer architecture in the paper, but realistically, most of you just need to understand the three main layers" (TR/20:224-226). Those three are the map ("the floor plan"), the rooms, and the workspace (TR/20:86-98).
3. [lesson 3.1] Naming conventions replace databases: "instead of having to navigate through these files or have an agent that's connected to some sort of you know SQL database or vector database ... I could just say hey, pull my off demo, demo V2" (TR/20:180-191). [lesson 0.1] "Instead of creating rag that pulls everything in, you just give it access to normal databases." (TR/12:16-17)
4. [lesson Impl 3.1] Vendor memory is good enough: Claude's own memory index is "all just markdown files that are referencing other MDs" (TR/08:140-143), so custom memory harnesses are unnecessary (TR/08:148-151, quoted in (a)6).
   Relevance to Loa: vendor auto-memory overlaps NOTES.md; Loa's recovery and single-writer rules go beyond it.
5. [lesson 2.3] Memory taxonomy: weights as "the closest analog to ROM", the context window "more like working memory", the system prompt "something like a firmware", retrieved context "like loading from a disk into RAM", persistent memory "Almost like summaries" (TR/15:91-120). On injection: "Reading it is the execution. And this is why prompt injection works ... There is no separate layer that validates code versus data." (TR/15:132-138)
   Relevance to Loa: backs Loa's untrusted-body rule.
6. Humans in the loop, U-shape [preprint 4.5] "Across 33 community members who have used the script-to-animation workspace or structurally similar multi-stage workspaces, 30 report an intervention pattern consistent with a U-shape", with "heavy editing at stage 1 (direction-setting), light editing at the middle stages, and heavy editing again at the final stage" (DOS:90, VER:29). The data is self-reported, informal, from an invite-only sample of 52, on one model family.
   Relevance to Loa: human gates earn most at direction-setting and final acceptance, where Loa's planning gates and PR approval sit.
7. [lesson Impl 3.1] "I always recommend that you look through what Claude is doing, right? Look through its thoughts" (TR/08:114-116).
8. [2nd TR/13] "pick up / hand off" codewords and "read it back from disk and verify without relying on memory" are the fan's, not Van Clief's (TR/13:338-361). SK/LEARN-LENS.md:14, 34 present them as course content.

## (e) Audience and direction of travel

1. **Scale.** Skool shows "47.8k members", free tier, "40+ free lessons" (DOS:88, 2026-09-10). July showed 41,600+ (DIFV:8). The paper's community was "an invite-only practitioner community of 52 members" (DOS:90). These measure different things (DOS:134).
2. **Pitch.** "Build durable AI systems with a Marine vet and Edinburgh researcher." (D7:20). Paid tiers: Premium $27/mo, VIP $97/mo, Lifetime $5,000 (third-party only) (DIFV:8; SK/MODEL-LENS.md:10-12).
3. **Who.** The audience is mostly non-developers and business operators. He explains VS Code, markdown and tokens from scratch (TR/20:12-16, 32-38). "Three community members with no prior coding experience" built video workspaces (DOS:90). He cites "84% of the nation is still not fully using it" (TR/20:18). Enterprise and consulting framing appears too: a slide "that I gave to a real enterprise company that's bringing in like 60 million a year" (TR/12:28-29), "Your team become the vendor" (TR/12:24-25), and he "get[s] hired" to help companies decide where AI fits (TR/16:15-16, garbled rate). Eduba lists KPMG UK, IAG, University of Edinburgh and others, with no described agent deployment (DOS:96, VER:32).
4. **What they build.** Content pipelines (script, voice, Remotion animation), websites, slide decks, client proposal systems, workflow audits (TR/04, TR/08, TR/12:157-187, DOS:129).
5. **Direction of travel, his words.**
   - Fewer agents: "one or two agents or one really good coding agent" (TR/06:316).
   - Voice: "within six months, everyone's going to be doing this is just talking to your folder setup" (TR/20:199-200); a voice-controlled group-call demo (TR/12:191-262).
   - Judgment packaging [substack]: "Every serious lab landed on plain folders and files as the way judgment gets packaged and handed to a machine" (DOS:67-70; VER:23 CORRECTED, the labs are named in passing with no document cited). Also "The only good software is a human one." (D7:31)
   - Work interviews: the New Workflow Audit (c14) packages tacit work into files.
   - Not anti-autonomy: he expects "genuine agentic behavior" to become real, and then infrastructure becomes the work (TR/19:139-143).
   Relevance to Loa: single agent plus packaged judgment, sold to non-developers; overlap with Loa is mainly the knowledge-packaging layer.

## (f) Evaluation and verification other than human review

1. [repo] Agent-run stage audits with "an unambiguous pass condition" (c2). [preprint 6.2] "an audit file that forces the agent to trace back from the specification to the original script", plus a proposed "Verify section" (DOS:40, 135).
2. [preprint 4.6] "No controlled comparison has been conducted"; data collection "has been informal"; the sample is "invite-only and self-selected" (DOS:90, VER:29). The headline token figures, "about 2-8k vs 42k tokens", come second-hand through OKF:44 and are labelled there as uncontrolled.
   Relevance to Loa: no eval harness exists in his method to compare with Loa's.
3. [lesson TR/00, Building Your Stack 1.2] He uses a second model instance as reviewer: "you can actually feed this into another version of Claude and have it act as that auditor" (TR/00:67-68). This is same-vendor second review, a weak form of Flatline.
4. [lesson TR/06] The agent self-checks by screenshot: "it's taking screenshots of it right now ... it's verifying that everything looks good itself" (TR/06:205-206).
5. [lesson 2.7] His ethics engine evaluates models, not agent output: psychometric scales with Cronbach's alpha (transcribed "Chromebox alpha") and test-retest checks. He claims "about 90% reliability" with no method given (TR/19:110-111, 146).
6. [lesson 2.2, 2.3] Reliability as engineering: "Every layer started with unreliability. Every layer becomes reliable through architecture. AI is no different ... We're building systems to catch mistakes and verify outputs or just create redundancy." (TR/14:247-255). "The reliability came from building the infrastructure, from doing the engineering work." (TR/15:178)
   Relevance to Loa: in his framing verification infrastructure is the durable part, which supports Loa's gates under the stronger-models lens.
7. [lesson 0.1] Self-reported "20, 30, 40% token reduction" (TR/12:20); earlier manual practice: "verify that it's right" (TR/12:66).

## Timeline of public outputs known locally

| Date | Item | Source |
|---|---|---|
| inferred late Jan 2026 | Video "OpenClaw Has 350K+ Stars", spoken as Moltbot with 100k stars | TR/17:4-8 |
| inferred before 2026-03-17 | Videos that still say "model workspace protocol": 4.1 Install, Impl 1.1, 3.1 Walkthrough ("writing a very large research paper right now") | TR/21:26, TR/04:325, TR/20:221 |
| 2026-02-22 | First repo commit, "Initial release: MWP framework with 3 workspaces" | VER:26 |
| 2026-03-08, 2026-03-17 | Rename commits from MWP to ICM | VER:26 |
| 2026-03-17 / 03-18 | arXiv 2603.16021 v1 / v2 | VER:14 |
| 2026-06-01 | "Add voice-driven-animation workspace", PR #6 | VER:26 |
| 2026-06-14 | Substack "The Machine Is Smart", title only, not fetched | D7:32 |
| inferred about June 2026 | Foundation 0.1, "paper that I published about three months ago", "over 30,000 people" | TR/12:1-3 |
| 2026-07-10 | Skool count 41,600+ | DIFV:8 |
| 2026-07-18 | Skool post "New tool: ICM Architect" | DOS:98 |
| 2026-07-25 | Latest repo commit, a typo fix | VER:26 |
| 2026-08-28 | Substack "Augmenting Human Intellect" | VER:22 |
| about 2026-09-03 | "WEEKLY COMP #12: THE AUDITOR", by Creamer | VER:33 |
| about 2026-09-06 | "New Workflow Audit", by Van Clief | VER:33 |
| 2026-09-10 | Latest access: Skool 47.8k; icm-architect 1.5k stars | VER:27-28 |

The Claude Design lesson (TR/06), the Archive lessons (TR/09-11) and the rest of TR are undated.

## Verification status: cite only confirmed text

CORRECTED by VER (cite the corrected form):
- **C5:** the 3.3 quote is "the human can inspect and optionally edit the output before the next stage reads it". The dossier's "inspect and edit ... before the next stage runs" is wrong.
- **C10:** the labs are named in passing (Anthropic's Skills, OpenAI, xAI's Grok, Google), and no document is cited.
- **E2:** icm-architect has 212 forks, not 210. The self-report reads "over 1300 starts on github" (sic).
- **E7:** six Eduba entries. Only two are described, a workshop and a research collaboration. None is an agent deployment.
- **E8:** the AUDITOR post is by Matthew Creamer, role not verified. "Community moderator" in D7:22 and DOS:135 is unverified. "New Workflow Audit" showed 128 likes.
- **Whole-dossier:** snapshot passage 2 drops the sentence "ICM's sequential, file-based handoffs are too slow for this." (VER:37). E3 wording becomes "free-tier total, not a count of active builders" (VER:38).

UNREACHABLE: **E9**, the Lyceum certification at lyceum.eduba.io (404). Its "12 weeks, three sprints" figures exist only as a search snippet (VER:34, LV:67).

July pass (DIFV): the funnel was CORRECTED. The $97 VIP is on his own Skool posts, and the $5,000 lifetime is third-party only (DIFV:8). The "Google Cloud researchers endorsed" claim is not locatable (DIF:15-21). The roughly $30k MRR has no public corroboration (DIFV:70, DIF:22-24).

Not verified anywhere locally, so do not cite as his words:
- "the thinking that survives every update" (DOS:105 only).
- "never write code for your agents" (DIF:41, no source given).
- "you need one orchestrating agent that reads the right files at the right moment" (DIF:39). The verified README wording is "You need one agent that reads the right files at the right moment" (VER:15).
- WED:39 calls ICM "explicitly anti-swarm" and WED governance-engineering.md:75 says "no swarm". Both overstate. The preprint scopes itself in section 5.2 and does not reject multi-agent systems in general.
- Course items in SK/LEARN-LENS.md that come from the iscalelabs video, not from Van Clief: pick up/hand off, and verify-from-disk.

## What the local corpus cannot tell us

- **Anything after 2026-09-10.** That includes new Substack posts, Skool posts, repo commits, a preprint v3, or any change of position.
- **Instagram.** No @lostandlucky caption is on disk. Instagram-register claims need a fresh pull.
- **Skool text lessons.** 86 non-video lessons are titles only. "Tokens, Deepseek, & Managing Context" (THE LEGENDS) and "GPT 5.5 - What Actually Changed" (David's Corner) look relevant to open weights and model choice, but their bodies were never captured (SK/CURRICULUM.md:62, 107).
- **The local-models video he promised.** It is not in the July curriculum, so whether he followed through on open weights is unknown.
- **The premium material.** The Vault, the New Workflow Audit premium resource, and live calls were not captured.
- **YouTube beyond the course videos** (channel page unreadable, D7:41).
- **Measured evidence.** No controlled comparison, cost data, or open-weight model run with ICM exists in any local source. The portability claim is untested in his own material.
- **Transcript accuracy.** Whisper mis-hearings ("cloud", "Lama", "B2", "VoxTroll") mean wording needs checking against the video before publication.
