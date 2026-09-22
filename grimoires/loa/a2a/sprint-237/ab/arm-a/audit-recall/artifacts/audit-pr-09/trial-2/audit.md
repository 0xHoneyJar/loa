# Security Audit Report

**PR**: fix(#938): butterfreezone-validate skips Express/Fastify route patterns
**Scope**: `.claude/scripts/butterfreezone-validate.sh`, `tests/unit/butterfreezone-validate-route-false-positive.bats`
**Auditor**: auditing-security skill

## Executive Summary

The PR adds a one-line skip condition to `validate_references()` in `butterfreezone-validate.sh` so that backtick-fenced references whose file segment starts with `/` and contains no `.` (e.g. `/factors/:factorId` from an Express/Fastify route table) are no longer reported as missing files. The fix is narrowly scoped, accompanied by a 3-case regression suite (route pattern skipped, real absolute path with extension still validated, real relative path still validated), and matches the documented false-positive (route params were being split on `:` and the leading path segment treated as a filesystem reference).

The change is low blast-radius as claimed, but the heuristic is a coarser proxy than the stated intent ("skip route patterns") — it actually skips *any* absolute-path reference lacking a dot anywhere in the string, not just ones shaped like Express/Fastify routes. That silently removes file-existence validation (no FAIL, no WARN, not even counted in `checked`) for a class of legitimate absolute paths this script is meant to catch (extensionless config/binary paths, e.g. `/etc/hosts`, `/usr/local/bin/foo`, `Makefile`-style absolute refs). This is a documentation-integrity gap, not a code-execution or data-exposure vulnerability — `validate_references` never `eval`s or executes referenced content, and the new conditional uses safe bash glob comparison (no injection surface). No CRITICAL or HIGH issues found. One MEDIUM (overbroad heuristic / silent bypass with no telemetry) and one LOW (comment/behavior precision) are raised below.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 1 |

## Findings

### MEDIUM-1: Overbroad heuristic silently disables file-existence validation for all extensionless absolute-path references, with no compensating signal

**Component**: `head/.claude/scripts/butterfreezone-validate.sh:294-296`

```bash
294:        if [[ "$file" == /* && "$file" != *.* ]]; then
295:            continue
296:        fi
```

**Description**: The condition is "starts with `/`" AND "contains no `.` anywhere in the string." This is a strict superset of "looks like an Express/Fastify route." Any absolute-path reference that happens to have no extension — `/etc/hosts`, `/usr/local/bin/rg`, `/opt/app/bin/migrate`, a directory reference, or simply a typo'd/nonexistent absolute path an agent hallucinated into BUTTERFREEZONE.md — matches the same branch and is `continue`d before `checked` is incremented (`head/.claude/scripts/butterfreezone-validate.sh:298`). Unlike the pre-existing skip list just above it (`http`, `//`, `head_sha`, `generated_at`, `generator` — all exact/structural matches on known non-file tokens), this new skip is a heuristic over attacker/author-controlled free text, and it produces **zero output**: no `log_fail`, no `log_warn`, and the item isn't reflected in the final `"All file references valid ($checked checked)"` pass message denominator. A reviewer or downstream automation reading the validator's output has no way to tell that a given absolute-path reference was silently exempted versus genuinely validated.

Per the file's own header, this script is "Used by RTFM gate and `/butterfreezone` skill" — i.e., it is the mechanism that keeps `BUTTERFREEZONE.md` (the project's "Agent-Grounded README," consumed by other agents as ground truth per `.claude/loa/CLAUDE.loa.md` §BUTTERFREEZONE) honest. Because `BUTTERFREEZONE.md` content can originate from PR-supplied or agent-generated text, an author (malicious or merely sloppy) can now put any nonexistent extensionless absolute path in a reference — `See \`/opt/backdoor/installer:setup\` for details` — and the RTFM/ground-truth gate will pass it silently. This doesn't grant code execution or leak data, but it does undermine the specific guarantee this script exists to provide (that referenced paths are real), for exactly the class of reference (absolute paths) where a wrong claim is most likely to mislead a human or an agent following it.

