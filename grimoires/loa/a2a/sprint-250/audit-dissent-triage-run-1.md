# sprint-250 audit dissent run 1: triage

- **Run.** The full Sprint 4 diff `2fcd4af8..db49cd32`, 2026-10-07T01:01:41Z–01:47:57Z, in sixteen chunks (`groups-250-audit.sh`: the review run 1 groups, plus the review-round files, `claude_headless_adapter.py`, `generate_test_licenses.py`, the SDD and the plan; DOCS split three ways; a new `b-bb` chunk for the Bridgebuilder sources). Coverage check: every changed file is in a chunk or in GENERATED.
- **Voices.** All sixteen chunks were two-voice [codex-headless (gpt-5.5-pro), claude-headless], the companion on `claude-bedrock` (KF-040). No chunk needed a retry.
- **Envelope.** `adversarial-audit-run1-merged.json`, which is also the current `adversarial-audit.json`.
- **Findings.** 51: 4 HIGH, 12 MEDIUM, 35 LOW. 46 from claude-headless, 5 from gpt-5.5-pro (all four HIGHs).
- **Rejected payloads.** None. `rejected_count` is 0 on every chunk; the five audit sidecars (g-gate, m1-pins, m2-pins, p2-platform, r-perms) are 0 bytes.
- **Size cap.** The dissenter skipped full-file context for eleven large files (`cheval.py`, `flatline-orchestrator.sh`, `constraints.json`, `model-adapter.sh`, …); the diff hunks were still reviewed.
- **Verification.** Two Opus 5.5 verifiers, read-only against `4d37029e`: `audit-dissent-run-1-verifier-A.md` (n1–26) and `audit-dissent-run-1-verifier-B.md` (n27–51). Each finding's evidence (file:line, probes, diffs against the sprint base) is in those files; this document records the lead's rulings and the actions.
- **Budget.** This is audit dissent run 1 of the 3 allowed for this sprint. Run 2 covers the round r250-6 fix delta.

## Headline

**No finding holds at HIGH or CRITICAL.** The four HIGH claims:

| n | Claim | Ruling |
|---|---|---|
| 5 | `anthropic:claude-headless` is classified `execution_mode: remote_model` while it is a local `claude -p` | **DECLINED** (repeats review run 1 n11). The adapter runs the CLI with `--permission-mode plan`, `--tools ""`, `--no-session-persistence`, in an isolated private cwd; `execution_mode` and `capabilities` have no runtime consumer — the only registry reader is `lookup_trust_scopes`, under a feature flag. No authorization boundary reads the row. |
| 13 | agy prompts still travel on argv | **PRE-EXISTING, tracked.** The agy adapter dates from #1089 (2026-06-24); claude- and gemini-headless use stdin. This sprint only relayed the existing WARN (bd-pw7e LOW-001). The opt-in / fail-closed gate is the maintainer-pending bead bd-ugmi. |
| 17 | a model can write `.loa.config.yaml` (`implement_gate.mode: authoritative`) and then self-attest `tool_input.active_skill: implement` for an unconditional allow | **TRUE mechanically, FIXED as a tightening (round r250-6).** No hook protects `.loa.config.yaml`, and the authoritative branch allowed a claimed implementation skill without the heuristic check. Before the sprint the mode was selected by the model-writable `.run/platform-features.json`, so the sprint already narrowed the selector; the branch body itself predates the sprint. Rather than argue severity, the branch now follows the rule the Fable reviewer's MED 1 also asked for: a model-authored claim may only tighten — a claimed implementation skill falls through to the heuristic, a claimed non-implementation skill asks and leaves an audit row. |
| 27 | `validate-skill-capabilities.sh` honours an ungated `AGENT_TYPES_FILE` env override | **REAL, LOW, FIXED (round r250-6).** Its only setter is the test file; the repo convention gates such overrides on the bats markers. Ungated `PROJECT_ROOT`/`SKILLS_DIR` predate the sprint and already gave the same power (follow-up bead). |

## Rulings

