# Sprint 3 implementation report — cycle-124 "model-generation floor" (global sprint-237)

Sprint goal (sprint.md): the always-loaded prompt surface fits the byte budgets with no measured quality loss, review prompts are coverage-first with the mechanical filter doing the filtering, and effort defaults reach the dispatched paths — gated by byte-identical parity goldens and a deterministic A/B over a 10-PR corpus.

This report covers the range `da3bd07f..HEAD` on `feature/cycle-124-model-generation-floor`. Sprint-scoped artifacts live under `grimoires/loa/a2a/sprint-237/` (gitignored a2a; force-added at close): `prompt-audit/` (49 unit reports, proposals, patches, briefs, method, keep list) and `ab/` (arm A / arm B results, baselines, compare output).

## Commits (one per unit or batch, no squash — SDD §7)

| Commit | Task | Content |
|---|---|---|
| `72bdb7d2` | 3.2 | `evals/harness/execute-agent.sh`, `run-eval.sh` agent hook + `--trials`, 10-PR review corpus (`build-review-corpus.sh`, hidden manifests, `SHA256SUMS`), implement-discipline fixtures, three graders, suites, `compare.sh` freshness + `--ab` (`compare-ab.py`), four bats |
| `00a6ce1e` | 3.1 | `tools/check-prompt-budget.sh`, `tools/prompt-keeplist.txt`, `protocol-refs.allowlist`, seven bats gates, `check-prompt-budget.yml`, `no-backup-files.yml` regex, the 10 `*.constraint-XXXXXX` twins deleted |
| `12a83a87` | 3.4 + 3.5 | coverage-first review prompts, `verdict-derive.sh` `excluded` / `excluded_confirmed`, `golden-path.sh` surfaces the count, `model-adapter.sh resolve_effort()`, Flatline mode → effort, dead config block removed, `effort-dispatch.bats`, `verdict-observations-section.bats` |
| `a1337ed4`, `4a95512d` | late Sprint 2 input | reviewer slices A/B/C folded in (case-insensitive trailer detection, guarded ledger walks, bounded repair loop, strict enforced parse, `_effective_stop_reason`, anchored headless rejection, float cache rates, KF-004 correction) |
| `c6ac82f4` | 3.6 (lead) | `CLAUDE.loa.md` 22,005 → 10,222 B kernel, three protocols archived, registry/include history tokens removed, `prompt-auditor` agent |
| `cfce9f9d` | 3.7 | `reminder-hooks-one-shot.bats` |
| `105629d2` | 3.6 batch 2 | six largest skills ≤ 16,384 B, eight protocols, `prompt-auditor-io` agent, contracts test ≥1 validator invocation, constraints golden tables regenerated |
| `d3331091` | 3.6 batch 3 | grounding-enforcement, recommended-hooks; four small protocols lead-authored |
| `036b0608` | 3.6 batch 4 | beads-integration, five personas, doc-lock phrases kept, ledger concurrency test follows the guarded jq filter |
| `5c69a0ec` | late input | Sprint 1 fallout: `tools/ceiling-probe.py` (cycle-109 fixture probe) restored, live probe → `tools/ceiling-probe-live.py`; bug-881 tests follow the catalog; danger-level audited |
| `846b9004` | 3.6 batch 5 | rtfm-testing, bug-triaging, translating-for-executives (lead-authored) |
| `164f08bf` | 3.6 batch 6 | planning-sprints, beads-preflight (fence-blocked line spliced by the lead) |
| `bb160546` | 3.6 batch 7 | change-validation, safe-file-creation, subagent-invocation (lead-authored) |
| `5153856b` | 3.6 batch 8 | feedback-loops, git-safety (lead-authored) |
| `a25273f8` | 3.6 batch 9 | simstim-workflow, input-guardrails |
| `635bb277` | 3.6 batch 10 | riding-codebase, ride-translation, visual-communication — protocols under the 200,000 B fail line |
| `7e8b8345` | 3.6 batch 11 | autonomous-agent 28,499 → 16,248 B; `### Coverage` heading alignment; `checksums.json` regenerated — PB-9 and PR-1 green |
| `534ff4d2` | 3.3 | arm-A baselines (`evals/baselines/{review-recall,audit-recall,implement-discipline}.baseline.yaml`, `prompt_tree_sha 4e38de26`, `captured_at_commit 72bdb7d2`, `executor_model claude-sonnet-5`, corpus sha pinned); `compare.sh` first-row reads slurp JSONL (BF-9 extended) |
| `734f3837` | 3.6 (lead restore) | simstim-workflow keeps the literal Flatline invocations `simstim-flatline-mode.bats` reads; `checksums.json` regenerated |
| `f19dd6d0` | 3.8 (iteration) | reviewing-code: cite the failing statement as a range; `high` needs a nameable failing input — the one post-A/B iteration, re-measured as arm B2 |
| (a2a, force-added) | 3.3 / 3.8 / 3.9 | `ab/arm-a`, `ab/arm-b`, `ab/arm-b2`, `ab/compare/*.{json,txt}`, `prompt-audit/` (49 reports, proposals, patches, briefs, method, keep list), this report |

## AC Verification

