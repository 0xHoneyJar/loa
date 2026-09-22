# Security Audit Report — PR: chore(ledger,tools,cheval): lighter ledger content check, simpler heredoc skipping, fewer except clauses

**Audit type**: Ad-hoc PR audit (no sprint/beads context; PR-file-only review)
**Scope**: `head.diff` touching `.claude/scripts/ledger-lib.sh`, `tools/check-no-swallowed-jq.sh`, `.claude/adapters/loa_cheval/providers/agy_headless_adapter.py`

## Executive Summary

This PR frames itself as a pure simplification ("lighter check", "simpler heredoc skipping",
"fewer except clauses"), but all three hunks trade away real defensive behavior for less code.
The `ledger-lib.sh` change downgrades a content-integrity guard from "single JSON object" to
"parses as JSON at all," which reopens a variant of the exact corruption class the guard's own
comment (`GUARD (bug 20260808-a008c6)`) says it exists to prevent. The `check-no-swallowed-jq.sh`
change deletes the heredoc-body scanning entirely, silently narrowing a security tripwire whose
own file header cites two prior known-failure incidents (KF-004, KF-015) of exactly this failure
mode (a masked/loud-vs-silent verdict). The `agy_headless_adapter.py` change removes a
`ValueError` handler that converts a specific, real Python failure mode (embedded NUL byte in a
subprocess argument) into a controlled provider-chain-walk error; without it, that failure now
propagates as an unhandled exception instead of triggering the documented chain-walk/voice-drop
fallback.

None of these are directly remotely-exploitable RCE/injection bugs, but all three are regressions
in gate/guard code whose entire purpose is defense-in-depth against silent failure and data
corruption — exactly the class of bug this repository's own conventions (stash-safety.md,
known-failures.md precedent cited in the diff itself) treat as high-severity.

## Overall Risk Level: **HIGH**

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 1 |
| Low | 0 |

## Findings

### [HIGH-1] Ledger write guard weakened from "single JSON object" to "parses as JSON at all" — reopens multi-document corruption

**Component**: `head/.claude/scripts/ledger-lib.sh:157`

```bash
157:    if [[ -z "$content" ]] || ! echo "$content" | jq empty 2>/dev/null; then
```

The prior guard (visible in `head.diff`'s removed lines, and still described by the unchanged
comment directly above at `head/.claude/scripts/ledger-lib.sh:152-155`) was:

```bash
! printf '%s' "$content" | jq -es 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1
```

`jq empty` only verifies that its input is well-formed JSON; unlike `jq -es 'length==1 and ...'`,
it does **not** slurp the input, so it happily accepts input containing **multiple
whitespace/no-separator-concatenated JSON documents** (jq's stream parser processes each
top-level value independently) and it does **not** check that the parsed value is an object.

Verified locally:
```
$ printf '%s' '{"a":1}{"b":2}' | jq empty        # exits 0, no output -> PASSES new guard
$ printf '%s' '{"a":1}{"b":2}' | jq -es 'length == 1 and (.[0] | type == "object")'
false                                             # exits 1 -> old guard correctly rejected this
```

