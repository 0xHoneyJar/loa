# Security Audit Report

**Audit type**: Codebase (PR) audit
**Scope**: `head.diff` — 3 files (`​.claude/scripts/ledger-lib.sh`, `tools/check-no-swallowed-jq.sh`, `.claude/adapters/loa_cheval/providers/agy_headless_adapter.py`)
**PR**: "chore(ledger,tools,cheval): lighter ledger content check, simpler heredoc skipping, fewer except clauses"

## Executive Summary

This PR is framed as a "chore" — three independent simplifications with no behavior
change intended. All three "simplifications" instead remove real defensive logic, and
two of them reopen bugs that this repository's own code comments say were
deliberately fixed:

1. The `_write_ledger` content guard (`ledger-lib.sh`) is weakened from "exactly one
   JSON object" to "parses as JSON" — this reintroduces the class of ledger-corruption
   bug the guard's own comment (bug `20260808-a008c6`) says it exists to prevent.
2. The swallowed-jq tripwire scanner (`check-no-swallowed-jq.sh`) is changed from
   "skip heredoc bodies unless they get executed" to "always skip heredoc bodies" —
   silently disabling the scanner for exactly the executable-heredoc shape it was
   built to catch, on a scanner whose own header names two prior incidents
   (KF-004, KF-015) caused by this class of masked failure.
3. The `ValueError` handler around the `agy` CLI exec (`agy_headless_adapter.py`) is
   deleted outright. It exists to catch a real, reachable CPython failure mode
   (embedded NUL byte in subprocess argv) and convert it into a graceful
   provider-chain fallback; without it, that failure mode is an unhandled crash,
   breaking the file's own stated "never crash the chain" invariant.

None of the three changes are pure refactors — each removes a case the prior code
handled correctly. Two are directly on gate-critical / ledger-integrity paths.

## Overall Risk Level: HIGH

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 1 |
| Low | 0 |

## High Priority Issues

### HIGH-1: Ledger write guard no longer rejects non-object / multi-document content, reopening the corruption bug it documents

**Component**: `head/.claude/scripts/ledger-lib.sh:157` (guard), `head/.claude/scripts/ledger-lib.sh:179` (stamp)

```bash
157:    if [[ -z "$content" ]] || ! echo "$content" | jq empty 2>/dev/null; then
158:        echo "ERROR: refusing to write empty or unparseable ledger content" >&2
159:        return $LEDGER_ERROR
160:    fi
...
179:    updated_content=$(echo "$content" | jq --arg ts "$(now_iso)" '.last_updated = $ts')
```

The prior guard was:

```bash
! printf '%s' "$content" | jq -es 'length == 1 and (.[0] | type == "object")'
```

`jq -es` slurps the entire input into a single array and asserts it decodes to
**exactly one JSON value that is an object**. `jq empty` only asserts the input is
*valid JSON* — it accepts scalars, arrays, `null`, and (because `jq` without `-s`
processes a stream of whitespace/newline-separated JSON texts one at a time) it also
accepts **multiple concatenated JSON documents** in a single string. Two concrete
regressions follow directly from that change:

