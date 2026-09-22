# Review: chore(ledger,tools,cheval): lighter ledger content check, simpler heredoc skipping, fewer except clauses

## Overall Assessment

This PR frames itself as pure simplification ("lighter check", "simpler ... state machine",
"fewer except clauses") but all three hunks quietly remove correctness guarantees that were
put in place to fix specific, named incidents (bug `20260808-a008c6` for the ledger guard;
an ARG_MAX/embedded-NUL exec failure for the adapter). None of the three regressions are
mentioned or justified in the PR description. **CHANGES REQUIRED.**

## Critical / High Issues

### 1. `_write_ledger` guard drops the object-type check — `null` content silently truncates the ledger (HIGH)

`head/.claude/scripts/ledger-lib.sh:157`

```bash
if [[ -z "$content" ]] || ! echo "$content" | jq empty 2>/dev/null; then
```

The base version (`base/.claude/scripts/ledger-lib.sh:152-153`) required the content to parse
as a **single JSON object**: `jq -es 'length == 1 and (.[0] | type == "object")'`. The new
version only checks that `content` parses as *some* JSON value — arrays, numbers, strings, and
`null` all pass.

`null` is the dangerous case, because of jq's null-promotion semantics: assigning a key to
`null` auto-vivifies it into an object. The very next step,
`head/.claude/scripts/ledger-lib.sh:179`:

```bash
updated_content=$(echo "$content" | jq --arg ts "$(now_iso)" '.last_updated = $ts')
```

turns `content="null"` into `updated_content='{"last_updated":"<ts>"}'` — non-empty, so the
`[[ -z "$updated_content" ]]` fallback at line 180 does **not** catch it, and this gets written
over the real ledger (`version`, `cycles`, `active_cycle`, everything) via the atomic
temp-file+mv path a few lines later. This is exactly the failure mode the guard's own comment
(lines 152-156) describes — "passed through the last_updated jq stamp ... and truncated the
ledger ... while every caller reported success" — just reachable through `null` instead of an
empty string. The comment was kept verbatim while the protection it describes was narrowed.

Every other malformed shape (arrays, numbers, plain strings) still fails safely downstream
because `.last_updated = $ts` errors on them and `updated_content` comes back empty — `null` is
the one shape jq treats specially. Restore the `type == "object"` check (or check
`content != "null"` explicitly) rather than a bare `jq empty`.

### 2. Heredoc bodies are now unconditionally inert — real, executed heredocs are no longer scanned (HIGH)

`head/tools/check-no-swallowed-jq.sh:138-146`

```awk
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

The base version (`base/tools/check-no-swallowed-jq.sh:158-178`) tracked `hd_exec` — whether
the heredoc's terminator was unquoted (shell-interpolated) or the heredoc was piped/fed into an
interpreter (`sh`, `bash`, `python`, etc., detected via `_hd_command`/`INTERP`). When `hd_exec`
was true, the scanner kept matching `_line_has_swallowed_jq` *inside* the heredoc body, because
that body is executable code, not documentation.

The new version removed `_hd_command`, `INTERP`, and `hd_exec` entirely and treats every
heredoc body as inert fixture text, always `next`-ing past it. This is a real detection
regression, not just a simplification: a gate-critical script that does something like

```bash
cat <<EOF | bash
result=$(jq -r '.field' file.json 2>/dev/null || echo "default")
EOF
```

— i.e. the exact output-swallowing shape this tripwire exists to catch (per this file's own
header, KF-004/KF-015) — will now silently pass the scan, because it's inside a heredoc that
used to be flagged as executable (`hd_exec=1`, unquoted terminator piped to `bash`) and is now
unconditionally skipped. The new "Step 1" comment justifies this purely from the false-positive
side ("bats test fixtures ... planted bad examples") and never addresses the false-negative
cost of losing `hd_exec`. No test file is part of this diff, so there's no evidence the
trade-off was validated against a case that exercises real executed-heredoc detection.

### 3. Removed `ValueError` handler reintroduces a raw crash instead of walking the provider chain (MEDIUM-HIGH)

`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:157-165` (post-diff, the
handler is gone; compare `base/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:161-165`)

The removed code was:

```python
except ValueError as exc:
    raise ProviderUnavailableError(
        self.provider,
        f"agy -p got un-execable argv (embedded NUL in the prompt?): {exc}",
    ) from exc