Two concatenated JSON objects is exactly the shape a caller can produce accidentally (e.g. two
racing writers' output concatenated, or a caller that forgot to overwrite vs. append). With the
new guard this content now reaches the timestamp-stamping step at
`head/.claude/scripts/ledger-lib.sh:179`:

```bash
179:    updated_content=$(echo "$content" | jq --arg ts "$(now_iso)" '.last_updated = $ts')
```

`jq FILTER` (no `-s`) applied to multi-document input runs the filter over **each** document and
emits one output per document — i.e. `updated_content` becomes two stamped JSON objects
concatenated, which then gets written atomically as the entire ledger file
(`head/.claude/scripts/ledger-lib.sh` write-and-`mv` block below the shown range). This corrupts
the ledger into a non-single-object multi-document file that every other consumer of this ledger
(anything doing `jq '.some_field'` on the whole file, e.g. the `jq -r '.version // "missing"'`
pattern already used elsewhere in this same file at line 121) will silently misparse against only
the *first* embedded document, hiding state from the second.

This is a regression of the same class the guard's own comment says it was hardened against
("passed through the last_updated jq stamp … and truncated the ledger … while every caller
reported success") — the failure mode changes from "truncate to empty" to "corrupt to
multi-document," but the mechanism (a stamping step that doesn't validate document count/shape)
and the outcome (silent corruption, callers still see exit 0) are the same.

**Impact**: Silent ledger corruption; downstream readers of the ledger get inconsistent/partial
state with no error surfaced at write time.

**Remediation**: Restore the `-es 'length == 1 and (.[0] | type == "object")'` check (or
equivalent), or explicitly slurp-and-validate before stamping. If the intent was only to drop the
"not empty" duplication, that could have been done without also dropping the object/single-document
constraint.

---

### [HIGH-2] `check-no-swallowed-jq.sh` no longer scans executed heredoc bodies — reopens the tripwire's own stated evasion class

**Component**: `head/tools/check-no-swallowed-jq.sh:113-156`

The removed code (visible in `head.diff`) tracked, per heredoc, whether the heredoc's *body* was
going to be executed (fed to `bash`/`sh`/`python`/etc., or an unquoted heredoc subject to expansion)
via the `hd_exec` flag computed in `_start_heredoc()`/`_hd_command()`, and — only in that case —
continued applying `_line_has_swallowed_jq()` to lines inside the heredoc. The new version
(`head/tools/check-no-swallowed-jq.sh:130-142`) removed `hd_exec`, `_hd_command`, and all of the
interpreter-detection logic, and now unconditionally does:

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

i.e. **every** line inside **every** heredoc is now skipped, regardless of whether that heredoc's
content is inert documentation/fixture text or is piped straight into `bash`/`sh` and executed.

This file's own header (`head/tools/check-no-swallowed-jq.sh:5-10`) states the entire reason this
tripwire exists: `jq … 2>/dev/null || echo <default>` shapes previously caused KF-004 ("zero-findings
canonical verdicts masking real findings, recurrence ≥20") and KF-015 ("silent-clean red-team gate
pass, 4/4 sprints"). A gate-critical script that constructs its jq-swallowing logic inside a heredoc
passed to `bash <<EOF … jq foo || echo default … EOF` — a completely ordinary way to write a
templated subshell — is now invisible to this scanner, on both the default `ENFORCED_FILES` scan and
the `--root` recursive scan used by the bats integration suite
(`tests/integration/check-no-swallowed-jq.bats`, per line 55 of the header). The base version's
`hd_exec` logic existed specifically to keep this distinction (fixture heredocs excluded, executed
heredocs still scanned); the new version collapses that distinction to "never scan," silently
narrowing this security gate's coverage rather than preserving it while removing incidental
complexity.

The PR description ("simpler heredoc skipping") frames this purely as a simplification, but the
`_hd_command`/`hd_exec` machinery it removed was the part of the tool doing actual security work,
not incidental complexity — the surrounding comment added in this same diff
(`head/tools/check-no-swallowed-jq.sh:113-115`, "Without this, --root scans of bats tests can flag
planted bad examples") only justifies skipping *non-executed* heredoc bodies, but the patch skips
*all* of them.

**Impact**: A whole class of swallowed-jq shapes (anything inside a heredoc fed to an interpreter)
is no longer caught by this tripwire, in both CI enforcement and the bats regression suite that is
supposed to guard this tool's own behavior.

**Remediation**: Restore the executed-vs-fixture heredoc distinction (or, if the bats false-positive
problem is the real motivation, fix it by tagging fixture heredocs explicitly rather than by
disabling detection for all heredocs).

---

### [MEDIUM-1] Removing the `ValueError` handler drops a documented, real failure mode instead of converting it to the chain-walk contract

**Component**: `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:163` (context: lines 122-170 in `base/`, now ending at line ~168 in `head/`)

The removed code was:
```python
except ValueError as exc:
    raise ProviderUnavailableError(
        self.provider,
        f"agy -p got un-execable argv (embedded NUL in the prompt?): {exc}",
    ) from exc
```

`subprocess`/`os.exec*` on CPython raises `ValueError` (not `OSError`) when an argv element
contains an embedded NUL byte — this is distinct from the `OSError` case (E2BIG/ARG_MAX) still
handled two lines below at `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py`'s
retained `except OSError` clause, and distinct from `FileNotFoundError`. A prompt containing an
embedded NUL byte (e.g. from binary content accidentally included in a diff/prompt payload) will
now raise a bare `ValueError` that is **not** caught by any of the remaining `except` clauses in
this `try` block, propagating up past this adapter instead of being converted into
`ProviderUnavailableError`.

Per this repository's own multi-model conventions
(`.claude/loa/reference/multi-model-reference.md`, summarized in `CLAUDE.loa.md` — "chain-walk on
retryable errors; voice-drop on chain exhaustion"), every other exec-failure branch in this exact
function (`FileNotFoundError`, `OSError`, `SubprocessOutputCapExceeded`, `_SemaphoreExhausted`,
`subprocess.TimeoutExpired`) is deliberately converted to a typed error so the cheval dispatcher can
walk to the next provider in the chain rather than crash. Removing only the `ValueError` branch
means this one specific, previously-anticipated failure mode (per the deleted comment: "embedded
NUL in the prompt?") now breaks that contract — an unhandled exception surfaces instead of a
graceful fallback to the next model in the chain.

**Impact**: A single malformed prompt (embedded NUL byte) can crash the whole multi-model dispatch
instead of falling back to another provider, for this one adapter only — inconsistent with every
sibling error branch in the same function.

**Remediation**: Restore the `except ValueError` branch, or fold it into a combined
`except (OSError, ValueError) as exc:` if the intent was only to reduce clause count.

## Security Checklist Status

- [x] Input Validation — **FAILED** (HIGH-1: ledger write path no longer validates document
      shape/count before use)
- [x] Error Handling — **FAILED** (MEDIUM-1: one exec failure mode now unhandled, inconsistent
      with sibling branches)
- [x] Defense-in-depth / Tooling integrity — **FAILED** (HIGH-2: security tripwire coverage
      silently narrowed)
- [ ] Secrets & Credentials — N/A to this diff
- [ ] Authentication & Authorization — N/A to this diff
- [ ] Supply Chain — N/A to this diff

## Threat Model Summary

None of these three changes are attacker-facing injection/RCE vectors on their own — the ledger
content and the swallowed-jq scanner both operate on repo-internal/CI-internal inputs, and the
cheval adapter's NUL-byte case requires a caller to construct a pathological prompt. The actual
risk is **regression of guard rails that exist specifically because this repository has already
been burned by this exact failure class** (per the diff's own retained comments citing bug
20260808-a008c6, KF-004, and KF-015). Each finding independently reduces the blast-radius
protection these three pieces of code were written to provide, with no compensating control added
in exchange.

## Verdict

**CHANGES_REQUIRED**

Recommended action: restore the object/single-document check in `_write_ledger`, restore the
executed-heredoc scanning distinction in `check-no-swallowed-jq.sh`, and restore the `ValueError`
handler (or merge it with the `OSError` handler) in `agy_headless_adapter.py`. If the PR author's
goal is genuinely just fewer lines, each of these can be re-simplified without losing the specific
guarantee it currently drops.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":1,"low":0},"sprint_id":"pr-audit","ts":"2026-09-22T00:00:00Z"} -->
