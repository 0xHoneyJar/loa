All good (with noted concerns)

# Review: fix(#938): butterfreezone-validate skips Express/Fastify route patterns

## Overall Assessment

The fix correctly resolves the reported false positive: a route pattern like `/factors/:factorId` is split by the existing `path:symbol` parser into `file="/factors/"` and `symbol="factorId"`, and the new guard at `head/.claude/scripts/butterfreezone-validate.sh:291-294` skips any reference whose file portion starts with `/` and contains no `.`. The three new bats tests (`head/tests/unit/butterfreezone-validate-route-false-positive.bats:38-56, 58-84, 86-113`) exercise the reported bug, a real absolute path that must still be flagged, and a real relative path that must still be flagged — all three assertions are logically consistent with the implementation (bash `errexit` makes the bare `[[ ]]`/`! [[ ]]` idiom used here fail the test correctly when the pattern under test breaks). Style and indentation match the surrounding file; the comment block explaining the heuristic is appropriate given the trade-off isn't obvious from the code alone.

The heuristic is an intentionally narrow, documented partial fix ("candidate-fix-A … low blast radius" per `head/.claude/scripts/butterfreezone-validate.sh:289`), not a complete solution to route-pattern detection — see concerns below.

## Adversarial Analysis

### Concerns Identified

1. **Incomplete fix for dotted route segments** — `head/.claude/scripts/butterfreezone-validate.sh:291`: the skip condition is `"$file" != *.*`, so any route whose path contains a literal dot anywhere still falls through to the file-existence check. A versioned route like `` `/api/v1.2/users/:id` (`./src/routes/users.ts:20`) `` would parse to `file="/api/v1.2/users/"`, which contains a dot, so it is *not* skipped and would still be reported as `Referenced file missing: /api/v1.2/users/` — the exact bug class #938 was filed for, just narrower. No test covers this shape, so the gap is undetected by the new suite.
2. **Silent validation regression for extensionless absolute paths** — `head/.claude/scripts/butterfreezone-validate.sh:291-294`: before this change, a real reference like `` `/etc/hosts:L1` `` or `` `/usr/local/bin/mytool:main` `` (a legitimate absolute-path reference to a file with no extension) was checked for existence. After this change it is silently skipped (`continue`), because it "starts with `/`" and "has no `.`" — indistinguishable from a route pattern by this heuristic. A genuinely missing extensionless absolute-path reference would now pass validation undetected. This is a real (if narrow) weakening of the gate the RTFM check relies on, and it isn't called out as a known limitation anywhere the reader would see it (only in a code comment, not in PR.md).
3. **Test suite only proves the happy path, not the boundary the heuristic actually draws** — the three tests cover "route without dot" (skipped, correct), "absolute path with extension" (checked, correct), and "relative path with extension" (checked, correct). None test the two edge cases above (dotted route segment; extensionless absolute file), which are exactly where this heuristic's false-negative and false-positive boundaries sit. A reviewer six months from now has no regression test to warn them if either edge case regresses further or is "fixed" in a way that reintroduces the original bug.

### Assumptions Challenged

- **Assumption**: "Real absolute-path file references would have extensions … those still match below" (`head/.claude/scripts/butterfreezone-validate.sh:288-289`).
- **Risk if wrong**: Extensionless absolute-path references (config files, shell scripts without `.sh`, binaries, `/etc/*` files) are common enough in real docs that this assumption will occasionally be false, and when it is, the validator fails silently rather than loudly — worse than the original false-positive, which was at least visible and annoying rather than invisible.
- **Recommendation**: Either narrow the skip to require an actual route-param marker (see alternative below) so the extension assumption isn't load-bearing, or explicitly document the limitation in the PR description / a code-level `NOTE:` so a future maintainer doesn't need to re-derive it from behavior.

### Alternatives Not Considered

- **Alternative**: Detect the Express/Fastify route-param shape directly — i.e., skip only when the original backtick-fenced text contains a `/:` followed by an identifier (`grep -oE '/:[a-zA-Z_][a-zA-Z0-9_]*'` against the pre-split `ref`, or restricting the reference-extraction regex itself to not treat a `:` immediately preceded by `/` as the `path:symbol` separator).
- **Tradeoff**: This targets the actual root cause (route params use `:` as a path-segment prefix, not as the `file:symbol` delimiter the parser assumes) instead of an indirect proxy (absolute path + no extension). It would correctly handle dotted/versioned routes (concern 1) and would not need to skip any legitimate absolute file path (concern 2), at the cost of a slightly more involved regex.
- **Verdict**: Given the PR's own comment frames this as "candidate-fix-A" chosen for "low blast radius," treating this as a deliberate, incremental first step is reasonable — but the follow-up (root-cause fix, or at least a tracked issue for the two gaps above) should be scoped explicitly rather than left implicit in a code comment only two people will ever read.

## Verdict

No critical or high-severity issues — the change does what it claims for the reported bug shape and ships with genuine regression coverage. The two gaps above are real but narrow (medium), and the author has already signaled awareness of the heuristic's limits via the code comment. Recommend approving as an incremental fix, with a follow-up issue filed for the dotted-route and extensionless-absolute-path edge cases rather than blocking this PR on them.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":2,"low":1},"sprint_id":"pr-938","ts":"2026-09-22T00:00:00Z"} -->