### AC-8.1 budget tool and CI gate
- **Status**: ✓ Met
- **Evidence**: `tools/check-prompt-budget.sh:53` (`SKILL_LIMIT, LOA_LIMIT, PROTO_FAIL, PROTO_WARN = 16384, 10240, 200000, 143360`; `--json`, `--root`, `--quiet`; unconditional `resources/*.md` reads charged per the imperative/guard regexes documented at `:14-19`); `tests/unit/prompt-budget.bats` PB-1..PB-9 (fixture tree fails at 16,385 and passes at 16,384; PB-9 is the live gate); `.github/workflows/check-prompt-budget.yml` runs the live gate plus the `tests/fixtures/prompt-budget/{over,under}` sentinel controls. Live numbers at close (`tools/check-prompt-budget.sh --json` → `ok: true`): `CLAUDE.loa.md` 10,222 B; protocols 199,313 B total (fail 200,000; warn 143,360 — warn stays on, see the residual table); largest skill 16,359 B (reviewing-code); no resource charged.

### AC-8.2 no history in rule text; MUST/NEVER/ALWAYS name their mechanism
- **Status**: ✓ Met
- **Evidence**: `tests/unit/no-history-in-rule-text.bats` NH-1/NH-2/NH-3 green on the audited set (CLAUDE.loa.md, 13 skills, 27 protocols, 5 personas) with the KF-pointer exemption (`grimoires/loa/known-failures.md` / `kf-write-lib.sh` lines) and the `## Provenance` footer / `<!-- provenance: -->` comment / backticked-path exemptions; each unit report's MUST/NEVER/ALWAYS section names the hook, validator or gate kept beside the surviving line (e.g. `adversarial-review-gate.sh` in reviewing-code / auditing-security Phase 2.5 / 1C, `validate-ac-verification.sh` in implementing-tasks, `verdict-derive.sh` self-check in both review skills).

### AC-8.3 keep list, archived reports, byte-identical generated sections, resolving protocol references, validators green, 32 goldens, reminder-hook fence
- **Status**: ✓ Met
- **Evidence**: `tools/prompt-keeplist.txt` (K-01..K-45) committed in `00a6ce1e` before the first audit diff; `tests/unit/prompt-audit-keeplist.bats` green after every batch; 49 reports under `grimoires/loa/a2a/sprint-237/prompt-audit/units/*.report.md` with the spliced proposals and `*.patch` files one level up; `generate-constraints.sh --dry-run` and `generate-skill-includes.sh --check` report no drift after the audit (the lead gate splices every `@constraint-generated` / `@skill-include` region back from the original before applying); `protocol-refs-resolve.bats` PR-1/PR-2/PR-3 green after `.claude/checksums.json` was regenerated with mount-loa's algorithm (3,254 files); `validate-skill-capabilities.sh` 36/36, `lint-invariants.sh` 10 pass / 2 warn / 0 error, `skill-capabilities.bats`, `skill-includes.bats`, `validation-skill-contracts.bats` green; `grimoires/loa/perf/skill-loop-2026-07-05/golden/capture.sh --verify` → `VERIFY OK: all 32 golden outputs match` (no hook or hook-emitted text touched); `.claude/hooks/*reminder*` unmodified (`git diff 80be4b0f..HEAD -- .claude/hooks` empty for them) and `tests/unit/reminder-hooks-one-shot.bats` green.

### AC-9.1 coverage-first prompts, `excluded` mechanics, effort dispatch
- **Status**: ✓ Met
- **Evidence**: `### Coverage` block in `.claude/skills/reviewing-code/SKILL.md:92`, `auditing-security/SKILL.md` (Phase 2 → 2.5), `flatline-reviewer/persona.md`, `flatline-skeptic/persona.md`; `grep -c '≥3 concerns'` → 0 in all four; `tests/unit/verdict-observations-section.bats` VO-1..VO-11 (Observations items on an APPROVED file consistent; the same items under `## Findings` a violation; a `confidence: low` CRITICAL still forces CHANGES_REQUIRED; `speculative` + `confidence: low` HIGH excluded with `excluded: 1`; a speculative CRITICAL a violation; audit `excluded_confirmed` cross-check via `--review-file`); effort: `.claude/scripts/model-adapter.sh:319` `resolve_effort()` (arg > SKILL.md frontmatter > none), `flatline-orchestrator.sh:1023-1024` (`review|skeptic → xhigh`, `score → medium`), `effort-dispatch.bats` ED-1..ED-10 (stubbed `MODEL_INVOKE`, byte-identical argv on repeated resolution, dead `.loa.config.yaml.example` block gone); `validate-skill-capabilities.sh` passes on `reviewing-code: xhigh`, `implementing-tasks: xhigh`, `auditing-security: medium`.

### AC-9.2 A/B results

