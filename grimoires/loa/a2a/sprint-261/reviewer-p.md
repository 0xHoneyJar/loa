# Sprint 261 fix implementer P: codex pre-flight 6 refinements (DISS-C-003, DISS-C-004)

Worktree `/home/merlin/Documents/thj/code/loa-wt-s4p` at 4af3294b. Files changed: `evals/harness/run-ablation.sh`, `evals/tests/run-ablation.bats` (plus this report copy).

## What was built (file:line in the worktree)
- `evals/harness/run-ablation.sh:331` reads `LOA_ABLATION_CODEX_HORIZON_S`; `:414` validates it as positive whole seconds, 1 to 999999999, else `die` (exit 2, usage error, before any batch dir is created).
- `:806-813` writes `$WORK/codex-scope.json` (resume flag, rows file, batch, --rerun ids, --rerun-status statuses, --rerow ids) for the pre-flight.
- `:836-848` `remaining()`: the plan entries this invocation launches. Fresh batch or dry run: all. On --resume: entries with no row of this batch, plus --rerun ids, plus rows whose status is a --rerun-status (never a --rerow id), mirroring the reconciliation loop at the resume block.
- `:850-858` horizon: `required_until = now + override` (`horizon_source: "override"`) or `now + 2 x sum(watchdog_s of remaining) / concurrency` (`"plan"`); `trials_counted = len(remaining)`.
- `:866-877` API-key mode: no usable `tokens.access_token` and a non-empty string `OPENAI_API_KEY` passes with `auth_mode: "apikey"`, `checked: false`, `token_exp: null`, and a stderr note (`:903-904`). Neither present: refused, the reason names both remedies. A non-object JSON is refused as "is not a JSON object"; "is not JSON" now names both remedies too.
- `:891-896` the expiry refusal now says `now + 2 x summed watchdog of <n> trial(s) / concurrency` or `now + LOA_ABLATION_CODEX_HORIZON_S`.
- `:1148` STATUS.json gains `codex_preflight` (this invocation's record); MANIFEST.json keeps the start's (unchanged rule: a resume never rewrites MANIFEST.json).
- Header: pre-flight 6 paragraph (`:110-131`), MANIFEST `codex_preflight` fields (`:236-244`), STATUS.json `codex_preflight`, Env list (`LOA_ABLATION_CODEX_HORIZON_S`, `LOA_EVAL_CREDS_HOME`). `codex_token_exp` keeps its meaning.

## codex_preflight shape as built
```
{checked: bool, auth_file_present: bool, codex_arms: [arm...],
 token_exp: ISO|null, required_until: ISO|null,
 auth_mode: "chatgpt"|"apikey"|null,
 trials_counted: int|null, horizon_source: "plan"|"override"|null}
```
`auth_mode`, `trials_counted`, `horizon_source` and `required_until` are null when the check was skipped (smoke, no codex arm) or no auth.json exists. `auth_mode` is "chatgpt" once a non-empty `tokens.access_token` string is found (even if the JWT is then malformed and refused).

## Tests (evals/tests/run-ablation.bats)
| Case | Before (HEAD script) | After |
|---|---|---|
| RAB-35 API-key auth.json accepted, note once, key never printed, `tokens: null` variant | fail | pass |
| RAB-36 neither token nor key refused, both remedies named | fail | pass |
| RAB-37 --resume with 3 of 4 rows, token between one trial's and the plan's horizon: not refused, STATUS trials_counted 1, MANIFEST keeps 4; same token refuses a fresh dry run of the plan; --rerun-status brings a row back (trials_counted 1) | fail | pass |
| RAB-38 override 60 s vs a 120 s token: accepted, `override`; override 600 refused naming the override; `abc`, `0`, `-5`, `1.5` usage errors | fail | pass |

Literals changed in existing cases: RAB-28 (refusal text now `... summed watchdog of 1 trial(s) / concurrency ...`), RAB-30 (`codex_preflight | keys` gains `auth_mode`, `horizon_source`, `trials_counted`; added an assertion `chatgpt 2 plan`), RAB-32 (full-object literal gains the three null keys). With the old test file and the new script exactly those three fail; nothing else changed.

## bats counts
- Before: 414/414 (per the brief at HEAD; my own first run used the old test file with the new script: 411/414, the three literals above).
- After: 418/418 (`evals/tests/`, the four new cases RAB-35 to RAB-38 included).

## DECISIONS
- DECISION: the resume horizon counts plan entries with no row of this batch PLUS --rerun ids PLUS rows whose status is a --rerun-status (excluding --rerow ids); this mirrors the resume reconciliation exactly, so it was simple.
- DECISION: a paused arm's unrowed trials still count (conservative; they launch once --clear-arm is given, and --clear-arm is not modelled). The override covers any excess.
- DECISION: on --resume trials_counted is recorded in STATUS.json `codex_preflight` (this invocation's record), because MANIFEST.json keeps the start's record; the fresh start writes the same record to both.
- DECISION: `auth_mode`, `trials_counted`, `horizon_source` are null when no horizon is computed (smoke, no codex arm, no auth.json), matching `required_until`.
- DECISION: API-key mode is decided by the file's content, not its `auth_mode` field: no non-empty `tokens.access_token` string and a non-empty (after strip) `OPENAI_API_KEY` string. A file with a usable access token is treated as ChatGPT mode even if it also carries a key.
- DECISION: the override bound is 999999999 s (about 31 years), validated like the other `LOA_ABLATION_*` knobs; it still applies the exp comparison, it does not skip the check; the override also applies on --resume and --dry-run.
- DECISION: "is not JSON" and the new "is not a JSON object" reasons name both remedies, since either a login or an API key fixes them; JWT-shape and exp failures keep "run codex login on the host" only.
- DECISION: the expiry refusal text names the trial count or the override, so RAB-28's literal was updated.

## Could not do / limitations
- The rows file is read once by the pre-flight before --rerow replaces rows; a --rerow id is never rerun, so the count is unaffected.
- Not tested against a real codex 0.162.1 API-key auth.json; the shape follows the brief (`OPENAI_API_KEY`, optional `auth_mode`, no `tokens`).

## Handoff notes
- Apply `~/.cache/loa/cycle-130/patches/s4-p.patch`. No shared file touched. The bats markers are not needed (operator knob).
