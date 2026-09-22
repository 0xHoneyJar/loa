# Security & Quality Audit Report

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-09-22
**Scope:** PR `chore(ledger,tools,cheval): lighter ledger content check, simpler heredoc skipping, fewer except clauses` — 3 files: `.claude/scripts/ledger-lib.sh`, `tools/check-no-swallowed-jq.sh`, `.claude/adapters/loa_cheval/providers/agy_headless_adapter.py`
**Methodology:** Line-by-line diff review (base → head) of all three touched files, with call-site tracing for `_write_ledger` and the `check-no-swallowed-jq` heredoc scanner.

---

## Executive Summary

This PR presents itself as a pure simplification ("lighter", "simpler", "fewer") of three unrelated pieces of gate/safety infrastructure, but two of the three changes measurably weaken the exact protections their surrounding comments claim to preserve.

The `ledger-lib.sh` change replaces a strict "must be a JSON object" content check with a bare `jq empty` (any valid JSON, including scalars and `null`) syntax check. Because the subsequent `jq '.last_updated = $ts'` stamp step *auto-vivifies* a `null` input into a fresh object, a caller (or a corrupted/uninitialized ledger file) that produces literal `null` content now passes the guard and silently replaces the entire ledger with `{"last_updated": "<ts>"}` — the identical failure class ("ledger truncated to near-nothing while the caller reports success") that the guard's own inline comment says it exists to prevent (bug 20260808-a008c6).

The `check-no-swallowed-jq.sh` change deletes the entire `hd_exec` heuristic that distinguished heredocs fed to an interpreter (executable code, must be scanned) from heredocs used as static data (fixtures/templates, safe to skip). The new version unconditionally skips **every** heredoc body regardless of whether it is executed. This is a coverage regression in a tool whose sole purpose, per its own header, is preventing exactly this class of "silent-clean gate pass" (KF-004/KF-015) on the enforced gate-critical script set (`adversarial-review.sh`, `flatline-orchestrator.sh`, `scoring-engine.sh`, `post-pr-triage.sh`, `red-team-*`).

