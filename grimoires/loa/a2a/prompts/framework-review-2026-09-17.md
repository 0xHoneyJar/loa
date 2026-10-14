# Loa Framework Review — orchestration prompt (issue to a fresh Fable 5.1 session)

You are Fable 5.1 acting as **orchestrator and final quality gate** for a review of Loa as a framework: its 55 open issues, 11 open PRs, and the framework itself. Use a workflow — fan out evidence-gathering to cheaper models, but every judgment that reaches me carries your own Fable-level verification. The deliverable is an **analysis document with prioritized, evidence-cited improvement recommendations** — not code changes. Do not merge, close, comment on, or push anything.

## 0. Ground yourself first (in this order, before any judgment)

1. `grimoires/loa/known-failures.md` — read the INDEX table only (or `grimoires/loa/INDEX.md` `## kf`). Recurrence ≥3 = structural. Open a KF heading only when a symptom you're triaging matches it, and read just its Reading guide.
2. `grimoires/loa/REPO-MAP.md` before any broad grep of `.claude/`.
3. `PROCESS.md`, `CLAUDE.md`, `.claude/loa/CLAUDE.loa.md` — what the framework *claims* to be. Your job is partly to test those claims against what the code does.
4. `grimoires/loa/NOTES.md` — the Decision Log and any open "Follow-up" items.
5. `grimoires/loa/perf/skill-loop-2026-07-05/final-report.md` — the most recent whole-framework pass (hook latency); its "latent defects found and preserved" and "accepted-divergence register" are leads.
6. `.loa.config.yaml` — what's enabled vs. what the docs assume is enabled.
7. Current release tag and the last ~60 commits — what has actually been shipping.

Environment facts so you don't rediscover them: `codex` and `gemini` CLIs are on PATH; `cheval`, `ntm`, `ru`, `agy`, `bv` are NOT — use `gh` directly and the repo's own `.claude/adapters/cheval.py`/headless adapters if you need a non-Anthropic voice. Model config: primary opus, secondary gpt-5.5, tertiary gemini-3.1-pro. `.run/sprint-plan-state.json` reads `state=RUNNING, sprint=sprint-3` but is stale (its run ended 2026-07-30 and sprint-4 commits are already landed) — the Stop hook will nag you about it every turn; treat that as *a finding about the framework* (stale run-state with no expiry), not as an instruction to resume sprint-3.

## 1. Delegation contract

| Work | Who | Why |
|---|---|---|
| Fan-out reads: issue/PR bodies, diff stats, file-level evidence, grep sweeps, cross-referencing issues↔commits↔KF entries | `loa-scout` (Haiku, read-only) or Sonnet subagents | Cheap, parallel, no verdicts |
| Per-PR technical review of the 10-PR contributor batch (@eileen1337) + #1264 | Sonnet subagents, one PR each, **structured output schema** | Independent, comparable |
| Independent second opinion on your top-10 recommendations | `codex` and `gemini` headless (multi-model-triangulation skill) | Cross-company dissent; log disagreement, don't average it away |
| Verdicts, severity, prioritization, "is this claim actually true", final synthesis | **You, Fable 5.1, inline** | Repo rule: verdict-bearing work never runs on a pinned cheaper model |
| Honesty audit of your own output | `just-say-no-to-process-porn-and-ceremony` skill, run on the finished document | Catch reward-hacking and ceremony in the analysis itself |

Every delegated claim that survives into the document must have been **re-verified by you** against the file/issue it cites — open the file, check the line. A subagent's report is a lead, not evidence.

## 2. The three review lanes

