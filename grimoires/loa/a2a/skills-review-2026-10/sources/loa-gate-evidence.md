# Loa build-gate evidence: mechanical vs prompted (implement → review → audit)

Source: repo `0xHoneyJar/loa` at `main` 76e7650b (v2.0.0-rc.3), read 2026-10-12. Read-only sweep; no scripts executed.
Legend: **MECH** = a hook, script exit code, or CI job decides. **MECH-ASK** = a hook that prompts the human but never blocks. **PROMPTED** = SKILL/command prose the model is asked to follow (including "MUST run script X", where the script is mechanical but its *invocation* is prompted).

Key wiring fact: the live hook inventory is `.claude/settings.json` (PreToolUse `Write|Edit|MultiEdit|NotebookEdit` chain = team-role-guard-write, spiral-dispatch-guard, zone-write-guard, implement-gate, notes-size-guard; a second entry = adversarial-review-gate; PostToolUse = write-mutation-logger, karpathy-surgical-diff-check). The registration table in `.claude/loa/reference/hooks-reference.md:170-188` omits zone-write-guard, spiral-dispatch-guard, adversarial-review-gate and karpathy-surgical-diff-check, so it is not a complete fence inventory.

---

## G1. Test-first

Where stated:
- `/bug` only: `.claude/commands/bug.md:7` and `:67` "Test-first is non-negotiable."; `.claude/skills/bug-triaging/SKILL.md:74` same; `.claude/skills/bug-triaging/index.yaml:17`.
- The bug micro-sprint template makes it the first task: `.claude/skills/bug-triaging/resources/templates/micro-sprint.md:23-31` "#### Task 1: Write Failing Test [G-5] … Verify test fails with current code"; AC `:29` "Test fails with current code, proving the bug exists"; `:45` "Failing test proves the fix".
- `.claude/skills/run-mode/resources/bug-run-mode.md:12` "IMPLEMENT /implement sprint-bug-{N} (test-first: write test → fix → verify)".
- General principle (not a rule for /implement): `.claude/protocols/karpathy-principles.md:86` "\"fix the bug\" → \"write a failing repro test first, then make it pass\"; \"refactor X\" → \"tests green before AND after\"". `:88-91`: non-trivial logic "MUST leave at least one runnable check that fails if the logic breaks — satisfied by the sprint's acceptance-criteria tests."

What /implement actually says (tests alongside, not first):
- `.claude/skills/implementing-tasks/SKILL.md:231` "implement to spec following those patterns … with tests for the happy path, error conditions and edge cases".
- `:151` (generated constraint) "DO NOT skip tests—comprehensive test coverage is non-negotiable".
- `:162` "**Success** = every acceptance criterion met, tests pass, report written."
- `:177` run the CI fast checks before handoff; "A format or type failure is a failing test."
- `:241` red flag: "no tests for new code".

Red-green-refactor: **not named anywhere** in `.claude/skills`, `.claude/commands`, `.claude/protocols`, `.claude/rules`, `CLAUDE.loa.md` (grep for `red-green|red/green|TDD` returned zero hits). No "refactor" step exists in any implement loop; Karpathy "surgical" actively discourages unrequested refactors (`karpathy-principles.md:76` "don't refactor the unbroken").

Enforcement: **PROMPTED only.**
- No hook checks that a test exists or failed before source was edited. `implement-gate.sh` keys on path + run state, never on tests (G2).
- `validate-ac-verification.sh` header `:10-14` is explicit: it "does NOT verify … that tests pass — it prevents ABSENT evidence, not FABRICATED evidence."
- Review checks tests exist and assertions are meaningful (`reviewing-code/SKILL.md:215` "read every modified file and its tests (verify the assertions)"; `reviewing-code/resources/REFERENCE.md:30-37` Testing checklist), but nothing asks the reviewer to verify the bug test *failed before the fix*. The only "failed first" signal is the micro-sprint AC text, which reaches review only as an AC row the implementer self-reports in `## AC Verification`.
- No verdict rule references tests. The one-way rule is severity-count only.

## G2. The implement gate

