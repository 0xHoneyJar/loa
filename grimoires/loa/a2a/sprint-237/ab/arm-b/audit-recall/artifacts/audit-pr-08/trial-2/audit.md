# Security Audit — chore(ledger,tools,cheval): lighter ledger content check, simpler heredoc skipping, fewer except clauses

## Scope

This PR touches three files, each part of a security- or integrity-critical control:

- `.claude/scripts/ledger-lib.sh` — `_write_ledger`, the atomic-write guard added after bug 20260808-a008c6 (silent ledger truncation).
- `tools/check-no-swallowed-jq.sh` — the sprint-bug-208 / #1025 tripwire that detects output-swallowing `jq ... || echo` shapes on gate-critical scripts (the exact mechanism behind KF-004/KF-015 canonical-verdict masking).
- `.claude/adapters/loa_cheval/providers/agy_headless_adapter.py` — the `agy -p` headless provider adapter used in the multi-model review/audit chain, which explicitly treats the prompt as **untrusted review content** (see the adapter's own docstring on the fixed-argv rationale).

All three changes are framed by the PR description as simplifications. In practice each one removes a specific, documented defense that was added to close a previously-diagnosed incident, and none of the removed logic is dead code — each path is reachable from the description of the very code it guards.

## Findings

### Finding 1 — `_write_ledger` no longer rejects non-object JSON, reopening the class of bug it was built to fix (Medium, confidence: Medium)

`head/.claude/scripts/ledger-lib.sh:157`
```bash
if [[ -z "$content" ]] || ! echo "$content" | jq empty 2>/dev/null; then
    echo "ERROR: refusing to write empty or unparseable ledger content" >&2
    return $LEDGER_ERROR
fi
```
`head/.claude/scripts/ledger-lib.sh:179`
```bash
updated_content=$(echo "$content" | jq --arg ts "$(now_iso)" '.last_updated = $ts')
```

`base/.claude/scripts/ledger-lib.sh` guarded with:
```bash
! printf '%s' "$content" | jq -es 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1
```
i.e. content had to parse as **exactly one JSON value, and that value had to be an object**. The new guard (`jq empty`) accepts *any* syntactically valid JSON — arrays, strings, numbers, booleans, and — critically — `null`.

This matters because of what happens two lines later. `jq --arg ts "$ts" '.last_updated = $ts'` is not a no-op on non-objects:

- On `null`, jq **silently promotes it to an object**: `null | .last_updated = "x"` → `{"last_updated":"x"}`. This passes the new guard, produces non-empty `updated_content` (so the `-z` check at line 180 does not catch it), and is written atomically to the ledger — silently discarding every cycle/sprint previously recorded. This is functionally the same failure mode as bug 20260808-a008c6 (empty/degenerate content reaching the ledger write path while every caller reports success), just reached via a different content shape.
- On arrays/scalars/strings the `.last_updated = $ts` assignment does raise a jq type error, which is caught by the existing `-z "$updated_content"` guard — so those shapes fail safe. `null` is the one that slips through both guards.

The comment retained directly above the check ("GUARD (bug 20260808-a008c6): refuse empty/unparseable content BEFORE touching lock, backup, or ledger... while every caller reported success") describes exactly the failure this change reopens for the `null`-content case, while asserting the guard still prevents it.

Today's internal callers (`create_cycle`, `update_cycle_field`, `allocate_sprint_number`, `add_sprint`, `archive_cycle`) all build `content` by piping the existing ledger object through a `jq` filter, so in the current call graph the object shape is normally preserved. The regression is in the removed type check itself, not in a currently-demonstrated call site — but `_write_ledger` is a general-purpose internal function and the removed check was the only thing standing between "any future/refactored caller that passes something other than an object" and silent ledger corruption. Restoring the `length == 1 and (.[0] | type == "object")` check (or an equivalent explicit `type == "object"` test) costs nothing and directly closes the reopened window.

**CWE-20 (Improper Input Validation)** / relates to the incident tracked as bug 20260808-a008c6.

### Finding 2 — `check-no-swallowed-jq.sh` no longer scans *any* heredoc body, silently disabling its own detection for a whole class of executable content (High, confidence: High)

`head/tools/check-no-swallowed-jq.sh:135-146`
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

`base/tools/check-no-swallowed-jq.sh` distinguished two cases via `_hd_command`/`hd_exec` (removed in this diff, previously at `base/tools/check-no-swallowed-jq.sh:46-59,88-89`): a heredoc that is **executed** (piped/redirected into `sh`/`bash`/`python`/etc., or unquoted so it undergoes shell expansion) versus one that is inert documentation/fixture text. Only the inert case was meant to be skipped; an executable heredoc body was still scanned line-by-line for the swallowed-`jq` shape:
```bash
if (hd_exec) {
    if ($0 ~ /^[[:space:]]*#/) next
    if ($0 ~ /#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/) next
    if (_line_has_swallowed_jq($0)) print FILENAME ":" NR ":" $0
}
```

The new version deletes `hd_exec` and the `_line_has_swallowed_jq` call inside `in_heredoc` entirely — **every** heredoc body is now unconditionally skipped, with no distinction between inert fixture text and a heredoc that is actually executed (e.g. `ssh "$host" bash <<EOF … jq … || echo default … EOF`, or an unquoted `cat <<EOF | sh` that assembles a script). Any `jq ... || echo/printf` swallow shape written inside such a heredoc will no longer be flagged by this tool, on either the default enforced-file scan or a `--root` sweep.

This is a direct capability regression in the tool whose entire purpose — per its own header (`head/tools/check-no-swallowed-jq.sh:1-17`) — is to catch the exact shape behind KF-004 (zero-findings canonical verdicts masking real findings) and KF-015 (silent-clean red-team gate pass). The stated motivation for the change (avoiding false positives when `--root` scans bats fixtures containing planted bad examples) is legitimate, but the fix over-corrects: it trades a cosmetic false-positive problem for a functional false-negative hole in a security gate. The prior `hd_exec` classification existed specifically to keep that distinction; simply not restoring an equivalent guard (e.g., skip only when the heredoc is provably inert — unexecuted, quoted delimiter — while still scanning executed heredocs) reopens exactly the risk class this scanner exists to close.

**CWE-693 (Protection Mechanism Failure)**; directly weakens the control described in `head/tools/check-no-swallowed-jq.sh:5-11`.

### Finding 3 — Uncaught `ValueError` on embedded-NUL prompts breaks the adapter's documented "never crash, walk the chain" contract for attacker-influenced input (High, confidence: Medium)

`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:157-165` (end of the inner `try`, no further `except` clauses before the block closes):
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

`base/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:166-170` had one more clause here:
```python
                except ValueError as exc:
                    raise ProviderUnavailableError(
                        self.provider,
                        f"agy -p got un-execable argv (embedded NUL in the prompt?): {exc}",
                    ) from exc
```

`run_subprocess_pgkill(cmd, ...)` at `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:132-138` wraps `subprocess`, which raises `ValueError` (not `OSError`) when argv contains an embedded NUL byte (`embedded null byte`). `cmd` is built from `prompt` at `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:104,274-282`, and `prompt` is the flattened content of `request.messages` (`_build_prompt`, `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:294-326`) — content the adapter's own docstring repeatedly calls **untrusted**: "The prompt is untrusted review content" (`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:270-271`), a characterization used elsewhere in this same file to justify removing an operator-supplied extra-flags escape hatch specifically because untrusted content was found to defeat a denylist (council #1109).

With the `ValueError` handler removed, review/diff content that happens to contain a NUL byte (plausible in a binary-ish diff hunk, a crafted PR body, or any adversarial input deliberately targeting this path) now propagates an unhandled `ValueError` out of `complete()` instead of being converted to `ProviderUnavailableError`. Every sibling failure mode in this same function (`TimeoutExpired`, `SubprocessOutputCapExceeded`, `FileNotFoundError`, `OSError`, `_SemaphoreExhausted`) is deliberately caught and normalized into a typed, walkable error specifically so "the fallback chain advances instead of hanging/crashing" — the `OSError` comment immediately above says this in as many words. An uncaught `ValueError` breaks that invariant for exactly the one input class (attacker/adversarial-controlled prompt bytes) the surrounding code is most defensive about. Depending on the caller, this surfaces as a crashed review/audit run rather than a graceful fallback to the next provider in the chain — a denial-of-service on the automated review pipeline triggerable by content under review, not by the operator.

**CWE-248 (Uncaught Exception)** → **CWE-400 (Uncontrolled Resource Consumption / DoS)** on the multi-model review chain; reachable via untrusted PR/diff content per the adapter's own threat framing.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 1 |
| Low | 0 |

## Verdict

All three changes are individually small, but each removes a specific defense that was added in response to a named, documented incident (bug 20260808-a008c6; sprint-bug-208/#1025 and KF-004/KF-015; council #1109's untrusted-prompt framing), and none of the removed branches were unreachable. Findings 2 and 3 are High severity and force a CHANGES_REQUIRED verdict under the one-way rule.

**Recommendation:**
1. Restore an explicit object-type check in `_write_ledger` (Finding 1) — e.g. `jq -es 'length == 1 and (.[0] | type == "object")'` or equivalent — rather than accepting any valid JSON.
2. Restore heredoc-executability classification in `check-no-swallowed-jq.sh` (Finding 2), or otherwise narrow the heredoc skip so it does not blanket-exempt heredocs that are piped to an interpreter or left unquoted.
3. Restore the `except ValueError` handler in `agy_headless_adapter.py` (Finding 3), or fold it into the existing `OSError` handler if `ValueError` is the only additional exception type expected from embedded-NUL argv.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":1,"low":0},"ts":"2026-09-22T02:08:01Z"} -->
