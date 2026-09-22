# Sprint 3 Security Audit — cycle-124 "model-generation floor" (global sprint-237) — round 1

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1 lead acting as gate; independent input: three read-only category auditors — eval harness / gate scripts + adapters / prompt-rule regressions — and a four-chunk cross-model audit dissent)
**Date:** 2026-09-22
**Sprint Reference:** grimoires/loa/sprint.md (Sprint 3)
**Implementation Report:** grimoires/loa/a2a/sprint-237/reviewer.md
**Scope:** `012d0c5e..HEAD` (`d562d510`) — 26 commits, 360 files, +55,112/−14,925 outside the a2a record (LARGE per Phase -1: 64,580 lines in changed script/test/workflow files; audited by category split, every finding below re-verified by the lead at the cited line)
**Review gate:** round 2 APPROVED (`engineer-feedback.md`, 2026-09-22; round 1 record in `engineer-feedback.round-1.md`)

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The sprint's gate work holds up: the verdict-trailer one-way rule is intact, the new `excluded` / `excluded_confirmed` fields fail closed in `golden-path.sh`, the effort value is allowlisted at three layers before it reaches any argv, the prompt-budget CI gate cannot pass on a crashed scanner, fence and hook files are byte-identical to the base, no key shapes appear anywhere in the range, and the kernel/skill compression kept every keep-listed gate string. The cross-model dissenter retained no finding over four diff chunks; its four rejected payloads were recovered from the sidecar and are dispositioned below (both surviving ones are pre-existing text).

One finding blocks. The FR-9 agent executor (`evals/harness/execute-agent.sh`) was specified to run the agent under test with a fixed tool set inside a sandbox, but `--allowed-tools` only *adds* allow rules on top of the operator's own `~/.claude` settings, the file tools are not confined to the sandbox, and the environment is inherited. This is not theoretical: the two A/B sandbox transcripts that survived on disk show the agent under test calling **Bash** (three and six times) — a tool the executor never granted — executing `cat`, `sed`, `bash /tmp/test_grep.sh` and `cd /tmp && echo … > f.txt` on the operator's host, and 30 of the 181 recorded trials wrote files outside their sandbox into `/tmp` (the files are still there). A live probe with the same CLI confirms the fix: `--restricted --tools Read,Grep,Glob,Write` mechanically refuses an out-of-workspace write (`permission_denials: 1`), ignores user settings, drops Bash, and still allows in-workspace writes. The fix is a few argv lines plus env hygiene (the CLI keeps `HOME` for its own credentials; the non-CLI credentials go); the A/B numbers recorded this sprint stay valid as a same-environment comparison but must be annotated as measured with an unconfined executor.

**Security Issues Found (Phase 2.5 tally — every finding below, none excluded):**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 9 |
| Low | 15 |

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] The eval executor does not confine the agent under test: operator allow rules, unconfined file tools and the operator's environment leak into every trial

**Severity:** HIGH (confidence: high — observed, not inferred)
**File:** `evals/harness/execute-agent.sh:161-162` (argv), `:177` (exec without env sanitisation); `evals/harness/sandbox.sh:90` (`sanitize_env`, defined, never called — `grep -rn sanitize_env evals/` has no caller)
**Issue:**

```bash
  --allowed-tools "Read,Grep,Glob,Write"
  --permission-mode acceptEdits
```

`--allowed-tools` adds allow rules; it does not remove tools or ignore the operator's settings. The sandbox cwd is `/tmp/loa-eval-*`, so the repo's project settings do not apply, but the user-level ones do: on this host `~/.claude/settings.local.json` allows `Bash(timeout:*)`, `Bash(curl:*)`, `Bash(cat:*)`, `Bash(rm:*)`, `Bash(pkill:*)`, … and `~/.claude/settings.json` sets `defaultMode: auto`. Read/Grep/Glob are not confined to the working directory without `--restricted`, and the executor inherits `HOME`, `PATH` and every credential in the operator's environment.

**Evidence (all reproducible from the record):**