```

This sits in a block whose sibling handler (kept, `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:157-164`) states the invariant explicitly: *"WALK the chain, never
crash with a raw OSError."* `subprocess`/exec on POSIX raises `ValueError` (not `OSError`) when
argv contains an embedded NUL byte — a distinct, documented Python exec failure mode from the
`OSError`/`E2BIG` case handled just above it. The comment on the removed handler shows this was
a specific, previously-diagnosed failure ("un-execable argv (embedded NUL in the prompt?)"), not
a speculative catch-all.

With the handler gone, a prompt containing an embedded NUL now propagates a raw `ValueError` out
of `execute()` instead of being converted to `ProviderUnavailableError` and walking the
fallback chain like every other exec failure in this block (`FileNotFoundError`, `OSError`,
`TimeoutExpired`, `SubprocessOutputCapExceeded`). That's a behavioral regression for callers
that rely on this adapter degrading gracefully (the whole point of the chain-walk pattern used
throughout this method), and it isn't mentioned in the PR description beyond "removes the
ValueError handler."

## Adversarial Analysis

### Concerns Identified
1. `null`-promotion footgun in the ledger guard (`head/.claude/scripts/ledger-lib.sh:157`) — see Issue 1.
2. Loss of `hd_exec`-gated heredoc scanning (`head/tools/check-no-swallowed-jq.sh:138`) — see Issue 2.
3. Removed `ValueError` handler reintroduces a crash path (`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:157`) — see Issue 3.
4. No test changes accompany any of the three hunks, despite each one touching a piece of code whose header comments explicitly reference a prior incident (`bug 20260808-a008c6`, KF-004/KF-015) — there's no evidence the regressions in Issues 1–2 were caught by an existing suite, and no new coverage was added to lock in the (narrower) new behavior.

### Assumptions Challenged
- **Assumption**: the engineer assumed `jq empty` is an equivalent, merely-simpler replacement for `jq -es 'length==1 and (.[0]|type=="object")'`.
- **Risk if wrong**: it isn't equivalent — it silently accepts `null`, which jq's assignment operator promotes into a fresh object, exactly reproducing the "clean ledger, all fields gone" failure the guard was written to prevent (Issue 1).
- **Recommendation**: restore the object-type check; if the goal was just to drop the `-es`/slurp usage, `jq -e 'type == "object"'` (non-slurped) achieves the same validation with the requested simplicity.

### Alternatives Not Considered
- **Alternative**: for the heredoc scanner, keep `hd_exec` detection but make the "planted bats fixture" false-positive case (the stated motivation for Step 1) go away by requiring `--root` scans to also filter on `_is_script`/shebang the same way default-mode scans do, or by having bats fixtures use `<<'EOF'` with a marker the scanner already special-cases, rather than deleting real detection for every heredoc everywhere.
- **Tradeoff**: this preserves the tripwire's ability to catch swallowed-jq inside genuinely executed heredocs (the scanner's actual job) while still fixing the bats false-positive that motivated the change.
- **Verdict**: should reconsider — the diff optimizes for "fewer false positives in bats scans" at the cost of "zero detection inside any heredoc," which is a much larger blast radius than the problem being solved.

## Next Steps

1. Restore a type check in `_write_ledger` (object-type or explicit `null` rejection) before merging.
2. Restore `hd_exec`-style detection in `check-no-swallowed-jq.sh`, or explicitly scope down the tripwire's documented guarantees (update the header's "Detection logic" / "Tripwire scope" sections) if the maintainers accept that heredocs are now entirely out of scope — that's a documentation obligation this diff doesn't meet either way.
3. Restore the `ValueError` handler in `agy_headless_adapter.py`, or provide evidence (e.g. a test, or confirmation the embedded-NUL scenario is now prevented upstream) that this failure mode can no longer occur.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":1,"low":0},"sprint_id":"pr-review","ts":"2026-09-22T00:00:00Z"} -->
