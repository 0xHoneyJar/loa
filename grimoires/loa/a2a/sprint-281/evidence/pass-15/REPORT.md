# Pass 15 - beads-health.sh --json: NO CHANGE (no lever scores >= 2.0)

## Baseline (hyperfine -N -i, warmup 3, 20 runs; before.json)
- --json: 226.6 +- 6.2 ms (min 212.7)
- --quick --json: 51.5 +- 2.4 ms

## Profile (PS4 EPOCHREALTIME trace, 477 lines, 226.8 ms)
| Item | Cost | % wall | Removable? |
|---|---|---|---|
| br doctor (line 304) | 172 ms in trace (77 ms nominal) | 76% | No: br contract, floor |
| timeout 10 br sync --status (358) | 10 ms | 4.4% | No: br contract; only runs when jsonl mtime stale |
| br --version (157) | 4.1 ms | 1.8% | No: br contract / availability probe |
| sqlite3 x3 (PRAGMA table_info 3.1, SELECT 1 2.1, third) | ~6 ms total | 2.7% | Merge saves ~2-4 ms, corruption-path semantics interlock (each probe has its own recommendation + return code) |
| jq -nR '[inputs]' (446) | 2.7 ms | 1.2% | No: needed for recommendations JSON |
| dx-utils jq (107) | 2.6 ms | 1.1% | Error-catalogue load, not on the hot path of the health checks |
| stat x5, grep x2 | ~1.5 ms each | ~4% | Already GNU-first (pass-5), builtin epoch, no date spawns |

Total external spawns: br 2, sqlite3 3, jq 2, stat 5, grep 2, timeout 1 = 15. No single non-br gap exceeds 4 ms.

## Opportunity matrix
| Lever | Impact | Confidence | Effort | Score |
|---|---|---|---|---|
| Merge 3 sqlite3 probes into one | 1 (~3 ms, 1.3%) | 2 (semantics interlock) | 3 | 0.7 |
| Collapse 5 stat calls (e.g. one stat -c with several files) | 1 (~3 ms) | 3 | 2 | 1.5, and changes fallback chain per file / BSD form |
| Skip br --version | 1 | 1 | 1 | br contract, not allowed |
Nothing >= 2.0 outside br contracts. No edit made; git status shows no source changes from this pass.

## Checked and found already optimal
- No date spawns (builtin printf %()T), no cat/sed/awk/tr/wc spawns, no repeated jq over the same JSON.
- Heredoc output assembled with builtin read; single jq for recommendations.
- stat is GNU-first with BSD fallback; --quick path is already 51 ms (4.4x faster) and skips br doctor.
- br doctor is the documented full-mode floor (not re-litigated).

Isomorphism proof: N/A (no code change). Golden/bats not required for a no-change pass.
