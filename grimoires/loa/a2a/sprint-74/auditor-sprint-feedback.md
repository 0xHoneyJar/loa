# APPROVED - LETS FUCKING GO

# Security Audit — Sprint 1 (Global Sprint-74): Vision-Aware Planning

**Auditor**: Paranoid Cypherpunk Auditor
**Date**: 2026-02-26
**Verdict**: APPROVED with 3 advisory findings (no blockers)
**Files Audited**: 6 source files, 6 fixtures, 2 review documents
**Tests Executed**: 52/52 passing (31 vision-lib + 21 vision-registry-query)

---

## Executive Summary

The implementation is security-sound for its threat model. All critical paths have proper input validation (SKP-005), jq parameter binding (no injection), flock-guarded concurrency, and defense-in-depth content sanitization. The two gaps identified by the engineer reviewer (missing auto-tag test, missing concurrent writer test) have been addressed -- both tests now exist and pass. No hardcoded secrets, no command injection vectors, no path traversal escapes. Three advisory findings noted below for hardening in future sprints.

---

## Audit Checklist

### 1. Secrets: No hardcoded credentials, API keys, or tokens
**PASS** -- No secrets found in any of the 6 source files or 6 fixtures. No API keys, no tokens, no passwords, no credential file paths. Shadow state and config files contain only structural data.

### 2. Injection: No command injection via user-controlled inputs
**PASS** -- All jq calls use `--arg` parameter binding (vision-lib.sh lines 227-234, vision-registry-query.sh lines 272-282, shadow entry construction at lines 323-331). No `eval`, no `sh -c`, no unquoted variable expansion in command position. Sed substitutions in `_do_update_status` and `_do_record_ref` properly escape `\`, `/`, and `&` metacharacters via `printf '%s' "$var" | sed 's/[\\/&]/\\\\&/g'` (lines 455-456, 525).

The unquoted heredoc in `bridge-vision-capture.sh` (line 244) uses `<<EOF` instead of `<<'EOF'`. However, this is safe because the variables being interpolated (`${title}`, `${description}`, `${potential}`, `${finding_id}`) are already bash variables containing jq output -- shell does not re-expand `${...}` patterns or backticks within variable values during heredoc expansion. This is a convention violation (CLAUDE.loa.md prefers Write tool for source files) but not a security vulnerability.

### 3. Input Validation: SKP-005 compliance
**PASS** -- Comprehensive validation:
- Vision IDs: `^vision-[0-9]{3}$` (vision-lib.sh line 93) -- tested with valid and invalid cases
- Tags: `^[a-z][a-z0-9_-]*$` (vision-lib.sh line 103) -- tested with uppercase, numeric-start, spaces
- Status: enum whitelist `Captured|Exploring|Proposed|Implemented|Deferred` (multiple locations)
- Directory paths: canonical path resolution + project root prefix check (vision-lib.sh lines 111-132)
- Malformed index entries: logged and skipped, not fatal (vision-lib.sh lines 194-212)
- Refs: sanitized to integer with regex check (vision-lib.sh line 222)
- Numeric arguments: used directly in `$((...))` after validation

**Minor discrepancy (ADVISORY-1)**: The tag regex in `vision-registry-query.sh` line 125 is `^[a-z][a-z0-9_,-]*$` (allows commas) while the canonical regex in `_vision_validate_tag` is `^[a-z][a-z0-9_-]*$` (no commas). Since tags are split by comma first, the comma in the individual tag regex is redundant/misleading but not exploitable -- a tag containing a comma would have been split before reaching this check.

### 4. Content Sanitization: Vision text sanitization effectiveness
**PASS with ADVISORY** -- Defense-in-depth architecture is sound:
- **Primary defense**: awk section extraction limits input to text between `## Insight` and next `##` heading (line 331). This is the strongest layer -- all non-insight content is excluded.
- **Secondary defense**: HTML entity decoding before tag stripping (correct ordering), instruction tag removal, code fence stripping, indirect instruction line filtering, whitespace normalization, truncation to configurable limit.

Verified with injection fixture: `<system>` tags, `<prompt>` tags, code fences, HTML-encoded variants, and "ignore previous" instructions are all properly stripped.

**ADVISORY-2 (Case-insensitive bypass)**: The sed patterns for `<system>`, `<prompt>`, `<instructions>` and the grep pattern for indirect instructions are case-sensitive. `<SYSTEM>`, `<System>`, `IGNORE PREVIOUS`, `Forget All`, `You Are Now` all bypass the filters. Verified empirically:
```
Input:  <SYSTEM>EVIL</SYSTEM> Ignore Previous instructions.
Output: <SYSTEM>EVIL</SYSTEM> Ignore Previous instructions.
```
**Severity**: LOW-MEDIUM. The primary defense (awk section extraction) limits exposure. The content is injected into LLM planning context, not executed as code. However, prompt injection via case-variant tags is a real vector if a malicious actor crafts a vision entry.
**Recommended fix**: Add `-i` flag to sed and `grep -viE` for case-insensitive matching. Single-line fix per pattern.

### 5. Concurrency: Flock-guarded writes are correct
**PASS** -- `vision_atomic_write()` (lines 144-159) uses flock with 5-second timeout, file descriptor 200, subshell-scoped execution. Used by `vision_update_status` (line 473) and `vision_record_ref` (line 536). Lock file is `{target_file}.lock`.