File: `.claude/hooks/compliance/implement-gate.sh` (451 lines), wired in `.claude/settings.json` PreToolUse `Write|Edit|MultiEdit|NotebookEdit` via `hook-guard.sh`.
- Tools intercepted: Write, Edit, MultiEdit, NotebookEdit; path from `tool_input.file_path // tool_input.notebook_path` (`:170`). Not Bash.
- App Zone: `:293` `src/*|lib/*|app/*|*/src/*|*/lib/*|*/app/*` at any depth under the root, matched on a lowercased physical OR logical canonical path (`:252-259`).
- Decisions (`hooks-reference.md:219-228`):
  - allow = silent exit 0 (`:299-301` non-App-Zone; `:442-444` active run).
  - ask = `hookSpecificOutput.permissionDecision: "ask"` (`:449`) for an App-Zone write with no fresh run state; also on unparsable payload/jq missing (`:162-165`), un-canonicalisable path (`:246-249`), and writes to its own trust inputs `.run/state.json|sprint-plan-state.json|simstim-state.json|platform-features.json|audit.jsonl|.loa.config.yaml` (`:272-280`).
  - **Never deny.** `hooks-reference.md:187` "ADVISORY: `ask` … never blocks"; script `:446` "No active implementation detected — ADVISORY ask".
- How it knows /implement is active: **state files, not the skill.** `check_implementation_active` `:390-437`: `.run/sprint-plan-state.json` `state==RUNNING` + `plan_id`; `.run/simstim-state.json` `phase==implementation`; `.run/state.json` `state==RUNNING`; each needs `last_activity` within 24 h either side (`:377-388`). So the gate detects **`/run` / `/simstim`**, not `/implement` or `/bug`. It never reads `.run/bugs/*/state.json`, so interactive `/bug` → `/implement sprint-bug-N` also asks, despite the header at `:5-6` saying "within an active /implement or /bug".
- Authoritative mode: opt-in `implement_gate.mode: authoritative` (`:310-314`), tighten-only: a model-authored `tool_input.active_skill` can add an ask but never grant an allow (`:337-350`). Repo config leaves it unset (heuristic).
- Documented gaps (`hooks-reference.md:232`): "writes through the Bash tool are not seen (the C-PROC-001 fence gap). The heuristic trusts `.run/` files a Bash command can write (bead bd-taee). A direct `/implement` without `/run` leaves no state file, so its writes ask." Also restated in `CLAUDE.loa.md:74` "Bash-path App-Zone writes remain review-territory (accepted fence gap…)". Other gaps: only `src/lib/app` count, so any other code directory (e.g. `pkg/`, `cmd/`, root files, `tests/`) is unguarded; any fresh RUNNING state allows *every* App-Zone write from any skill.
- Cycle-126 changes (CHANGELOG.md, `[2.0.0-rc.3]` section):
  - `:54` "`implement-gate.sh` emitted a top-level `{\"decision\":\"ask\"}`, a shape the PreToolUse contract does not define … so the App-Zone ask was validated away and \"fail-asks\" was prose rather than mechanics". The fix emits `hookSpecificOutput.permissionDecision: ask`. The gate's ask was therefore dead from cycle-050 (`CHANGELOG.md:1373` "ADVISORY compliance hook prototype") until rc.3.
  - `:29` D-4.4: the payload "carries no harness-set skill field … `tool_input.active_skill` is evidence, never a switch"; nothing in `.run/` selects authoritative mode any more.
  - `:33` authoritative mode can only tighten.
  - `:56-57` canonical-path classification (the textual prefix test was bypassable via `/proc/self/cwd/src/x`, `//root/src/x`, `..`, symlinked root), physical+logical forms, lowercase, trust-input guard.
  - `:58` the root no longer follows `$(pwd)`. Before, "from a subdirectory … an App-Zone or trust-input Write was allowed silently"; every heuristic state file must be fresh.
  - `:59` the freshness bound covers both directions (future-dated is stale).

## G3. What makes review/audit non-bypassable

