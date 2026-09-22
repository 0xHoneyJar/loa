# Sprint Review: chore(ledger,tools,cheval) — lighter ledger check, simpler heredoc skipping, fewer except clauses

## Overall Assessment

This PR frames itself as pure simplification ("lighter", "simpler", "fewer except
clauses") across three unrelated files, but two of the three changes remove
behavior that was load-bearing, not incidental. The heredoc-skip rewrite in
`check-no-swallowed-jq.sh` defeats the exact class of bug the tool exists to
catch (KF-004/KF-015 — silent-clean gate passes), and the removed `ValueError`
handler in `agy_headless_adapter.py` reintroduces the raw-crash failure mode
that every sibling `except` clause in the same block was written to prevent.
The `ledger-lib.sh` change is lower severity but still measurably weakens a
guard added for a named bug (20260808-a008c6). None of the three changes touch
or add tests, despite two of them altering detection/error-handling logic with
observable behavioral differences.

**Verdict: Changes Required.**

## Critical Issues

### 1. `check-no-swallowed-jq.sh` — heredoc bodies are now unconditionally exempt from the scan, defeating the tripwire for executed heredocs

`head/tools/check-no-swallowed-jq.sh:135-146`:

```awk
# Step 1: when in a heredoc body, skip fixture/documentation text until the
# terminator. Without this, --root scans of bats tests can flag planted bad
# examples instead of executable scanner code.
in_heredoc {
    if ($0 == hd_term) { in_heredoc = 0; next }
    if (hd_dash) {
        no_tabs = $0
        gsub(/^\t+/, "", no_tabs)
        if (no_tabs == hd_term) { in_heredoc = 0; next }
    }
    next
}
```

The base version (`base/tools/check-no-swallowed-jq.sh:112-148`) computed
`hd_exec` per heredoc — a heuristic distinguishing a heredoc that is piped to
an actual interpreter (`bash <<EOF`, unquoted `<<EOF` expanded and executed,
etc.) from one that is inert fixture/documentation text (quoted terminator,
`cat <<'EOF'` written to a file). Only `hd_exec` heredocs were scanned for the
swallowed-jq shape; `hd_exec = 0` heredocs (fixtures) were skipped. The new
version deletes `hd_exec`, `_hd_command`, and the `INTERP[]` table entirely and
skips **every** heredoc body unconditionally.

This is a real regression, not just a simplification: any gate-critical script
in `ENFORCED_FILES` (`.claude/scripts/adversarial-review.sh`,
`flatline-orchestrator.sh`, `scoring-engine.sh`, `post-pr-triage.sh`, or any
`red-team-*` script) that constructs an executed shell block via heredoc —
e.g. `ssh host <<'EOF' ... jq ... || echo default ... EOF` or
`bash <<SCRIPT ... jq ... || echo fallback ... SCRIPT` — can now contain the
exact swallowed-jq shape this tool was built to fence (per the file's own
header: "the literal mechanism behind KF-004 ... and KF-015") and it will
score clean. The tool's own module docstring still claims this is a tripwire
against silent-clean verdict masking; this change opens a blind spot in
service of a stated goal ("Without this, --root scans of bats tests can flag
planted bad examples") that only required distinguishing *inert* heredocs, not
exempting *all* heredocs.

No test in this PR exercises an executed-heredoc case to show the tradeoff was
evaluated — see Test Coverage below.

### 2. `agy_headless_adapter.py` — removed `ValueError` handler lets an embedded-NUL prompt crash instead of walking the fallback chain

`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:157-166`:

```python
                except OSError as exc:
                    # E2BIG (ARG_MAX — a huge diff on argv; agy is argv-transport, no
                    # --prompt-file exists) or another exec failure → WALK the chain,
                    # never crash with a raw OSError. The gemini-api HTTP fallback
                    # covers oversized diffs. (FileNotFoundError is handled above.)
                    raise ProviderUnavailableError(
                        self.provider,
                        f"agy -p exec failed (likely ARG_MAX on an oversized prompt): {exc}",
                    ) from exc
        except _SemaphoreExhausted as exc:
```

The deleted `except ValueError` clause (`base/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:167-171`)
converted the specific `ValueError` that Python's `subprocess` machinery
raises for an embedded NUL byte in argv into a `ProviderUnavailableError`,
letting the multi-model chain-walk logic advance to the next provider (per
`CLAUDE.loa.md` Multi-Model Activation: "chain-walk on retryable errors").
With the handler gone, that same `ValueError` now propagates unhandled out of
`complete()`. The comment on the immediately adjacent `except OSError` clause
— "WALK the chain, never crash with a raw OSError" — states the exact design
invariant this change violates for `ValueError`. This is not dead code being
pruned; it is the specific defense against a real, previously-identified
failure mode (the original message literally names it: "embedded NUL in the
prompt?"), and removing it turns one provider's edge case into an unhandled
exception that kills the whole completion call instead of degrading to the
next provider in the chain.

### 3. `ledger-lib.sh` — content guard relaxed from "single JSON object" to "any parseable JSON," permitting multi-document streams to corrupt the ledger silently

`head/.claude/scripts/ledger-lib.sh:157-158`:

```bash
    if [[ -z "$content" ]] || ! echo "$content" | jq empty 2>/dev/null; then
        echo "ERROR: refusing to write empty or unparseable ledger content" >&2
```

vs. the removed check (`base/.claude/scripts/ledger-lib.sh:161-162`):

```bash
    if [[ -z "$content" ]] || \
       ! printf '%s' "$content" | jq -es 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1; then
```

`jq empty` validates that every JSON value in the input stream parses — it
does not require exactly one value, nor that the value be an object. The
removed `-es 'length == 1 and (.[0] | type == "object")'` check specifically
enforced "exactly one top-level object." Two observable behavior changes:

- A single non-object JSON value (e.g. `"oops"`, `42`, `[1,2,3]`) now passes
  the guard at line 157-158. It is caught later, but only incidentally: the
  `.last_updated = $ts` filter at line 179 errors on a non-object root, so
  `updated_content` is empty and the `-z` check at line 180 aborts the write.
  This still works today, but only because a second, unrelated piece of code
  happens to fail correctly — the actual documented type contract ("must be a
  JSON object") is no longer enforced at the guard whose comment
  (`GUARD (bug 20260808-a008c6)`) says it exists precisely to catch bad
  content *before* it reaches that stamping step.
- A multi-document JSON stream (e.g. `'{"a":1}\n{"b":2}'`) now passes **both**
  checks: `jq empty` accepts a stream of syntactically valid values, and
  `jq '.last_updated = $ts'` at line 179 (no `-s`/slurp) processes each
  document independently and emits one modified JSON object per input
  document — two valid-looking lines, `updated_content` non-empty, no error,
  exit 0. The ledger file would then silently contain two concatenated JSON
  objects instead of one, which every other reader (`jq empty "$ledger_path"`
  at line 739, `jq -r '.version // ...'` at line 118, etc.) will treat as
  "still valid JSON" while downstream consumers reading it as a single object
  get only the first document (jq without `-s` on a multi-document ledger.json
  silently ignores later documents in most call sites in this file). This is
  the same "reports success while corrupting state" pattern bug
  20260808-a008c6 was opened for.

This is a real relaxation of a targeted guard, not merely simpler code —
worth confirming no caller can ever produce multi-document or non-object
`content` before accepting this as safe.

## Test Coverage

None of the three changes are accompanied by test changes in this diff (no
`tests/` files appear in `head.diff`). Given that:

- the heredoc-skip rewrite changes which lines are considered scannable at all,
- the `ValueError` removal changes what exception shape reaches the caller for
  a specific, previously-named input (embedded NUL), and
- the ledger guard relaxation changes what content is accepted,

each of these deserves at least one regression test (an executed-heredoc
fixture that should still be flagged; an embedded-NUL prompt that should
still resolve to `ProviderUnavailableError`; a multi-document or non-object
`content` argument that should still be rejected by `_write_ledger`). None are
present.

## Adversarial Analysis

### Concerns Identified

1. `head/tools/check-no-swallowed-jq.sh:135-146` — unconditional heredoc
   skip removes detection coverage for the tool's actual stated threat model
   (executed heredocs containing swallowed-jq shapes), not just the
   fixture/documentation false-positive case the commit message targets.
2. `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:157-166`
   — removing the `ValueError` handler contradicts the chain-walk invariant
   documented one clause above it in the same `try` block.
3. `head/.claude/scripts/ledger-lib.sh:157-158` — the new check accepts
   multi-document JSON streams that the old check explicitly rejected via
   `length == 1`, with no analysis in the PR of whether `_write_ledger`
   callers can ever produce such content.
4. No tests were added or updated for any of the three behavioral changes,
   despite all three altering pass/fail outcomes for specific inputs.

### Assumptions Challenged

- **Assumption**: the PR treats all three changes as equivalent-behavior
  simplifications ("lighter", "simpler", "fewer except clauses") safe to land
  as a single chore commit.
- **Risk if wrong**: two of the three (`check-no-swallowed-jq.sh`,
  `agy_headless_adapter.py`) are not behavior-preserving — they narrow
  detection coverage and remove a specific error-classification path,
  respectively. Bundling them with the truly cosmetic parts of the diff (e.g.
  `printf '%s'` → `echo` is genuinely equivalent for these callers) makes it
  easy for a reviewer skimming the "chore" label to wave the whole thing
  through.
- **Recommendation**: split into (a) a pure formatting/cosmetic commit and
  (b) a behavior-change commit for the heredoc and exception-handling logic,
  each justified against the specific bug/KF numbers already cited in the
  surrounding comments, with tests demonstrating the new boundary is still
  caught where it matters.

### Alternatives Not Considered

- **Alternative** (heredoc scanner): keep the `hd_exec` heuristic but simplify
  only the parts causing false positives — e.g. if the real problem is
  bats-fixture heredocs specifically, key the skip off `--root` mode or off a
  heredoc quoted-terminator check (`cat <<'EOF'` is definitionally inert)
  rather than deleting execution-context detection altogether.
- **Tradeoff**: this would keep the diff larger than the current PR, but
  preserves the tool's core guarantee (flagging swallowed-jq in code that
  actually runs) instead of trading it away for scanner simplicity.
- **Verdict**: the current approach should be reconsidered — it optimizes the
  scanner's own code size at the cost of the property the scanner exists to
  provide.

## Non-Critical Improvements

- `head/.claude/scripts/ledger-lib.sh:114` and `:739` still use `jq empty`
  for backup/ledger validation (pre-existing, unchanged) — worth confirming
  those sites don't have the same non-object/multi-document gap, since they
  are the read-side analog of the write-side guard weakened in this PR.

## Next Steps

1. Restore execution-context detection in `check-no-swallowed-jq.sh` (or
   narrow the skip to genuinely-inert heredocs only) so gate-critical scripts
   using heredocs to build executed shell blocks remain covered.
2. Restore a handler (or equivalent chain-walk conversion) for the
   embedded-NUL `ValueError` case in `agy_headless_adapter.py`, or explain why
   this input can no longer occur.
3. Either keep the `length == 1 and type == "object"` check in
   `ledger-lib.sh`'s `_write_ledger`, or justify why the looser `jq empty`
   check is sufficient given multi-document stream content is not rejected.
4. Add regression tests for whichever of the above land, covering the
   specific input shapes called out in this review.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":1,"low":0},"sprint_id":"pr-review","ts":"2026-09-22T00:00:00Z"} -->
