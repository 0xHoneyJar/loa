# Sprint sprint-bug-283 — Implementation Report (bug 20261028-90f357)

**Engineer:** lead (Claude Fable 5.1), under `/bug` → implement on `fix/post-merge-release-readback` from `main` 2abe98199
**Date:** 2026-10-29
**Bug:** post-merge publisher: release read-back fails when GitHub rewrites backslash-u control escapes in the release body (KF-064, bead bd-0atxs)
**Triage:** `grimoires/loa/a2a/bug-20261028-90f357/triage.md` (score 4 ACCEPT, severity medium, integration test, risk medium)
**Ledger:** `cycle-bug-20261028-90f357`, sprint `sprint-bug-283` (ledger commit 46962aab0)

## Commits (red first)

| Role | SHA | Files | What |
|---|---|---|---|
| Red commit | **698ab4eca** | `tests/unit/post-merge-publication.bats` | the `gh` stub gains `GH_BODY_REWRITE=caret` (stores the POSTed body the way GitHub does: a literal `\u00XX` escape of a C0 control or DEL becomes caret notation `\^<c>`; observed on v2.0.0-rc.9); case A (red): a merge whose commit subject quotes `\u0000-\u001f` → the candidate body quotes it → publish under the rewrite must end DONE with one POST, the ledger pushed, the stored body rewritten and the sealed candidate untouched; case B (guard): under the same rewrite a pre-existing release whose body differs by an appended line still fails read-back, nothing pushed |
| Bridgebuilder adoptions | **50ee08bbc** | `.claude/scripts/post-merge-orchestrator.sh`, `.claude/checksums.json`, REPO-MAP, `tests/unit/post-merge-publication.bats`, fixture README | PR #1313 round 1 (2/2 voices, 0 blockers): refusal message without the tool-claim prefix (F-002); success receipt `body_match` (F-012); README observed-vs-assumed mappings + GitHub display note (F-005, F-007); cleanup assertions in the four publish-path cases (F-004); F1 refuted by `cmp` (GitHub's diff view rendered the escapes in caret form); 71/71; red-test-check VERIFIED against this head |
| Decisions | **a687dbe09** | `grimoires/loa/decisions.yaml` | DEC-1141 (the tolerance and its shape), DEC-1142 (round 3 lead-only), DEC-1143 (literal rc.9 fixtures) |
| Audit hardening | **af514ab6a** | `.claude/scripts/post-merge-orchestrator.sh`, `.claude/checksums.json`, REPO-MAP, `tests/unit/post-merge-publication.bats` | audit DISS-C-001 … C-004 (all LOW): a non-object read-back refuses in python; the comparison's temp directory is removed by a `RETURN` trap; a failed `mktemp` for the stderr capture is a recorded phase failure; the test setup exports `TMPDIR` under the case directory and the big-body case asserts the comparison left nothing behind; 71/71; red-test-check VERIFIED against this head (`logs/rtc-bug-283-final.json`) |
| Review r2 red | **ceaeba1f8** | `tests/unit/post-merge-publication.bats` | red: `release_body_identical` on a 200 000-byte body and a read-back JSON above 131 072 bytes must print `equal` (on 64e8eabf8: `jq: Argument list too long`); guards: the production comparator maps the REAL rc.9 pair to `equal` and refuses a one-caret shift (`\^@` → `\^A`); the fixture precondition uses `run cmp -s` + status |
| Review r2 fix | **462d4fd80** (+ test correction **36fcbbfe5**) | `.claude/scripts/post-merge-orchestrator.sh`, `.claude/checksums.json`, REPO-MAP; the big-body fixture trimmed like the sent side | one shared `RELEASE_BODY_CARET_PY` definition for both helpers; `release_body_identical` writes both inputs to a `mktemp -d` directory with the `printf` builtin (no argv-borne bodies, no jq) and one `python3 -I` reads bytes, normalises and prints `equal` / `differ a b`; the refusal message carries python's last stderr line; 71/71; red-test-check VERIFIED (`logs/rtc-bug-283-r2.json`: red fails only the big-body case) |
| Review r1 red | **1c7588151** | `tests/unit/post-merge-publication.bats`, `tests/fixtures/post-merge/rc9-release-body/{candidate-line,github-line}.txt,README.md` | red: under the caret rewrite a stored body with two appended newlines must still fail read-back (status 0 on 00597308e — the command-substitution strip); guards: a CRLF-only difference fails; `release_body_normalize` maps the REAL rc.9 candidate line onto GitHub's stored line (literal captures) and a five-entry caret table (NUL, TAB, FS, US, DEL; `A`, `ÿ` untouched) |
| Review r1 fix | **64e8eabf8** | `.claude/scripts/post-merge-orchestrator.sh`, `.claude/checksums.json`, REPO-MAP | `release_body_identical <sent> <readback-json>`: jq builds `{sent, read}` → one `python3 -I` normalises both and prints `equal` / `differ <a> <b>`; `phase_release` refuses on any other output (python3/jq failure, unparsable read-back); `release_body_normalize` is bytes-in/bytes-out (no newline translation) for direct callers; 69/69; red-test-check VERIFIED (`logs/rtc-bug-283-r1.json`: red fails only the trailing-newline case) |
| Hardening commit | **00597308e** | `.claude/scripts/post-merge-orchestrator.sh`, `.claude/checksums.json` | both normaliser calls guarded: a non-zero exit (no python3, a crash) or an empty result for a non-empty body records a named release failure instead of a bare `set -e` abort or an accidental pass (the lead's own review, concern 3; no behaviour change on the happy path — 66/66) |
| Fix commit | **f2b3d97e9** | `.claude/scripts/post-merge-orchestrator.sh`, `.claude/checksums.json`, `grimoires/loa/REPO-MAP.md{,.checksum}` | `release_body_normalize` (one `python3 -I -c` text transform: `\u00XX` with XX ∈ 00–1F, 7F → `\^` + `chr(XX+64)`, DEL → `\^?`), applied to BOTH the sent notes and the read-back body before the comparison; `id`, `tag_name`, `draft`, `prerelease`, `name` unchanged exact; the failure reason now lists the mismatching terms and both normalised lengths; manifests regenerated under the bounded marker |

## Evidence

- **Red run** (698ab4eca, unfixed orchestrator): `bats tests/unit/post-merge-publication.bats -f bug-283` → case A `not ok` with the production transcript (`[TAG] Verified v1.0.1 …` then `[release] Release identifier or read-back mismatch`, publish status 1); case B `ok`.
- **Fix run** (f2b3d97e9): the whole file 66/66 ok (64 existing + 2 new).
- **red-test-check:** `red-test-check.sh --json --timeout 1500 --env-pass PYTHONUSERBASE --red 698ab4eca --green HEAD -- bats tests/unit/post-merge-publication.bats` → `VERIFIED` (red exit 1 failing only `bug-283 … publishes DONE`; green exit 0; red-again exit 1) — `~/.cache/loa/cycle-137/logs/rtc-bug-283.json`. (A first run without `--env-pass PYTHONUSERBASE` reported `GREEN_FAILS` because the sandbox could not import `rfc8785` for `jcs-helper.py` — an environment effect on the `recanon` cases, not the change; same recipe as Sprint 282's pytest runs.)
- **Real-world proof:** the normaliser applied to the v2.0.0-rc.9 candidate `release_body` equals the body GitHub stored for release 426462979 (`norm(sent) == github`: true; raw: false) — the exact production mismatch is reconciled, nothing else changes.
- **Manifests:** `gen-checksums.sh` 2080 entries OK, `repo-map-gen.sh --validate` consistent, `check-manifest-paths.sh` 0 untracked / 0 missing, `check-loa.sh` All checks passed on f2b3d97e9.

## Acceptance criteria (micro-sprint)

| Criterion | Status |
|---|---|
| Failing test reproduces the bug; committed alone before the fix | Pass — 698ab4eca, `not ok` on the unfixed script with the production message |
| Fix is a later commit and does not weaken the test (`red-test-check.sh` exits 0) | Pass — f2b3d97e9, VERIFIED |
| No regressions | Pass — 66/66 in the file; the change is confined to `phase_release`'s comparison (no other phase touched) |
| Root cause, not symptom | Pass — the comparison tolerates exactly GitHub's documented storage rewrite and nothing else (case B pins it); the sealed candidate is never modified |

## Judgment calls

- **No `--ledger-only` widening.** With the fix, a re-run of `--publish` on a FAILED receipt completes the pending `ledger` and `notify` phases (the runbook's retry path, test "crash after the release is created: the re-run reuses it"), so the recovery gap closes without a new flag. Recorded in the triage constraints.
- **python3 for the transform** rather than awk/sed: the publication path already requires python3 (`jcs-helper.py`); `-I` isolates it from the caller's site; the regex is the whole specification of the rewrite.
- **The rc.9 release is not re-published.** Its ledger write landed through the archive PR #1311; a re-run would try to push the candidate's ledger commit onto a main that has moved (deferral path). Verified by hand instead (e2e.md § G-6).
- **Branch name without a cycle id** (`fix/post-merge-release-readback`) so the merge classifies `other` (DEC-1004); the Bugfix-or-Other job prepares an rc.10 candidate that this sprint does not publish.

## Deviations

None from the micro-sprint plan.