| Mechanism | What it does | Type | Cite |
|---|---|---|---|
| LOA-VERDICT trailer | Last line of `engineer-feedback.md` / `auditor-sprint-feedback.md`; JSON with verdict + severity counts | Format PROMPTED; validated by script | `reviewing-code/SKILL.md:247-253`; `auditing-security/SKILL.md:238-242` |
| `verdict-derive.sh` | Validates trailer present/last line, prose↔trailer agreement ("All good" / "APPROVED - LET'S FUCKING GO"), one-way rule `critical+high>0 ⇒ CHANGES_REQUIRED`, no `## Changes Required/Findings/Issues` on approved file, `excluded`/`excluded_confirmed` parity, rejected-dissent triage | MECH as a script (exit 0/1/2). Invocation PROMPTED in the skills (`reviewing-code/SKILL.md:255-257` "MUST self-check"); consumed mechanically by `golden-path.sh:108,146-192` and by the run loop | `.claude/scripts/verdict-derive.sh:7-28` |
| One-way rule | Severity counts, not reviewer judgement, force CHANGES_REQUIRED; zero does not force APPROVED | MECH (script) over model-authored counts | `verdict-derive.sh:12-13`; `auditing-security/SKILL.md:226`. Counts are self-reported by the reviewing model. The audit severity table (`:217-224`) is checked against the trailer, but nothing checks it against reality |
| `/audit-sprint` precondition | `engineer-feedback.md` must contain "All good" | PROMPTED (command frontmatter `pre_flight` + skill Phase 0) | `commands/audit-sprint.md:70-73`; `auditing-security/SKILL.md:166` |
| COMPLETED marker gate | `adversarial-review-gate.sh` exits 2 on a Write/Edit/MultiEdit/NotebookEdit to `*/COMPLETED` when flatline review/audit is enabled and `adversarial-review.json` / `adversarial-audit.json` lacks `.metadata.type` + `.metadata.model` | **MECH block** (exit 2), but narrow. It checks that the dissent artefact *exists and is well-formed*, **not** that the audit verdict is APPROVED. Bash `touch …/COMPLETED` is not intercepted. Override `LOA_ADVERSARIAL_REVIEW_ENFORCE=false`; fail-open if yq missing | `.claude/hooks/safety/adversarial-review-gate.sh:5-24, 202-214`; skills `reviewing-code/SKILL.md:223-224`, `auditing-security/SKILL.md:182` |
| AC Verification | `validate-ac-verification.sh` checks every sprint AC appears verbatim in `## AC Verification`, `✓ Met` rows carry `file:line` | Script MECH, invocation PROMPTED (`implementing-tasks/SKILL.md:170-172` "MUST, immediately before writing a COMPLETED marker"). Not wired to any hook (grep: no hook/script caller). Header `:10-14` says it is honest about absent vs fabricated evidence | `validate-ac-verification.sh:3-25` |
| Review auto-fail | Missing/vague `## AC Verification` ⇒ automatic CHANGES_REQUIRED | PROMPTED | `reviewing-code/SKILL.md:237-241` |
| Run-mode loop | `/review-sprint` → `verdict-derive --gate review` must exit 0 with APPROVED, else loop back; same for audit | PROMPTED (the loop is SKILL pseudocode the model executes) | `run-mode/SKILL.md:100-122` |
| Circuit breaker | same-issue 3 / no-progress 5 / cycles 20 / 8 h; trips to HALTED | PROMPTED (the model runs the jq checks and writes `.run/circuit-breaker.json` by hand) | `run-mode/SKILL.md:129-159` |
| Stop guard | `run-mode-stop-guard.sh` injects a reminder when a run is active at Stop | MECH (reminder, not a review gate) | `hooks-reference.md:105-113` |
| ICE | `run-mode-ice.sh` blocks push to protected branches, merge and branch delete; draft PRs only | MECH *inside the wrapper*, but the wrapper is called by prompt ("All git operations MUST go through"). A raw `git push origin main` is not fenced by block-destructive-bash, which covers force push and tags only | `run-mode/SKILL.md:236-244`; `run-mode-ice.sh:4-22`; `hooks-reference.md:238-240` |
| Bridgebuilder | Post-PR multi-model review (run-bridge, post-pr-validation) | PROMPTED/optional (config-gated; bridgebuilder-review skill) | `run-bridge/SKILL.md:1-3, 155-156` |
| Two-voice dissent | `adversarial-review.sh --type review|audit`, two voices by default (`companion_voice`) | Script MECH when run; the run itself is enforced only by the COMPLETED gate's artefact check above (presence of `.metadata.model`, not two voices) | `reviewing-code/SKILL.md:221-227`; `auditing-security/SKILL.md:180-184` |
| golden-path | `/loa` navigation refuses to advance on inconsistent trailer or `excluded`≠`excluded_confirmed` | MECH (navigation only; does not block writes) | `golden-path.sh:108-111, 182`; `auditing-security/SKILL.md:242` |
| CI | No workflow inspects a2a feedback files (they are gitignored). CI runs the bats suites that test the gates (`tests/unit/implement-gate.bats`, `compliance-hook.bats`, `verdict-derive.bats`, `validate-ac-verification.bats`, `skill-capabilities*.bats`) | MECH for the gates' own regressions only | `.github/workflows/bats-tests.yml` |