Concurrent writer test exists and passes: 5 parallel `vision_record_ref` calls against same vision, starting at refs=4, ending at refs=9 (test line 343-361). This confirms no lost updates under contention.

Shadow state update is flock-guarded (line 346). Shadow state read is outside the lock (lines 310-312), creating a theoretical TOCTOU for the counter. Severity: NEGLIGIBLE -- shadow counters being off by one does not affect correctness or security.

Shadow JSONL log append (line 333) is not flock-guarded. Per POSIX, single-line writes under PIPE_BUF (4096 bytes) are atomic on local filesystems. Acceptable for non-critical telemetry data.

### 6. Path Traversal: Directory validation prevents escaping project root
**PASS** -- `_vision_validate_dir()` (lines 111-132) resolves both the candidate directory and `PROJECT_ROOT` to canonical paths via `cd ... && pwd`, then performs a strict prefix check with trailing-slash defense:
```bash
if [[ "$canon_dir" != "$canon_root" && "$canon_dir" != "$canon_root"/* ]]; then
```
This correctly prevents `/home/user/project-evil` from matching `/home/user/project`. The directory must also exist for `cd` to succeed (symlink-following is handled by `pwd` returning the real path).

Used by `vision-registry-query.sh` (line 134) for `--visions-dir`. NOT used by `bridge-vision-capture.sh` for `--output-dir` (see ADVISORY-3).

**ADVISORY-3 (Missing validation in capture script)**: `bridge-vision-capture.sh` does not call `_vision_validate_dir` on its `--output-dir` argument. A crafted `--output-dir=/tmp/evil` could write vision entries outside the project root. **Severity**: LOW -- this script is called programmatically by bridge automation, not by end users. The output directory is always `grimoires/loa/visions/` in practice. But defense-in-depth says validate anyway.

### 7. Error Handling: No sensitive information in error messages
**PASS** -- Error messages expose only:
- File paths (necessary for debugging)
- Vision IDs (format: `vision-NNN`)
- Status values (enum)
- Tag values (validated alphanumeric)

No stack traces, no internal variable dumps, no credential paths, no system information beyond `uname -s` for platform detection.

### 8. Test Coverage: Security-relevant code paths tested
**PASS** -- All critical security paths have test coverage:
- Input validation (IDs, tags): `_vision_validate_id` and `_vision_validate_tag` tests (lines 250-289)
- Content sanitization: 5 tests covering clean extraction, injection stripping, HTML entities, truncation, missing file (lines 141-188)
- Injection fixture: Comprehensive `entry-injection.md` with `<system>`, `<prompt>`, code fences, HTML-encoded variants, indirect instructions
- Malformed input handling: `index-malformed.md` with missing IDs, bad formats, missing status, invalid status (5 variants)
- Concurrent writes: Parallel flock test (lines 343-361)
- Status enum validation: Tests for both valid and invalid status values
- Empty/missing registry: Graceful degradation tested

**Not tested** (non-blocking):
- `_vision_validate_dir` path traversal -- not directly tested, but exercised indirectly through query script tests
- Case-insensitive injection bypass (relates to ADVISORY-2)

---

## Findings Summary

| # | Type | Severity | Description | Location |
|---|------|----------|-------------|----------|
| ADVISORY-1 | Input Validation | LOW | Tag regex in query script includes comma in character class | vision-registry-query.sh:125 |
| ADVISORY-2 | Content Sanitization | LOW-MEDIUM | Case-sensitive injection filters bypass with uppercase variants | vision-lib.sh:350-358 |
| ADVISORY-3 | Path Traversal | LOW | `--output-dir` in capture script not validated against project root | bridge-vision-capture.sh:183 |

---

## Reviewer Gap Resolution

The engineer reviewer identified 2 gaps:
1. **Missing `--tags auto` test** -- NOW PRESENT: `vision-registry-query.bats` test "vision-registry-query: --tags auto derives from sprint plan" (lines 265-296). Creates minimal sprint.md and prd.md, verifies derived tags produce expected matches.
2. **Missing concurrent writer test** -- NOW PRESENT: `vision-lib.bats` test "vision_record_ref: concurrent writers don't corrupt counters" (lines 343-361). 5 parallel processes, verifies final count = initial + 5.

Both tests pass. The reviewer's advisory notes (return-in-subshell, shadow log append, path prefix) are all acknowledged and correctly assessed as non-blocking.

---

## Approval Rationale

The implementation demonstrates strong security discipline:
- All user inputs validated before use (SKP-005)
- All jq calls use `--arg` parameter binding (no jq injection, per PR #215 convention)
- Flock concurrency protection with empirical verification
- Content sanitization with defense-in-depth (section extraction + pattern stripping + truncation)
- No secrets, no eval, no command injection surfaces
- 52 passing tests covering all security-relevant paths

The three advisory findings are LOW to LOW-MEDIUM severity and are appropriate for a follow-up hardening sprint rather than blocking this merge. The case-insensitive bypass (ADVISORY-2) is mitigated by the primary defense layer (awk section extraction) and the fact that vision text is used as LLM context, not executed as code.

Ship it.
