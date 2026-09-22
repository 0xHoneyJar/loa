# Security Audit — fix(#938): butterfreezone-validate skips Express/Fastify route patterns

**Scope**: `head.diff` touching `.claude/scripts/butterfreezone-validate.sh` (production validator, System Zone) and `tests/unit/butterfreezone-validate-route-false-positive.bats` (new regression tests).

**Context**: `butterfreezone-validate.sh` is the validator used by "the RTFM gate and /butterfreezone skill" (file header, `head/.claude/scripts/butterfreezone-validate.sh:6`) to confirm that file references embedded in generated `BUTTERFREEZONE.md` context documents actually exist. Because these documents are the context other agents in the framework read and trust, `validate_references()` is effectively an integrity/anti-hallucination gate, not cosmetic linting — a reference that should be flagged as missing but silently passes undermines the guarantee downstream consumers rely on.

## Finding 1 (Medium): Skip heuristic is broader than the stated fix and silently disables the missing-file check for a real class of legitimate references

- **File**: `head/.claude/scripts/butterfreezone-validate.sh:294-296`
- **Code**:
  ```bash
  if [[ "$file" == /* && "$file" != *.* ]]; then
      continue
  fi
  ```
- **Issue**: The comment justifies the heuristic by asserting "real absolute paths would have extensions" (`head/.claude/scripts/butterfreezone-validate.sh:291`), but that premise is false in general. Plenty of legitimate, extensionless absolute-path file references exist: `/etc/hosts`, `/etc/passwd`, `/usr/local/bin/<tool>`, `Dockerfile`-style build artifacts referenced by absolute path, extensionless shell entry points, etc. `$file != *.*` matches on "no dot anywhere in the string" (not "no dot in the final segment"), so any absolute path lacking a `.` anywhere — not just route templates — takes this branch and is never checked for existence at `head/.claude/scripts/butterfreezone-validate.sh:300` (`[[ ! -f "$file" ]]`).
- **Failure scenario**: A `BUTTERFREEZONE.md` document (hand-written, stale, or produced by an agent that hallucinated a path) contains a backtick reference like `` `/opt/deploy/rollback:main` `` or `` `/usr/local/bin/migrate:run` ``. Pre-fix, a nonexistent path here would be caught and reported as `Referenced file missing: ...`, failing the RTFM gate. Post-fix, because the path starts with `/` and contains no `.`, `validate_references()` silently `continue`s past it — the check passes even though the referenced file does not exist. The gate that is supposed to catch broken/hallucinated file references in trusted context documents no longer catches this entire class, and there is no test in the new suite that would catch the regression (the tests only cover extensionless *route* paths and extension-bearing absolute/relative paths — see Finding 2).
- **Why this matters here specifically**: this script's stated job is anti-hallucination verification of documents other agents treat as ground truth (`used by RTFM gate`). A validator whose core check (`file exists`) can be routed around by omitting an extension is a protection-mechanism weakening (CWE-693, https://cwe.mitre.org/data/definitions/693.html) relative to its own design intent, even though the PR's own motivating case (routes) is legitimately out of scope for this check.
- **Remediation**: Tighten the heuristic to match the actual shape of Express/Fastify route tokens instead of "any extensionless absolute path" — e.g. require a `:paramName` segment in the *original backtick reference* (before the `path`/`symbol` split discards it), such as `[[ "$ref" == *"/:"* ]]`, or restrict the skip to a path component matching `^:[a-zA-Z_][a-zA-Z0-9_]*$`. That would exclude `/factors/:factorId` (the reported bug) while still validating extensionless absolute paths that don't contain a route-param token.

## Finding 2 (Low): Regression suite doesn't cover the case the heuristic gets wrong

- **File**: `head/tests/unit/butterfreezone-validate-route-false-positive.bats:104-160`
- **Issue**: The three new test cases cover (a) route params with no extension → skip, (b) absolute path with extension → still validated, (c) relative path with extension → still validated. None covers an extensionless absolute path that is *not* a route pattern (e.g. `` `/usr/local/bin/tool:main` `` pointing at a nonexistent file), which is exactly the case Finding 1 shows regresses. The suite documents and locks in the narrow bug being fixed but doesn't guard the boundary the fix actually draws.
- **Failure scenario**: A future contributor "fixes" the heuristic differently (or extends it) believing it's already narrowly scoped and fully tested; there's no regression test to catch a real extensionless-path false negative reappearing or worsening.
- **Remediation**: Add a case asserting `Referenced file missing: /usr/local/bin/tool` (or similar) still fires for a nonexistent extensionless absolute path with no `:param` shape.

## Non-findings checked

- **Command/glob injection**: `$file` is only used in bash `[[ ]]` glob comparisons and quoted `-f` tests (`head/.claude/scripts/butterfreezone-validate.sh:294,300`); no `eval`, no unquoted expansion into a shell command. Not exploitable.
- **Path traversal**: the check only *decides whether to validate existence*, and does so with `-f`, not with any privileged read/write; skipping validation doesn't grant new filesystem access, it only degrades an integrity check.
- **Test-file safety**: the new `.bats` file uses quoted heredocs (`<<'EOF'`) and a fresh `$(mktemp -d)` per test with `teardown() { rm -rf "$TMP_DIR"; }` — no stash/heredoc/rm hazards per `.claude/rules/shell-conventions.md` and `.claude/rules/stash-safety.md`.
- **Zone boundaries**: both changed files are within the PR's own declared scope (a System Zone script fix + its test); no unrelated `.claude/` edits.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 1 |

## Verdict

Only Medium/Low findings — no Critical or High. Per the one-way rule (critical+high > 0 forces CHANGES_REQUIRED), this does not force a block, but Finding 1 is a real, demonstrable weakening of a documentation-integrity gate that the PR description doesn't acknowledge (it frames the change as purely route-pattern-scoped when the shipped heuristic is broader). Recommend tightening the heuristic per Finding 1's remediation before merge; not a hard blocker if the team accepts the residual gap as documented risk.

APPROVED - LET'S FUCKING GO (with the Finding 1 heuristic tightening requested as a fast-follow)

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":1},"ts":"2026-09-22T00:00:00Z"} -->
