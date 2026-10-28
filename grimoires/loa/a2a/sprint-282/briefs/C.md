# Implementer C — Task 2.5 (test-suite runtime: corpus-once fixture, bounded companion waits)

Read `COMMON.md` first. Specs: `grimoires/loa/sdd.md` § 5.6, § 7 row C-6, D-6.1, D-6.2; `grimoires/loa/sprint.md` Task 2.5 and the Sprint 2 acceptance criteria for FR-6. Bead: bd-wctli. This is a TEST-ONLY task: ONE commit, exempt from the red/fix pair; your evidence is the serial before/after TAP pass/fail/skip set per test name, the `bats -T` timing tables and the NEGATIVE CONTROL below.

## Allowlist
`tests/unit/block-destructive-bash.bats`, `tests/unit/adversarial-review-companion.bats`. Nothing else — nothing under `.claude/`, no other test file, nothing under `tests/fixtures/`.

## Part 1 — `tests/unit/block-destructive-bash.bats`
Today `corpus_json()` (≈ line 1542) runs `tests/fixtures/fence-corpus/run-corpus.sh --hook "$HOOK" --json` on every call; three tests call it (≈ lines 1546, 1553, 1583; ~28 s each). There is no `setup_file()` yet (only `setup()` at line 9). Add `setup_file()` that runs the corpus ONCE: `bash "$PROJECT_ROOT/$CORPUS_RUNNER" --hook "$HOOK" --json > "$BATS_FILE_TMPDIR/corpus.json" 2> "$BATS_FILE_TMPDIR/corpus.err"; echo $? > "$BATS_FILE_TMPDIR/corpus.status"` — capture WITHOUT failing `setup_file` (`|| true` on the pipeline), so a runner failure fails the three tests with the runner's stderr instead of aborting the whole file. `HOOK` and `PROJECT_ROOT` are set in `setup()` today — `setup_file` runs before `setup`, so compute them in `setup_file` too (same expressions). `corpus_json()` becomes: assert `corpus.status` is `0` (print `corpus.err` on failure) and `jq -e . corpus.json` succeeds, then `cat corpus.json`. The runtime test (≈ 1583) keeps reading `runtime_ms` from that JSON (one measured run). `-f <name>` selection and `--jobs` still run `setup_file` once per file process — verify with `-f 'cycle-125 corpus: benign'` alone. No assertion, expected value or skip condition changes.

## Part 2 — `tests/unit/adversarial-review-companion.bats` (284 tests, > 900 s serial)
Baseline FIRST: `npx --no-install bats --tap -T tests/unit/adversarial-review-companion.bats > before.tap` on the idle host, three times; keep the per-test `# time=` values (median of three totals is the baseline). Identify where the time goes.

Rules for what you may change:
- The env knob `CMP_STUB_HOLD_S` (default 300 = today) is read ONLY by the `cheval` shim the bats file itself defines (≈ lines 160–240: behaviours `stubborn` (182), `slow` (206), `unavailable-companion-slow` (232)) and by the holder lines in test bodies (`sleep 30` holders at ≈ 1253, 1310, 1594, 1613, 1624, 1719, 1741, 1749; the `sleep 20` sleeper at 183). No production script reads it. Set it in the file's `setup()` to the shortened value; a hold that exists to be REAPED must stay ≥ 2× the longest wait any test places on it (read each affected test's bound — the `_await_*` polls, the `kill -0` loops, the reaper cap — and list test name → bound → new hold in your report).
- A fixed `sleep N` that no test waits on shortens to the minimum its own bound requires; polls keep their bounds (they stop at the first observable event already).
- CMP-37 (`a shared hop is skipped only while the companion is ON it …`) is NOT to be made deterministic (D-6.2; out of scope); do not touch its assertions.
- No assertion, expected value or skip condition changes anywhere; the synchronisation states each test demonstrates before asserting (holder ready, lock contended, released, timed out, cleaned up) are preserved.

Then: `after.tap` three times, serial, idle host. Pass/fail/skip set per test NAME identical before vs after (`sed -E 's/^(ok|not ok) [0-9]+ //; s/ # time=.*//'` both and `diff`). Target: file wall time ≤ 300 s; if the engineering floor (the script's own per-test runtime) is higher, report the measured floor and the per-test costs that remain — the lead records the decision row (do not relax anything to hit the number).

NEGATIVE CONTROL (the red-first substitute; mandatory): for each test whose waits you shortened, deliberately break the behaviour it asserts — e.g. make the holder exit immediately instead of holding, or disable the reaper path the test exercises — run the test, show it FAILS under the shortened waits, remove the break, show it passes. Record test name → break applied → failed → restored → passed. Do the breaks on a scratch copy; your patch contains none of them.

## Report
`REPORT.md` per COMMON.md plus: the before/after `bats -T` tables (totals, median of three, and the twenty slowest tests each side), the affected-test table (name, bound, old hold, new hold), the negative-control table, the `-f` single-test and `--jobs` runs for Part 1, the TAP-set diff output (empty), and the CHANGELOG line as text.