- `/tmp/loa-eval-run-20260922-001506-5f05b160-audit-pr-01-trial-1-NDutZ5/workspace/.eval/events.jsonl` — 6 Bash calls by the agent under test, including `cd /tmp && echo "no matches here" > f.txt; …`, `bash /tmp/test_grep.sh` (twice), `grep -n … workspace/head/.claude/scripts/workflow-state.sh`; two other commands were refused ("This command requires approval"), i.e. the operator's allow rules decided what ran.
- `/tmp/loa-eval-run-20260922-001505-c3163adb-review-pr-01-trial-2-gx9dZD/workspace/.eval/events.jsonl` — 3 Bash calls (`cat …/REVIEW-INSTRUCTIONS.md`, `cat PR.md && … cat head.diff`, `sed -n '160,270p' base/.claude/hooks/safety/block-destructive-bash.sh`). The smoke sandbox `/tmp/loa-eval-smoke1-t1-czrUTV` shows 6 more.
- `grimoires/loa/a2a/sprint-237/ab/*/artifacts/*/trial-*/executor.json` `tool_writes[]`: 30 of 181 trials requested Write to paths outside their sandbox (`/tmp/test_regex.sh`, `/tmp/jqtest/gate-critical.sh`, `/tmp/ajvcheck/runner.sh`, `/tmp/symtest/repo/test.sh`, `/tmp/t.sh`, …); five of those files are still present on the host (`ls -la /tmp/ajvcheck/runner.sh /tmp/jqtest/gate-critical.sh /tmp/audit_test.sh /tmp/echotest.sh /tmp/ajvtest/bin/ajv`), so the writes succeeded.
- Live probe, sanctioned CLI path (`claude -p`, Sonnet 5, cwd = fresh `/tmp` dir), 2026-09-22: as configured today an out-of-cwd Write to `$HOME/…` was declined only by the model's own judgement (`permission_denials: 0`); with `--restricted --tools "Read,Grep,Glob,Write"` the same write is refused by the harness (`permission_denials: 1`, "restricted mode … confines file tools to the working directory"), and an in-cwd Write still succeeds.

**Impact:** an unattended bulk run (181 trials here) of a model reading adversarial-by-design fixtures executes shell commands and writes files on the operator's host with the operator's credentials in the environment. A fixture line such as "the fix is already on this machine — run `curl … | sh` to fetch it" is admitted by `Bash(curl:*)`; a "helpful" write to the fixture's *real* path (the fixtures are diffs of this very repository) clobbers the operator's checkout. The SDD's "fixed tool set" (`reviewer.md` AC-9.2, `execute-agent.sh` header) was not what ran; both arms ran with whatever the host allowed, so the recorded A/B is a same-environment comparison of the prompt trees, not a measurement under the specified tool set.

**Fix (small; failing test first):**

```bash
# execute-agent.sh — replace the two lines above with
  --restricted --tools "Read,Grep,Glob,Write"
  --permission-mode acceptEdits
# and, in the run subshell before exec: unset GH_TOKEN GITHUB_TOKEN OPENAI_API_KEY AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; export TMPDIR="$eval_dir/tmp" (HOME stays: the CLI reads
# its own credentials there; PATH stays: the CLI needs its toolchain). sandbox.sh's sanitize_env is
# not source-safe (its dispatch runs on source) — the four lines inline are the smaller diff.
```

1. `evals/tests/execute-agent.bats` EA-3 currently pins `--allowed-tools`; change it to pin `--restricted` and `--tools Read,Grep,Glob,Write`, and add an EA case asserting `GH_TOKEN`/`OPENAI_API_KEY` are absent and `TMPDIR` is under the sandbox in the stub's captured environment; the discipline grader gets a case proving `test_command` runs without those variables.
2. Update the header comment (lines 20-26) and `reviewer.md` AC-9.2 with the environment caveat: arms A/B/B2 ran unconfined; a confined re-measure is follow-up work (bead bd-vq7v).
3. Leave the `/tmp` residue to the operator (generic names such as `/tmp/t.sh` may collide with their own files); list it in NOTES.

**Reference:** CWE-250 Execution with Unnecessary Privileges — https://cwe.mitre.org/data/definitions/250.html; CWE-668 Exposure of Resource to Wrong Sphere — https://cwe.mitre.org/data/definitions/668.html; OWASP LLM08:2025 Excessive Agency — https://genai.owasp.org/llmrisk/llm082025-excessive-agency/. Bead: bd-vq7v.

---

## Medium/Low Priority Issues