Net: the only **hard block** on the review→audit→COMPLETED path is adversarial-review-gate. It proves a dissent artefact exists, not that the sprint passed. Verdict consistency is mechanically *checkable* (verdict-derive) and mechanically *consumed* by golden-path, but the gate sequence is driven by prose.

## G4. disallowed-tools

All `disallowed-tools` uses (grep over `.claude/skills/*/SKILL.md`):
- `reviewing-code/SKILL.md:8-9` → `NotebookEdit` only. `:7` "# Write/Edit: State-Zone feedback/checkmarks only (C-PROC-001, by zones)."
- `auditing-security/SKILL.md:8-9` → `NotebookEdit` only. `:7` "# Write/Edit: State-Zone feedback/COMPLETED markers only (C-PROC-001, by zones)."
- `red-teaming/SKILL.md:10-14` and `bridgebuilder-review/SKILL.md:10-14` → `NotebookEdit`, `Bash(git add *)`, `Bash(git commit *)`, `Bash(git push *)`.

**No skill in the repo strips Write or Edit.** The rule table in `.claude/rules/skill-invariants.md:38-42` defines a "Pure-review (`write_files: false`)" class that gets `Write, Edit, NotebookEdit`. The four `role: review` + `write_files: false` skills (eval-running, flatline-knowledge, rtfm-testing, validating-construct-manifest) declare **no** `disallowed-tools`. They rely on a narrow `allowed-tools` list instead (e.g. `flatline-knowledge/SKILL.md:5` "allowed-tools: Read, Grep, Glob"). [ASSUMPTION, verify against Claude Code docs: `allowed-tools` pre-approves tools and does not remove others, so this is not the same barrier as `disallowed-tools`.]

The two review skills that matter (/review-sprint, /audit-sprint) **keep Write+Edit by design**. App-code prevention for them is "by zones": frontmatter `zones.app.permission: read` (`reviewing-code/SKILL.md:52-54`, `auditing-security/SKILL.md:52-54`) plus prose (`reviewing-code/SKILL.md:134` "app zone … = **Read-only**"). The only runtime check on an App-Zone write from a review skill is implement-gate's *ask*, and it **allows** when a `/run` state file is RUNNING and fresh, which is exactly when review runs inside `/run`. `skill-invariants.md:51-52` says it plainly: "`disallowed-tools` is tool-granular, not path-granular; it cannot express \"no `src/` writes but yes `grimoires/` writes\"."

