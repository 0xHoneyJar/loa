# FR-8 triage: the referenced command set (sprint-252, Task 1.8)

> Author: implementer C, cycle-128 Sprint 1. Rule (SDD D-8.2): a triage-set
> command is flagged only when every reference to it in another command or
> skill body is advice to the human; an orchestrator step keeps it unflagged.
> Line numbers are those of worktree `wt/s1c` after the patch (three command
> files gained frontmatter lines; no referencing line moved except in
> `loa-eject.md` and `toggle-gpt-review.md`).

## Harness check (Task 1.0)

Outcome: **verified**. One live `claude -p` run (Claude Code 2.1.296, model
`global.anthropic.claude-opus-5-5`, Skill tool only) in a temp project with
two fixture commands. The flagged command was refused and its body never
loaded; the control ran.

```
skill_call: fixture-hidden   is_error=true
  "Skill fixture-hidden cannot be used with Skill tool due to disable-model-invocation.
   Ask the user to run /fixture-hidden themselves ..."
skill_call: fixture-visible  is_error=false
  "Launching skill: fixture-visible" then the body "Reply with the single word VISIBLE-RAN"
verdict=verified rc=0   (4 turns, USD 0.088)
```

Both fixtures stayed in the session's slash-command list, so the operator can
still type a flagged command. FR-8 is therefore enforced by the harness, not
lint-only; G-7 is met for the flagged set. Raw stream:
`~/.cache/loa/cycle-128/s1c-harness-stream.jsonl`.

## Decision per command

| Command | References | Orchestrator steps | Decision | Rationale | Evidence |
|---|---|---|---|---|---|
| `update-loa` | 11 | 0 | not flagged (deferred) | Every reference is advice, but the D-8.3 lint reads `Run /update-loa --force-restore` in the `translate-ride.md:145` troubleshooting table as operative; part C may not edit that file | `translate-ride.md:145`; probe output below |
| `mount` | 13 | 0 | not flagged (deferred) | Every reference is advice, but seven user-facing error strings (`error: "... Run /mount first."`, troubleshooting rows) trip the lint; part C may not edit those files | `ride.md:62,66,70,282,283`, `run.md:60`, `run-sprint-plan.md:44` |
| `contribute` | 1 | 0 | **FLAGGED** | The only reference is advice (`loa-eject.md`); the command opens an upstream PR, an outward-facing act | `loa-eject.md:260` |
| `feedback` | 24 (10 are path matches) | 0 in bodies | not flagged | Body references are advice, but `.claude/loa/reference/agent-teams-reference.md:59,278` sanctions teammate invocation of `/feedback`, a model invocation path outside the command and skill bodies | `agent-teams-reference.md:59` |
| `deploy-production` | 12 | 7 | not flagged | `/ship` executes it and the autonomous agent runs it in Phase 6 | `ship.md:60`, `autonomous-agent/SKILL.md:180` |
| `archive-cycle` | 12 | 7 | not flagged | `/ship` executes it; `/loa` invokes it after the user confirms | `ship.md:64`, `loa.md:265` |
| `ship` | 16 | 1 | not flagged | `/loa` invokes it when the user picks the menu option | `loa.md:262` |
| `run-halt` | 9 | 0 | **FLAGGED** | Every reference is a related-commands list, help line or recovery option for the human; the run-mode circuit breaker halts without the command | `run-mode/SKILL.md:224`, `escalation-report.md:151` |
| `run-resume` | 29 | 2 | not flagged | `/simstim` resume invokes it in place of a fresh run | `simstim.md:462`, `simstim-workflow/resources/resume-support.md:132` |

Lint probe: with all nine names appended to a copy of the allowlist, the
`user-invoked-commands.bats` operative check reports exactly the orchestrator
lines above for `deploy-production`, `archive-cycle`, `ship` and
`run-resume`, plus the advice-shaped false positives for `mount`,
`update-loa` and `feedback`. For `contribute` and `run-halt` it reports
nothing.

## Safe-set note

The safe set was fixed as "zero references" (PRD D8), and all four are
flagged. One reference is an orchestrator step: `loa.md:263` routes the
`loa-setup` menu choice with "Invoke the `/loa setup` skill". `loa.md:268`
already says to show the copyable command when a skill invocation is denied,
so `/loa` degrades to advice. The `loa-setup` skill itself stays unflagged
(D-8.1, A12), so a Skill call naming `loa-setup` may still resolve to the
skill; the single harness run did not test a shared command and skill name.

