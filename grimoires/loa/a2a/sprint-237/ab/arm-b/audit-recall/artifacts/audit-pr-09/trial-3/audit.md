# Security Audit: fix(#938): butterfreezone-validate skips Express/Fastify route patterns

## Scope

Single-file bash change plus a new regression test suite:

- `head/.claude/scripts/butterfreezone-validate.sh` — adds a 10-line skip heuristic to `validate_references()` (a doc-reference integrity check used by the RTFM/butterfreezone gate).
- `head/tests/unit/butterfreezone-validate-route-false-positive.bats` — new bats coverage for the fix.

No other files in the diff. This validator only checks BUTTERFREEZONE.md-shaped documents for broken file/symbol references (existence + advisory symbol-grep); it is not part of any auth, execution, or trust-boundary path. Reviewed by reading the full script (`head/.claude/scripts/butterfreezone-validate.sh:1-806`) for context, and by manually tracing the new branch against the added test fixtures.

## Findings

### MEDIUM: Skip heuristic is broader than the stated route-pattern intent and silently suppresses genuine broken-reference detection

`head/.claude/scripts/butterfreezone-validate.sh:294`

```bash
if [[ "$file" == /* && "$file" != *.* ]]; then
    continue
fi
```

The comment above this line (`head/.claude/scripts/butterfreezone-validate.sh:287-293`) justifies the heuristic on the premise that "real absolute paths would have extensions." That premise is false in general: absolute references to extensionless files — shell scripts invoked without a suffix, compiled binaries, `Makefile`/`LICENSE`/`Dockerfile`-style files, directories — are common in this repo's own tree (e.g. `.claude/scripts/butterfreezone-validate` style invocations, `/usr/local/bin/<tool>`). Any BUTTERFREEZONE.md entry of the form `` `/some/real/path:symbol` `` where the path has since been deleted or renamed, and happens to have no `.` anywhere in it, now passes `validate_references` silently instead of failing.

**Failure scenario:** a future edit deletes or renames an extensionless script (e.g. an entry point wrapper), leaving `` `/scripts/deploy:main` `` stale in BUTTERFREEZONE.md. Pre-patch, `validate_references` would emit `FAIL: Referenced file missing: /scripts/deploy` and (per `.loa.config.yaml`'s strict mode / the RTFM gate) block the merge. Post-patch, the same stale reference is matched by the new `/* && !*.* ` condition and is skipped entirely — `checked` is never incremented and no fail/warn is logged — so the gate reports success over drifted documentation. This is a real (if narrow) regression in the guarantee the check exists to provide, not merely a cosmetic false-positive fix.

The heuristic also does more than the PR title claims: it is not scoped to `:`-containing route-param patterns at all (the route-parameter shape is already fully constrained by the caller's regex at `head/.claude/scripts/butterfreezone-validate.sh:272`, which requires a `:[a-zA-Z_L][a-zA-Z0-9_]*` symbol suffix — matching only backtick spans like `` `/factors/:factorId` ``). Any absolute, extensionless `file` component reaching this point is skipped regardless of whether the reference actually looks like a route (e.g. a hypothetical `` `/opt/tool:VERSION` `` reference would be silently dropped too). A tighter fix would gate on the symbol actually beginning with the route-param leader (the code already splits `file`/`symbol` on the first `:`; checking that the raw match contains `/:` immediately before the symbol, or that `symbol` doesn't look like a `L<N>`/CamelCase code symbol used elsewhere in this file, would preserve the existence check for genuine absolute paths).

**Confidence:** high that the code behaves as described (manually traced against the PR's own fixtures); medium on real-world exploitability, since this only degrades an advisory/documentation-integrity gate rather than an authn/authz or execution boundary — no code path in this diff executes, reads, or serves the contents of attacker-influenced `$file` beyond the pre-existing `-f`/`grep -q` checks that were already present in `base/.claude/scripts/butterfreezone-validate.sh` and are unchanged by this PR.

**CWE-1284** (Improper Validation of Specified Quantity in Input) / **CWE-20** (Improper Input Validation) — the fix trades a false-positive (route params flagged as missing files) for an unbounded false-negative (any extensionless absolute-path reference, real or not, is no longer checked). https://cwe.mitre.org/data/definitions/1284.html

**Remediation:** narrow the skip condition to actually require the route-parameter shape, e.g. require the matched reference to contain `/:` right before the symbol (`[[ "$ref" == *"/:"* ]]`) rather than keying purely off "starts with `/`, has no dot anywhere." This keeps the Express/Fastify fix while still validating extensionless absolute file references such as `/usr/local/bin/foo:main`.

## Observations (not tallied)

- The new test file (`head/tests/unit/butterfreezone-validate-route-false-positive.bats`) is well-targeted and does correctly pin the intended behavior (route params skipped, real absolute paths with extensions still validated, relative paths unaffected) — but, consistent with the finding above, it does not include a case for an extensionless absolute path to a genuinely missing file, which is exactly the gap this heuristic opens. Adding that case would have caught the regression at review time.
- No injection, path traversal, command execution, or secrets-handling issues were introduced; the change is a pure string-comparison predicate inside `[[ ]]` with no `eval`, subshell interpolation, or unescaped expansion of attacker-controlled data beyond what already existed in `base/.claude/scripts/butterfreezone-validate.sh:266-316`.
- `.claude/scripts/butterfreezone-validate.sh` is a System Zone file in the Loa framework's own repository; since this workspace *is* the Loa framework's source tree, editing it here is the framework's own normal development activity, not a consumer-repo System Zone violation.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 0 |

## Verdict

No critical or high findings. One medium finding (validation-completeness regression in an advisory documentation gate) should be addressed before merge but does not block on security-critical grounds — recommend fixing the heuristic scope per the remediation above.

APPROVED - LET'S FUCKING GO

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":0},"ts":"2026-09-22T00:00:00Z"} -->
