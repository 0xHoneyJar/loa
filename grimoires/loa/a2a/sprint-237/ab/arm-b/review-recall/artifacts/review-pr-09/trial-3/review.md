All good

Sprint has been reviewed and approved. Observations documented and non-blocking. See Observations below.

## Context

This PR fixes issue #938: `butterfreezone-validate.sh`'s reference checker was flagging Express/Fastify route-parameter tokens (e.g. `` `/factors/:factorId` ``) as missing files, because its reference-extraction regex (`head/.claude/scripts/butterfreezone-validate.sh:272`) treats any backtick-fenced `path:symbol` token the same way regardless of whether `path` is a route or a filesystem path. The fix adds a skip condition at `head/.claude/scripts/butterfreezone-validate.sh:294` — `[[ "$file" == /* && "$file" != *.* ]]` — that exempts any extracted "file" starting with `/` and containing no `.` from the missing-file check, plus a new bats regression suite (`head/tests/unit/butterfreezone-validate-route-false-positive.bats`).

I traced the regex/heuristic interaction by hand against the fixtures in the new test file and two additional cases (bats wasn't invokable in this sandboxed review environment, but the extraction regex and skip condition are pure string logic and straightforward to trace). The reported scenarios (`/factors/:factorId`, `/users/:userId/sessions`, real absolute path with extension, real relative path) all behave as claimed.

## Observations

- **MEDIUM** (confidence: high) `head/.claude/scripts/butterfreezone-validate.sh:294` — The "starts with `/` and has no dot" heuristic is both too narrow and too broad, and the gap isn't covered by the new test suite:
  - *Too narrow*: a versioned route segment such as `` `/api/v1.0/users/:id` `` still trips the false positive this PR exists to fix. Trace: the extraction regex (`:272`) greedily matches `file="/api/v1.0/users/"`, `symbol="id"`; `file` contains a `.` (from `v1.0`), so the skip at `:294` does not apply, and the script falls through to `[[ ! -f "$file" ]]` → `Referenced file missing: /api/v1.0/users/`. This is the same bug class #938 reports (Express-style routes with parameters), just not fully closed — decimal-style API version segments are common in real route tables.
  - *Too broad*: any real absolute filesystem reference that happens to lack a dot anywhere in its path (a directory, or an extensionless script/binary, e.g. `` `/usr/local/bin/mytool:main` `` or `` `/etc/nginx:bootstrap` ``) is now silently exempted from the missing-file check, regardless of whether the file actually exists. Pre-PR, such a reference was validated normally. This is a real, if narrow, regression in validation coverage — the check silently stops catching genuinely broken doc references in this shape. The in-code rationale asserts "real absolute paths would have extensions" (`:290-291`); that assumption doesn't hold for directories or extensionless binaries/scripts.
  - Neither edge case is exercised by the new bats file, which only covers pure-route and dotted-extension shapes. Given the fix comment itself flags this as "heuristic chosen for low blast radius" with reference to an issue discussion of multiple candidate fixes, this looks like a consciously-accepted trade-off rather than an oversight — flagging for visibility rather than blocking, since the primary reported false positives are fixed and the blast radius is confined to an advisory documentation-linting gate.

## Fast-Gate / Complexity

- Change is surgical: one conditional plus a comment block in `validate_references()`, no unrelated reformatting.
- Comment-to-code ratio (7 comment lines for a 3-line check) is justified — the heuristic's rationale is genuinely non-obvious and the comment correctly cites the issue and the chosen candidate fix.
- No formatter/type-checker applicable to this shell script; `shellcheck`/bats are the relevant fast-gate tools here — I was unable to execute `bats` in this sandbox to run the new suite live, so this review's confidence is based on manual trace rather than an executed run. Recommend running `bats tests/unit/butterfreezone-validate-route-false-positive.bats` in CI before merge to confirm.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":0},"sprint_id":"pr-938","ts":"2026-09-22T00:00:00Z"} -->
