# Security analysis working notes — sprint-bug-283 audit (bug 20261028-90f357, KF-064)

Scope: `git diff 46962aab0..<head> -- .claude/scripts/post-merge-orchestrator.sh tests/unit/post-merge-publication.bats tests/fixtures/post-merge/rc9-release-body/` — the release phase's read-back comparison, its test stub, two literal fixtures. Statuses: SAFE / PARTIAL / CONFIRMED / N/A.

## Sources (untrusted inputs reaching the changed code)

| # | Source | Trust | Reaches | Guard | Status |
|---|---|---|---|---|---|
| S1 | GitHub API release read-back JSON (`gh api repos/…/releases/<id>` or `/releases/tags/<tag>`) | UNTRUSTED (remote service; a hand-edited release) | `release_body_identical "$notes" "$readback"` → `jq -n --argjson rb` → python `json.load` → regex → `equal`/`differ` token | the body is DATA to jq (`--argjson`) and to python (`json.load`); never evaluated, never written anywhere; a non-JSON or invalid-UTF-8 response makes jq/python exit non-zero → named refusal | SAFE |
| S2 | The sealed candidate's `release_body` (`$notes` = `RELEASE_BODY`) | TRUSTED (approved digest, verified before any phase) | the same comparison as the SENT side | passed as a jq `--arg` (data); the candidate file is never rewritten | SAFE |
| S3 | The verdict token printed by python | internal | `[[ "$body_verdict" != equal && "$body_verdict" != differ\ * ]]` → refusal unless exactly one of two shapes | python `-I` (no site, no env hooks); stderr dropped; any extra stdout fails the shape test → refusal | SAFE |
| S4 | Test fixtures `tests/fixtures/post-merge/rc9-release-body/*.txt` | REPO (literal captures of public release-note text) | the fixture test only | no secrets (a Bridgebuilder finding sentence about `.reviewignore` globs); read-only | SAFE |

## Sinks

| # | Sink | Guard | Status |
|---|---|---|---|
| K1 | `gh api --method POST …/releases` (release creation) | unchanged by this sprint; still gated by `publish_gate release` (main contains the merge) and the sealed title/body/flags | N/A (unchanged) |
| K2 | `python3 -I -c '<static program>'` | program text is a literal in the script; inputs arrive on stdin as JSON; `-I` isolates site-packages and PYTHON* env | SAFE — no interpolation of body text into the program |
| K3 | `jq -nc --arg sent "$1" --argjson rb "$2"` | both values are jq arguments (data); `--argjson` requires valid JSON → otherwise non-zero → refusal | SAFE |
| K4 | `fail_phase release "… (terms: ${mismatch}; …)"` → state receipt | `mismatch` is built by a static jq program from fixed strings and two integers; no body text enters the receipt | SAFE (no body disclosure beyond lengths; bodies are public anyway) |
| K5 | `.claude/checksums.json` / REPO-MAP | regenerated under the bounded marker at each System Zone commit; `check-loa.sh` All checks passed | SAFE |

## Properties to confirm at audit time

- **Fail closed**: python3 missing, jq missing, invalid JSON, invalid UTF-8, empty read-back → refusal (no `equal`). Evidence: the shape test on the token; `set -euo pipefail` with the explicit `if ! …` capture.
- **Tolerance is exactly GitHub's rewrite**: `\u00XX` with XX ∈ 00–1F or 7F → `\^` + `chr(XX+64)` (DEL → `\^?`), applied to both sides; anything else (CRLF, trailing newlines, an appended line, `\^A` vs `\u0000`) refuses. Evidence: cases A/B, r1 CRLF + trailing-newline cases, the caret table, the real rc.9 pair (`equal`), tampered (`differ`), CRLF (`differ`).
- **The sealed candidate is never modified**: the fixture test checks the digest after a publish; `--argjson`/`--arg` are read-only.
- **No new flag, config or dependency** (python3 and jq already required on the publish path).
