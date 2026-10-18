# Sprint 261 implementer C: the KF-048 credential-copy fix and the codex token-freshness preflight

Status: done. Worktree `/home/merlin/Documents/thj/code/loa-wt-s4c` at d80c5c32, not committed.

## What was built
- `evals/harness/pipeline-run.sh:610` `make_home()`: `config.toml` is copied verbatim as before. `auth.json` now goes through a `python3 -I -c` stdlib step that gets only the two paths in argv. It reads the host file, drops `tokens.refresh_token`, keeps every other key (known or unknown), and writes the per-run copy with `os.open(..., O_WRONLY|O_CREAT|O_TRUNC, 0o600)` plus `fchmod 0600`. If the file is not JSON or not an object, no copy is written and one WARN line goes to stderr (line 640). The host file is opened read-only. The header comment at line 84 and the per-run HOME block comment at line 600 explain the KF-048 reason.
- `evals/harness/run-ablation.sh:780`: pre-flight 6, codex token freshness. It runs after the plan is built (`$WORK/plan-only.json`) and before any MANIFEST is written. A refusal goes through `refuse` (REFUSED.txt, exit 2). It applies to fresh, `--resume` and `--dry-run` batches and is skipped for `--smoke`. MANIFEST gains `codex_token_exp` and `codex_preflight` (line 903). The header documents pre-flight 6 at line 110 and the MANIFEST fields at line 227.

## Interface as built
`codex_preflight` shape in MANIFEST.json (keys sorted):
```
{"auth_file_present": bool, "checked": bool, "codex_arms": ["a1_full", ...], "required_until": "YYYY-MM-DDTHH:MM:SSZ"|null, "token_exp": "YYYY-MM-DDTHH:MM:SSZ"|null}
```
Top-level `codex_token_exp` equals `codex_preflight.token_exp`.

Refusal lines, written to REFUSED.txt as `reason: …` and to stderr as `run-ablation: refused: …`:
```
codex access token expires <ISO>, before the batch's required horizon <ISO> (now + 2 x summed watchdog / concurrency; KF-048) — run codex login on the host
codex auth.json <path>: is not JSON (KF-048) — run codex login on the host
codex auth.json <path>: has no tokens.access_token (KF-048) — run codex login on the host
codex auth.json <path>: tokens.access_token is not a three-part JWT (KF-048) — run codex login on the host
codex auth.json <path>: the access token's JWT payload does not decode (KF-048) — run codex login on the host
codex auth.json <path>: the access token has no numeric exp claim (KF-048) — run codex login on the host
```
Warnings:
```
run-ablation: WARN no codex auth.json under <creds>/.codex; codex-using arms will run without the OpenAI voice
pipeline-run: WARN codex auth.json unreadable; the run has no codex credential
```
`required_until = ceil(now + 2 × Σ plan[].watchdog_s / concurrency)`. The batch is refused when `exp <= required_until`.

## Tests added (each fails on d80c5c32 and passes now)
- pipeline-run.bats "container: KF-048 — the per-run auth.json has no tokens.refresh_token, keeps every other key, mode 0600; the host file is untouched". A test-local docker wrapper snapshots the mounted HOME's `.codex/` before the stub runs, because the HOME is deleted at exit. The test also checks that no token value appears in the docker argv.
- pipeline-run.bats "container: KF-048 — an unreadable auth.json …". Covers not-JSON input: one WARN line, no copy, exit 0.
- pipeline-run.bats "container: KF-048 — a JSON auth.json that is not an object is unreadable too".
- run-ablation.bats RAB-28: an expired token on a fresh batch is refused, with no MANIFEST and no pipeline call. RAB-29: a token expiring inside the horizon is refused. RAB-30: a fresh token is accepted, with exp at second precision and required_until about now + 17,600 s. RAB-31: a0_bare only is not refused, with checked false and `[]`. RAB-32: no auth.json gives a WARN and null. RAB-33: `--smoke` skips the check. RAB-34: `--dry-run` with an expired token is refused, and so are a non-JWT token, a token with no exp, and a non-JSON file.
- The existing home-listing case at pipeline-run.bats:790 still passes. The setup's `{}` is copied as `{}`.

## bats counts
| | before | after |
|---|---|---|
| evals/tests/ (whole) | 386/386 | 396/396 |
| pipeline-run.bats | 60/60 | 63/63 |
| run-ablation.bats | 28 | 35 |

## Decisions
- DECISION: A host auth.json that is present but not JSON, or JSON but not an object, produces no per-run auth.json and one `pipeline-run: WARN codex auth.json unreadable; the run has no codex credential` line on stderr. The run proceeds, and the row writer flags the missing voice as a degradation. Any other failure of the copy step, such as a write error, takes the same path.
- DECISION: `tokens` that is not an object is copied unchanged. Only a `refresh_token` key inside a `tokens` object is removed. A top-level `refresh_token` is not part of the codex format and is left alone.
- DECISION: run-ablation.bats setup now exports `LOA_EVAL_CREDS_HOME="$T/creds"`, an empty `.codex/`. Without it, every non-smoke RAB case would read the operator's real `~/.codex/auth.json`, and the suite would pass or fail with the host token's age. Existing cases now see the missing-file WARN, which no existing assertion depends on.
- DECISION: `checked` is true only when the token was read and its exp compared. That includes the refusal path, though a refused batch writes no MANIFEST. A missing file, a smoke batch, or a plan with no codex arm records checked false. A missing file also records `auth_file_present: false`.
- DECISION: The pre-flight runs after the plan is built, because it needs `plan-only.json`. That puts it after the other pre-flights, not directly after the hard gate. It still runs before any MANIFEST write or dispatch.
- DECISION: On `--resume` the horizon sums the whole recorded plan, not just the remaining trials. This is conservative and simple. A resume does not rewrite MANIFEST.json, so the start's `codex_preflight` record stays. The check still runs and can still refuse.
- DECISION: The horizon uses each plan entry's `watchdog_s`, as the brief specifies. It ignores `--watchdog-s`/`LOA_ABLATION_WATCHDOG_S` overrides and the grace period.
- DECISION: `codex_arms` lists the planned arms, sorted, whose suite toggles do not set `loa_mount: false`. An arm missing from the suite counts as codex-using. A smoke batch still lists its codex arms but records checked false.
- DECISION: A float exp is truncated to an integer. A boolean or non-finite exp counts as "no numeric exp".
- DECISION: Malformed-token refusals name the auth.json path, which is not a secret. No refusal or warning prints any token content.

## Could not do / limitations
- No dedicated bats case covers the `--resume` path of the pre-flight. It runs the same code on the recorded plan.
- There is no live check that the codex CLI works with an access-token-only auth.json inside the image. Until the token expires codex should not need to refresh, but the first real a1_full row is the proof.

## Handoff notes for the lead
- Run `--dry-run` for priority-v2-p1b first. With the operator's token valid to 2026-10-28, the horizon is about 2 × Σ watchdog / 3, so it should pass. MANIFEST.json then shows `codex_token_exp`.
- KF-048's ledger entry can record this patch as the attempt once the lead commits it.
- The report copy at grimoires/loa/a2a/sprint-261/reviewer-c.md is gitignored (.gitignore:193), so the patch does not carry it.