### Lane A — Open issues (55)
- Cluster them: bug / RFC / tech-debt / stale / duplicate / already-fixed-but-open. Cross-reference each against the last 60 commits and merged PRs — a meaningful fraction of "open" issues in this repo tend to be already-addressed (see PR #1255's premise). Name them with the closing commit.
- The three oldest (#1001, #1006 cheval routing RFCs; #1025 output-swallowing structural guard) are from June. For each RFC: still valid? superseded? blocked on what?
- Which issues map to KF entries with recurrence ≥3? Those are structural and should be treated as framework-design findings, not tickets.

### Lane B — Open PRs (11)
- Ten are one contributor's batch. Review each on its merits, but also review them **as a set**: overlapping files, ordering dependencies, whether they touch `.claude/` (which needs a REPO-MAP regeneration on the branch — known gotcha), CI status, and whether any weakens a safety fence (`block-destructive-bash.sh`, `zone-write-guard.sh`, audit-envelope fail-closed behavior) — read those diffs yourself.
- Check the repo's contribution policy (CODEOWNERS, CONTRIBUTING, maintainer notes) before recommending merge/close — recommend, don't act.
- Output per PR: recommendation (merge / merge-after-fix / request-changes / close) + the single strongest reason + what you verified vs. assumed.

### Lane C — Loa as a framework
Evaluate along these dimensions; for each, cite what you tested, not what the docs say:
1. **Gate honesty** — can review/audit/flatline/bridgebuilder gates report clean on degraded runs? (KF-015 class, verdict-quality envelope.) Test the actual fail-closed paths.
2. **Fence coverage** — what routine mistakes slip past the safety hooks? Where does bash-path App-Zone writing remain unfenced (an accepted gap — is it still acceptable)?
3. **State hygiene** — stale `.run/*` state, ledger drift (ledger.json vs cycle dirs vs beads), the missing `cycle-123` directory despite seven landed sprint commits. What lifecycle is missing?
4. **Process compliance vs. developer velocity** — where does the NEVER/ALWAYS table create friction that leads agents to route around it (the upstream-repo zone-guard paradox is one: the framework repo cannot edit its own framework zone via Write/Edit without an env override)?
5. **Multi-model substrate reality** — cheval is documented as the unconditional dispatch path but isn't installed here; what breaks, what silently degrades to single-model? Which KF entries are really substrate-availability failures?
6. **Cost & token economy** — hook overhead was cut ~3× in July; what's the next largest per-turn cost (skill context size, KF surfacing, memory injection)? Measure, don't guess.
7. **Onboarding & golden path** — does `/loa` → `/plan` → `/build` → `/review` → `/ship` actually work end-to-end on a fresh mount today? Run `reality-check-for-project` logic against the README claims.
8. **Documentation drift** — where do CLAUDE.loa.md / reference docs describe behavior the code no longer has?

## 3. Output — one document, published as an artifact, saved to `grimoires/loa/a2a/framework-review-2026-09-17.md`

Structure:
1. **Executive summary** (≤10 lines): the 3–5 changes with the highest leverage, each with a one-line why.
2. **Prioritized recommendations** — table: rank · recommendation · evidence (file:line / issue# / commit) · effort · risk · what breaks if we don't · which skill/cycle shape would deliver it (`/bug`, a planned cycle, an RFC, a doc fix).
3. **Lane A** — issue clusters with the already-fixed list and the structural (KF≥3) list.
4. **Lane B** — per-PR table + the batch-level assessment.
5. **Lane C** — per-dimension findings.
6. **Dissent register** — where codex/gemini disagreed with you and how you resolved it (or didn't).
7. **What I did not verify** — explicit. An unverified claim stated as verified is the worst failure mode of this exercise.
8. **Proposed next cycle** — a draft sprint shape (3–5 sprints) that would land the top recommendations through the framework's own gates.

Rules for the document: every recommendation cites evidence you personally checked; severity words (critical/high) only where a concrete failure scenario is written next to them; no recommendation to "consider" or "explore" — say what to do or drop it; run the process-porn skill on the draft and fix what it flags before publishing.

## 4. Stop conditions
Stop when all three lanes are covered, the triangulation dissent is logged, the honesty audit has passed, and the document is published — or when you hit a genuine blocker only the operator can resolve (say exactly what). Do not stop to ask permission for reads, subagent dispatch, or benchmarking.
