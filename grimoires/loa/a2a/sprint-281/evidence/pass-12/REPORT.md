# ESO pass 12 — audit-envelope.sh verify-chain (loa-status): NO CHANGE (score < 2.0)

## Finding
loa-status calls verify-chain once per EXISTING chain file; in this repo only grimoires/loa/handoffs/INDEX.md exists
(L1-L4 files absent). Command profiled: `audit-envelope.sh verify-chain $PWD/grimoires/loa/handoffs/INDEX.md`
(rc=1 by design: INDEX.md is not JSONL; `-i` used). Baseline: 155.5 ms +- 7.5 ms (before.json).
(Mission's `verify-chain <root>` form is a directory -> rc 2 "file not found" in <10 ms; not the loa-status call.)

## Hotspot (not per-entry work: the chain is 7 lines, fails on line 1)
| Phase | ms | % of 155 |
|---|---|---|
| bash (source script, to python launch; 61 trace lines) | ~6 | 4% |
| python startup | ~13 | 8% |
| import loa_cheval.audit_envelope (package __init__ pulls loa_cheval.types -> dataclasses/inspect = 19 ms) | ~30 | 19% |
| _check_trust_store -> _trust_store_snapshot (cProfile 92 ms total in audit_verify_chain) | ~85-100 | ~60% |
|   of which: subprocess `python3 audit-signing-helper.py trust-store-verify` (75 ms standalone: interpreter 13 + cryptography.serialization/ed25519 ~36 + yaml/rfc8785 ~24) | ~68-73 | ~45% |
|   of which: parent `import yaml` + yaml.safe_load + tempdir snapshot | ~19 | ~12% |

The live trust-store is VERIFIED (signed), so the helper subprocess always runs. Everything is interpreter/import cost
of a second python process; there is no per-entry loop, jq, or sha256 spawn to hoist.

## Levers considered
| Lever | Impact | Conf | Effort | Score | Verdict |
|---|---|---|---|---|---|
| Verify trust-store in-process (importlib the helper) instead of subprocess | 2 (~25 ms = 16% of call, ~3% of loa-status) | 2 | 4 | 1.0 | REJECTED |
| Lazy/trim imports in helper (argparse etc.) | 1 (<5 ms) | 3 | 2 | 1.5 | REJECTED |
| Cache VERIFIED across processes | 3 | 1 | 3 | 1.0 | REJECTED (trust-boundary) |

Why in-process is rejected: tests/security/test_audit_trust_policy.py:147-165
(test_authentication_uses_the_pin_bytes_captured_for_cache_identity) patches `subprocess.run` to mutate the pin mid-verify;
the subprocess boundary over a tempdir snapshot is a deliberate TOCTOU-defence design, and uncaught-exception/sys.exit(78)
text differs between process and in-process (public audit_trust_store_verify returns that text). A cross-process cache would
weaken the "fail closed on tampered trust store" gate. Changing this security-sensitive adapter for ~3% of loa-status
does not clear the 2.0 bar, and CLAUDE.md demands "Security first".

## Not changed
Repo diff from this pass: none (git status shows only the pre-existing .skill-loop-progress.md). No chain written.

## Checked and found already optimal / correct
1. bash side: only ~6 ms and 61 trace lines before python launch; script sourcing is not a cost.
2. Parent already caches trust-store status per process (_TRUST_STORE_CACHE keyed by sha256 of store+pin bytes); verify-chain is one process per file so it can't hit.
3. Chain walk itself: single in-process pass, no per-entry subprocess; INDEX.md fails at line 1 in microseconds (not the cost).
4. yaml has libyaml (`__with_libyaml__` True) but safe_load uses the pure loader; switching to CSafeLoader would change parser behaviour at a trust boundary (parent/helper differential) -> not touched.
5. loa-status passes `>/dev/null 2>&1` and uses only the rc, but the skip-cannot-be-done: rc depends on the same verification.

## Suggestion (outside this pass's rules)
If loa-status cost matters, the structural fix is to run the five verify-chain calls only when a file exists (already the case) or to
batch them in one python process — a behaviour/interface change for the orchestrator to decide.

## Isomorphism proof
Not applicable (no code change). Golden: N/A. Tests: none needed (no diff).
