# Security Audit Report — PR: fix(#938) butterfreezone-validate skips Express/Fastify route patterns

**Audit Date**: 2026-09-22
**Auditor**: Paranoid Cypherpunk Auditor
**Scope**: `head.diff` (2 files: `.claude/scripts/butterfreezone-validate.sh`, `tests/unit/butterfreezone-validate-route-false-positive.bats`)
**Audit Type**: Ad-hoc PR audit (no sprint plan / beads / a2a context available — audited from diff + head/base snapshots only)

## Executive Summary

The PR adds a single heuristic to `validate_references()` in `butterfreezone-validate.sh`: any backtick-referenced "file" that starts with `/` and contains no `.` character is now skipped by the missing-file check, on the theory that such tokens are Express/Fastify-style route parameters (e.g. `/factors/:factorId`) rather than filesystem paths. This is a narrowly-scoped, low-risk change to a documentation/legibility validator (BUTTERFREEZONE.md), not a runtime security control. There is no command injection, path traversal, or privilege-escalation surface introduced — the new conditional is a pure string test (`[[ ... ]]`) over a value already constrained by the extraction regex's `[a-zA-Z0-9_./-]+` character class, so no shell metacharacters can reach it.

The change does introduce a genuine (and openly documented) false-negative: any real absolute-path file reference lacking an extension (e.g. `/usr/local/bin/deploy:main`) will now silently bypass the missing-file check. This reduces the validator's power to catch stale/incorrect documentation and is gameable by anyone (human or agent) authoring a BUTTERFREEZONE.md, but the blast radius is confined to a documentation-accuracy gate, not an authorization or data-integrity boundary. One accompanying regression test also asserts a claim that isn't actually exercised due to a pre-existing (unrelated) regex limitation, which overstates the test's coverage.

**Overall Risk Level**: LOW

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 1 |

## Findings

### MEDIUM — Heuristic silently disables missing-file detection for all extensionless absolute-path references

- **Component**: `head/.claude/scripts/butterfreezone-validate.sh:294-296`
- **Description**: The new guard:
  ```bash
  if [[ "$file" == /* && "$file" != *.* ]]; then
      continue
  fi
  ```
  skips the missing-file check (`head/.claude/scripts/butterfreezone-validate.sh:300-302`) for *any* backtick reference whose file portion starts with `/` and contains no `.`, not only route-parameter tokens. A genuinely broken documentation reference to a real, missing, extensionless absolute path — e.g. `` `/opt/security/audit-tool:main` `` or `` `/usr/local/bin/deploy:bootstrap` `` (common for shell wrappers, compiled binaries, or Node CLI shims installed without an extension) — will now be silently treated as "not a file" and pass validation even though the referenced path does not exist.
- **Impact**: `validate_references` backs the RTFM/BFZ quality gate that keeps `BUTTERFREEZONE.md` (an agent-grounded project summary consumed by downstream tooling and other agents per `CLAUDE.loa.md` "BUTTERFREEZONE") accurate. This heuristic is a strict superset of the intended fix — it doesn't distinguish "looks like a route because it's followed by a `:paramName` token that itself starts with a colon-prefixed segment" from "any extensionless absolute path." Anyone editing BUTTERFREEZONE.md (including an automated generator or a malicious/careless contributor) can now cause a nonexistent absolute-path reference to pass the validator undetected simply by omitting a file extension, weakening the gate's ability to catch inaccurate agent-facing documentation.
- **PoC**: Given a BUTTERFREEZONE.md containing `` See `/opt/nonexistent-tool:run` for details. ``, `butterfreezone-validate.sh` reports no failure for this reference (verified by tracing the logic: `file="/opt/nonexistent-tool"` starts with `/`, contains no `.`, hits the new `continue`, `checked` is never incremented, and `[[ ! -f "$file" ]]` — which would otherwise fire `log_fail "references" "Referenced file missing: ..."` at `head/.claude/scripts/butterfreezone-validate.sh:300-302` — is never reached).
- **Remediation**: Narrow the heuristic to actually require route-parameter shape rather than "any extensionless absolute path" — e.g. also require that the *symbol* portion of the match is itself preceded by a `:` inside the path (true Express/Fastify params look like `/factors/:factorId`, where the literal `:` appears mid-path, not just as the `path:symbol` delimiter already stripped by the extraction regex). A more robust check: skip only when `$file` matches `^/([a-zA-Z0-9_-]+/)*[a-zA-Z0-9_-]+/$` (trailing slash before the stripped `:param`, which is how Express routes render once split on the *first* remaining `:`) — or, simpler and still low-blast-radius per the PR's own stated goal, keep the extensionless-absolute-path skip but downgrade it from a silent `continue` to a `log_warn` so extensionless absolute references are still surfaced for human review instead of disappearing entirely from the report.
- **References**: CWE-1173 (Improper Use of Validation Framework — a validation heuristic broader than its documented intent), OWASP quality-gate erosion pattern.

