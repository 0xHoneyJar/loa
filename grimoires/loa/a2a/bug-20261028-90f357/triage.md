# Bug Triage: post-merge publisher: release read-back fails when GitHub rewrites backslash-u control escapes in the release body (KF-064)

## Metadata
- **schema_version**: 1
- **bug_id**: 20261028-90f357
- **classification**: logic_bug
- **severity**: medium
- **eligibility_score**: 4
- **eligibility_reasoning**: reproducible steps (+2: re-running `--publish` from the approved candidate reproduces the failure deterministically — done twice on 2026-10-28); error log from a production incident (+1: the publish output and the state receipt `~/.cache/loa/cycle-137/publish-checkout-rc9/.run/post-merge-state.json`, phase release failed, ledger + notify pending); regression from a known baseline (+1: v2.0.0-rc.8 published through the same C-3 path on 2026-10-24 with a body that carried no backslash-u text). No disqualifier (no new endpoint, UI, schema or configuration). Severity medium: a workaround exists (the tag and release were verified by hand; the archive PR carried the ledger write), but every future release whose body quotes a backslash-u escape fails the same way.
- **test_type**: integration
- **risk_level**: medium
- **created**: 2026-10-28T23:06:02Z

## Reproduction
### Steps
1. Merge a PR whose commit subjects include a literal backslash-u control escape, e.g. ``a `\u0000-\u001f` range`` (cycle-137's loop commit about the KF sanitiser did), so the prepared candidate's `release_body` contains that text.
2. Publish the candidate from an isolated clone: `post-merge-orchestrator.sh --publish .run/post-merge-candidate.json --approve-sha256 <digest>` (the cycle-137 run: `~/.cache/loa/cycle-137/ship/ship-5-publish.sh` with `APPROVE=1`).
3. Observe `[TAG] Verified v2.0.0-rc.9 at <merge>`, then `[release] Release identifier or read-back mismatch`, `publish rc=1`; `gh release view v2.0.0-rc.9` shows the release exists (id 426462979, prerelease true, title `v2.0.0-rc.9`).
4. Re-run the same command (the runbook's retry path): `[TAG] Existing remote v2.0.0-rc.9 matches the candidate; not pushed again`, then the identical release failure.
5. Diff the candidate `release_body` against `gh api repos/0xHoneyJar/loa/releases/tags/v2.0.0-rc.9 | jq -r .body`: equal except that GitHub stored the 6-character sequences `\u0000` and `\u001f` as `\^@` and `\^_` (37634 vs 37628 characters, first difference at offset 17660).

### Expected Behavior
The release phase verifies the release it created (or an existing release with the same identity) and completes; the ledger phase pushes the sealed ledger commit and the notify phase posts the PR comment; the state receipt ends `DONE`. A body that differs from the sent notes ONLY by GitHub's own storage rewrite of backslash-u control escapes is the same release; any other body difference, or a different tag, title, draft or prerelease flag, still fails the read-back.

### Actual Behavior
`phase_release` compares the read-back `.body` with the sent notes by exact equality (`.body == $body`), so GitHub's rewrite makes the comparison false; `fail_phase release "Release identifier or read-back mismatch"` records FAILED, `--publish` exits 1, and the `ledger` and `notify` phases stay `pending`. Retries fail identically because the GET-by-tag path performs the same comparison against the stored (rewritten) body. `--ledger-only` refuses (`completes a deferred ledger step; run --publish with this candidate first`) because no deferral file exists, so the pending ledger write has no recovery path except a hand-made PR (cycle-137 used the archive PR).

### Environment
Host fukuoka (Linux 6.16, bash 5.2, gh 2.x, jq 1.7), isolated non-shallow clone `~/.cache/loa/cycle-137/publish-checkout-rc9`, candidate schema_version 2 (`release-candidate-a1360dac2…`), GitHub REST API via `gh api`. Production incident: the v2.0.0-rc.9 publish of 2026-10-28 (KF-064).

## Analysis
### Suspected Files
| File | Line(s) | Confidence | Reason |
|------|---------|------------|--------|
| .claude/scripts/post-merge-orchestrator.sh | 1245-1256 | high | `phase_release` read-back: `jq -e … '.id == $id and .tag_name == $tag and .body == $body and .draft == false and .prerelease == $pre and ($title == "" or .name == $title)'` — the `.body == $body` term is the failing comparison; the GET-by-tag branch (1241) reuses it for a pre-existing release |
| .claude/scripts/post-merge-orchestrator.sh | 1230-1236 | medium | `notes="${RELEASE_BODY:-}"` — the sealed candidate body is what is POSTed and what the read-back is compared against; the normalisation must apply to both sides, never to the sealed candidate itself (the digest guards it: tests "mutated notes … refuse") |
| tests/unit/post-merge-publication.bats | 61-68 | high | the `gh` stub stores the POSTed body verbatim (`jq '. + {id:81}'`) and echoes it on read-back, so the suite cannot see GitHub's rewrite; a stub mode that rewrites `\u00XX` control escapes to caret notation on storage is the red fixture |
| tests/unit/post-merge-publication.bats | 206, 342, 543-610 | medium | existing read-back tests ("approved candidate publishes and verifies tag release and comment", "pre-existing release whose prerelease flag disagrees … fails read-back", "existing tag … another release identity refuses") pin the identity property the fix must keep |

### Related Tests
| Test File | Coverage |
|-----------|----------|
| tests/unit/post-merge-publication.bats | 64 tests over --generate / --publish incl. the C-3 read-back identity (tag, title, body, flags), crash-and-retry, mutated-notes refusal; the three KF-034 `semver evidence` tests fail on hosts with `tag.gpgsign` (allowed-failure list) |
| tests/unit/post-merge-orchestrator*.bats | phase plumbing (state receipt, metrics) |

### Test Target
An integration test in `tests/unit/post-merge-publication.bats`: with `GH_MODE=ok` and a new stub knob `GH_BODY_REWRITE=caret` (the stub stores the POSTed body with every `\u00XX` C0/DEL escape rewritten to `\^<char>`, as GitHub does), a candidate whose `release_body` contains ``a `\u0000-\u001f` range`` publishes with status 0, one POST, state `DONE`, `phases.release.result.verified == true`, and the ledger pushed. A second new case: with the same rewrite, a pre-existing release whose stored body differs in ANY OTHER way (e.g. one appended word) still fails read-back (status 1, nothing pushed) — the identity property survives the tolerance.

### Constraints
- System Zone file: `.claude/scripts/post-merge-orchestrator.sh` is changed under the bounded zone marker with `checksums.json` and REPO-MAP regenerated (`tools/gen-checksums.sh`, `repo-map-gen.sh`, `check-manifest-paths.sh`, `check-loa.sh`); red commit first (test-only), fix commit second; `red-test-check.sh --red <red> --green HEAD -- bats tests/unit/post-merge-publication.bats`.
- Never weaken the C-3 identity check: id, tag_name, draft, prerelease and name stay exact; only the body comparison gains a normalisation that maps GitHub's documented storage rewrite (backslash-u escapes of U+0000–U+001F and U+007F → caret notation) applied to BOTH sides; a body-only mismatch after normalisation still fails (no silent WARN-and-pass).
- The sealed candidate is never rewritten (the approved digest covers it); the normalisation lives in the comparison only.
- No new configuration key, no new CLI flag; `--ledger-only` is out of scope (with the fix, a re-run of `--publish` completes the pending phases, which is the runbook's retry path).
- Branch name without a cycle id (`fix/…`) so the merge classifies `other` (DEC-1004); the Bugfix-or-Other job prepares a candidate (not published by this sprint).

## Fix Strategy
Add a `release_body_normalize` helper beside `phase_release` that applies GitHub's storage rewrite — every literal `\u00XX` with XX in 00–1F or 7F becomes `\^` + the caret character (`chr(XX + 64)`, DEL → `\^?`) — implemented with one `python3 -c` (python3 is already a publish-path dependency through `jcs-helper.py`) or a POSIX-safe awk, and compare `normalize(readback.body) == normalize(sent notes)` in place of `.body == $body`, keeping every other identity term exact. On a mismatch, record the first differing offset and both lengths in the phase result so the state receipt explains the refusal. Red first: extend the test stub with `GH_BODY_REWRITE=caret` and add the two cases above; then the fix; then `red-test-check.sh`; manifests regenerated. Re-verify the rc.9 state by hand only (no re-publish: the ledger write already landed through the archive PR).

### Fix Hints
Structured hints for multi-model handoff (each hint targets one file change):

| File | Action | Target | Constraint |
|------|--------|--------|------------|
| tests/unit/post-merge-publication.bats | add | `GH_BODY_REWRITE=caret` stub mode (rewrite `\u00XX` C0/DEL escapes to `\^<chr(XX+64)>` when storing the POSTed release) + two cases: rewritten body publishes DONE; any other body difference still fails read-back | test-only red commit first |
| .claude/scripts/post-merge-orchestrator.sh | fix | `phase_release` read-back: normalise both bodies before comparing; identity terms unchanged; mismatch detail in the phase result | System Zone under the marker; manifests regenerated |