## Per-reference table

| Command | Reference | Reference type | Decision | Rationale | Evidence |
|---|---|---|---|---|---|
| `update-loa` | `.claude/commands/translate-ride.md:145` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `e integrity violation" \| .claude/ modified \| Run /update-loa --force-restore \|` |
| `update-loa` | `.claude/commands/loa.md:212` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `/update-loa              Pull framework up` |
| `update-loa` | `.claude/commands/loa-eject.md:15` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `- Framework updates via /update-loa no longer work` |
| `update-loa` | `.claude/commands/loa-eject.md:49` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `x Framework updates via /update-loa will no longer work` |
| `update-loa` | `.claude/commands/loa-eject.md:307` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `x Framework updates via /update-loa will no longer work` |
| `update-loa` | `.claude/skills/mounting-framework/SKILL.md:52` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `echo "Use '/update-loa' to sync framework, or continu` |
| `update-loa` | `.claude/skills/mounting-framework/SKILL.md:134` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `pdate-loa-bump-version.sh — the same resolver /update-loa uses (Phase 5.6). This makes ` |
| `update-loa` | `.claude/skills/mounting-framework/SKILL.md:171` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `# Replace placeholder via the SAME resolver /update-loa uses (single source of truth).` |
| `update-loa` | `.claude/skills/mounting-framework/SKILL.md:333` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `eady mounted" \| .loa-version.json exists \| Use /update-loa or confirm remount \|` |
| `update-loa` | `.claude/skills/riding-codebase/SKILL.md:39` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `ude/overrides/ or reset via --force-restore / /update-loa --force-restore, and block un` |
| `update-loa` | `.claude/skills/translating-for-executives/SKILL.md:49` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `move customizations to .claude/overrides/, run /update-loa --force-restore, or set inte` |
| `mount` | `.claude/commands/run-sprint-plan.md:44` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `error: "Loa not mounted. Run /mount first."` |
| `mount` | `.claude/commands/run.md:60` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `error: "Loa not mounted. Run /mount first."` |
| `mount` | `.claude/commands/reality.md:233` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `- /mount - Install Loa on a repository` |
| `mount` | `.claude/commands/plan-and-analyze.md:231` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `- Use /mount only if you need manual contr` |
| `mount` | `.claude/commands/loa.md:211` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `/mount                   Install Loa ` |
| `mount` | `.claude/commands/ride.md:62` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `error: "Loa not mounted. Run /mount first. The Loa must mount befo` |
| `mount` | `.claude/commands/ride.md:66` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `error: "System Zone missing. Run /mount to install framework."` |
| `mount` | `.claude/commands/ride.md:70` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `error: "State Zone missing. Run /mount to initialize."` |
| `mount` | `.claude/commands/ride.md:282` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `"Loa not mounted" \| No .loa-version.json \| Run /mount first \|` |
| `mount` | `.claude/commands/ride.md:283` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `\| "System Zone missing" \| No .claude/ \| Run /mount first \|` |
| `mount` | `.claude/skills/autonomous-agent/SKILL.md:100` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `unted) — if not, halt and tell the user to run /mount. Select the highest-priority ` |
| `mount` | `.claude/skills/mounting-framework/SKILL.md:134` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `olver /update-loa uses (Phase 5.6). This makes /mount and /update-loa share a sin` |
| `mount` | `.claude/skills/riding-codebase/SKILL.md:39` | advice to the human | not flagged (deferred) | help list, next-step hint, user-facing message or description | `sion.json (if missing, instruct the user to run /mount first; extract and display th` |
| `contribute` | `.claude/commands/loa-eject.md:260` | advice to the human | FLAGGED | help list, next-step hint, user-facing message or description | `- **Want to contribute**: Keep connected for /contribute` |
| `feedback` | `.claude/commands/toggle-gpt-review.md:19` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `f you rely on /toggle-gpt-review**, please run /feedback or file an` |
| `feedback` | `.claude/commands/oracle-analyze.md:147` | not a command reference | not flagged | path match (grimoires/loa/feedback/, a feedback resource or schema) | `\| Feedback \| grimoires/loa/feedback/*.yaml \| Captured learnings f` |
| `feedback` | `.claude/commands/deploy-production.md:89` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `10. **Feedback**: Suggest /feedback command` |
| `feedback` | `.claude/commands/flatline-review.md:155` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `display: "Multi-model review working as designed. /feedback if you disagree."` |
| `feedback` | `.claude/commands/loa.md:120` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `Something broken? /feedback reports it directly.` |
| `feedback` | `.claude/commands/loa.md:157` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `/feedback            Report issues or su` |
| `feedback` | `.claude/commands/loa.md:221` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `/feedback                Submit DX feedb` |
| `feedback` | `.claude/commands/loa.md:423` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `Something unexpected? /feedback reports it directly.` |
| `feedback` | `.claude/commands/gpt-review.md:23` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `If you relied on /gpt-review, run /feedback or file an issue at` |
| `feedback` | `.claude/skills/designing-architecture/SKILL.md:364` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `sume with /plan next time. Not what you expected? /feedback helps us fix it."` |
| `feedback` | `.claude/skills/designing-architecture/SKILL.md:384` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `- "Stop here" always includes /feedback mention` |
| `feedback` | `.claude/skills/autonomous-agent/resources/phase-checklist.md:299` | not a command reference | not flagged | path match (grimoires/loa/feedback/, a feedback resource or schema) | `- [M] Save learnings to grimoires/loa/feedback/` |
| `feedback` | `.claude/skills/autonomous-agent/resources/phase-checklist.md:307` | not a command reference | not flagged | path match (grimoires/loa/feedback/, a feedback resource or schema) | `ls grimoires/loa/feedback/` |
| `feedback` | `.claude/skills/autonomous-agent/resources/feedback-protocol.md:115` | not a command reference | not flagged | path match (grimoires/loa/feedback/, a feedback resource or schema) | `At end of Phase 7, flush to grimoires/loa/feedback/{date}.yaml:` |
| `feedback` | `.claude/skills/autonomous-agent/resources/feedback-protocol.md:118` | not a command reference | not flagged | path match (grimoires/loa/feedback/, a feedback resource or schema) | `# grimoires/loa/feedback/2026-01-31.yaml` |
| `feedback` | `.claude/skills/autonomous-agent/resources/feedback-protocol.md:193` | not a command reference | not flagged | path match (grimoires/loa/feedback/, a feedback resource or schema) | `# .claude/schemas/feedback.schema.yaml` |
| `feedback` | `.claude/skills/autonomous-agent/resources/feedback-protocol.md:276` | not a command reference | not flagged | path match (grimoires/loa/feedback/, a feedback resource or schema) | `output_dir: grimoires/loa/feedback` |
| `feedback` | `.claude/skills/autonomous-agent/resources/templates/escalation-report.md:130` | not a command reference | not flagged | path match (grimoires/loa/feedback/, a feedback resource or schema) | `- **File**: grimoires/loa/feedback/{feedback_file}` |
| `feedback` | `.claude/skills/autonomous-agent/SKILL.md:188` | not a command reference | not flagged | path match (grimoires/loa/feedback/, a feedback resource or schema) | `ds more detail. Capture feedback to grimoires/loa/feedback/{date}.yaml; see resources/f` |
| `feedback` | `.claude/skills/discovering-requirements/resources/REFERENCE.md:384` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `sume with /plan next time. Not what you expected? /feedback helps us fix it."` |
| `feedback` | `.claude/skills/discovering-requirements/resources/REFERENCE.md:395` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `- "Stop here" always includes /feedback mention` |
| `feedback` | `.claude/skills/planning-sprints/SKILL.md:384` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `sume with /plan next time. Not what you expected? /feedback helps us fix it."` |
| `feedback` | `.claude/skills/planning-sprints/SKILL.md:402` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `- "Stop here" always includes /feedback mention` |
| `feedback` | `.claude/skills/enhancing-prompts/SKILL.md:213` | not a command reference | not flagged | path match (grimoires/loa/feedback/, a feedback resource or schema) | `2. Map to refinement action per resources/feedback.md` |
| `deploy-production` | `.claude/commands/ship.md:14` | orchestrator step | not flagged | /ship executes it as its archive phase | `.** It routes to the existing truename commands (/deploy-production + /archive-cycle) with read` |
| `deploy-production` | `.claude/commands/ship.md:50` | orchestrator step | not flagged | /ship executes it as its deploy phase | `1. Deploy to production (/deploy-production)` |
| `deploy-production` | `.claude/commands/ship.md:60` | orchestrator step | not flagged | /ship executes it as its deploy phase | `Unless --skip-deploy, execute /deploy-production.` |
| `deploy-production` | `.claude/commands/ship.md:110` | orchestrator step | not flagged | /ship executes it as its deploy phase | `→ Running /deploy-production` |
| `deploy-production` | `.claude/commands/ship.md:138` | orchestrator step | not flagged | /ship executes it as its deploy phase | `1. /deploy-production` |
| `deploy-production` | `.claude/commands/loa.md:69` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `\| complete \| /deploy-production \| /ship \|` |
| `deploy-production` | `.claude/commands/loa.md:190` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `/deploy-production       Deploy to production` |
| `deploy-production` | `.claude/skills/autonomous-agent/resources/phase-checklist.md:266` | orchestrator step | not flagged | autonomous checklist step | `- [M] Run /deploy-production if approved` |
| `deploy-production` | `.claude/skills/autonomous-agent/SKILL.md:180` | orchestrator step | not flagged | autonomous Phase 6 runs it | `Run /deploy-production, monitor progress, and captur` |
| `deploy-production` | `.claude/skills/auditing-security/resources/templates/sprint-audit-feedback.md:91` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `2. Move to next sprint or /deploy-production` |
| `deploy-production` | `.claude/skills/continuous-learning/SKILL.md:184` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `/implement, /review-sprint, /audit-sprint, /deploy-production, or /ride:` |
| `deploy-production` | `.claude/skills/continuous-learning/SKILL.md:231` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `\| /deploy-production \| YES \| Infrastructure discov` |
| `archive-cycle` | `.claude/commands/ledger.md:105` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `\| /archive-cycle \| Archive current cycle and s` |
| `archive-cycle` | `.claude/commands/ledger.md:119` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `/archive-cycle "MVP Complete"  # Archives cyc` |
| `archive-cycle` | `.claude/commands/ship.md:14` | orchestrator step | not flagged | /ship executes it as its archive phase | `isting truename commands (/deploy-production + /archive-cycle) with readiness validation.` |
| `archive-cycle` | `.claude/commands/ship.md:51` | orchestrator step | not flagged | /ship executes it as its archive phase | `2. Archive cycle (/archive-cycle)` |
| `archive-cycle` | `.claude/commands/ship.md:64` | orchestrator step | not flagged | /ship executes it as its archive phase | `Execute /archive-cycle to archive the completed deve` |
| `archive-cycle` | `.claude/commands/ship.md:113` | orchestrator step | not flagged | /ship executes it as its archive phase | `→ Running /archive-cycle` |
| `archive-cycle` | `.claude/commands/ship.md:139` | orchestrator step | not flagged | /ship executes it as its archive phase | `2. /archive-cycle` |
| `archive-cycle` | `.claude/commands/ship.md:149` | orchestrator step | not flagged | /ship executes it as its archive phase | `→ Running /archive-cycle` |
| `archive-cycle` | `.claude/commands/plan-and-analyze.md:297` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `\| /archive-cycle "label" \| Archive current cyc` |
| `archive-cycle` | `.claude/commands/loa.md:215` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `/archive-cycle           Archive development ` |
| `archive-cycle` | `.claude/commands/loa.md:265` | orchestrator step | not flagged | /loa invokes it after the user confirms the menu choice | `chive is recoverable. Continue?" — then invoke /archive-cycle \|` |
| `archive-cycle` | `.claude/skills/autonomous-agent/resources/templates/escalation-report.md:169` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `1. Archive current state: /archive-cycle "escalation-{date}"` |
| `ship` | `.claude/commands/review.md:67` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `All clear. Next: /build (if more sprints) or /ship` |
| `ship` | `.claude/commands/review.md:105` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `Next: /build (sprint-3 remaining) or /ship (if all done)` |
| `ship` | `.claude/commands/loa.md:69` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `\| complete \| /deploy-production \| /ship \|` |
| `ship` | `.claude/commands/loa.md:88` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `?? /build ━━●━━━━ /review ─── /ship    │` |
| `ship` | `.claude/commands/loa.md:129` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `??━━━━ /build ─── /review ─── /ship` |
| `ship` | `.claude/commands/loa.md:145` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `/ship     Deploy and archive` |
| `ship` | `.claude/commands/loa.md:178` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `/ship                    Deploy and ` |
| `ship` | `.claude/commands/loa.md:239` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `\| complete \| All sprints done \| /ship \|` |
| `ship` | `.claude/commands/loa.md:262` | orchestrator step | not flagged | /loa invokes it when the user picks the ship option | `\| ship \| Invoke the /ship skill \|` |
| `ship` | `.claude/commands/loa.md:416` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `??━━━━ /build ─── /review ─── /ship        │` |
| `ship` | `.claude/commands/loa.md:440` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `?? /build ━━●━━━━ /review ─── /ship    │` |
| `ship` | `.claude/commands/loa.md:468` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `?? /build ━━●━━━━ /review ─── /ship    │` |
| `ship` | `.claude/commands/loa.md:488` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `ild ━━━━━━━ /review ━━━━━ /ship ●│` |
| `ship` | `.claude/commands/loa.md:495` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `Next: /ship` |
| `ship` | `.claude/skills/deploying-infrastructure/SKILL.md:351` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `\| Aspect \| Manual (/ship) \| Automated (post-merge) \|` |
| `ship` | `.claude/skills/deploying-infrastructure/SKILL.md:353` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `\| Trigger \| User invokes /ship \| GH Actions on merge \|` |
| `run-halt` | `.claude/commands/run-resume.md:56` | advice to the human | FLAGGED | help list, next-step hint, user-facing message or description | `- /run-halt - Stop execution` |
| `run-halt` | `.claude/commands/run-sprint-plan.md:78` | advice to the human | FLAGGED | help list, next-step hint, user-facing message or description | `- /run-halt — Stop execution` |
| `run-halt` | `.claude/commands/run.md:98` | advice to the human | FLAGGED | help list, next-step hint, user-facing message or description | `- /run-halt — Gracefully stop execution` |
| `run-halt` | `.claude/commands/loa.md:197` | advice to the human | FLAGGED | help list, next-step hint, user-facing message or description | `/run-halt                Stop active run` |
| `run-halt` | `.claude/commands/run-status.md:49` | advice to the human | FLAGGED | help list, next-step hint, user-facing message or description | `- /run-halt - Stop execution` |
| `run-halt` | `.claude/skills/autonomous-agent/resources/templates/escalation-report.md:151` | advice to the human | FLAGGED | help list, next-step hint, user-facing message or description | `\| **Abort** \| Stop execution, preserve state \| /run-halt \|` |
| `run-halt` | `.claude/skills/run-mode/resources/halt-resume.md:1` | advice to the human | FLAGGED | help list, next-step hint, user-facing message or description | `# run-mode /run-halt and /run-resume` |
| `run-halt` | `.claude/skills/run-mode/SKILL.md:55` | advice to the human | FLAGGED | help list, next-step hint, user-facing message or description | `/run-halt, and /run-resume behavior. ` |
| `run-halt` | `.claude/skills/run-mode/SKILL.md:224` | advice to the human | FLAGGED | help list, next-step hint, user-facing message or description | `## /run-halt — Graceful Stop` |
| `run-resume` | `.claude/commands/run-sprint-plan.md:79` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `- /run-resume — Continue from halt` |
| `run-resume` | `.claude/commands/run.md:99` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `- /run-resume — Continue from checkpoint` |
| `run-resume` | `.claude/commands/loa.md:198` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `/run-resume              Resume halted run` |
| `run-resume` | `.claude/commands/run-status.md:50` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `- /run-resume - Continue from halt` |
| `run-resume` | `.claude/commands/run-halt.md:57` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `- /run-resume - Continue from halt` |
| `run-resume` | `.claude/commands/simstim.md:462` | orchestrator step | not flagged | /simstim resume invokes it instead of a fresh run | `# Will invoke /run-resume instead of fresh /run sprint-p` |
| `run-resume` | `.claude/skills/simstim-workflow/resources/resume-support.md:132` | orchestrator step | not flagged | simstim resume step 3 invokes it | `3. Invoke /run-resume instead of fresh /run sprint` |
| `run-resume` | `.claude/skills/simstim-workflow/SKILL.md:320` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `= "HALTED": Mark as "incomplete", inform user of /run-resume` |
| `run-resume` | `.claude/skills/autonomous-agent/resources/templates/escalation-report.md:148` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `ume** \| Address findings manually, then resume \| /run-resume \|` |
| `run-resume` | `.claude/skills/autonomous-agent/resources/templates/escalation-report.md:165` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `3. Resume execution: /run-resume` |
| `run-resume` | `.claude/skills/implementing-tasks/SKILL.md:204` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `y there are invisible to cross-session recovery, /run-resume, and beads health checks. If ` |
| `run-resume` | `.claude/skills/run-mode/resources/conditional-procedures.md:70` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `d after the limit resets they should resume with /run-resume.` |
| `run-resume` | `.claude/skills/run-mode/resources/render-templates.md:33` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `:warning: **INCOMPLETE** - Use /run-resume to continue` |
| `run-resume` | `.claude/skills/run-mode/resources/render-templates.md:212` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `/run-resume` |
| `run-resume` | `.claude/skills/run-mode/resources/render-templates.md:238` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `║   /run-resume` |
| `run-resume` | `.claude/skills/run-mode/resources/render-templates.md:241` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `║   /run-resume --reset-ice` |
| `run-resume` | `.claude/skills/run-mode/resources/sprint-plan-mode.md:50` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `halted at $failed_sprint / Reason: $reason / Use /run-resume to continue` |
| `run-resume` | `.claude/skills/run-mode/resources/halt-resume.md:1` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `# run-mode /run-halt and /run-resume` |
| `run-resume` | `.claude/skills/run-mode/resources/halt-resume.md:9` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `already halted. Use /run-resume to continue or clean up with ` |
| `run-resume` | `.claude/skills/run-mode/resources/halt-resume.md:25` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `Use /run-resume to continue from this point.` |
| `run-resume` | `.claude/skills/run-mode/resources/halt-resume.md:63` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `ade changes outside Run Mode. / To force resume: /run-resume --force.` |
| `run-resume` | `.claude/skills/run-mode/resources/halt-resume.md:67` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `continue: /run-resume --reset-ice. To continue with` |
| `run-resume` | `.claude/skills/run-mode/SKILL.md:55` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `/run-halt, and /run-resume behavior. Those commands are ` |
| `run-resume` | `.claude/skills/run-mode/SKILL.md:127` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `the recovery truth — the checkpoint is a hint /run-resume reports.` |
| `run-resume` | `.claude/skills/run-mode/SKILL.md:144` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `BREAKER TRIPPED: $reason" then "Run halted. Use /run-resume --reset-ice to` |
| `run-resume` | `.claude/skills/run-mode/SKILL.md:172` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `[INCOMPLETE] PR and preserves state for /run-resume, and a consolidated completio` |
| `run-resume` | `.claude/skills/run-mode/SKILL.md:230` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `## /run-resume — Continue From Checkpoint` |
| `run-resume` | `.claude/skills/run-mode/SKILL.md:285` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `.run/. Use /run-status to see current state, /run-resume` |
| `run-resume` | `.claude/skills/run-mode/SKILL.md:286` | advice to the human | not flagged | help list, next-step hint, user-facing message or description | `to continue, /run-resume --reset-ice if the circuit br` |