### LOW — Regression test asserts route-with-trailing-segment behavior that the extraction regex never exercises

- **Component**: `head/tests/unit/butterfreezone-validate-route-false-positive.bats:81-102`
- **Description**: The first test's fixture includes `` **POST** `/users/:userId/sessions` (`./src/routes/auth.ts:42`) `` and asserts `! [[ "$output" == *"Referenced file missing: /users/"* ]]` (line 101). However, the reference-extraction regex at `head/.claude/scripts/butterfreezone-validate.sh:272` — `` `[a-zA-Z0-9_./-]+:[a-zA-Z_L][a-zA-Z0-9_]*` `` — requires the backtick-delimited token to end immediately after the symbol's `[a-zA-Z0-9_]*` run. For `` `/users/:userId/sessions` ``, after matching symbol `userId` the very next character is `/` (not a closing backtick), so the whole token fails to match the extraction regex and is never even considered by `validate_references` — with or without this PR's new skip logic. The assertion therefore passes vacuously: it does not verify that the new `/*`+no-extension heuristic handles multi-segment routes, only that a token the extractor was already incapable of parsing continues to be ignored.
- **Impact**: Test-coverage overstatement. If a future change alters the extraction regex to also match multi-segment backtick tokens, this test would give false confidence that the route-skip heuristic still holds for that shape, since it was never actually exercising that code path.
- **PoC**: N/A (static regex-trace analysis of `head/.claude/scripts/butterfreezone-validate.sh:272` against the fixture at `head/tests/unit/butterfreezone-validate-route-false-positive.bats:71`).
- **Remediation**: Either add a fixture line using a single-segment route (e.g. `` `/factors/:factorId` `` alone, which the first assertion at line 100 already correctly covers) and drop the `/users/` assertion, or fix the extraction regex/test setup so the multi-segment case is genuinely reachable before asserting on it.
- **References**: CWE-1120-adjacent (test does not validate the claimed condition); general test-quality concern, not a runtime defect.

## Security Checklist Status

- [x] No secrets/credentials introduced
- [x] No command/SQL/template injection surface (new value flows only through `[[ ]]` string test, never `eval`/`bash -c`/subshell interpolation)
- [x] No new external network calls or privilege changes
- [x] No authentication/authorization logic touched
- [x] Extraction regex character class (`[a-zA-Z0-9_./-]+`) already excludes shell metacharacters before reaching the new check
- [ ] Validator's missing-file detection is now systematically weaker for extensionless absolute paths (see MEDIUM finding)
- [x] `set -euo pipefail` and existing script conventions preserved; no new unbound-variable or arithmetic-under-`set -e` hazards introduced
- [x] New test file follows existing bats conventions (setup/teardown, `mktemp -d`, no untrusted input)

## Threat Model Summary

This script runs locally as part of the RTFM/BFZ documentation-quality gate, operating only on repository-local file paths already constrained to a safe character set by the extraction regex. There is no network-facing or privilege-boundary-crossing behavior in the diff. The realistic "threat" here is documentation drift/gaming — an author (human, or an automated BFZ generator run by an agent) causing an inaccurate absolute-path reference to pass validation — rather than a classic exploit primitive (RCE, injection, auth bypass). This is consistent with the tool's role as an agent-legibility/documentation validator, not a security control gating dangerous actions.

## Recommendations

- **Immediate (24h)**: None required — no CRITICAL/HIGH issues.
- **Short-term (1wk)**: Tighten the route-detection heuristic per the MEDIUM finding's remediation (require the path to look like a stripped Express param, not merely "extensionless absolute path"), or downgrade the silent skip to a warning so extensionless absolute references stay visible.
- **Long-term (1mo)**: Consider replacing the ad-hoc regex/heuristic approach to reference classification with an explicit tag (e.g. a `provenance: route` annotation already used elsewhere in this file's SDD-driven tagging scheme) so route tokens are unambiguously distinguished from file paths at generation time rather than inferred post-hoc by shape.

## Verdict

**APPROVED - LET'S FUCKING GO**

No CRITICAL or HIGH severity findings. The MEDIUM finding is a scoped, documented trade-off in a documentation-quality validator (not a security-boundary control) and matches the PR's own stated "low blast radius" rationale; it is worth tightening but does not block merge. The LOW finding is a test-quality nit.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":1},"sprint_id":"pr-938","ts":"2026-09-22T00:00:00Z"} -->
