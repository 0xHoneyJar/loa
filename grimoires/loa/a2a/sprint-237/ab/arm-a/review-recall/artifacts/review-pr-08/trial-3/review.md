# Review: chore(ledger,tools,cheval): lighter ledger content check, simpler heredoc skipping, fewer except clauses

## Overall Assessment

The PR is framed as three unrelated "simplification" cleanups, but two of the three changes are not simplifications of accidental complexity — they remove protections that were purpose-built against previously-diagnosed failure modes, without replacing them with an equivalent-strength check. The third (heredoc scanning) trades a real detection capability for reduced false positives in one usage mode (`--root` scans of test fixtures) without acknowledging the trade-off. None of the three changes come with updated/new tests in this diff, and the PR description doesn't mention that safety properties are being narrowed rather than just code being shortened.

**Verdict: CHANGES_REQUIRED.**

## Critical / High Issues

### 1. `_write_ledger` no longer rejects non-object or multi-value JSON (HIGH)
`head/.claude/scripts/ledger-lib.sh:152-160`

```
152	    # GUARD (bug 20260808-a008c6): refuse empty/unparseable content BEFORE
...
157	    if [[ -z "$content" ]] || ! echo "$content" | jq empty 2>/dev/null; then
158	        echo "ERROR: refusing to write empty or unparseable ledger content" >&2
```