> **Environment caveat (sprint-237 audit HIGH-001, 2026-09-22):** arms A, B and B2 ran under `--allowed-tools Read,Grep,Glob,Write`, which only adds allow rules on top of the operator's `~/.claude` settings; the two surviving sandbox transcripts show the agent under test calling Bash (never granted) and 30 of 181 trials wrote helper files to `/tmp`. Both arms shared that environment, so the comparison below is internally valid, but it is a comparison of the prompt trees under the host's permissions, not under the SDD's fixed tool set. The executor now runs `--restricted --tools` (fixed in the audit follow-through); a confined re-measure is bead bd-vq7v.
- **Status**: ◐ Partially met. After one diagnosis-driven iteration on reviewing-code (arm B2): review recall ✓ (0.944 vs 0.958, within the 0.1 tolerance), review clean-PR false positives ✗ (0.167 vs 0 — one HIGH in one of six clean trials), audit recall ✓ and audit false positives ✓ (identical to baseline), audit tokens per call ✗ (0.758 vs the ≤ 0.5 target), implement discipline ✓ only vacuously (0/0). Both arm B and arm B2 are reported; every number is reproducible from `grimoires/loa/a2a/sprint-237/ab/` with the commands in the verification steps. A second prompt tweak aimed at the one remaining HIGH would be hill-climbing on a 10-PR corpus, so the iteration stops here and the residual is stated. **Scope-split**: each `✗` sub-gate is carried out of the cycle as a named follow-up task in `grimoires/loa/sprint.md` ("Sprint 3 follow-ups" block under Sprint 3: bd-azrr, bd-gvxy, bd-a4td, bd-fwt0 with the concrete next action for each).
- **Setup**: arm A = Sprint-2 tip worktree `72bdb7d2` (prompt tree `4e38de26`); arm B = audited tree `734f3837` (prompt tree `4f13f15c`); both Sonnet 5 (`claude-sonnet-5`) at `--effort medium`, `EVAL_MAX_TURNS=40`, 3 trials per task, `prompt_tree_dirty: false` on every row; corpus manifest `1e96a406…` pinned in the baselines. Errored attempts (session caps, and turn-cap truncations: A 1, B 3) were excluded and their slots re-run; two arm-B rows recorded on a transiently dirty tree were discarded and re-run (see the Decision Log).
- **Gates** (`compare.sh --ab`, `ab/compare/<suite>.{json,txt}`):

| Suite | Gate | A | B | Rule | Result |
|---|---|---:|---:|---|---|
| review-recall | anchored recall (defect tasks) | 0.958 | 0.820 | B ≥ A − 0.1 | ✗ (−0.139) |
| review-recall | critical+high on the 2 clean PRs | 0.000 | 0.333 | B ≤ A | ✗ |
| audit-recall | anchored recall | 0.972 | 0.972 | B ≥ A − 0.1 | ✓ |
| audit-recall | critical+high on clean PRs | 0.000 | 0.000 | B ≤ A | ✓ |
| audit-recall | tokens per call B/A (all four usage fields) | 1,346,836 | 1,021,364 | ≤ 0.5 | ✗ (0.758) |
| implement-discipline | composite pass rate | 0.000 | 0.000 | B ≥ A | ✓ (vacuous) |
| review-recall (arm **B2**, tree `397d9036`) | anchored recall | 0.958 | 0.944 | B ≥ A − 0.1 | ✓ (−0.014) |
| review-recall (arm **B2**) | critical+high on the 2 clean PRs | 0.000 | 0.167 | B ≤ A | ✗ (1 HIGH in 1 of 6 clean trials) |
| review-recall (arm **B2**) | tokens per call B/A | 1,621,778 | 1,575,798 | (informational) | 0.972 |