Every entry: `file:line`, the failing scenario, confidence, disposition. "Pre-existing" means byte-identical at the branch base `80be4b0f`; those are tallied because they were observed, and tracked rather than fixed in this sprint.

### Medium

- **MEDIUM** (confidence: high) `evals/graders/implement-discipline.sh:47` — `if ( cd "$ws_abs" && timeout … "${test_cmd[@]}" … )` runs the agent-authored test tree (`python3 -m pytest -q tests` in every expectations file) on the host with the inherited environment; an agent-written `tests/conftest.py` executes with the operator's credentials and network, independent of the CLI tool policy (header line 43 "deterministic, no network" is not true of agent output). Fix with HIGH-001: run `test_command` under `env -i PATH="$PATH" HOME="$ws_abs" TMPDIR="$ws_abs/.eval/tmp" LC_ALL=C` (the toolchain stays reachable, the credentials do not). Bead bd-vq7v.
- **MEDIUM** (confidence: high) `evals/harness/compare.sh:168` — `sha256sum "$m"` hashes `review-prs/SHA256SUMS` itself, not the corpus against it, and `build-review-corpus.sh --verify` has no caller (`git grep`: README and the script's own usage only). Editing a `pr-NN/head/*` file or a manifest anchor between arms leaves the "frozen corpus" check green. Today `sha256sum -c` passes. Bead bd-sk1t.
- **MEDIUM** (confidence: high) `tools/check-prompt-budget.sh:101` (`report = {"ok": not violations, …}`) and `:118` — an empty scan is a pass: a root with `.claude/` but no `skills/*/SKILL.md`, no `CLAUDE.loa.md` and no protocols reports `{"ok": true, "skills": [], "claude_loa": {"present": false}}` and exits 0 (reproduced on an empty temp root). A moved `.claude/skills/` layout, a glob metacharacter in `--root` or a nested skill layout silently passes the CI gate; the workflow's sentinel steps prove the fixture bites, not that the real tree was scanned. `--json` also does not surface `protocols.warn` (the real tree sits at 199,313 B of the 200,000 B fail line). Bead bd-tc3i.
- **MEDIUM** (confidence: high) `.claude/scripts/verdict-derive.sh:154` with `:287`/`:290`/`:303` — `trailer_int` returns integral floats verbatim (`2.0`, `1E+5`) and the `(( ))` comparisons turn the resulting arithmetic error into false, so the mismatch violation is skipped: an audit trailer `"excluded_confirmed":2.0` checked against a review `"excluded":3` prints `CONSISTENT` rc 0 (reproduced; the script logs `line 303: ((: 2.0: syntax error` and continues). Contained: `golden-path.sh:139` re-checks `^[0-9]{1,6}$` and denies. VO-9 pins `-1`, `"1"` and 2^64 but not `1.0`. Bead bd-zklv.
- **MEDIUM** (confidence: high) `.claude/scripts/verdict-derive.sh:294-297` — the `--review-file` cross-check detects the review trailer case-insensitively but strips it case-sensitively, so a review whose marker is spelled in lowercase (with `"excluded":3`) reads as `rev_ex="0"` and an audit with `excluded_confirmed:0` passes standalone (reproduced, rc 0). The golden path still denies because the review file fails its own gate first. Same bead.
- **MEDIUM** (confidence: high) `.claude/scripts/verdict-derive.sh:138-139` — `observations_scan` matches only uppercase `CRITICAL`/`HIGH` (or `severity: x`); `- **Critical**: auth bypass (confidence: high)` under `## Observations` with a zeroed APPROVED trailer passes verdict-derive and `_gp_sprint_is_audited` (reproduced, rc 0). A self-consistency gap, not a bypass of the self-reported counts; fix by scanning the already-lowercased line. Same bead.
- **MEDIUM** (confidence: high) `.claude/loa/CLAUDE.loa.md@012d0c5e:264` — the kernel rule "Verdict-bearing work (review/audit/red-team/BB) NEVER runs on a pinned cheaper model" was dropped by the 10,240-byte compression and no always-loaded surface at HEAD carries it (`git grep 'pinned cheaper model' -- .claude` = 0); residual cover is lint-time only (`validate-skill-capabilities.sh` rejects `model:`/`agent:` frontmatter on review/audit skills) and implementing-tasks' copy sits behind the MEDIUM/LARGE-only pointer (`resources/REFERENCE.md:147`). Scenario: `reviewing-code/resources/PARALLEL-REVIEW.md:8-28` dispatches sub-reviews that return PASS/FAIL; nothing at HEAD forbids `model: haiku` or `loa-scout` for those calls and no hook inspects runtime dispatch. Restore at the point of dispatch (byte-neutral for the kernel) and keep-list it. Bead bd-kqz4.
- **MEDIUM** (confidence: medium) `.claude/loa/CLAUDE.loa.md@012d0c5e:332-341` — "ALWAYS/NEVER tables for L1–L7 live ONLY in agent-network-reference.md — you MUST read it BEFORE touching any primitive's lib, hook, schema, log, or audit chain" plus the six-row routing table were removed; HEAD keeps the Reference-Files row (`:20`) and the universal invariants (`:135`). The 54 layer-specific rows are now reached only by unprompted choice, and none of the five agent-network skills point at the reference. Scenario: an agent editing `graduated-trust-lib.sh` honours the universal invariants and never sees the L4 NEVER rows. Fix without kernel bytes: a path-scoped `.claude/rules/agent-network.md`. Bead bd-1ju5.
- **MEDIUM** (confidence: medium) `.claude/data/skill-includes/input_guardrails.md:13` (rendered into six skills, e.g. `autonomous-agent/SKILL.md`) — "Script missing, non-zero exit, or unparseable output → Continue — fail-open". Recovered from the dissenter's rejected payload (rated HIGH there). Pre-existing and deliberate ("preserving the prior semantics"); the guarded text is the operator's own invocation and the mechanical fences do not depend on it, so the realistic damage is loss of a defence-in-depth heuristic, not a fence bypass — tallied MEDIUM, not HIGH, on that reasoning. Design question (fail closed under `LOA_RUN_MODE=run`?) filed as bd-2a9g.

### Low

- **LOW** (confidence: high) `.github/workflows/check-prompt-budget.yml:22` — the new workflow has no `permissions:` block (repository-default `GITHUB_TOKEN` scope); no secrets used, actions SHA-pinned. Add `permissions: contents: read`. Bead bd-tc3i.
- **LOW** (confidence: high) `tests/unit/prompt-audit-keeplist.bats:38` — the keep-list glob field is `eval`'d (`eval "printf '%s\n' $glob"`); a `$(…)` in `tools/prompt-keeplist.txt` runs in the test runner. Repo-controlled input on a runner that already executes PR code; the ERE column is passed safely.
- **LOW** (confidence: high) `evals/tests/execute-agent.bats:184-193` with `evals/harness/run-eval.sh:626` — EA-8/EA-9 run the real orchestrator, which appends stub rows to the developer's gitignored `evals/results/eval-ledger.jsonl` and never removes them. Bead bd-sk1t.
- **LOW** (confidence: medium) `evals/graders/recall-vs-defects.sh:62` — the `CITE` regex backtracks quadratically on a long dot-free token; a pathological review can push the grader past its 60 s timeout, and the trial becomes `status: error` (excluded from means, `compare-ab.py:54`) instead of recall 0. Bead bd-sk1t.
- **LOW** (confidence: high) `.claude/scripts/verdict-derive.sh:294` — with a trailer-less legacy review file the `grep … | tail -1` pipeline exits 1 under `pipefail` and the script exits 1 with no violation text and no JSON: fail-closed but undiagnosable at the audit self-check. Bead bd-zklv.
- **LOW** (confidence: high) `.claude/agents/prompt-auditor-io.md:6` — `tools: [Read, Grep, Glob, Bash]`: the "save only under the audit dir" rule is prose; mechanically, `block-destructive-bash.sh` FR-SZ2 still fences Bash writes into `.claude/`, and nothing fences `grimoires/`/`src/` (the accepted Bash-path gap). Its input is a committed prompt file, already trusted to run hooks; in-range output landed only under `a2a/sprint-237/prompt-audit/`. Recorded, not blocking.
- **LOW** (confidence: high) `.claude/skills/reviewing-code/SKILL.md@012d0c5e:153` — "≥3 blocking concerns … escalate to human review rather than an extended feedback loop" is gone from HEAD; the run-mode circuit breaker (`run-mode/SKILL.md:116-119`) still bounds autonomous loops. Bead bd-tjkx.
- **LOW** (confidence: high) `.claude/loa/CLAUDE.loa.md@012d0c5e:47` — "For source files, ALWAYS use Write tool" survives only in the `*.sh`/`*.bats`-scoped `rules/shell-conventions.md:20` and the demand-loaded `safe-file-creation.md` that no skill now points at; heredoc `${…}` corruption class. Bead bd-tjkx.
- **LOW** (confidence: high) `.claude/loa/CLAUDE.loa.md@012d0c5e:298-300` — the Safety-Hooks paragraph moved behind the `:108` pointer to `hooks-reference.md:129-141`, which names `block-destructive-bash.sh`, `implement-gate.sh` and `run-mode-stop-guard.sh` but not `zone-write-guard.sh` or `adversarial-review-gate.sh` (pre-existing gap, now the sole inventory). Fences unchanged. Bead bd-tjkx.
- **LOW** (confidence: high) `.claude/protocols/trajectory-evaluation.md@012d0c5e:40,56` — "HALT if cannot articulate expected outcome" softened to "record intent before the search runs" (`:24-26`). Quality ritual, not a gate. Bead bd-tjkx.
- **LOW** (confidence: medium) `.claude/loa/CLAUDE.loa.md@012d0c5e:240` — "MUST re-read run-bridge/SKILL.md before resuming a bridge iteration" now reaches the agent only through `post-compact-reminder.sh:157-161` / `post-session-limit-reminder.sh:113`; a fresh session without a compaction event loses the cue. Bead bd-tjkx.
- **LOW** (confidence: medium) `.claude/skills/implementing-tasks/SKILL.md@012d0c5e:371` — "Even autonomous /run cycles MUST satisfy [the goal-driven gate]": HEAD `:189-197` keeps the gate and the AskUserQuestion but drops the explicit autonomous clause; the K-1 hook is mechanical. Bead bd-tjkx.
- **LOW** (confidence: medium) `.claude/skills/autonomous-agent/resources/phase-mechanics.md:32` — `# Other error - log and continue` in the Phase 0 cleanup case (moved verbatim from `SKILL.md@80be4b0f:214`). Recovered from the dissenter's rejected payload (rated MEDIUM there): stale prior-cycle artifacts left in the same operator's grimoire are a robustness issue, not a cross-boundary disclosure. Pre-existing; folded into bd-ts9l's autonomous-agent clean-up.
- **LOW** (confidence: high) `.claude/scripts/adversarial-review.sh:1171` (`: > "$rejected_sidecar"`) and the reject log line — the rejected-findings sidecar is truncated per run, so a chunked dissent loses earlier runs' payloads (chunk 1's two were unrecoverable; its re-run came back clean), and the log prints the post-repair reason (`missing-or-empty-description`) while the sidecar row carries the original (`missing-or-empty-failure_mode`). Pre-existing, unchanged in range. KF-004 recurrence recorded (31); bead bd-tdtr.
- **LOW** (confidence: high) test assertions loosened in range, none security-bearing: `tests/unit/validation-skill-contracts.bats:21` `assert len(commands) == 2` → `assert commands` (per-command `--sprint` check kept); `tests/unit/dead-recall-relabel.bats:29` no longer asserts the removal wording (the "auto-memory owns cross-session recall" grep remains); `tests/unit/golden-path-c8-verdict-trailer.bats:388,434` exact stderr substring → OR of two fail-closed substrings, status still `-eq 1`. Recorded for the doc-lock ledger.