The third change (dropping the `ValueError` handler in `agy_headless_adapter.py`) is a smaller robustness regression: a `ValueError` from the subprocess exec path (the documented Python failure mode for an embedded NUL byte in argv) is no longer converted into a graceful `ProviderUnavailableError`, so it will now propagate uncaught and abort the whole multi-model call instead of advancing the provider fallback chain — reachable via attacker-influenced prompt content (e.g. PR diff text fed into a review pipeline, which is precisely this workspace's own use case).

None of the three changes are flagged in the PR description as behavior changes — all are framed as pure simplification/cleanup, which is not an accurate characterization of any of them.

**Overall Risk Level:** HIGH

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 2 |
| Low | 1 |

---

## Severity Tally (Phase 2.5)

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 2 |
| Low | 1 |

`critical + high = 2 > 0` → verdict is **CHANGES_REQUIRED** under the one-way rule.

---

## High Priority Issues (Fix Before Merge)

### [HIGH-001] Ledger content guard now accepts non-object JSON, and `null` reintroduces the exact truncation bug the guard exists to prevent

**Severity:** HIGH | **Confidence:** MEDIUM
**Component:** `head/.claude/scripts/ledger-lib.sh:157` (guard), `head/.claude/scripts/ledger-lib.sh:179` (stamp)

**Description:**
The base check was:
```bash
if [[ -z "$content" ]] || \
   ! printf '%s' "$content" | jq -es 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1; then
```
which requires `content` to parse as exactly one JSON *object*. The head version (`head/.claude/scripts/ledger-lib.sh:157`) is:
```bash
if [[ -z "$content" ]] || ! echo "$content" | jq empty 2>/dev/null; then
```
`jq empty` only validates that the input is *some* syntactically valid JSON — arrays, strings, numbers, booleans, and `null` all now pass. The stamp step immediately after (`head/.claude/scripts/ledger-lib.sh:179`):
```bash
updated_content=$(echo "$content" | jq --arg ts "$(now_iso)" '.last_updated = $ts')
```
behaves differently depending on which non-object JSON slips through:
- arrays/strings/numbers/booleans → `jq` raises "Cannot index X with string" and produces no stdout, so `updated_content` is empty and the existing `[[ -z "$updated_content" ]]` check (`head/.claude/scripts/ledger-lib.sh:180-185`) safely aborts the write.
- `null` → jq's assignment operator auto-vivifies `null` into `{}` before setting the key, producing `{"last_updated": "<ts>"}` — non-empty, so it passes the safety-net check and is written to the ledger via the atomic `mv` at `head/.claude/scripts/ledger-lib.sh:198`, **overwriting every other field in the ledger** (`cycles`, `active_cycle`, `next_sprint_number`, etc.) with a single-key object.

The comment immediately above the guard (`head/.claude/scripts/ledger-lib.sh:152-156`) explicitly describes this as the failure this guard prevents: "An empty string here previously passed through the last_updated jq stamp … and truncated the ledger to a 1-byte newline while every caller reported success." The new implementation reopens the same class of bug via the literal string `null` instead of the empty string, because it dropped the `type == "object"` constraint that the base version used specifically to exclude this case (`-es 'length==1 and (.[0]|type=="object")'` rejects `[null]` since `null`'s type is `"null"`, not `"object"`).

**Impact:** Total loss of ledger state (all cycles, sprint tracking, active-cycle pointer) reduced to a single timestamp key, on any code path where `_write_ledger` is invoked with literal JSON `null` as content — e.g. a ledger file that is itself `null` (partial-write/corruption recovery scenario), or a future/refactored caller that forwards a `jq` filter result which evaluates to `null` (a common jq idiom, e.g. `.some.optional.field`). All current call sites in this file build `ledger_content` via `jq '.field = ...' "$ledger_path"` against an already-object ledger, so today's shipped callers are not directly observed to trigger it — but the guard's entire reason for existing is to be the last line of defense against exactly this shape regardless of caller behavior, and that defense is now gone for the `null` case.

**Proof of Concept:**
```bash
source .claude/scripts/ledger-lib.sh
_write_ledger "null"
# guard: echo null | jq empty  → exits 0, passes
# stamp: echo null | jq '.last_updated = $ts' → {"last_updated":"..."}
# ledger file is now {"last_updated":"..."} — every prior cycle/sprint gone
```

**Remediation:**
```bash
# Before (head — weakened)
if [[ -z "$content" ]] || ! echo "$content" | jq empty 2>/dev/null; then

# After (restore the object-type constraint the base version had)
if [[ -z "$content" ]] || \
   ! printf '%s' "$content" | jq -es 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1; then
```
If the `printf`/`echo` swap (see MED-001) is kept, use `printf '%s'` here too rather than `echo`.

**References:** CWE-20 (Improper Input Validation), CWE-704 (Incorrect Type Conversion or Cast) — https://cwe.mitre.org/data/definitions/20.html, https://cwe.mitre.org/data/definitions/704.html

---

### [HIGH-002] `check-no-swallowed-jq.sh` no longer distinguishes executed heredocs from inert ones — blind spot on the tool's own enforced gate-critical scripts

**Severity:** HIGH | **Confidence:** HIGH
**Component:** `head/tools/check-no-swallowed-jq.sh:108-146` (removal of `hd_exec`/`_hd_command`/`INTERP` logic; `in_heredoc` block now unconditionally `next`s)

**Description:**
The base AWK scanner tracked, per heredoc, whether its body was actually going to be *executed* as shell/interpreter code (`hd_exec`, computed by `_hd_command`/`_start_heredoc` at `base/tools/check-no-swallowed-jq.sh:122-165`): it inspected the command immediately preceding the `<<` redirect (stripping `env`/`sudo`/`command`/`exec`/`nohup`/`time`, checking against an interpreter allowlist `sh bash zsh ksh dash ash python python2 python3 perl ruby node deno php`) and whether the heredoc's output was piped into an interpreter. Only when `hd_exec` was true did the base scanner scan the heredoc body for the swallowed-jq shape (`base/tools/check-no-swallowed-jq.sh:174-178`); otherwise it treated the body as inert data (e.g. a `cat <<EOF > file.json` template) and skipped it — this is what let `--root` scans of the bats test fixtures avoid false-positiving on planted bad examples in test data.

The head version deletes `hd_exec`, `_hd_command`, `_start_heredoc`'s command-sniffing, and the `INTERP` allowlist entirely (compare `base/tools/check-no-swallowed-jq.sh:108-165` to `head/tools/check-no-swallowed-jq.sh:108-133`). The new `in_heredoc` block (`head/tools/check-no-swallowed-jq.sh:138-146`) unconditionally `next`s every line until the terminator, with no scanning at all:
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
This means a gate-critical script (one of `ENFORCED_FILES` at `head/tools/check-no-swallowed-jq.sh:66-71`, or a `.claude/scripts/red-team-*` script) that builds an executed heredoc — e.g. `bash <<'SCRIPT' … jq '.verdict' report.json || echo "clean" … SCRIPT` piped to a subshell, ssh, or another interpreter — is now completely invisible to this scanner. The tool's own header explicitly frames its entire purpose as preventing "zero-findings canonical verdicts masking real findings" (KF-004) and "silent-clean red-team gate pass" (KF-015) (`head/tools/check-no-swallowed-jq.sh:5-11`); silently losing detection coverage on an executed-heredoc variant of the exact shape it's built to catch is the same failure category the tool exists to prevent, now reintroduced into the tool itself.

The PR description calls this "simpler heredoc skipping," which undersells the change: it isn't a simplification of the skip logic, it's the removal of the exec/non-exec distinction that skip logic depended on. The header's "Detection logic" section (`head/tools/check-no-swallowed-jq.sh:19-36`) and the "Tripwire scope (NOT exhaustive defense)" caveat (`head/tools/check-no-swallowed-jq.sh:38-43`) are unchanged by this PR, so the shipped documentation still doesn't disclose that heredoc bodies are now unconditionally exempt — a reader of the header alone would not know this blind spot exists.

**Impact:** A gate-critical script that embeds the swallowed-jq anti-pattern inside a heredoc fed to an interpreter will pass this tripwire scan silently, undermining the CI/pre-commit enforcement this tool is meant to provide on `adversarial-review.sh`, `flatline-orchestrator.sh`, `scoring-engine.sh`, `post-pr-triage.sh`, and all `red-team-*` scripts.

**Mitigating factor:** The header already disclaims "multi-line forms … are out of scope" as a general tripwire-scope caveat, so this isn't a broken promise so much as a silent narrowing of what was previously extra, purpose-built coverage beyond that baseline disclaimer.

**Remediation:** Restore the `hd_exec` computation (or an equivalent, simpler heuristic — e.g. "heredoc redirected into `sh|bash|python...` on the same line") so heredocs that are actually executed are still scanned, while fixture/documentation heredocs remain skipped. At minimum, update the header's "Tripwire scope" section to explicitly state that *all* heredoc bodies (including executed ones) are now out of scope, so the documented scope matches actual behavior.

**References:** CWE-693 (Protection Mechanism Failure) — https://cwe.mitre.org/data/definitions/693.html

---

## Medium Priority Issues

### [MED-001] `printf '%s'` → `echo` swap reintroduces the `echo` leading-flag footgun in the ledger content pipeline

**Severity:** MEDIUM | **Confidence:** MEDIUM
**Component:** `head/.claude/scripts/ledger-lib.sh:157`, `head/.claude/scripts/ledger-lib.sh:179`

**Description:** Both the content-validation line and the timestamp-stamp line switched from `printf '%s' "$content"` to `echo "$content"`. Bash's `echo` builtin treats a sole argument matching `^-[neE]+$` (e.g. `-n`, `-e`, `-en`) as an option rather than literal data, regardless of quoting — this is exactly the class of bug `.claude/rules/shell-conventions.md`'s "Bash Strict Mode Safety" guidance in this repo warns about for shell scripting generally. Concretely: if `content` is the literal 2-character string `-n` (not valid JSON, so it *should* be rejected), `echo "$content"` at `head/.claude/scripts/ledger-lib.sh:157` emits nothing; piped into `jq empty` on empty stdin, `jq` exits 0 (per this file's own comment at `head/.claude/scripts/ledger-lib.sh:154-155`: "jq on empty input emits nothing and exits 0"). The guard's `[[ -z "$content" ]]` half doesn't catch it either, since `content` itself (`"-n"`) is non-empty. The invalid content silently passes the "refuse empty, unparseable" gate it was supposed to be rejected by.

**Impact:** In the current code, this does not directly cause ledger corruption — the same `echo` flag-swallowing happens again at the stamp step (`head/.claude/scripts/ledger-lib.sh:179`), producing empty `updated_content`, which is caught by the existing `[[ -z "$updated_content" ]]` check and aborts with an error. So the practical effect today is a *wrong error path* (the operator sees "timestamp stamping produced empty content" instead of the more accurate "refusing to write ... unparseable ... content"), not data loss. But this is a latent landmine: it relies on the same footgun firing twice in a row to be safe, and any future edit to either line (e.g. adding a `--` before the variable, or changing one call site but not the other) can turn it into a silent data-loss path again.

**Remediation:** Revert both call sites to `printf '%s' "$content"`, which has no flag-interpretation ambiguity.

**References:** CWE-20 (Improper Input Validation) — https://cwe.mitre.org/data/definitions/20.html

---

### [MED-002] Removing the `ValueError` handler drops graceful fallback for a documented subprocess failure mode, reachable from attacker-influenced prompt content

**Severity:** MEDIUM | **Confidence:** MEDIUM
**Component:** `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:157` (surviving `OSError` handler, now the last except clause in this try block)

**Description:** The base version caught `ValueError` immediately after `OSError` in the `run_subprocess_pgkill` try block (`base/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:166-170`, removed in head) and converted it into `ProviderUnavailableError` with the message "agy -p got un-execable argv (embedded NUL in the prompt?)". `ValueError` is not a subclass of `OSError` in Python, so it is not covered by the surviving `except OSError as exc:` clause at `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:157`. Python's `subprocess`/`os.exec*` machinery raises `ValueError` (not `OSError`) for an embedded NUL byte in an argv string — a well-documented CPython behavior. With the handler removed, that `ValueError` now propagates uncaught out of `_execute_headless`, past the `_SemaphoreExhausted` handler (a different exception type, `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:166-169`), and crashes the call instead of raising `ProviderUnavailableError` to let the multi-model fallback chain advance to the next provider.

The prompt fed to `agy -p` is built from `request.messages` (`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:104`, `_build_prompt`), which in a review/audit pipeline context is typically derived from PR diff content, file contents, or other text that is not fully trusted (this very audit workspace is an instance of that pattern: an externally-supplied diff feeding an automated review chain). A NUL byte embedded in that content is a plausible, low-effort way to reach this path.

**Impact:** Denial of service against the specific `agy-headless` fallback step: instead of a clean provider-unavailable signal that lets the chain proceed to the next configured provider (e.g. the gemini-api HTTP fallback mentioned in the neighboring `OSError` comment), the whole multi-model call raises an unhandled exception.

**Remediation:**
```python
# Restore
except ValueError as exc:
    raise ProviderUnavailableError(
        self.provider,
        f"agy -p got un-execable argv (embedded NUL in the prompt?): {exc}",
    ) from exc
```
placed before/alongside the existing `except OSError as exc:` block.

**References:** CWE-248 (Uncaught Exception) — https://cwe.mitre.org/data/definitions/248.html

**[ASSUMPTION]** This finding assumes `run_subprocess_pgkill` ultimately calls into `subprocess.Popen`/`os.exec*` with the built argv without pre-sanitizing NUL bytes; the helper's implementation is not included in this PR's diff/base/head file set, so this could not be directly verified in this workspace.

---

## Low Priority Issues

### [LOW-001] `check-no-swallowed-jq.sh` header documentation not updated to reflect the heredoc-scope narrowing

**Severity:** LOW
**Component:** `head/tools/check-no-swallowed-jq.sh:19-43`

**Description:** See HIGH-002. The "Detection logic" and "Tripwire scope" sections of the header comment still describe the tool as it behaved before this PR (no mention that executed heredocs are now also skipped). This is a documentation-accuracy gap, not a functional one.

**Remediation:** Update the header to state that all heredoc bodies, executed or not, are currently out of scope, so the documented behavior matches actual behavior.

---

## Positive Findings

- The `ledger-lib.sh` atomic-write structure (temp file + `mv`, `flock` around the critical section, backup-before-write) is untouched by this PR and remains sound.
- `check-no-swallowed-jq.sh`'s core same-line detection regex (`_line_has_swallowed_jq`) and its word-boundary handling are unchanged and unaffected by this PR.
- The `agy_headless_adapter.py` change is narrowly scoped to one `except` clause; it does not touch the surrounding semaphore, timeout, or output-cap handling, which remain correct.
- All three changes are small and easy to review in isolation, which is what made the HIGH-001/HIGH-002 regressions traceable in the first place.

---

## Recommendations

### Immediate Actions (before merge)
1. Revert the `ledger-lib.sh` content guard to the object-type-checking form (HIGH-001), or explicitly add a `type == "object"` (or equivalent) constraint to the new `jq empty` check.
2. Restore heredoc-exec detection in `check-no-swallowed-jq.sh`, or explicitly document (and get sign-off on) the new blind spot in the header (HIGH-002).

### Short-Term Actions (this week)
1. Revert `echo "$content"` back to `printf '%s' "$content"` in both `ledger-lib.sh` call sites (MED-001).
2. Restore the `ValueError` handler in `agy_headless_adapter.py`, or confirm (by reading `run_subprocess_pgkill`'s implementation, not available in this PR's file set) that `ValueError` cannot actually occur on this path before dropping it (MED-002).

### Long-Term Actions
1. Add a bats/unit test asserting `_write_ledger "null"` is rejected, to lock in the HIGH-001 fix and prevent recurrence.
2. Add a `check-no-swallowed-jq` self-test fixture containing an executed heredoc with the swallowed-jq shape, so any future regression of HIGH-002's class fails CI rather than being caught only by manual audit.

---

## Verdict

**Overall Risk Level: HIGH**

**Next Steps:**
1. Address HIGH-001 and HIGH-002 before merge; both silently narrow protections whose entire stated purpose is guarding against exactly the failure modes reopened here.
2. Address MED-001 and MED-002 in the same PR if feasible, since they are one-line reverts.

---

**Audit Completed:** 2026-09-22
**Remediation Tracking:** N/A — no `grimoires/loa/a2a/` directory present in this evaluation workspace; this is a standalone PR audit.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":2,"low":1},"ts":"2026-09-22T00:00:00Z"} -->
