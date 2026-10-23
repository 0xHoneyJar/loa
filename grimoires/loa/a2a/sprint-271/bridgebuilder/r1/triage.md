## Bridgebuilder round 1 — triage (lead, 2026-10-23)

Round 1 ran from a cache copy of the skill with the `gh` child-process buffer raised (the stock run dies on this PR's ~22 MB files payload before any exclusion applies — KF-054, upstream bead bd-ra4im; the copy differs from `.claude/skills/bridgebuilder-review/dist` in that one constant). Voices gpt-5.5-pro and claude-headless, consensus verdict COMMENT: 2 MEDIUM, 6 LOW, 2 SPECULATION, 1 REFRAME, 5 PRAISE. Each finding was read against the code and the recorded runs.

| finding | severity | disposition |
|---|---|---|
| F-001 pricing helpers fail open on jq errors (`evals/harness/lib/session-exec.sh`) | MEDIUM | Confirmed as written: `blind-session.sh:315-332` estimates only when `prices != null`, and a jq failure inside `price_events` reads as a 0-crossing estimate that never trips the watchdog. **Deferred to bd-wqaj4** (next harness cycle): `evals/harness` is the pinned pipeline `fbd36a0c` that REGISTRATION-8…17, `reproduce.sh` and the record branch attest; a post-hoc harness change would break the pin attestation and the proof. The runner's spend gates and the session timeout still bound every session. |
| F001 `os.closerange(3, 65536)` leaves higher descriptors open | MEDIUM | Confirmed as written; exposure needs the driver to hold ≥ 65,536 open descriptors (host hard limit 4,096; container 1,048,576 with a handful open). Same bead, same reason; fix both copies with a regression. |
| F-002 shared mechanics copied, not sourced | LOW | bd-g2c5i (source the lib, stage it in the bats harness, drop the drift test). |
| F-004 SECRET_KEYS is a second allowlist | LOW | PASS_KEYS carries one secret today (AWS_BEARER_TOKEN_BEDROCK, redacted as `<set>`); folded into bd-wqaj4. |
| F-006 fixture snapshots visible to repo-wide gates | LOW | bd-dt5r8 (`.gitattributes` + a bats tripwire; check the gates' scoping first). |
| F-007 power-mini synthetic diffs with contradictory hunk headers | LOW | bd-qxwrm (generate at test time via `synth.py`). |
| F-008 label set behind the headline, at the point of citation | LOW | **Fixed in 0f4a5f5c6**: § The answer now names the v2 key and its key dependence beside the headline. |
| F-009 eighteen addenda without a timeline relative to the looks | LOW | **Fixed in 0f4a5f5c6**: `registration-timeline.md` (first-commit UTC time of every pre-registration document, registration and data look; hashes from the chain listing; `scripts/registration-timeline.sh`) is rendered into the report, and caveat 9 now states which addenda followed which look: 10–11 after look 1 (look 1 re-read under them), 12 before and 13–15 after look 3 (judge packets and the chain validator), 16–18 after the final read (analysis-only; every registered figure byte-identical). Anchoring each look's rows hash into the next registration goes to bd-y1smc. |
| F-003 exec contract depends on PATH in the filtered environment | SPECULATION | The callers build the keys CSV explicitly and every recorded session executed; documenting the contract rides with bd-wqaj4. |
| F-010 contiguous +0 −0 runs | SPECULATION | Refuted: no zero-byte file under `evals/fixtures/review-prs` (0 of 1,800); SHA256SUMS covers the tree and the Fixture Sync Check passed on this head. |
| F-005 PR bundles code, fixtures, reports and the release bump | REFRAME | Acknowledged. This cycle the record branch (DEC-0811) and `REPRODUCE.md` are the checksum path for the fixtures and reports; stacked PRs for the next measurement cycle: bd-y1smc. |
| F-011 … F-014, F002 | PRAISE | Logged. |

Also noted: the "Eval Results — regression" comment above is PR-independent (the same FAILURES DETECTED block appears on #1288 and #1286; that suite runs with no model). Decision row DEC-0818. A second Bridgebuilder round runs on 0f4a5f5c6.