**Failure scenario**: A BUTTERFREEZONE.md is generated/edited (by hand, by a compromised dependency, or by a hallucinating agent) with a reference like `` `/etc/shadow:credentials` `` or `` `/nonexistent/tool:run` ``. Pre-fix, this would `FAIL` the reference check (correctly, or as a false positive for a real route — the bug being fixed). Post-fix, it is silently skipped: `validate_references` returns 0 for this entry, contributes to neither `failures` nor `checked`, and the RTFM gate sees a clean pass. Anything (human reviewer or an agent) that later trusts the "ground truth" of BUTTERFREEZONE.md and acts on that absolute path does so without the validator ever having looked at it.

**Remediation**: Narrow the skip condition to what the comment actually describes — a route pattern — rather than "any extensionless absolute path." A route-param shape requires the symbol half (already available in this loop as `$symbol`, i.e. the text after the first `:`) to itself look like a path segment/identifier that continues the URL (Express/Fastify params are `:name` immediately following a `/`), and/or requires the `ref` to have been sourced from a section tagged as HTTP routes (the fixture uses `### HTTP Routes` / `tier2_grep` provenance). A concrete tightening: only skip when the *symbol* portion is a bare identifier **and** the original unsplit `ref` contains a second `/` after the colon-split point would have occurred inside a path (i.e., reconstruct and check for the literal substring `` :`$symbol` `` embedded mid-path, not just "no dot in the file part"). At minimum, emit `log_warn` (not silent `continue`) when the skip fires, so the check count and audit trail reflect that a reference was exempted rather than validated — this preserves the "low blast radius" intent while removing the silent-bypass property.

---

### LOW-1: Skip condition is broader than the code comment claims

**Component**: `head/.claude/scripts/butterfreezone-validate.sh:287-293`

The comment states real absolute-path file references "would have extensions ... those still match below," presented as if the heuristic is airtight. That's true only for the common case of scripts/binaries with extensions; it is not true for extensionless real files (shell scripts without `.sh`, compiled binaries, `Makefile`-style artifacts referenced by absolute path). The comment should be updated to state the actual trade-off (extensionless absolute paths are unconditionally exempted, accepting some false negatives) rather than asserting the heuristic is complete — this is a documentation-precision issue that would have made MEDIUM-1 more visible in review, not a functional defect on its own.

**Remediation**: Rephrase the comment to acknowledge the known gap (this is effectively already done in the test file's docstring at `head/tests/unit/butterfreezone-validate-route-false-positive.bats:10-12`, which correctly hedges with "real absolute-path file references have extensions" as an assumption rather than a guarantee — align the script comment with that framing, or fold in the honest caveat).

## Test Coverage Assessment

The three added bats tests (`head/tests/unit/butterfreezone-validate-route-false-positive.bats:32-52`, `:54-80`, `:82-112`) correctly cover: (1) the reported false positive is fixed, (2) real absolute paths *with* extensions are still validated (guards against over-fixing), (3) real relative paths are unaffected. They do **not** cover the gap identified in MEDIUM-1 — an extensionless absolute path that is *not* a route and does not exist (e.g. `` `/etc/nonexistent-file:foo` ``) — which is exactly the case that would demonstrate the false-negative regression. Recommend adding a fourth case asserting current (accepted-risk) behavior for that input, so any future tightening of the heuristic has a test to update deliberately rather than a silent behavior change.

## Security Checklist Status

- [x] No secrets or credentials introduced
- [x] No command injection / eval of untrusted content (bash glob comparison only, no `eval`, no unquoted expansion into a command)
- [x] No path traversal risk introduced (existing `[[ ! -f "$file" ]]` check is unaffected by the skip; skip only *bypasses* a check, doesn't `cd`/read/write using the skipped path)
- [x] Regression tests added for the stated bug
- [ ] Gap in test coverage for the false-negative case introduced by the heuristic (see above)
- [ ] Silent (unlogged) bypass path added to a validator whose consumers (RTFM gate, `/butterfreezone`) rely on complete signal

## Verdict

MEDIUM/LOW only, no CRITICAL/HIGH findings. Per the one-way rule, this does not force `CHANGES_REQUIRED`; the underlying bug fix is correct and well-tested for the case it targets. Recommend the MEDIUM-1 remediation (narrow the heuristic and/or emit `log_warn` on skip) as a fast follow-up before this validator is depended on further, but it does not block this PR.

**APPROVED - LET'S FUCKING GO**

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":1},"sprint_id":"pr-938","ts":"2026-09-22T00:00:00Z"} -->