- **Reading the review-recall miss** (per trial, `ab/arm-{a,b}/review-recall/artifacts/<task>/trial-N/review.md`): the grader credits a defect only when a `path:line` or `path:start-end` citation falls within ±3 of the manifest anchor. Arm B found and described the planted defects but cited the neighbouring statement or a single line — `audit_envelope.py:462` for the D04 anchor at 468, `semver-bump.sh:79` for D06 at 83 (trial text: "`bump_version` no longer bumps prerelease tags") — where arm A cited ranges (`462-473`, `80-94`) that contain the anchor. Per defect: D01 improved 0.33 → 1.0; D04 1.0 → 0.33; D06 1.0 → 0.33; D07, D10 1.0 → 0.67; the other seven unchanged at 1.0. The clean-PR false positives are a severity shift on one finding both arms made: the dotted-route skip heuristic in `butterfreezone-validate.sh:291-294` — arm A rated it MEDIUM in all three trials, arm B HIGH (confidence: high) in two. Arm B reviews were shorter (output tokens mean 14.3K vs 16.1K) at similar turn counts (21.6 vs 20.6).
- **Audit suite**: recall and false positives identical to baseline; tokens per call fell 24 %, not the 50 % the PRD gate assumed — cache reads of the diff (~1.0M tokens per call) dominate, and the prompt bytes the diet removed are a minority of the call (bd-gvxy proposes re-specifying the gate against prompt-attributable tokens).
- **Discipline suite**: composite 0/15 in both arms because no trial wrote its test before its source file (`test_first` 0/15 each); per check — surgical A 15/15, B 13/15 (two arm-B trials created `_verify*.py` scratch files at the workspace root); zone 15/15 both; tests-pass 15/15 both. The `B ≥ A` gate passes vacuously; the surgical dip is small-sample but is the shape of regression the diet could cause and is filed as bd-azrr. Tokens per trial B/A 1.09.
- **Iteration (arm B2)**: one change to reviewing-code only (`f19dd6d0`, prompt tree `397d9036`): the Coverage block asks for a citation of the failing statement itself, as a range when the defect spans lines, and states that `high` needs a nameable failing input or exploit path while a check that only might misfire is `medium`. Result (`ab/arm-b2/review-recall/`, `ab/compare/review-recall.b2.{json,txt}`): 30/30 trials, same model, no dirty rows; anchored recall 0.944 — D04 and D07 back to 1.0, D01 and D17 above baseline, D06/D13/D16/D24 at 0.67 (one trial each); the dotted-route heuristic on the clean PR is MEDIUM in all three trials, and the one remaining clean-PR HIGH is a different finding in one trial (a test-fixture route the validator's regex never extracts, `butterfreezone-validate-route-false-positive.bats:39`). Output tokens per review rose back to 15.8K (A 16.1K). The grader was not changed after seeing results (bd-a4td records the anchor-granularity artifact for a future corpus revision). The audit and implement arms stand on `4f13f15c` — auditing-security and implementing-tasks did not change between `734f3837` and `f19dd6d0`.
- **Operator step**: the credentialed `cost_micro_usd` / effort measurement (no Anthropic HTTP credential on this host); headless `usage` is the token source above.

### AC-9.3 parity harness and unit suites green after the diff
- **Status**: ✓ Met for every suite this range touches; the pre-existing red set is unchanged and listed.
- **Evidence**: full `tests/unit` on `f19dd6d0` (2026-09-22T06:02Z): 38 red = the 30 pre-existing (aleph release ingestion 7, post-merge publication 19, semver evidence 3, template-safety 1 — all red at `80be4b0f`) + the 8 licence grace-period tests, which are time-dependent fixtures (35/35 green immediately after `tests/fixtures/ensure_license_fixtures.sh` regeneration at 23:47Z, red again hours later; bd-85xd); every other unit test green, including the gate suites re-run after the last prompt commit. Adapter pytest 2276 passed / 6 skipped; the seven named integration suites 101/101; `capture.sh --verify` → `VERIFY OK: all 32 golden outputs match` on `f19dd6d0`; `generate-constraints.sh --dry-run` / `generate-skill-includes.sh --check` clean.

### Sprint-level ACs (sprint.md)
- validators/lints/bats named above green ✓ (`validate-skill-capabilities.sh` 36/36, `lint-invariants.sh` 10/2/0, `skill-capabilities`, `skill-includes`, `validation-skill-contracts` bats); `generate-constraints.sh` / `generate-skill-includes.sh` dry-run diff empty ✓. The sprint-level row "AC-8.1 … AC-9.3 as written" stays unticked in sprint.md because AC-9.2 is partially met (see above).
- The 10 `*.constraint-XXXXXX` twins gone and `no-backup-files.yml` extended (`\.constraint-[A-Za-z0-9]{6}$`): ✓ (`00a6ce1e`, `tests/unit/no-constraint-temp-files.bats`).

## Deliverables (sprint.md)

- [x] Budget tool + resource charging, keep list, CI workflow, the seven bats gates
- [x] Arm-A baseline + executor + corpus + graders + suite + baseline with `prompt_tree_sha` (`534ff4d2`)
- [x] 49-unit prompt audit with lead gate; 13 skills ≤ 16 KB; `CLAUDE.loa.md` ≤ 10 KB; 3 protocols archived; protocols ≤ 200 KB with the per-file residual below
- [x] Coverage-first block in reviewing-code, auditing-security, flatline-reviewer/skeptic; `verdict-derive.sh` additive `excluded`; floors and escalation removed
- [x] Effort: frontmatter declarations, `resolve_effort()`, Flatline mode → effort, dead example block deleted
- [x] Arm B + `compare.sh` (gates per AC-9.2: partially met, stated above); `capture.sh --verify` 32/32; reminder-hook one-shot fence test

## Tasks completed

**3.1 / 3.2 / 3.4 / 3.5 / 3.7** as tabled above (beads bd-0h84, bd-9eo6 closed; bd-ng37, bd-s67e, bd-dsbw close after 3.3 because beads orders them behind it).

**3.3 Arm-A baseline** — captured on the pinned worktree at `72bdb7d2` (the Sprint-2 tip: no prompt, eval or corpus change between tip selection and capture; every later prompt hunk landed on the main tree only): review-recall 30/30, audit-recall 30/30, implement-discipline 15/15 completed trials, every row `model_id claude-sonnet-5`, `effort medium`, `prompt_tree_sha 4e38de26`, `prompt_tree_dirty false`; results and per-trial artifacts under `ab/arm-a/<suite>/`, baselines in `evals/baselines/` (freshness rule BF-1..BF-9 green). The runner is resumable per (task, trial) slot; three session caps interrupted it and cost time, not data (one `review-pr-09` trial errored with `execute-agent exit 1` and was re-run).

**3.6 49-unit prompt audit** — method `prompt-audit/METHOD-prompt-audit.md` + `METHOD-fable-5.1-migration.md`; one brief per unit; dispatch ≤ 6 concurrent Sonnet auditors. Two agent types were used: `prompt-auditor` (Read/Grep/Glob, returns text) and — after in-conversation delivery proved lossy (idle notifications truncate at 16,000 chars; the first six deliverables were recovered from the session transcript) — `prompt-auditor-io` (adds Bash, contractually limited to saving its own files under the audit dir). This deviates from the plan's "no Write/Edit tools at all" wording; the mechanical write boundary is the lead gate (`lead-gate.sh`: generated-block splice, keep-list grep, protected-string re-read, history-token scan, byte target), and nothing reached `.claude/` without it. Every auditor landed 1–8 KB above the skill target (their byte estimates ran low); the lead did the second passes itself — deduplicating against `CLAUDE.loa.md`, moving conditionally-needed material behind guarded `resources/*.md` pointers, collapsing tables to prose — and lead-authored 16 units outright (CLAUDE.loa.md, karpathy-principles, the three archivals, eight small protocols, the five personas, rtfm-testing, bug-triaging, translating-for-executives). Each lead-authored unit has a report in the same shape.

Skills (bytes before → after; target 16,384; budget tool total incl. charged resources — none charged):

| Skill | Before | After | Moved behind guarded resources |
|---|---:|---:|---|
| run-mode | 32,958 | 15,761 | sprint-plan loop, halt/resume, run-status, bug run, completion modes, conditional gates |
| implementing-tasks | 32,076 | 16,358 | CLI tool policy; parallel dispatch → REFERENCE.md |
| auditing-security | 32,538 | 16,326 | parallel split prompts, dissenter merge/failure record, source/sink lists → REFERENCE.md |
| reviewing-code | 32,398 | 16,359 | parallel review, adversarial review, beads labels; YAGNI taxonomy → REFERENCE.md |
| deploying-infrastructure | 29,313 | 16,332 | verification checklists |
| discovering-requirements | 28,610 | 16,282 | codebase grounding, ingestion prompt, debrief, pre-generation gate → REFERENCE.md |
| autonomous-agent | 28,499 | 16,248 | exact invocations, exit codes and post-PR config → `resources/phase-mechanics.md`; Implementation Guard rule restored by the lead |
| riding-codebase | 28,130 | 16,323 | enrichment config, extended markers, completion summary, trajectory fields |
| simstim-workflow | 26,152 | 16,212 | Flatline HITL review procedure, resume support, error handling |
| planning-sprints | 21,902 | 16,348 | beads-flatline loop, Mermaid guidance |
| translating-for-executives | 21,787 | 14,486 | worked translations → REFERENCE.md |
| bug-triaging | 19,376 | 16,241 | — (triplicated procedure/failure-mode blocks folded back) |
| rtfm-testing | 17,170 | 15,317 | tester prompt reunited in `resources/cleanroom-prompt.md` (a prior split had orphaned its tail) |

`CLAUDE.loa.md`: 22,005 → 10,222 (kernel; verbatim regions alone are 7,933 B).

Protocols (bytes before → after vs the 70 % per-file target; total 267,433 → 199,313; fail line 200,000 met, warn line 143,360 not — the residual is named per file, not cut for the count):

| Protocol | Before | After | Target | Residual and why |
|---|---:|---:|---:|---|
| session-continuity | 24,138 | 14,518 | 16,896 | — |
| trajectory-evaluation | 18,853 | 13,314 | 13,197 | +117: schema/exit-code tables |
| helper-scripts | 17,228 | 16,830 | 12,059 | +4,771: script man page — usage, flags, exit codes for ~40 scripts; auditor found only version pins and migration phrasing (bd-72fq) |
| synthesis-checkpoint | 15,562 | 8,446 | 10,893 | — |
| constructs-integration | 14,434 | 14,434 | 10,103 | +4,331: JWT/licence loader reference (schema, CLI, exit codes, verbatim error strings); returned unchanged as clean (bd-72fq) |
| continuous-learning | 13,905 | 7,810 | 9,733 | — |
| citations | 13,399 | 9,309 | 9,379 | — |
| grounding-enforcement | 12,309 | 7,246 | 8,616 | — |
| recommended-hooks | 11,628 | 11,773 | 8,139 | +3,634: Claude Code hook reference (types, JSON config, exit codes); grew by a Provenance footer and a factual fix (`once: true`) (bd-72fq) |
| flatline-protocol | 11,370 | 8,793 | 7,959 | +834: tier diagram, orchestrator invocation, NotebookLM setup are contract text |
| cross-platform-shell | 10,956 | 7,354 | 7,669 | — |
| beads-integration | 10,467 | 9,439 | 7,326 | +2,113: eight `br` reference tables and nine command blocks (bd-72fq) |
| danger-level | 9,985 | 5,698 | 6,989 | — |
| beads-preflight | 9,513 | 8,177 | 6,659 | +1,518: two JSON schemas, exit-code and status tables, four recovery blocks |
| ride-translation | 8,426 | 5,893 | 5,898 | — |
| visual-communication | 8,276 | 5,771 | 5,793 | — |
| input-guardrails | 8,075 | 7,426 | 5,652 | +1,774: result schema and orchestrator contract (bd-72fq) |
| git-safety | 7,783 | 6,217 | 5,448 | +769: warning text, remediation guide, detection snippets |
| feedback-loops | 6,906 | 5,220 | 4,834 | +386: absorbed sprint-completion's live verdict-trailer rule |
| subagent-invocation | 6,733 | 4,534 | 4,713 | — |
| safe-file-creation | 6,396 | 3,235 | 4,477 | — |
| change-validation | 5,224 | 3,158 | 3,656 | — |
| structured-memory | 2,446 | 2,137 | 1,712 | +425: the where-knowledge-goes table is the contract |
| tool-result-clearing | 2,466 | 2,446 | 1,726 | +720: thresholds, 4-step process, edge cases (the include points here) |
| implementation-compliance | 2,266 | 2,003 | 1,586 | +417: registry-rendered checklist + error codes |
| karpathy-principles | 1,858 | 6,247 | 1,300 | +4,947 by design: received the full principle text from CLAUDE.loa.md |
| agent-ergonomics | 1,822 | 1,885 | 1,275 | +610: tables/snippets only; Provenance footer added |
| risk-analysis, upgrade-process, sprint-completion | 6,946 / 6,487 / 5,151 | archived | — | `grimoires/loa/archive/protocols/`; sprint-completion's live rule moved to feedback-loops |

Personas: flatline-reviewer, flatline-skeptic, flatline-scorer, gpt-reviewer clean (unchanged apart from the `### Coverage` heading form); flatline-attacker's issue origin moved to a Provenance footer (6,226 → 6,222).

**3.8 Arm B + compare** — see AC-9.2: arm B measured (gates failed on the review suite and the audit token ratio), one diagnosis-driven iteration re-measured as arm B2 (review recall recovered to within tolerance; one clean-PR HIGH remains). Both arms, the B2 arm and the compare outputs are under `ab/`; the pre-fix arm-B rows set aside for tree consistency are not part of the record.

**3.9 this report** — follow-up beads created: bd-72fq (protocol residual / warn line), bd-8p63 (codex/gemini `--output-schema` forwarding), bd-bo7g (headless capability-probe cache), bd-vmil (mock-dispatch marker in the MODELINV envelope), bd-p5fh (repair-loop retirement), bd-ee4p (OpenAI strict `anyOf` live check), bd-gu4h (stale `test_process_compliance.bats` greps), bd-85xd (licence fixture aging).

## Late input folded into this range

- **Sprint 2 reviewer slices A/B/C** (`a1337ed4`, `4a95512d`) — see the Sprint 2 report addendum; folded in, never discarded.
- **Sprint 1 fallout found by the first full `tests/unit` run since the cycle started** (`5c69a0ec`): Task 1.8 had overwritten `tools/ceiling-probe.py` — the cycle-109 fixture-backend probe that `loa-substrate-recalibrate.sh` and ten bats depend on — with the new live probe; the cycle-109 tool is restored byte for byte from `80be4b0f` and the live probe is `tools/ceiling-probe-live.py` (scaffold bats, live pytest, workflow, CHANGELOG, catalog comment follow). `bug-881-headless-context-window.bats` now expects the Sprint 1 catalog's `claude-headless context_window: 1000000`. `ledger-transactions.bats` #1248 paused its workers at the literal pre-cycle jq filter text; the pause now matches the type-guarded filter from `a1337ed4`. The licence grace-period tests go red once the gitignored fixtures age past 24 h — regenerated for this run (bd-85xd).
- **Test expectation changes made in this range, with reasons**: `validation-skill-contracts.bats` requires ≥ 1 (was exactly 2) `validate-ac-verification.sh` invocations in implementing-tasks — the count was structural, the invariant (each carries `--sprint "$SPRINT_FILE"`) is kept; `dead-recall-relabel.bats` greps `### 4. Memory Injection Hook` instead of a heading that carried a history token; `tests/fixtures/golden-{never,always}-table.md` regenerated from the registry after the history-token cleanup.

## Testing summary

NFR-9 verification matrix on the audited tree (`a424391c`+):

| Command | Result | ACs |
|---|---|---|
| `python3 -m pytest .claude/adapters/tests -q -p no:cacheprovider` | 2276 passed, 6 skipped (live scaffolds), 175 subtests | adapter ACs unchanged by this range |
| `npx --no-install bats tests/unit/` | 38 red on `f19dd6d0`: the 30 pre-existing (aleph release ingestion 7, post-merge publication 19, semver evidence 3, template-safety 1) + 8 time-dependent licence grace-period fixtures (green right after regeneration; bd-85xd); every other test green | gate / verdict / prompt-budget ACs |
| `tests/integration/{flatline-content-qualified-quorum,ledger-hygiene-tripwire,cheval-input-gate,cheval-error-json-shape,ledger-workflow,sprint-2D-resolver-parity,cheval-redaction-emit-path}.bats` | 101/101 | AC-3.5, tripwire, quorum |
| `gen-adapter-maps.sh --check`, `npm run gen-bb-registry -- --check`, `tools/regen-model-artifacts.sh --check` | OK (one pre-existing alias-duplication WARN) | AC-3.2 |
| `tools/check-ledger-hygiene.sh`, `tools/check-no-swallowed-jq.sh`, `tools/check-prompt-budget.sh` | OK / OK / exit 0 (protocol warn line on) | FR-6, FR-7, AC-8.1 |
| `capture.sh --verify` | 32/32 | AC-8.3 |
| `repo-map-gen.sh --validate` | consistent | REPO-MAP drift gate |
| `compare.sh --ab` ×3 (+ B2) | review B: recall ✗ / FP ✗ → B2: recall ✓ / FP ✗ (0.167); audit: recall ✓ / FP ✓ / tokens ✗ (0.758); discipline ✓ (vacuous) | AC-9.2 |

Interim: gate suites for the changed units green after every batch (`prompt-audit-keeplist`, `no-history-in-rule-text` NH-1..3, `prompt-audit-generated-blocks`, `skill-includes`, `skill-capabilities`, `validation-skill-contracts`, `golden-path-c8-verdict-trailer`, `effort-dispatch`, `verdict-observations-section`, `reminder-hooks-one-shot`, `skill-loop-golden-scope`, `post-compact-active-skill`, `implementing-tasks-success-criteria-gate`, `skill-inputs-manifest`, `dead-recall-relabel`, `quality-gates`, `ledger-transactions`, `ceiling-probe-protocol`, `cycle-109-t5-6-substrate-recalibrate`, `cycle-124-live-scaffold`, `bug-881-headless-context-window`, `test_license_validator`); `tests/test-constraints.sh` 17/17; `qmd-context-integration-tests.sh` green (implementing-tasks, reviewing-code, riding-codebase keep their pinned qmd strings); `capture.sh --verify` 32/32.

Pre-existing red, unchanged by this range (listed so the reviewer does not chase them): `tests/integration/test_process_compliance.bats` 6/7/10 (greps for wording that already differed at `80be4b0f`; bd-gu4h), aleph-release-ingestion (7), post-merge-publication (19), semver-evidence (3), template-safety vision ISO (1), `evals/harness/tests/test-compare.sh` 1 case, `evals/tests/golden-path.bats` 33, the unwired `.claude/scripts/tests/test-interview-config.sh` / `test-ux-phase2.sh`.

## Measurement notes and honesty pass

- Byte figures are `wc -c` on the applied files; the budget tool's totals include charged resources (none are charged: every moved-material pointer carries a guard word).
- The protocol warn line (143,360) is not met and is not claimed; the per-file residual above says what stays and why, and bd-72fq carries the decision (relocate reference docs vs archive vs accept). Nothing was archived to make byte room: `helper-scripts.md` and `constructs-integration.md` came back clean and stay.
- Auditor-reported byte counts were estimates in the first six units (no Bash); the gate measured every proposal. Every auditor landed above the skill target; the lead cut the rest and, three times, restored something an auditor had dropped that a test or a fence rule protects (riding-codebase's qmd step, autonomous-agent's Implementation Guard, simstim-workflow's literal Flatline invocations).
- A/B validity: `compare-ab.py` refuses an arm with a dirty tree or mixed prompt trees. Arm B was restarted from zero once (after the simstim restore changed the tree) and two arm-B rows were discarded and re-run because a `--check` regen and a unit-suite idempotence test wrote under `.claude/` while a trial was in flight; the final arms have `prompt_tree_dirty: false` on every row and one tree each. Errored attempts (session caps; turn-cap truncations A 1, B 3, B2 0) never enter `results.jsonl`. Pre-fix arm-B rows are kept outside the record (`scratchpad`), not under `ab/`.
- The A/B gates as written are not all met (AC-9.2 above). The one prompt iteration was made from a diagnosis of the artifacts, not from the scores, and the deterministic grader was left unchanged after seeing results; its anchor rule rewards range citations and that artifact is filed (bd-a4td), not patched in this range.
- The implement-discipline composite is 0/15 in both arms (no test-first trial); the metric therefore cannot show a regression or an improvement. The per-check breakdown is the honest reading, and the surgical dip (15/15 → 13/15) is filed (bd-azrr).
- The audit token gate assumed prompt bytes dominate a call; measured cache reads of the diff are ~1.0M tokens per call, so a 24 % reduction is what the diet delivers (bd-gvxy).
- A/B arms ran Sonnet 5 at `medium` effort for cost; the effort declarations in frontmatter (`xhigh` for review/implement) apply to production dispatch through `model-adapter.sh`, not to these runs.
- The audit dir is `sprint-237/` (ledger-resolved global id), not the plan's literal `sprint-3/`.
- Full unit suite: the pre-existing red set (30) is listed under Testing; every failure introduced in this cycle and found by the runs was fixed in this range (Sprint 1 fallout, ceiling-probe clobber, ledger test pause filter, simstim doc-lock, model-config artifacts).

## Known limitations / operator items

- AC-9.2 residuals: review clean-PR false positives 0.167 (one HIGH in one of six clean trials, arm B2) and audit tokens per call at 0.758 of baseline against a ≤ 0.5 target — both stated, neither hidden behind a passing gate.
- No Anthropic HTTP credential on this host: the `cost_micro_usd` / effort cost measurement in AC-9.2 and the live floor scaffold remain operator steps.
- Protocol warn line: bd-72fq. Recall grader anchor rule: bd-a4td. Token-ratio gate specification: bd-gvxy. Implement discipline (test-first, scratch files): bd-azrr.
- codex/gemini headless remain schema-unenforced (bd-8p63); the persona prose "JSON only" contracts stay for that reason.
- `.run/zone-guard-authorization.json` stays armed until the cycle closes (Sprint 4 report deletes it).

## Verification steps for the reviewer

```bash
tools/check-prompt-budget.sh --json | jq '{skills_over: [.skills[] | select(.ok|not) | .path], claude_loa: .claude_loa.bytes, protocols: .protocols.total}'
npx --no-install bats tests/unit/prompt-budget.bats tests/unit/no-history-in-rule-text.bats tests/unit/prompt-audit-keeplist.bats tests/unit/prompt-audit-generated-blocks.bats tests/unit/protocol-refs-resolve.bats tests/unit/verdict-observations-section.bats tests/unit/effort-dispatch.bats
bash .claude/scripts/generate-constraints.sh --dry-run; bash .claude/scripts/generate-skill-includes.sh --check; bash .claude/scripts/validate-skill-capabilities.sh
bash grimoires/loa/perf/skill-loop-2026-07-05/golden/capture.sh --verify
ls grimoires/loa/a2a/sprint-237/prompt-audit/units/*.report.md | wc -l   # 49
for m in recall:review-recall audit:audit-recall discipline:implement-discipline; do evals/harness/compare.sh --ab --arm-a grimoires/loa/a2a/sprint-237/ab/arm-a/${m#*:} --arm-b grimoires/loa/a2a/sprint-237/ab/arm-b/${m#*:} --metric ${m%%:*}; done
evals/harness/compare.sh --ab --arm-a grimoires/loa/a2a/sprint-237/ab/arm-a/review-recall --arm-b grimoires/loa/a2a/sprint-237/ab/arm-b2/review-recall --metric recall
```

## Round 1 review response (2026-09-22)

Review round 1 (`engineer-feedback.md`, CHANGES_REQUIRED 0/2/4/3; cross-model dissent gpt-5.5-pro over four diff chunks) asked for two things and observed seven; all addressed in the follow-up commit:

- **CHANGELOG** — Unreleased now opens with the Sprint 3 entries (budget gates + keep list + CI; the 49-unit audit with the kernel, archivals, protocol total and resources/ moves; coverage-first review/audit + `excluded` + effort dispatch; the eval A/B harness with the measured outcome; the Sprint 1 fallout fixes).
- **AC-9.2 scope-split** — `grimoires/loa/sprint.md` gains a "Sprint 3 follow-ups" block naming each residual `✗` sub-gate with its bead and next action; the AC-9.2 row above points at it. The sprint-level AC row stays unticked.
- **Dissent findings** — DISS-001 (chunk 1, executor tool list): refuted by the A/B rows (58 `Edit` calls under `--permission-mode acceptEdits`); the SDD's fixed tool set is kept (`execute-agent.bats` EA-3 pins it) and the header comment now says why the extractor records `Edit`. DISS-001/002 (chunk 4): pre-existing at `80be4b0f`, outside this range — beads bd-hf7g (implementing-tasks zone manifest) and bd-ts9l (autonomous-agent phase sequence in `constraints.json`, plus simstim's dangling "Phase 6.5").
- **Complexity** — `compare-ab.py` `summarize()` / `main()` carry `loa:shortcut:` justifications (one-pass aggregation; visible exit-code contract) rather than a split that would thread five dicts through helpers.
- **Measurement** — the implement-discipline fixture gap (no test-first path) is bead bd-fwt0, alongside bd-azrr for the prompt side.

## Audit round 1 response (2026-09-22)

The security audit (`auditor-sprint-feedback.md`, CHANGES_REQUIRED 0/1/9/15) found one blocking item and it is fixed in this range:

- **HIGH-001 — executor confinement** — `evals/harness/execute-agent.sh:161` now passes `--restricted --tools "Read,Grep,Glob,Write"` (removes the code-running tools, ignores user/project/local settings, confines the file tools to the sandbox — the CLI's own semantics, confirmed by the audit's live probe) and the run subshell unsets `GH_TOKEN GITHUB_TOKEN OPENAI_API_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN` and points `TMPDIR` into `<ws>/.eval/tmp`; `HOME` and `PATH` stay because the CLI reads its own credentials and toolchain there (the sandbox library's `sanitize_env` would have moved `HOME`, and it is not source-safe — the four inline lines are the smaller diff). `evals/graders/implement-discipline.sh:44-56` runs `test_command` under `env -i` with only `PATH`, `HOME`, `TMPDIR`, `LC_ALL` and, when set, `PYTHONPATH`/`VIRTUAL_ENV` (the first cut moved `HOME` into the workspace and broke user-site `pytest` — ID-1/ID-9 caught it). Tests first: EA-3 re-pinned to `--restricted`/`--tools` and refuting `--allowed-tools`, EA-10 (env hygiene) and ID-10 (grader isolation) were red before the change and are green after; `evals/tests/{execute-agent,implement-discipline-grader,eval-recall-grader}.bats` all pass. `evals/README.md` and `grimoires/loa/sdd.md` state the new argv; the header comment explains why `Edit` is no longer available (the earlier round-1 note about `acceptEdits` admitting `Edit` described the unconfined run).
- **A/B record** — annotated above (§AC-9.2 environment caveat); arms are not re-run in this sprint (hours of wall-clock; bead bd-vq7v).
- **Medium/low items** — carried as beads bd-vq7v, bd-sk1t, bd-tc3i, bd-zklv, bd-kqz4, bd-1ju5, bd-tjkx, bd-2a9g, bd-tdtr and as rows in the sprint plan's Sprint 3 follow-ups block. Nothing else in the audit blocks.
- **Host residue** — the helper files the unconfined arms left under `/tmp` (`/tmp/test_regex.sh`, `/tmp/jqtest/`, `/tmp/ajvcheck/`, `/tmp/ajvtest/`, `/tmp/symtest/`, `/tmp/audit_test.sh`, `/tmp/echotest.sh`, `/tmp/t.sh`, `/tmp/t.md`, `/tmp/line.txt`, …) are listed in NOTES.md for the operator; some names are generic, so they are not deleted here.