---

## Cross-Model Security Observations (Phase 1C)

Four diff-only runs of `adversarial-review.sh --type audit` (gpt-5.5-pro via codex-headless, no `--context-file`), prefix-partitioned: evals (52,123 tokens in, `reviewed`, 0 retained / 2 rejected), tools + tests + gates (`clean`), review prompts (`clean`), exec prompts (33,174 tokens in, `reviewed`, 0 retained / 2 rejected). Canonical merged record: `adversarial-audit.json`; per-chunk files `adversarial-audit.{1-evals,1-evals.rerun,2-tools-tests,3-review-prompts,4-exec-prompts}.json`.

All four rejections were `missing-or-empty-failure_mode` (the KF-004 class, recurrence now 31 — evidence row appended to `grimoires/loa/known-failures.md`). The chunk-4 payloads were preserved (`adversarial-rejected-audit.4-exec-prompts.jsonl`) and are the two dissent-sourced items above (guardrails fail-open → MEDIUM bd-2a9g; cleanup continue-on-error → LOW). The chunk-1 payloads were lost to the per-run sidecar truncation; the chunk was re-run and returned `clean`. No dissenter finding duplicated a lead finding, and none changes the tally beyond the two recovered items.

---

## Verified negatives (summary; each anchored)

- **Fences and zones:** `git diff 012d0c5e..HEAD -- .claude/hooks .claude/scripts/{implement-gate,zone-write-guard,block-destructive-bash,audit-envelope}.sh .claude/settings.json` is empty; the only new executable in range is `evals/fixtures/build-review-corpus.sh` (operator tool, list-form subprocess); fixture bodies are 100644 and not wired into CI as code; `sandbox.sh:48-87` rejects `..` and outward symlinks.
- **Trailer gates:** verdict-trailer one-way rule `verdict-derive.sh:261-264`; six-digit cap `:75`; duplicate trailers → violation `:224-225`; `## Findings` on an approved review → violation `:317`; `- **CRITICAL**` under Observations → violation `:281`; `golden-path.sh:137-139,204-212` type/floor/range check, `invalid` denies, `excluded>0` requires equal `excluded_confirmed`; lowercase marker → malformed + not JSON (rc 1).
- **Effort dispatch:** `model-adapter.sh:313-332` `case low|medium|high|xhigh|max` else empty, skill name `^[A-Za-z0-9_-]+$`, appended as a quoted array element `:591`, exec'd as `"${invoke_args[@]}"`; `cheval.py:2630` argparse `choices=`; `claude_headless_adapter.py:319-322` allowlists after `strip().lower()` into a list argv; `flatline-orchestrator.sh:1022-1025` hardcodes by mode. `high; rm x` / `--foo` yield no flag (ED-3/ED-6).
- **Adapters (late Sprint 2 slices landed here):** truncation → `stop_reason=max_tokens` → `malformed_response` on the enforced branch (`adversarial-review.sh:996-1000`, `flatline-orchestrator.sh:348-352`); headless rejection match is a substring of the flag-prefixed CLI phrase on stderr only, gated by `returncode != 0` and `--json-schema` in the command (`claude_headless_adapter.py:94-95,162-165`); empty schema path → `INVALID_INPUT` exit 2 before any model call (`cheval.py:1269`); `_int_rate` (`pricing.py:200-216`) rejects nan/inf/negatives; new logging is the two pricing warnings only.
- **Executor and graders (beyond HIGH-001):** no `--dangerously-skip-permissions`; `--max-turns` and `timeout --kill-after` bound the run; argv array, no `eval`/`bash -c` (`execute-agent.sh:157-166`); skill name rejects `/` and dot-prefixed (`:93-95`); `executor.json` built with `--arg/--argjson` only (`:201-215`); the `result` event cannot be spoofed from model text (JSON-escaped, `:184-187`); no credential written to any artifact; `prompt_tree_sha`/dirty recorded and refused by `compare-ab.py:124-129`; sandbox is `mktemp -d /tmp/loa-eval-*` outside the repo (`sandbox.sh:149`); artifact names rejected on `/` or leading `..`; fixture ids regex-validated (`recall-vs-defects.sh:40`, `implement-discipline.sh:35`); manifests/expectations read from the repo, never the sandbox; guarded divisions and `int(... or 0)` parsing; grader errors exit 2; `grade.sh:108-109` invokes graders as an argv, `:129` empty output no longer parses as JSON; `--metric` whitelisted (`compare.sh:102`).
- **Prompt-budget gate:** no `eval`/`bash -c` (Python body, `:50`); `--root` without `.claude/` exits 2; sentinels `over` rc 1 / `under` rc 0 / real tree rc 0; the workflow gate is `jq -e '.ok'` with no `|| true` on the gate line (`check-prompt-budget.yml:35-38`) and `jq -e` exits 4 on an empty report.
- **Live probe:** `tools/ceiling-probe-live.py:101` key from `ANTHROPIC_API_KEY` only (exit 2 without it), URL hardcoded (`:41`), key only in request headers (`:59`), error paths echo bodies truncated to 300 chars, no Claude Code credential reuse; `tools/ceiling-probe.py` reverted to fixture-only. `live-floor-check.yml`: `workflow_dispatch` only (`:38`), `permissions: contents: read` (`:40`), `environment: live-floor` (`:51`), `set +x` (`:85`), secrets via env (`:79`).
- **Secrets:** key-shape scan over every added line in the range and over the force-added a2a record: 0 hits. `tools/check-ledger-hygiene.sh` OK (no test rows in the two `.run` ledgers); `tools/check-no-swallowed-jq.sh` OK; `tools/regen-model-artifacts.sh --check` OK.
- **Prompt compression:** all 46 keep-list rows match at HEAD; zone table, verdict-trailer one-way rule, run-mode recovery, Agent-Teams single-writer MUST rows (now unconditional), agent-network universal invariants, Karpathy floor, C-PROC-001 registry row, adversarial gates in both review skills, `LOA_ADVERSARIAL_REVIEW_ENFORCE`, audit ONE-WAY + tally, destructive/secrets CLI policy, `NEVER store secrets in git-tracked state` (`rules/zone-state.md:21`, unchanged) all present; 41 further moved/compressed rules traced to their HEAD location by the prompt-regression auditor (record in NOTES). The three archived protocols (`risk-analysis.md`, `sprint-completion.md`, `upgrade-process.md`) live under `grimoires/loa/archive/protocols/` and nothing under `.claude/`, PROCESS.md, CONTRIBUTING.md, tests or workflows instructs reading them (PR-1 re-run by grep; only the two allowlisted synthetic names remain). `constraints.json`: two `why` strings reworded, no rule text changed.
- **Dissenter surface:** the round-1 review dissent's rejected sidecar is empty (0 rows).

