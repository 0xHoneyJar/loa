# sprint-250 review dissent run 2: triage

- **Run.** The fix delta `d785fc9a..4b347efc` (rounds r250-1 and r250-2), three chunks: b-bb, s-shell and v-eval. Every chunk was two-voice [codex-headless, claude-headless]. Envelope: `adversarial-review-run2-merged.json`, which is also the current `adversarial-review.json`.
- **Findings.** 15 in total: 2 BLOCKING (n11, n12) and 13 ADVISORY. The input file is `~/.cache/loa/cycle-126-dissent/r250-run2-findings.json`, with field `n`.
- **Rejected payloads.** None. Every `rejected_summary` is empty. All five `adversarial-rejected-review-*.jsonl` sidecars in this directory (g-gate, k1-kernel, k2-kernel, m1-pins, v-eval) are empty (0 bytes).
- **Budget.** This is review dissent run 2 of the 3 allowed for this sprint.

## Verdicts

| n | Sev | Area | Verdict | Action |
|---|---|---|---|---|
| 11 | BLOCKING | grader URL filter | REAL | A URL can still give a later partial match with no scheme: `https://example.com/x.js:8080` credits `example.com/x.js:8080`. Fix: a lookbehind, so a match never starts inside a URL. |
| 12 | BLOCKING | grader re-grade record | DOC | The 1.1.0 → 1.1.x re-score of the 16 stored A/B runs was not recorded in `replay-ab-rerun.md`. The lead appends the per-run table after round r250-3, so it also covers that round's grader changes. |
| 13 | ADV | grader number boundary | REAL | The boundary applies only to comma continuations. It is missing after the first range number and after a bare `:N`, and the en dash is not in the class. |
| 14 | ADV | grader bare `:N` guard | REAL (to verify against 1.1.0 / RG-13) | The `head\|base` branch picked up the JSON-punctuation lookbehind, and the backtick is missing from the bare set. |
| 15 | ADV | grader trailer | REAL | The strip pattern (tolerant, re.S) and the read pattern (exact) differ, so an unterminated trailer can over-strip. Fix: one shared pattern. |
| 4 | ADV | BB test | REAL (test) | The alias closing assertion in progressive-truncation is vacuous. Fix: an estimate strictly between the alias budget and the operator budget, with the clamp asserted. |
| 3 | ADV | BB reviewer | VERIFY | Only `sent[0]` is checked. Verify the Pass 2 / post-truncation skip condition against `inputBudget`, and assert `sent.every`. |
| 6 | ADV | model-adapter trap | VERIFY | `trap … EXIT` replaces any prior EXIT trap. Check the script and its sourced libraries, and preserve a prior trap if one exists. |
| 7 | ADV | model-adapter fallback | REAL (LOW) | The mktemp fallback is silent, so the agy WARN relay is lost without notice. Fix: a one-line stderr WARN. |
| 8 | ADV | license margin | REAL (LOW) | 300 s is shorter than the ~38 min full unit run. Fix: 3,600 s, which is still well inside the 12 h window. |
| 9 | ADV | check-permissions | REAL | `Bash(:*)` (empty prefix) matches every command in Claude Code's prefix grammar but was not treated as universal. Fix: map it to `ALL`, with CP-14 rows. |
| 10 | ADV | bats absence checks | REAL (LOW) | `run ! grep` also passes on grep exit 2 (missing file). Fix: `run -1 grep`. |
| 1 | ADV | gen-bb-registry | DECLINED | A malformed `aliases:` block coerces to `{}`. Codegen T13 pins the `opus` → `claude-opus-5-5` row, so losing the mapping fails CI loudly. The catalog schema validates `aliases:` upstream. |
| 2 | ADV | alias/id collision | DECLINED | No catalog alias collides with a different concrete id today. A future retarget is caught by T13 and by the catalog schema. |
| 5 | ADV | BB fixture size | DECLINED | The fixture asserts its own estimate window, so if a template change moves it out of range, the test fails loudly rather than vacuously. |

