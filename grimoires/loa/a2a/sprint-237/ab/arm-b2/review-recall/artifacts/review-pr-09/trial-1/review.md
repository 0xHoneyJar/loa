All good

This PR fixes issue #938 (route-parameter tokens like `/users/:id` being misreported as
missing file references) and adds a regression suite. No critical or high findings. See
Observations below for two non-blocking notes worth a follow-up.

## Summary

`head/.claude/scripts/butterfreezone-validate.sh:294` adds a skip for references whose
`file` portion starts with `/` and contains no `.`. This correctly suppresses the false
positive: for a backtick token like `` `/factors/:factorId` ``, the reference regex at
`head/.claude/scripts/butterfreezone-validate.sh:267` splits it into `file="/factors/"`,
`symbol="factorId"` — pre-fix this reported "Referenced file missing: /factors/". Verified
by directly running the reference-extraction regex against the fixture line: it matches
`` `/factors/:factorId` `` but does **not** match `` `/users/:userId/sessions` `` (the regex
requires the token to end in `symbol` immediately followed by a backtick, and `/sessions`
breaks that), so only the single-segment route form was ever actually mis-flagged. The fix
targets exactly that shape and the existing "real absolute path with extension" /
"relative path with extension" cases continue to validate normally (confirmed by reading
the control flow — `.sh`-suffixed and `./`-prefixed refs still fall through to the
existence check).

## Observations

- **MEDIUM** (confidence: medium) `head/.claude/scripts/butterfreezone-validate.sh:294` — The heuristic (`file` starts with `/` and has no `.` anywhere) is broader than the route-param case it's fixing. Every route-param match this regex can produce has a `file` portion ending in `/` (e.g. `/factors/` from `` `/factors/:factorId` ``), because the colon always follows a path-segment boundary. The current check instead matches *any* extensionless absolute path, so a real reference like `` `/usr/local/bin/node:main` `` or an extensionless script/binary path would now be silently skipped instead of validated — a false negative in the tool whose job is specifically to catch missing file references. Tightening the condition to also require `"$file" == */` (trailing slash) would close the reported false positive without widening the blast radius to legitimate extensionless absolute-path references. The PR comment at lines 287-293 acknowledges the tradeoff explicitly ("chosen for low blast radius"), so this is a deliberate scope choice, not an oversight — flagging in case the narrower form is preferred.
- **LOW** (confidence: high) `head/tests/unit/butterfreezone-validate-route-false-positive.bats:77` — The second assertion (`! [[ "$output" == *"Referenced file missing: /users/"* ]]`) doesn't exercise the fix: the fixture's `` `/users/:userId/sessions` `` token (line 47) never matches the reference-extraction regex at `head/.claude/scripts/butterfreezone-validate.sh:267` in the first place — trailing `/sessions` after the route param breaks the required closing-backtick adjacency — so this assertion passes identically with or without the fix. It doesn't hurt, but it isn't testing what the comment above it implies. A route line without a trailing path segment (e.g. `` `/users/:id` (`./src/routes/users.ts:10`) ``) would actually exercise the multi-word-route case.

## AC Verification

- "Route-parameter tokens such as `/users/:id` were being reported as missing file references" → Fixed: confirmed by tracing the regex/split logic against the `/factors/:factorId` fixture case (`head/.claude/scripts/butterfreezone-validate.sh:294`, test at `head/tests/unit/butterfreezone-validate-route-false-positive.bats:57`).
- "cover the shapes with a regression suite" → Met, with the caveat above (the multi-segment route assertion doesn't add coverage beyond what the regex already excluded); the two extension-preserving cases (absolute-with-extension, relative-with-extension) are genuinely covered and correctly assert the pre-existing missing-file behavior is retained.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":1},"excluded":0,"sprint_id":"pr-938","ts":"2026-09-22T00:00:00Z"} -->