Lint: `validate-skill-capabilities.sh:90` `REVIEW_WRITE_EXCEPTIONS=(red-teaming bridgebuilder-review spiraling autonomous-agent run-bridge run-mode reviewing-code auditing-security)`. `:596-617` WARNs (never errors) when a role:review skill has write_files:true, is not an exception, and does not disallow Write: "C-PROC-001 is enforced only by prose". The agent-type invariant (#553) at `:619+` errors. Run by `tests/unit/skill-capabilities.bats` in CI.

The real mechanical "no app code from review" barrier is the **Bash allowlist** (`reviewing-code/SKILL.md:6` `allowed-tools` lists only `git diff/log`, verdict-derive, adversarial-review, qmd, guardrails, `br sync/comments/label`; `capabilities.execute_commands … deny_raw_shell: true` `:15-37`). The same assumption caveat applies: whether `allowed-tools` restricts or only pre-approves Bash is a harness question. `deny_raw_shell` is linted by validate-skill-capabilities; no hook enforces it.

## G5. Two-axis review (spec + standards)

Yes, both axes exist, in prose:
- **Spec axis**: `reviewing-code/SKILL.md:215` "check the acceptance criteria"; `:235` approve only with "a complete `## AC Verification` walkthrough (every AC from `sprint.md` verbatim)"; `:237-241` automatic CHANGES_REQUIRED on a missing AC section, unsplit `✗ Not met`, undocumented deferral, or vague evidence; `:231` previous-feedback verification; `REFERENCE.md:11-15` Completeness checklist. Context reads PRD/SDD/sprint (`:206-210`). The mechanical half is `validate-ac-verification.sh`, which the *implementer* is prompted to run.
- **Standards axis**: `:215` "readability and conventions, SDD alignment, security … and performance"; `:217` Karpathy flags `SIMPLICITY:`/`SURGICAL:`/`GOAL-DRIVEN:`; `:219` Fast-Gate Parity (formatter + type checker); `:285` Complexity Review blocks approval for a ">50 lines function", "nesting deeper than 3", ">3 duplicate code blocks", "circular dependencies"; `REFERENCE.md:23-29` Code Quality, `:55-61` Architecture ("Follows patterns from SDD", "No tight coupling", "Separation of concerns"), `:89-95` Architecture Red Flags; `:269` documentation verification; `:275` subagent reports (architecture-validator, test-adequacy-reviewer).
- **Plus a third pass** Pocock lacks: cross-model adversarial dissent (`:221-227`) and a separate security audit skill (`auditing-security` five categories `:188`).
- Not split into two named, independent passes. Both axes are one reviewer's checklist. Findings are bucketed by severity, not by axis.

## G6. Run-mode loop

- State machine `run-mode/SKILL.md:60-63` "READY → JACK_IN → RUNNING → COMPLETE/HALTED → JACKED_OUT".
- Loop `:100-122`: `while circuit_breaker.state == CLOSED:` /implement → commit → /review-sprint → `verdict-derive --gate review` must be APPROVED else `record_cycle(findings)` and loop → /audit-sprint → same with `--gate audit` → optional RED_TEAM_CODE → COMPLETED ⇒ break → draft PR.
- Max rounds: cycle limit **20** default (`:137`; `/run --max-cycles`, `commands/run.md:13-16`); timeout **8 h** (`:138`).
- Repeated CHANGES_REQUIRED: same-issue trigger **3** (`:135`). The hash is `{verdict,counts}` from verdict-derive (`:149-155`), so identical counts on different findings collide and trip sooner ("the loud direction"). No-progress **5** (`:136`). Trip ⇒ breaker OPEN, state HALTED, "Use `/run-resume --reset-ice`" (`:140-145`).
- Bug runs are tighter: same-issue 3, no-progress 5, cycles **10**, timeout **2 h**, in `.run/bugs/{id}/circuit-breaker.json` (`resources/bug-run-mode.md:33-43`). High-risk area HALTs without `--allow-high` (`:27-28`).
- Checkpoints: `run-checkpoint.sh write --sprint … --phase REVIEW|AUDIT` (`:106,112,125-127`); per-task checkpoint on each `br close` (`implementing-tasks/SKILL.md:213`). "Beads stay the recovery truth — the checkpoint is a hint" (`run-mode/SKILL.md:127`).
- Resume: `/run-resume` validates state + branch divergence, resumes at the recorded phase, `--reset-ice` clears the breaker (`:230-234`). Post-compaction: `CLAUDE.loa.md` Run Mode Recovery (RUNNING ⇒ resume `sprints.current`).
- Schemas: `run-mode/resources/state-schemas.md:5-44` (state.json), `:46-59` (circuit-breaker.json), `:75-104` (sprint-plan-state.json v2 with `checkpoint`), `:106-143` (bug state + allowed transitions), `:145-170` config.
- Mechanical vs prompted: the loop, the breaker arithmetic and the state writes are **PROMPTED** (the model runs `jq` per SKILL). Mechanical pieces are `run-preflight.sh --unattended` (P1–P8, `:73-77`), `run-checkpoint.sh` (atomic, locked), `run-mode-ice.sh`, `danger-level-enforcer.sh` (`:40-47`), `verdict-derive.sh`, and the Stop guard. "The human checkpoint is PR review, not phase gates." (`:276-277`).

## G7. Disciplined diagnosis loop

`/bug` is **triage-to-handoff**, not a diagnose→fix loop:
- Phase 0 deps (`bug-triaging/SKILL.md:76-98`). Phase 1 eligibility scoring and disqualifiers (`:103-196`): failing test +2, repro +2, trace +1, prod log +1, regression +1; score <2 REJECT; any feature disqualifier REJECT. Phase 2 interview for repro/expected/actual/severity, then `reproduction_strength` strong|weak|manual_only (`:200-246`). Phase 3 codebase analysis (`:251-283`; `resources/analysis-steps.md:7-54`: parse stack trace → keyword grep → import chain 1-2 levels → test discovery → runner detection (HALT if none) → test_type → high-risk keywords) yields suspected files with confidence and `fix_hints`. Phase 4 micro-sprint, state, ledger, handoff (`:287-438`).
- `:257` compresses it to "reproduce → isolate → identify suspected files → assess risk class".
- **Absent**: an explicit hypothesise → instrument (logging/debugger/bisect) → falsify loop. grep finds no `hypothes`, `instrument` or `bisect` in bug-triaging or implementing-tasks. Triage does not execute the repro (signal table `:140` "Run the test" is the eligibility check, not a red-test confirmation). Root cause appears only as an AC ("Fix addresses root cause (not just symptoms)", `micro-sprint.md:41,47`).
- The failing test is written later inside `/implement` (micro-sprint Task 1). Its failure-before-fix is self-reported (G1).
- Adjacent: `continuous-learning` triggers on "Non-Apparent Root Cause" (`continuous-learning/SKILL.md:73`) as learning capture after the fact; known-failures ledger "Reading guide" prevents re-trying dead ends (project CLAUDE.md).

## G8. Architecture-deepening

- grep `deep module|module depth|architecture debt` → **zero hits**. `refactor` hits are incidental (enhancing-prompts classifier, bug fix-hint `action` enum `bug-triaging/SKILL.md:276`, eval re-baseline).
- Loa's stance is the opposite of "invest in design every day": `karpathy-principles.md:76` "never \"improve\" adjacent code … don't refactor the unbroken … \"while I'm here\" changes go in the PR description, not the diff". `karpathy-surgical-diff-check.sh:5-10` (PostToolUse, warn-only) flags a session diff over `diff_lines_per_task` (default 100).
- Nearest equivalents (none is a "scan for deepening opportunities" skill):
  - `/architect` (`designing-architecture`) writes an SDD from a PRD, for up-front design.
  - `/ride` (`riding-codebase`) does code→docs drift analysis.
  - `/audit` codebase mode has an Architecture category (`auditing-security/SKILL.md:188`).
  - Review complexity/architecture checklist (`reviewing-code/SKILL.md:285`; `REFERENCE.md:55-61, 89-95, 265` "Suggested Refactoring" diagram section).
  - `run-bridge` "Autonomous excellence loop" (`run-bridge/SKILL.md:3`). Bridgebuilder "reviews **quality and architecture** (is the design evolving well?)" (`:156`), and grant "MAY propose alternative approaches that challenge existing architecture" (`bridgebuilder-review/SKILL.md:45`).
  - `red-team-code-vs-design.sh` checks code-vs-SDD compliance (`run-bridge/SKILL.md:155`).

## G9. PR body / retro

- **PR bodies**: templated, generated by run mode. `run-mode/resources/render-templates.md:38-75` completion PR (Summary, Sprint Breakdown, Commits by Sprint, Flatline Review Summary, Test Results, Context Cleanup); `:5-36` INCOMPLETE PR; `:130-150` auto-mode PR; `:248-271` bug PR with "Confidence Signals" (reproduction strength, test type, files/lines changed, risk) and "Status: READY FOR HUMAN REVIEW". `completion-modes.md:40` deleted-files tree. ICE forces draft PRs (`run-mode/SKILL.md:241`). `/contribute` (`commands/contribute.md:1-5`) makes a "standards-compliant PR" upstream with secrets scan + DCO. No standalone `/pr` skill for hand-authored PRs.
- **Retro**: `/retrospective` (`commands/retrospective.md:3-5` "extract reusable skills from debugging discoveries"; 6-step flow `:19-65` writes `grimoires/loa/skills-pending/{name}/SKILL.md` and runs upstream detection); `/retrospective --batch` cross-session patterns (`retrospective-batch.md:1-11`); `/compound` end-of-cycle learning extraction (`compound.md:1-3`); `/propose-learning` files upstream issues with gates "score ≥ 70, applications ≥ 3, success rate ≥ 80%" (`propose-learning.md:13-18`); invisible retrospective postlude in every skill when `invisible_retrospective.enabled` (`implementing-tasks/SKILL.md:244-252`); `/feedback` files GitHub issues about the Loa experience. The known-failures ledger (`kf-write-lib.sh recur/attempt/new`, project CLAUDE.md) is the closest to "improve the agent environment". Loa's retro output is **skills/learnings and KF entries**, not suggestions to change hooks/settings/CLAUDE.md directly (System Zone is never-edit).

## G10. Prose-only rules in CLAUDE.loa.md NEVER/ALWAYS tables

| Row (CLAUDE.loa.md line) | Mechanical backing | Verdict |
|---|---|---|
| L74 NEVER app code outside /implement | implement-gate ASK on Write/Edit/MultiEdit/NotebookEdit to src/lib/app with no fresh `/run` state; Bash writes unseen; trusts Bash-writable `.run/` | **Partial (MECH-ASK, never blocks)** |
| L75 NEVER TaskCreate for sprint tracking | none (no hook references TaskCreate) | **Prose-only** |
| L76 NEVER skip /review-sprint + /audit-sprint | adversarial-review-gate blocks a Write-tool COMPLETED without dissent artefacts (flatline enabled only; env override; Bash bypass; does not check verdict) | **Partial** |
| L77 NEVER /bug for feature work | none. Eligibility scoring is model-executed prose; `validate-artifact.sh --type bug-triage` checks triage.md shape (prompted) | **Prose-only** |
| L78 NEVER implement directly under /spiraling | `spiral-dispatch-guard.sh` exit 2 on Write/Edit while the spiral sentinel exists and the harness is not dispatched (fail-open; Bash unseen) | **MECH (block)** |
| L86 ALWAYS route via /run or /bug | same as L74 (the gate actually rewards `/run`, and asks on interactive `/bug`→`/implement`) | **Partial (ask)** |
| L87 ALWAYS create beads from sprint plan | none (run-preflight P7 checks beads health, not task creation) | **Prose-only** |
| L88 ALWAYS full implement→review→audit | same as L76 | **Partial** |
| L89 ALWAYS validate bug eligibility | none | **Prose-only** |
| L90 ALWAYS Read before Write | enforced by Claude Code's own Write tool, not by Loa | **Harness (not Loa)** |
| L116 ALWAYS post-merge-orchestrator | invoked by `.github/workflows/post-merge.yml:150-155`; ad-hoc local runs unfenced | **CI-mechanical on merge; prose locally** |
| L117 NEVER manual tags | `block-destructive-bash.sh` FR-MERGE-2 (override `LOA_ALLOW_GIT_TAG=1`) | **MECH (block)** |
| L126 planning skills lead-only | `team-skill-guard.sh` LEAD_ONLY_SKILLS when `LOA_TEAM_MEMBER` set (fail-open) | **MECH (teams mode only)** |
| L127 beads via lead | `team-role-guard.sh` blocks `br` for teammates | **MECH (teams mode only)** |
| L128 `.run/` lead-only | `team-role-guard.sh` / `-write.sh` | **MECH (teams mode only)** |
| L129 git via lead | `team-role-guard.sh` blocks commit/push | **MECH (teams mode only)** |
| L130 no `.claude/` edits | `team-role-guard-write.sh` (teams); `zone-write-guard.sh` exit 2 (all sessions, marker/env bypass); FR-SZ2 for Bash writes | **MECH** |

Karpathy section (CLAUDE.loa.md "Every code-touching turn"): Goal-Driven Gate in `/implement` is prose with an AskUserQuestion (`implementing-tasks/SKILL.md:189-197`); `karpathy-surgical-diff-check.sh` is PostToolUse warn-only ("Non-blocking by design — returns 0 regardless", `:10`). Simplicity/think-first are prose plus review-time tags.

## Side observations (not asked, load-bearing for the comparison)

- `implementing-tasks/SKILL.md:26-28` frontmatter says `app … permission: read`, while `:76` prose says the app zone is "**Read/Write**" for this skill. The zones block is metadata, not a runtime control.
- `commands/implement.md:13,49`, `review-sprint.md:12,49` and `audit-sprint.md:43` validate `^sprint-[0-9]+$`. The `/bug` handoff is `/implement sprint-bug-N` (`bug-triaging/SKILL.md:432`), which that pattern would reject if the pre_flight block were applied literally. Who interprets command `pre_flight` was not traced.
- Repo config: `flatline_protocol.code_review.enabled: true`, `security_audit.enabled: true`, `run_mode.enabled: true`, `implement_gate.mode` unset (heuristic).