Verdict legend: FIX = changed in round r250-6, test-first; DOC = record change; REFUTED = false (evidence in the verifier file); DECLINED = true but by design, by plan, or already ruled; PRE-EXISTING = unchanged by this sprint's diff (a bead where it is a real defect).

| n | Sev | Area | Ruling | Action |
|---|---|---|---|---|
| 1 | LOW | `anthropic_adapter.py` beta-header regex (`$`, `\d`) | PRE-EXISTING, **FIX with n4** | `re.fullmatch` + `[0-9]`; the converse schema test. |
| 2 | LOW | `claude-opus-5-5` `probed_ceiling` 180K | DECLINED | The planned conservative ceiling (SDD amendment, `loa:shortcut`); a live probe is operator-only. Review run 1 n3/n4. |
| 3 | LOW | codegen T13 oracle vs `JSON.stringify` | REFUTED | `gen-bb-registry.ts:422-429` emits every alias through `JSON.stringify`. |
| 4 | LOW | V3 test asserts only schema ⊆ adapter | **FIX** | Add the converse assertion (`"…\n"`, Arabic-Indic digits); red first. |
| 5 | HIGH | claude-headless `execution_mode` | DECLINED | See Headline. |
| 6 | MEDIUM | same row, `kind: cli` | DECLINED | As n5; project hooks and settings are excluded by the isolated cwd. |
| 7 | LOW | trust-scope mirror test has no literal pins | **FIX** | Pin the reference row: every capability False, `security: redacted`; red first by mutation. |
| 8 | LOW | registry rows only for Anthropic entries | DECLINED (D-4.2 scope); gap is real | Bead: coverage test for every provider (`openai:gpt-5.5`, the `reviewer` default, has no row). |
| 9 | MEDIUM | trap body re-evaluated at composition | REFUTED | Probe: quotes, `;`, `$(…)` in a prior EXIT trap execute nothing at composition; `trap -p` output is re-input-safe. |
| 10 | MEDIUM | `flatline-proposal-review.sh` `.score` arithmetic injection | PRE-EXISTING (2026-02-03); real | Bead (P2): integer-check both scores; make the schema failure `return 4`; same audit for `flatline-validate-learning.sh`. The sprint changed only the model defaults. |
| 11 | LOW | model-adapter stderr temp file | DECLINED | mktemp 0600 under the operator's uid, removed inline and by the trap. |
| 12 | LOW | two `eval` sites in model-adapter | DECLINED (review run 2 #6) | Not exploitable; the n9 probe. |
| 13 | HIGH | agy argv | PRE-EXISTING, tracked | bd-ugmi. |
| 14 | MEDIUM | MA-5/6 test only the WARN relay | PRE-EXISTING, tracked | bd-ugmi; LOW-001's scope was the relay. |
| 15 | LOW | bats code under the persona hunk | REFUTED | Chunk-assembly mislabel (review run 1 n5/n23 class); the persona diff is one line, asserted by RES-4. |
| 16 | LOW | `map_value` awk + `bash -c` | DECLINED | Test helper over repo-owned scripts; callers pass literals. |
| 17 | HIGH | authoritative opt-in + forged `active_skill` | **FIX (tighten-only)** | See Headline. `expected.tsv` authoritative column: three `allow` → `ask`; IG-7 red first; new IG-12 proves authoritative is strictly tighter under a RUNNING state. Closes bd-8sxh with a `compliance.mode.model_signal` row. |
| 18 | MEDIUM | `active_skill` as proof | **FIX** | As n17. |
| 19 | MEDIUM | heuristic allows on a RUNNING `.run` state | PRE-EXISTING (review run 1 n24) | ADVISORY by design (hooks-reference); binding RUNNING to an unforgeable marker is its own cycle. |
| 20 | MEDIUM | `{"decision":"ask"}` is an invalid PreToolUse output | PRE-EXISTING (cycle-050), **FIX** | Must-fix: the installed harness's top-level `decision` enum is approve/block, so the gate's ask was never applied; this sprint's corpus codified the shape. Emit `hookSpecificOutput.permissionDecision: ask`; the bats `decision()` readers go red first. CHANGELOG line (operator-visible). |
| 21 | LOW | unsanitised `file_path`/`active_skill` in stderr | PRE-EXISTING, **folded into the n17 change** | `LC_ALL=C tr -d '[:cntrl:]'` before the echo and the audit row. |
| 22 | LOW | recorder fires before the App-Zone check | DECLINED (D-4.4) | Fixed strings only; the matcher admits no Bash payload. |
| 23 | MEDIUM | `/loa` labels the mode "authoritative" from config | DECLINED (D-4.4) | Honest label; superseded in substance by the n17 tightening. |
| 24 | LOW | `--line` passes U+202E/U+200B through | **FIX** | Printable ASCII only; shape-check `seen_at` and `source` in the refresh path; IG-10/13 red first. |
| 25 | LOW | prefix rule covers only exact/first-word/ALL | DECLINED (D-4.5) | `:*` is word-bounded in Claude Code; the fuzz set pins "narrower denies never cover the generic requirement". Embedded-newline split: operator-authored malformed JSON, advisory script. |
| 26 | LOW | "empty hunk" for the validator loader | REFUTED | The hunk is `:104-118`; structural yq, regex-checked names, fail-closed fallback (SC-T-AGENT-7/9). |
| 27 | HIGH | `AGENT_TYPES_FILE` ungated | **FIX (LOW)** | Bats-marker gate; SC-T-AGENT-10 red first. Bead: the same gate for `PROJECT_ROOT`/`SKILLS_DIR` (pre-existing). |
| 28 | LOW | env part + fallback + "mislabelled hunk" | FIX (dup n27) / DECLINED | The fallback is fail-closed (run 1 n36); yq v4 is a declared prerequisite. |
| 29 | LOW | deny detection on 3-word requirements | DECLINED (latent) | Every requirement is ≤ 2 words. Bead: a CP case pinning that, so a longer requirement forces the prefix rule. |
| 30 | LOW | sanitiser keeps UTF-8 C1 controls | **FIX** | Drop C2 80–C2 9F portably; a CMP-278 sibling with a C1 pair red first; `café` still passes. |
| 31 | LOW | hook-guard: missing target reads as "failed to parse" | PRE-EXISTING | Bead: `[[ -r ]]` check with a distinct WARN. The sprint changed only the WARN text. |
| 32 | MEDIUM | grader `python3 -` cwd module shadowing | PRE-EXISTING, **FIX** | Probe: a planted `json.py` forged `pass:true`. `python3 -I -`; RG-27 red first. The grader is the A/B instrument. |
| 33 | MEDIUM | grader: no precision term when planted > 0 | PRE-EXISTING / DECLINED | A recall grader by design (PRD FR-9); citations are reported; adjudication was blind. Bead: a precision/citation-volume field. |
| 34 | LOW | CITE path alternative quadratic on 200K tokens | PRE-EXISTING | Same class before the sprint (50K: 1.8 s vs 1.8 s); `grade.sh` wraps graders in `timeout`. Bead: byte cap + start anchor + `{1,512}` bound. |
| 35 | LOW | `$review_name` raw `%s` in JSON | PRE-EXISTING | Harness-sourced name. Bead: `jq --arg`, tighten the name class. |
| 36 | LOW | `agent_teams_constraints` block without a hash | DECLINED (run 1 n45/n47) | Hand-maintained block, byte-identical to `main`; the "generated" label is a pre-existing mislabel (optional DOC bead). |
| 37 | LOW | CLAUDE.loa.md ceiling "raised" to 10,240 B | DECLINED (run 1 n46/n53) | A restore of `main`'s own limit after the pre-registered revert (`bf988a43`). |
| 38 | LOW | resources charging regex | PRE-EXISTING, INFO | Documented accepted behaviour in the tool header. |
| 39 | LOW | `python3 -` in the budget tool and five new test sites | **FIX with n32** | `python3 -I -`; RG-27 pins the mechanism. |
| 40 | LOW | `constraints.json` flat map vs IDR-3 walker | REFUTED (run 1 n50) | The flat map is the fixture; IDR-3/4 pass 4/0/0. |
| 41 | MEDIUM | agy argv / gemini `--sandbox` fallback | PRE-EXISTING (sprint-248) | Comment on bd-ugmi: prompt via a 0600 file; gemini refuses `--sandbox`. |
| 42 | MEDIUM | `GIT_ATTR_SOURCE` on git < 2.41 | PRE-EXISTING (sprint-248) | Bead: `--text --no-textconv --no-ext-diff` or refuse. |
| 43 | LOW | fail-open run-lock paths | PRE-EXISTING / DECLINED | Sprint-248 design, each with a WARN. |
| 44 | LOW | `--record-fallback --since` caller-chosen | PRE-EXISTING | Optional bead: pin `--since` to the logged run start. |
| 45 | LOW | `GEMINI_SANDBOX=false` | PRE-EXISTING | Documented trade-off in an isolated cwd. |
| 46 | LOW | CHANGELOG on the undocumented opt-in | DECLINED (run 1 n24) | DOC: one SDD D-4.4 sentence on the tighten-only rule lands with round r250-6. |
| 47 | LOW | companion opt-out indistinguishable from `no_route` | PRE-EXISTING, partly refuted | `planned:false` without `reason` is the opt-out; `reason: no_route` is distinct. |
| 48 | LOW | KF-040 presents Bedrock as the run mode | **DOC** | Attempts row appended via `kf-write-lib.sh`: a geo 400 is an access-control decision, never an automatic fallback trigger; the Bedrock route is an operator decision. |
| 49 | LOW | 4-7 scopes copied to every entry release more | REFUTED | A row-less model gets no filtering at all; the new rows are strictly more restrictive. |
| 50 | LOW | alias coercion in gen-bb-registry | DECLINED (run 2 n1/n2) | T13 pins the `opus` row. |
| 51 | LOW | `effectiveInputBudget` fail-open for unknown ids | DECLINED (not a regression) | Pre-sprint behaviour; the alias hop narrows it. Comment on bd-j8v1: a construction-time WARN. |

**Counts.** FIX 12 (n1, 4, 7, 17, 18, 20, 21, 24, 27, 28-part, 30, 32, 39), DOC 2 (n46, n48), REFUTED 6 (n3, 9, 15, 26, 40, 49), DECLINED 16, PRE-EXISTING 15 (beads for n8, 10, 29, 31, 33, 34, 35, 42, 44; comments on bd-ugmi for n13/14/41 and on bd-j8v1 for n51).

## Round r250-6 outcome

Committed as `e151757d` (pushed). Two Opus 5.5 implementers worked on disposable worktrees (`wt-r250-6` for the gate, `wt-r250-7` for the rest); the lead reviewed both patches, applied them to the real tree, regenerated REPO-MAP and checksums, and ran the suites. Each item was red first (the test or corpus change landed before the code change).

| n | Outcome |
|---|---|
| 20 | **Fixed.** Both ask sites emit `hookSpecificOutput.permissionDecision: ask` with the reason. `implement-gate.bats` `decision()` now accepts only that shape (and reports `invalid:<output>` for anything else); CH-T8/T10 assert it and assert the old `"decision":"ask"` is absent. Against the old emit every ask case is mechanically red. |
| 17, 18 | **Fixed (tighten-only).** The implementation-skill case no longer `exit 0`s; it falls through to `check_implementation_active`. `expected.tsv` authoritative column: `write-src-active-implement`, `edit-lib-active-bug`, `write-src-subagent-run` `allow` → `ask` (IG-7 red on the old branch). IG-12: with a RUNNING state, heuristic allows `write-app-active-review.json` and authoritative asks, writing exactly one `compliance.mode.model_signal` row; a claimed `implement` allows with RUNNING and asks without. CH-T8 retitled accordingly. Closes bd-8sxh. |
| 21 | **Fixed (folded).** `safe_file_path`/`safe_skill` via `LC_ALL=C tr -d '[:cntrl:]'` before stderr and the audit row; IG-13 feeds `\u001b[31m`, `\u007f`, `\u0007`, `\r\n`. |
| 24 | **Fixed.** `--line` output is `LC_ALL=C tr -cd '[:print:]'`; the refresh keeps `active_skill_seen_at` only when it matches `\A[0-9]{4}-…Z\z` and `active_skill_source` only when it is `tool_input`. IG-14 feeds U+202E / U+200B and a forged source. |
| 27 | **Fixed.** `AGENT_TYPES_FILE` is honoured only when `BATS_TEST_FILENAME`/`BATS_VERSION` is set; SC-T-AGENT-10 runs the validator with the markers unset and a permissive file, expecting exit 1 and the `agent type 'Plan'` message. SC-T-AGENT-8/9 unchanged. |
| 30 | **Fixed.** A bash loop removes C2 80–C2 9F from `top_path_log` after the C0 `tr` (`printf -v` builds each pair; no GNU-sed `\x`). CMP-279: `src/a\xc2\x9b2J\xc2\x9db\xc2\x80\xc2\x9f.sh` logs as `src/a2Jb.sh`, no pair reaches stderr, and `src/café.sh` is verbatim. |
| 32, 39 | **Fixed.** `python3 -I -` at the grader, `check-prompt-budget.sh`, IDR-3, LFF-1/3/4 and RES-5. RG-27 plants a `json.py` that prints `{"pass":true,"score":100,"forged":true}`; from that cwd the old grader returned it with exit 0, the new one returns `pass:false`, no `forged` key, `grader_version` 1.1.2. |
| 1, 4 | **Fixed.** `_BETA_HEADER_RE` = `^[a-z0-9]+(-[a-z0-9]+)*-[0-9]{4}-[0-9]{2}-[0-9]{2}$` with `fullmatch`; `test_beta_header_allowlist_regex_is_the_documented_one` follows. The V3 bats case asserts pattern equality with the schema string and the converse: every value the ECMA reading rejects (`…\n`, `…\r\n`, Arabic-Indic digits, trailing space, leading newline) raises `ConfigError`. |
| 7 | **Fixed (test).** `test_mirror_reference_row_is_literally_pinned`: the 4-7 row's capabilities are all False and `context_access.security == "redacted"`; red by mutating the worktree's YAML to `security: full` (restored before the patch). |
| 48 | **Recorded.** KF-040 Attempts row appended via `kf-write-lib.sh attempt` (evidence: verifier B n48, `4d37029e`). |
| beads | bd-z5yw (n10), bd-lemw (n8), bd-7cur (n27 `PROJECT_ROOT`/`SKILLS_DIR`), bd-mt9c (n29), bd-gm9p (n31), bd-muk5 (n33), bd-6x75 (n34), bd-s03k (n35), bd-2rhn (n42), bd-w8lj (n44), bd-x2rp (n36); comments on bd-ugmi (n13/14/41) and bd-j8v1 (n51). |

**Suites, real tree, serial (ok / not ok / skip):** implement-gate 14/0/0, compliance-hook 14/0/0, skill-capabilities 36/0/0, eval-recall-grader 27/0/0, prompt-budget 9/0/0, instruction-diet-revert 4/0/0, license-fixture-freshness 5/0/0, model-residue 7/0/0, model-config-v3-schema 33/0/0, adversarial-review-companion `-f 'CMP-27[89]'` 2/0/0, repo-map-gen 6/0/0, loa-status-providers 4/1/0 in the batch (LSP-1, the recorded load flake; 3/3 alone). Adapters pytest `-k 'anthropic or beta or thinking or trust or full_size'`: 396 passed, 279 subtests. `regen-checksums --check` changed=0; `check-prompt-budget.sh` exit 0; `bash -n` clean on the six changed shell files.

**Docs:** CHANGELOG `[Unreleased]` — one Changed bullet (tighten-only) and two Fixed bullets (the ask shape; the audit-round hardening); SDD D-4.4 amendment 2026-10-07.

**Audit dissent run 2** covers this delta (`4d37029e..e151757d`) in three chunks: a6-gate, a6-misc, a6-docs.