Of the 2 BLOCKING findings, n11 holds as REAL and n12 holds as a record gap (DOC). Neither one changes a gate outcome. n12 depends on the re-score delta, which is recorded in `replay-ab-rerun.md` once round r250-3 lands.

## Round r250-3

Committed as `64c2eb09` (pushed). Each item was red first, except where noted.

| n | Outcome |
|---|---|
| 11 | **Fixed.** The literal case was already 0 citations at HEAD, because finditer consumed the `//…` match. The class was still real: `https://user@example.com/x.js:8080` and `https://example.com/~u/c.sh:7` each credited 1. Fix: reject a match whose whitespace token contains `scheme://` or starts with `//`. Pinned by RG-21. |
| 13 | **Fixed.** The range dash must be unspaced, and every number gets the lookahead `(?![A-Za-z0-9]\|[-–]\d)`. Pinned by RG-22, which includes the legitimate open `:369-...`. |
| 14 | **Fixed.** 1.1.0 bound `"head:40"` / `[head:40]`, so the 1.1.1 behaviour was a regression. The head\|base branch is back on the 1.1.0 set. For the bare `:N`, a closing backtick is rejected while an opening one (RG-13) still binds. Pinned by RG-23. |
| 15 | **Fixed.** One `TRAILER` pattern now does both strip and read. An unterminated trailer no longer swallows content. Pinned by RG-24. |
| 12 | **Recorded.** The re-score table is in `replay-ab-rerun.md`. 16/16 runs show a 0 detection change; citation counts under round 1's grader and round 3's are identical. |
| 4 | **Refuted.** `560_000` is a system-prompt length in characters (~140K tokens), so the total estimate of about 180K already lies between the 160K alias budget and the 300K operator budget. Probe: an unknown id gives excluded=0, level=1, so the assertion fails; `opus` and `claude-opus-5-5` give excluded=36. |
| 3 | **Code correct; test strengthened.** The post-truncation skips and adaptive retries use the clamped budget. Pass 2 carries no diff and has no size guard to get wrong. Gap: the test's mock never reached Pass 2. It now returns findings, asserts the call count, and asserts `sent.every(≤ CEILING)`. The mutation check (Pass 2 prompt inflated) made both two-pass cases red. |
| 6 | **Hardened.** No prior EXIT trap exists today. `main` captures `trap -p EXIT`, chains it and restores it. Pinned by MA-9. |
| 7 | **Fixed.** A one-line WARN now says stderr capture and the agy WARN relay are disabled. Pinned by MA-7. |
| 8 | **Fixed.** The margin is 3,600 s. LFF-3 uses a fixture expiring in 30 min, which is inside the new margin and outside the old one. |
| 9 | **Fixed.** An empty prefix body becomes `ALL`. Pinned by CP-14 rows for `Bash(:*)` and `Bash( :* )`, both allow and deny. |
| 10 | **Fixed.** All seven sites now use `run -1 grep`. A probe confirmed that `run !` passes on a missing file, while `run -1` fails on exit 2 and on exit 0. |

**Suites in the real tree after apply** (serial; ok / not ok / skip):

| Suite | ok / not ok / skip |
|---|---|
| eval-recall-grader | 24/0/0 |
| check-permissions | 14/0/0 |
| model-adapter | 9/0/0 |
| model-adapter json-schema / probe / skill | 4 / 13 / 3, all 0 not ok, 0 skip |
| implement-gate | 11/0/0 |
| hook-guard | 8/0/0 |
| model-residue | 7/0/0 |
| flatline-max-tokens | 6/0/0 |
| protocol-refs-resolve | 4/0/0 |
| license-fixture-freshness | 5/0/0 |
| test_license_validator | 35/0/1 (pre-existing jq skip) |
| repo-map-gen | 6/0/0 |
| skill-capabilities | 35/0/0 |
| gen-bb-registry-codegen | 37/0/0 |
| BB npm | 765/766 (persona.test, KF-036) |

`regen-checksums --check` reports changed=0.