1. **`content == "null"` passes the guard and corrupts the ledger.** `jq empty`
   accepts the literal `null`. At `head/.claude/scripts/ledger-lib.sh:179`,
   `jq '.last_updated = $ts'` applied to `null` does **not** error — jq's `=`
   assignment operator treats `null` as an implicit empty object and returns
   `{"last_updated": "<ts>"}`. That single-key object is written over the existing
   ledger (`head/.claude/scripts/ledger-lib.sh:189` `echo "$updated_content" >
   "$tmp_file"`, then atomically `mv`'d over the real ledger). This is the exact
   "ledger truncated while every caller reported success" failure class the guard's
   own comment at `head/.claude/scripts/ledger-lib.sh:150-155` says it exists to
   prevent — it is simply reachable via `null` instead of an empty string.
2. **Multiple concatenated JSON documents pass the guard and produce a
   multi-document ledger file.** `content == '{"a":1}\n{"b":2}'` is rejected by the
   old `length == 1` check but accepted by `jq empty` (jq validates each document in
   the stream independently). At line 179, `jq` (without `-s`) then emits **one
   stamped object per input document**, and `echo "$updated_content" > "$tmp_file"`
   writes all of them, back-to-back, into the ledger file — turning a file that must
   contain a single JSON object into a JSON-lines-shaped file that every other
   `jq '.foo'`-style reader in this codebase (e.g. the `.version` read in
   `recover_from_backup`, `head/.claude/scripts/ledger-lib.sh:120-122`) will parse
   incorrectly or silently read only the first record from.

Both cases are silent — `_write_ledger` returns success (`$LEDGER_OK`), matching the
failure mode the guard's own inline comment describes ("every caller reported
success").

**Impact**: Ledger data loss / corruption without any error surfaced to the caller,
on the append-only sprint ledger that sprint numbering and cycle lifecycle tracking
depend on (per the file's own header, "Sources: sdd.md:§5.1").

**PoC**: Any caller of `_write_ledger` that can be induced to pass a JSON `null`
(e.g. an upstream `jq` expression that legitimately produces `null` for a missing
field, then gets passed straight through) or two independently-serialized JSON
values concatenated without an intervening slurp will silently corrupt
`grimoires/loa/ledger.json`.

**Remediation**: Restore the object-type and single-document check, e.g.:

```bash
if [[ -z "$content" ]] || \
   ! printf '%s' "$content" | jq -es 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1; then
```

If the goal was only to drop the `-e`/`-s` naming for readability, that's fine, but
the semantic check (single document, object type) must stay — `jq empty` is not an
equivalent replacement.

**References**: CWE-20 (Improper Input Validation), CWE-704 (Incorrect Type
Conversion or Cast — `null`→object coercion).

---

### HIGH-2: Heredoc bodies are now unconditionally skipped, silently disabling the swallowed-jq tripwire for executed heredocs

**Component**: `head/tools/check-no-swallowed-jq.sh:138-146` (heredoc skip), `head/tools/check-no-swallowed-jq.sh:109-133` (removed exec classification)

```bash
138: in_heredoc {
139:     if ($0 == hd_term) { in_heredoc = 0; next }
140:     if (hd_dash) {
141:         no_tabs = $0
142:         gsub(/^\t+/, "", no_tabs)
143:         if (no_tabs == hd_term) { in_heredoc = 0; next }
144:     }
145:     next
146: }
```

The base version tracked `hd_exec` — whether a heredoc's body is actually going to be
*executed* (fed to an interpreter via `<<EOF | bash`, `bash <<EOF`, etc., or an
unquoted terminator enabling expansion) versus merely embedded as inert
documentation/fixture text (e.g. a `cat <<'EOF'` example block in a bats test). Only
in the non-executed case did it skip scanning the body; when `hd_exec` was true, it
still ran `_line_has_swallowed_jq` against every line inside the heredoc
(`base/tools/check-no-swallowed-jq.sh:174-178`).

The head version deletes `hd_exec`, `_hd_command`, and the interpreter allowlist
entirely (compare `base/tools/check-no-swallowed-jq.sh:108-165` to
`head/tools/check-no-swallowed-jq.sh:108-133`) and now takes the `next` branch
unconditionally for every line inside every heredoc, regardless of whether that
heredoc is a documentation fixture or a script body that will actually run. The
PR's own inline comment at `head/tools/check-no-swallowed-jq.sh:135-137` justifies
this only for the fixture case ("bats tests can flag planted bad examples") but the
mechanism now applies to the executable case too.

This scanner's own header (`head/tools/check-no-swallowed-jq.sh:2-17`) states its
purpose is catching `jq ... || echo <default>` — the exact mechanism named as the
cause of **KF-004** (zero-findings canonical verdicts masking real findings,
recurrence ≥20) and **KF-015** (silent-clean red-team gate pass, 4/4 sprints) in
`grimoires/loa/known-failures.md`. A `jq ... || echo` shape embedded inside a heredoc
that is piped to `bash` or `sh` for execution (a plausible authoring pattern in the
gate-critical scripts this scanner enforces —
`.claude/scripts/adversarial-review.sh`, `flatline-orchestrator.sh`,
`scoring-engine.sh`, `post-pr-triage.sh`, and any `red-team-*` script) will now pass
the scan silently, exactly reproducing the KF-004/KF-015 failure shape this tool
exists to fence.

**Impact**: A verdict-swallowing `jq ... || echo` bug written inside a heredoc in any
enforced gate script goes undetected by CI/lint, on the same class of finding this
tool's own changelog cites two prior real incidents for.

**PoC**: Add to any enforced file (or a `--root`-scanned tree):

```bash
bash <<EOF
result=\$(jq -r '.verdict' report.json 2>/dev/null || echo "APPROVED")
EOF
```

Base version: flagged (heredoc piped to `bash` ⇒ `hd_exec=1` ⇒ line scanned). Head
version: never scanned — `in_heredoc` unconditionally `next`s every body line.

**Remediation**: Restore the `hd_exec` classification (or an equivalent, simpler
exec-vs-inert distinction) rather than removing exec-awareness altogether. If the
`--root`/bats fixture false-positive was the only concrete motivating complaint,
scope the skip to `--root` mode or to a narrower fixture marker, not to every heredoc
scanned in any mode.

**References**: CWE-693 (Protection Mechanism Failure); repository precedent
`grimoires/loa/known-failures.md` KF-004, KF-015.

## Medium Priority Issues

### MEDIUM-1: Removing the `ValueError` handler turns a documented, reachable subprocess failure into an unhandled crash instead of a chain fallback

**Component**: `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:151-163`

```python
151:                except FileNotFoundError as exc:
152:                    raise ConfigError(
153:                        f"agy CLI not found on PATH (set AGY_HEADLESS_BIN to override). "
154:                        f"Install + authenticate the Antigravity CLI on the cheval host. "
155:                        f"Original: {exc}"
156:                    ) from exc
157:                except OSError as exc:
158:                    # E2BIG (ARG_MAX — a huge diff on argv; agy is argv-transport, no
159:                    # --prompt-file exists) or another exec failure → WALK the chain,
160:                    # never crash with a raw OSError. The gemini-api HTTP fallback
161:                    # covers oversized diffs. (FileNotFoundError is handled above.)
162:                    raise ProviderUnavailableError(
163:                        self.provider,
164:                        f"agy -p exec failed (likely ARG_MAX on an oversized prompt): {exc}",
165:                    ) from exc
```

removed (was directly after the `OSError` handler in base):

```python
except ValueError as exc:
    raise ProviderUnavailableError(
        self.provider,
        f"agy -p got un-execable argv (embedded NUL in the prompt?): {exc}",
    ) from exc
```

CPython's subprocess/exec path raises `ValueError` (not `OSError`) when an argv
string contains an embedded NUL byte — this is a well-known, deliberately-carved-out
case in `subprocess`/`os.execve`, and it is exactly the case the deleted handler's
message names ("un-execable argv (embedded NUL in the prompt?)"). `cmd` here is built
from `request.messages`/`prompt` (`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:104-105`),
i.e. attacker/upstream-diff-influenced content that this adapter's own comment at
line 157-161 already acknowledges can be adversarial in size (ARG_MAX). A NUL byte
reaching argv (e.g. from a diff containing binary content, or any upstream
transformation that doesn't strip control characters) is a realistic occurrence for
the same reason oversized argv is: the content is untrusted external input forwarded
close to verbatim into a subprocess argv.

With the handler removed, this `ValueError` is no longer caught by either of the two
enclosing `try` blocks (only `subprocess.TimeoutExpired`, `SubprocessOutputCapExceeded`,
`FileNotFoundError`, `OSError` are handled at
`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:133-165`, and
only `_SemaphoreExhausted` at the outer level, line 166-171) and propagates as an
unhandled exception out of `complete()`. This directly contradicts the module's own
stated invariant one line above the deleted code path ("WALK the chain, never crash")
and the framework-level guarantee in `CLAUDE.loa.md` that the cheval substrate
provides "chain-walk on retryable errors; voice-drop on chain exhaustion" — a crash
here does not walk the chain, it terminates the caller.

**Impact**: Denial of service for the calling review/audit flow (Flatline,
adversarial-review, etc.) on a specific, previously-handled malformed-input case,
instead of the intended graceful fallback to the next provider in the chain.

**Remediation**: Restore the `ValueError` handler exactly as it was; it is not dead
code — it targets a distinct, documented CPython failure mode that `OSError` does not
cover.

**References**: CWE-248 (Uncaught Exception), CWE-755 (Improper Handling of
Exceptional Conditions).

## Security Checklist Status

- [x] Input validation at trust boundaries — **regressed** (HIGH-1: ledger content
      guard no longer validates document shape/type)
- [x] Fail-loud on parse/verdict extraction — **regressed** (HIGH-2: scanner that
      enforces this property is itself weakened)
- [x] Graceful degradation / no unhandled crashes on malformed external input —
      **regressed** (MEDIUM-1)
- [ ] No secrets, credentials, or PII introduced — N/A, none touched
- [ ] No new injection surface — N/A, no new user-input sinks introduced

## Threat Model Summary

All three changes reduce defense-in-depth on paths that this repository's own
history (bug `20260808-a008c6`, KF-004, KF-015) shows have previously caused silent
data loss or silently-masked findings. None of the three are exploitable by an
external attacker directly, but all three degrade the framework's own self-defense
against malformed/adversarial *internal* data (a `null` or multi-document JSON blob
reaching the ledger writer, a `jq || echo` shape reaching an enforced script via a
heredoc, or a NUL byte reaching a subprocess argv from untrusted diff content) —
which is precisely the threat class this repository's own gates (jq_strict,
check-no-swallowed-jq, the ledger content guard) exist to catch.

## Recommendations

**Immediate (24h)**: Revert or fix HIGH-1 and HIGH-2 before merge — both directly
reopen documented prior incidents.

**Short-term (1wk)**: Restore MEDIUM-1's `ValueError` handler; add a regression test
asserting `_write_ledger` rejects `null` and multi-document content, and a bats case
asserting `check-no-swallowed-jq.sh` still flags a `jq ... || echo` shape inside an
executed heredoc.

**Long-term (1mo)**: None beyond the above — this PR should not proceed as a "chore"
without re-scoping to preserve the semantics it removes.

## Verdict

**CHANGES_REQUIRED**

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":1,"low":0},"sprint_id":"pr-audit","ts":"2026-09-22T00:00:00Z"} -->