The base version used `jq -es 'length == 1 and (.[0] | type == "object")'` — it required `$content` to be exactly **one** JSON value and for that value to be a **JSON object**. The new version only calls `jq empty`, which merely validates that the input is syntactically parseable JSON — it accepts arrays, scalars, `null`, strings, and (since there's no `-s`/slurp) an unbounded number of concatenated top-level JSON values with no complaint.

This reopens a narrower version of exactly the bug the guard's own comment cites (20260808-a008c6):
- If `$content` is the literal string `null` (e.g. a caller bug produces an empty/uninitialized variable that gets JSON-serialized as `null` rather than an empty string), `jq empty` accepts it, and then `.last_updated = $ts` at `head/.claude/scripts/ledger-lib.sh:179` turns `null` into `{"last_updated": "..."}` — silently truncating the ledger to a single field, with the caller believing the write succeeded. This is the same failure shape (ledger truncated, success reported) the original guard was written to close, just triggered by `null` instead of an empty string.
- If `$content` is multiple concatenated JSON documents (e.g. `{"a":1}{"b":2}`, which `jq empty` accepts without slurping), the subsequent `jq --arg ts ... '.last_updated = $ts'` at line 179 (also non-slurped) emits **one modified document per input value**, writing a multi-document blob to a file that every other reader in this codebase (`jq -r '.foo'`, etc.) expects to be a single JSON object. That's a ledger corruption path with no error reported.

The comment above the guard was edited to describe *why the empty-string case matters* but doesn't acknowledge that the object/single-value invariant it also enforced is now gone. A caller reading only the comment would reasonably assume the guard is unchanged in intent.

**Fix**: keep type/shape enforcement, e.g. `jq -e 'type == "object"' >/dev/null <<<"$content"` (no slurp needed for a single check, still O(1) simpler than the original `-es` form) so the "lighter" win is real without dropping the object-type invariant.

### 2. Removing the `ValueError` handler can crash the adapter instead of chain-walking (HIGH)
`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:151-165`

```
151	                except FileNotFoundError as exc:
...
157	                except OSError as exc:
...
164	                    ) from exc
165	        except _SemaphoreExhausted as exc:
```

The base version caught `ValueError` around `run_subprocess_pgkill(cmd, ...)` and converted it into `ProviderUnavailableError`, allowing the multi-model chain to advance to the next provider. CPython's `subprocess`/`os.execvp` path raises `ValueError: embedded null byte` (not `OSError`) when an argv element contains an embedded NUL — which can happen here because `cmd` is built from `prompt = self._build_prompt(request.messages)`, i.e. arbitrary caller-supplied message content (diff text, file content, etc.) that this adapter does not sanitize for NUL bytes before it becomes argv.

With the handler removed, that `ValueError` is not caught by any of the remaining `except` clauses (`TimeoutExpired`, `SubprocessOutputCapExceeded`, `FileNotFoundError`, `OSError` — none of which `ValueError` inherits from), nor by the outer `except _SemaphoreExhausted` at line 165. It propagates out of `_invoke` entirely, which per this project's own documented invariant ("chain-walk on retryable errors; voice-drop on chain exhaustion — never cross-company substitution", `.claude/loa/reference/multi-model-reference.md`) is exactly the case that's supposed to be caught and converted so the fallback chain can advance. Instead this one provider's un-execable-argv failure now takes down the whole request instead of falling back to the next provider/model.

**Fix**: restore the `ValueError` handler (or fold NUL-byte detection into the existing `OSError` branch's message if the intent was just to reduce redundant except clauses — but it must still be caught and converted to `ProviderUnavailableError`).

## Medium Issues

### 3. Heredoc bodies are now unconditionally skipped, losing detection of executed heredocs
`head/tools/check-no-swallowed-jq.sh:135-146`, `head/tools/check-no-swallowed-jq.sh:119-133`

The base scanner computed `hd_exec` — whether a heredoc's contents were actually going to run as a shell/interpreter script (piped into `bash`/`sh`/`python3`/etc., or an unquoted heredoc subject to expansion) — and only skipped scanning the heredoc body when it was *not* executable (e.g. plain `cat <<EOF` documentation text). The new version drops `hd_exec` and the entire `_hd_command` heuristic, and unconditionally treats every heredoc body as non-scannable (`in_heredoc { ... next }` with no exec check).

This is a real loss of tripwire coverage for exactly the shape this tool exists to catch, e.g.:

```bash
ssh "$host" bash <<EOF
jq '.result' out.json 2>/dev/null || echo "{}"
EOF
```

Previously flagged (heredoc piped to `bash`) because the body is genuinely executed code containing the swallowed-jq pattern; now silently skipped. The comment justifying the change ("Without this, `--root` scans of bats tests can flag planted bad examples") only addresses the false-positive side (fixture/documentation heredocs in test files) and doesn't weigh the true-positive loss for heredocs that really do get executed. Given this tool's stated purpose is closing KF-004/KF-015 recurrence, silently narrowing its detection surface deserves at least a mention in the PR description and ideally a regression test showing the executed-heredoc case is intentionally out of scope now.

**Fix**: either keep a minimal exec-heuristic (it doesn't need the full `_hd_command`/`INTERP` machinery — even a coarse "heredoc redirected into `sh`/`bash`/`python*` on the same line" check restores the common case) or, if the intent is genuinely to descope heredocs entirely, say so explicitly in the tool's header comment (§ "Tripwire scope (NOT exhaustive defense)") so it's an acknowledged gap rather than an implicit one.

## Non-Critical / Nit

### 4. `echo "$content"` replacing `printf '%s' "$content"`
`head/.claude/scripts/ledger-lib.sh:157,179`

Low risk here since this file is always `source`d into bash (never invoked as `sh`) and bash's builtin `echo` doesn't reinterpret backslash escapes unless `xpg_echo` is set, but it's still a behavior-narrowing substitution: `printf '%s'` is guaranteed byte-for-byte regardless of interpreter/shopt state, `echo` is not portable across shells/`shopt` settings, and ledger content is JSON that could start with `-` (e.g. a negative-number scalar) in edge cases. Since this file already uses `printf` idiomatically elsewhere in the same function, this substitution buys no real simplification and gives up the stronger guarantee. Not blocking, but consider reverting alongside the fix for finding 1 while that guard is already being touched.

## Adversarial Analysis

### Concerns Identified
1. `head/.claude/scripts/ledger-lib.sh:157-160` — object/single-value invariant dropped from the content guard, reopening a narrower version of the truncation bug the guard cites.
2. `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:151-165` — `ValueError` from embedded-NUL argv now propagates uncaught, breaking the chain-walk fallback guarantee for that failure class.
3. `head/tools/check-no-swallowed-jq.sh:135-146` — heredoc bodies piped to an interpreter are no longer scanned at all, silently narrowing the tripwire's detection surface.
4. `head/.claude/scripts/ledger-lib.sh:157,179` — `echo` vs `printf '%s'` is a portability/guarantee regression, low risk here but avoidable.

### Assumptions Challenged
- **Assumption**: the PR treats all three changes as pure simplification with no behavior loss ("lighter... simpler... fewer except clauses").
- **Risk if wrong**: two of the three changes (#1 ledger guard, #2 ValueError handler) actually remove targeted protections against previously-diagnosed bugs, not incidental complexity — the "lighter" framing masks a real reduction in safety margin.
- **Recommendation**: re-scope the PR description to explicitly call out which invariants are being relaxed, or restore equivalent-strength checks (see fixes above) so the diff really is complexity-only.

### Alternatives Not Considered
- **Alternative**: for the ledger guard, use `jq -e 'type == "object"' <<<"$content"` instead of dropping to `jq empty` — still a single, simple jq invocation (no slurp), but preserves the object-type invariant the original `-es` check enforced.
- **Tradeoff**: marginally more jq syntax than `jq empty`, but restores the exact safety property the guard exists for; the current diff optimizes line count over correctness.
- **Verdict**: should reconsider — this alternative gets the same simplification goal without the regression.

## Previous Feedback Status
N/A — no `engineer-feedback.md` exists for this change (PR-only review, no sprint context).

## Next Steps
1. Restore object/single-value enforcement in `_write_ledger`'s content guard (finding 1).
2. Restore the `ValueError` handler around `run_subprocess_pgkill` in `agy_headless_adapter.py` (finding 2).
3. Either restore a minimal exec-heuristic for heredoc scanning in `check-no-swallowed-jq.sh`, or explicitly document the reduced scope in the tool's header comment (finding 3).
4. Optional: revert `echo` back to `printf '%s'` in the same guard while it's being touched (finding 4).

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":1,"low":1},"sprint_id":"pr-review","ts":"2026-09-22T00:00:00Z"} -->
