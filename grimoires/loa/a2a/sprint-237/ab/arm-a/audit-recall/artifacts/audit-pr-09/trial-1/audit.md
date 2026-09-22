# Security Audit Report — PR: fix(#938): butterfreezone-validate skips Express/Fastify route patterns

**Audit type**: Ad-hoc PR audit (no sprint plan / beads / a2a directory present — audited from `PR.md`, `head.diff`, `base/`, `head/` only)
**Auditor**: Paranoid Cypherpunk Auditor
**Date**: 2026-09-22
**Files changed**: `.claude/scripts/butterfreezone-validate.sh`, `tests/unit/butterfreezone-validate-route-false-positive.bats`

## Executive Summary

This PR fixes a documented false-positive in `butterfreezone-validate.sh`'s `validate_references` check: Express/Fastify-style route parameter tokens (e.g. `` `/factors/:factorId` ``) inside BUTTERFREEZONE.md were being parsed as file references and reported as "missing file" because the regex extractor treats any backtick-fenced `path:symbol` token as a file reference. The fix adds a skip condition — absolute-looking tokens (`/...`) that contain no `.` anywhere are treated as route patterns and excluded from the missing-file check. Accompanying bats coverage exercises the route-skip case, a still-flagged absolute path with an extension, and a still-flagged relative path with an extension.

The change is narrowly scoped, non-executable-path (a documentation/RTFM gate script, not an application security boundary), and does not introduce injection, path traversal, or privilege issues. It does, however, weaken the completeness of the "missing file reference" check in a way broader than the stated route-pattern problem, creating a false-negative gap the tests don't cover. No CRITICAL or HIGH findings.

## Overall Risk Level: LOW

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 1 |

## Medium Priority Issues

### MEDIUM-1: Overbroad "no extension anywhere" heuristic silently disables missing-file validation for legitimate extensionless absolute paths

**Component**: `head/.claude/scripts/butterfreezone-validate.sh:293-295`

```bash
if [[ "$file" == /* && "$file" != *.* ]]; then
    continue
fi
```

**Description**: The new skip condition matches any token that (a) starts with `/` and (b) contains **no `.` character anywhere in the entire string** — not just "the final path segment has no extension." This is broader than "looks like a route pattern" in two ways:

1. **Extensionless real files are silently exempted from validation.** Absolute-path references to real files that legitimately lack an extension (shell scripts invoked without `.sh`, `Makefile`-style build files, extensionless binaries, symlinks, or directories referenced as anchors, e.g. `` `/usr/local/bin/mytool:main` `` or `` `/opt/service/bin/start:42` ``) now match `"$file" != *.*` and are skipped entirely — `[[ ! -f "$file" ]]` is never evaluated for them. If a future BUTTERFREEZONE.md (produced by `butterfreezone-gen.sh` or hand-edited) references such a path and the file is deleted, renamed, or was hallucinated, the RTFM gate (referenced in the script's own header comment, `head/.claude/scripts/butterfreezone-validate.sh:6`) will no longer catch it. This directly undermines the "agent-grounded, provenance-tagged" guarantee that BUTTERFREEZONE.md is designed to provide (per `.claude/loa/CLAUDE.loa.md` "BUTTERFREEZONE" section) — the validator is the only mechanism enforcing that grounding.
2. **The dot-anywhere check, not last-segment check, means paths with a dot elsewhere but an extensionless final segment are NOT skipped** (e.g. `` `/opt/app-v2.3/bin/start:main` `` still gets validated, inconsistently), while a genuinely deep path like `` `/very/long/real/path/to/binary:main` `` is unconditionally skipped regardless of depth or plausibility as a route.

**Impact**: False negatives in a documentation-integrity gate. Not directly exploitable (no code execution, no data exposure), but it silently degrades a check whose entire purpose is catching broken/hallucinated references before they reach agent-consumed documentation — a meaningful regression given how heavily this repository's own instructions (Factual Grounding, grounding_requirements) rely on citation accuracy.

**Suggested remediation**: Tighten the heuristic to what the fix actually needs to solve — route *parameter* syntax, not "any extensionless absolute path." E.g. only skip when the token contains a route-param segment (`:` followed by an identifier as a path component, or the well-known `/:` / `/*` Express/Fastify markers), rather than blanket-exempting every dot-free absolute path:

```bash
# Only skip tokens that actually contain a route-param segment (":name" or "*name")
if [[ "$file" == /* && "$file" =~ /(:|\*)[A-Za-z_][A-Za-z0-9_]* ]]; then
    continue
fi
```
This preserves the fix for `` /factors/:factorId `` and `` /users/:userId/sessions `` while still validating plain extensionless absolute file references.

## Low Priority Issues

### LOW-1: New test suite doesn't cover the false-negative case the heuristic introduces

**Component**: `head/tests/unit/butterfreezone-validate-route-false-positive.bats:98-119`

**Description**: The third test (`"real absolute path with extension is still validated"`) only proves the heuristic still catches extensioned absolute paths (`` /nonexistent/path/foo.sh ``). There is no test asserting the converse regression case identified in MEDIUM-1: an extensionless absolute path that is genuinely missing (e.g. `` `/nonexistent/bin/tool:main` ``) is now *silently accepted* rather than flagged. Without this test, a future change could not detect if the heuristic's blast radius grows further.

**Suggested remediation**: Add a bats case asserting that `` `/nonexistent/bin/tool:main` `` (no extension, genuinely missing) is either still flagged as an accepted known limitation (document why), or fix per MEDIUM-1 and assert it's now caught.

## Security Checklist Status

- [x] No secrets/credentials introduced
- [x] No command injection — the added condition uses bash `[[ ... ]]` glob matching on data already extracted by the pre-existing restrictive regex (`[a-zA-Z0-9_./-]+:[a-zA-Z_L][a-zA-Z0-9_]*`); no new shell interpolation into `eval`/subshells
- [x] No path traversal risk — check only affects whether `-f` existence test runs, not what is read/written
- [x] No privilege escalation surface — script remains a local, read-only documentation linter (RTFM gate), not part of a deployed/networked code path
- [ ] Validation completeness — weakened per MEDIUM-1 (false negatives possible for extensionless absolute references)
- [x] Test coverage added for the stated bug, though incomplete per LOW-1

## Threat Model Summary

`butterfreezone-validate.sh` is a local documentation linter run by the RTFM gate and `/butterfreezone` skill; it never executes attacker-controlled input beyond reading file contents already present in the repository and does not run over untrusted network input. The realistic threat here is not exploitation but **silent degradation of a grounding/correctness guarantee** that other agents (and this framework's own "Factual Grounding" mandates) rely on. That keeps this audit's overall risk at LOW despite the MEDIUM finding.

## Verdict

**APPROVED - LET'S FUCKING GO**

No CRITICAL or HIGH issues. The MEDIUM finding (overbroad extensionless-path skip) and LOW finding (missing regression test for the false-negative case) should be addressed in a fast-follow before this heuristic is broadened further, but they do not block merge of this targeted bug fix.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":1},"sprint_id":"pr-938","ts":"2026-09-22T00:00:00Z"} -->