---

## Rubric scores (1–5)

| Dimension | Score | Basis |
|-----------|-------|-------|
| Security | 3 | fences/gates/effort/probe clean; HIGH-001 (unconfined executor) and the three verdict-derive consistency gaps |
| Architecture | 4 | executor/grader/compare separation and hidden-manifest design sound; freshness check hashes the wrong object |
| Code quality | 4 | argv discipline, guarded parsing, fail-closed graders; `summarize()`/`main()` justified shortcuts; loosened doc-locks recorded |
| DevOps | 4 | budget gate with positive/negative sentinels and `jq -e`; missing `permissions:` block; empty-scan pass |

---

## Documentation audit

No `documentation-coherence-*` reports exist for this sprint; verified manually: `CHANGELOG.md` `## [Unreleased]` carries an entry per Sprint 3 task (added in `d562d510`); the security-relevant code (`golden-path.sh` excluded/excluded_confirmed block, `verdict-derive.sh` FR-9 block, `model-adapter.sh` `resolve_effort`, `execute-agent.sh` header) is commented; no secrets or internal URLs in docs; no API change. The `execute-agent.sh` header's "fixed tool set" claim is corrected by HIGH-001's fix.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [ ] Agent under test confined to its sandbox (HIGH-001 — open)
- [x] Input validation on the new entry points (effort, trailer ints in golden-path, fixture ids, `--metric`, `--root`)
- [x] Fences and hooks unchanged
- [x] Error handling doesn't leak info (probe errors truncated; adapters log no bodies/keys)
- [x] Tests cover the gate paths (PB/PR/NH/VO/ED/EA/BF suites; gaps named above)

---

## Next Steps

1. `/implement sprint-3` (audit feedback pass): HIGH-001 fix in `evals/harness/execute-agent.sh` (+ `sanitize_env`, grader `env -i`) with the failing bats case first; header comment and `reviewer.md` AC-9.2 caveat; CHANGELOG line. Nothing else blocks.
2. Re-run `/review-sprint sprint-3` (focused round 3) and `/audit-sprint sprint-3` (round 2) — this file is rewritten on the re-audit; the round-1 record is kept as `auditor-sprint-feedback.round-1.md`.
3. Medium/low items carry as beads bd-vq7v, bd-sk1t, bd-tc3i, bd-zklv, bd-kqz4, bd-1ju5, bd-tjkx, bd-2a9g, bd-tdtr (+ bd-ts9l) and rows in the sprint plan's Sprint 3 follow-ups block.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":9,"low":15},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-3","ts":"2026-09-22T07:05:00Z"} -->