## Out-of-scope references consulted (not lint-scoped)

| Command | Reference | Reading |
|---|---|---|
| `feedback` | `.claude/loa/reference/agent-teams-reference.md:59,278` | teammates allowed to invoke: model path, keeps it unflagged |
| `run-halt` | `.claude/loa/CLAUDE.loa.md:55`, `.claude/scripts/run-preflight.sh:285-286` | command list and remediation text for the human |
| `contribute` | `.claude/protocols/git-safety.md:160`, `.claude/mcp-registry.yaml:63` | descriptive |
| `update-loa`, `mount` | `.claude/scripts/*.sh` echo lines (`loa-status.sh:272`, `check-updates.sh:434`, `detect-drift.sh:75`, `loa-doctor.sh:269,305`) | remediation text for the human |

## DEC rows for the lead (D-8.5, `proposed`, `decided_by: agent`)

One per triaged command, `source` = the command file:

| Command | `source` | Summary |
|---|---|---|
| update-loa | `.claude/commands/update-loa.md` | Leave unflagged this sprint: advice-only, but one troubleshooting line trips the operative lint |
| mount | `.claude/commands/mount.md` | Leave unflagged this sprint: advice-only, but seven error-message lines trip the operative lint |
| contribute | `.claude/commands/contribute.md` | Flag: the one reference is advice and the command opens an upstream PR |
| feedback | `.claude/commands/feedback.md` | Leave unflagged: the agent-teams reference allows teammates to invoke it |
| deploy-production | `.claude/commands/deploy-production.md` | Leave unflagged: /ship and the autonomous agent execute it |
| archive-cycle | `.claude/commands/archive-cycle.md` | Leave unflagged: /ship executes it and /loa invokes it after confirmation |
| ship | `.claude/commands/ship.md` | Leave unflagged: /loa invokes it from its menu |
| run-halt | `.claude/commands/run-halt.md` | Flag: every reference is advice; the circuit breaker halts without it |
| run-resume | `.claude/commands/run-resume.md` | Leave unflagged: /simstim resume invokes it |
