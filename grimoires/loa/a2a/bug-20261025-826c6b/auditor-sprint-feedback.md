APPROVED - LET'S FUCKING GO

# sprint-bug-278 (bug 20261025-826c6b, bd-a8l0c) — Security Audit (Paranoid Cypherpunk Auditor)

**Auditor:** lead (Fable 5.1) · **Head audited:** `69bdf7680` on `fix/post-ship-bugs-classifier-bb-glob` (red `511a9e11d`, fix `01a5868eb`, review round `63a3a9d1f`, audit round `69bdf7680`) · **Review:** `engineer-feedback.md` (APPROVED after one round) · **Dissent:** one audit run (`adversarial-audit.json`, codex-headless + claude-headless 2/2, chain ok, consensus APPROVED, 2 MEDIUM + 1 LOW payloads) · **Code read:** `dotSegmentGlobMatch` and `matchesExcludePattern` (`truncation.ts:143-200`), the twelve tests, `parseReviewignoreFile` (`:277-350`, source of `.reviewignore`), the rebuilt `dist/core/truncation.js` · **Mechanical:** `npm test` 1080/1080, `tsc --noEmit` clean, `check-bb-dist-fresh.sh --check` fresh, `gen-checksums.sh --check`, `check-manifest-paths.sh`, `repo-map-gen.sh --validate` on the head; detect-secrets over the branch's added lines clean

## Summary

No finding above MEDIUM, and the two MEDIUMs are a product decision and a pre-existing defect, both now tracked with the operator's name on them. The change is a pure function over operator-supplied patterns and GitHub-supplied filenames: Node's `path.matchesGlob` first, then a segment-aware regex compiled once per pattern. Trust boundaries: patterns come from the operator (`--exclude`, `exclude_patterns`, and `.reviewignore` read from the reviewer's `repoRoot`, never from the PR head — `truncation.ts:304`); filenames come from the PR author. The regex is anchored, built from escaped literals and three fixed constructs (`[^/]*`, `[^/]`, `(?:[^/]*/)*`); each globstar group consumes whole `/`-terminated segments, so the only backtracking left is between several `*` inside one segment, bounded by the 255-byte segment limit (LOW, accepted). The denylist direction is the real security question: a wider exclusion hides more from the reviewer. The sprint keeps one consistent rule (every wildcard pattern matches dot-led names, as the Node < 22 fallback always did and as `.reviewignore`'s gitignore model implies), names the behaviour change in the CHANGELOG, relies on the coverage record (every excluded file listed with its reason) to keep it visible, and hands the protected-paths question to the operator as bd-i4fyw (DEC-1009). The pre-existing unanchored substring match for non-wildcard patterns is a genuine hiding path (`src/grimoires/backdoor.ts` behind the default `grimoires/`); this sprint did not introduce it, no longer pins it, and tracks it as bd-ow72o P2 (DEC-1010). System Zone edits under the bounded marker, dist rebuilt in every source-touching commit, no secrets.

## Security checklist

| Area | Result | Evidence |
|---|---|---|
| Secrets | none | detect-secrets over the branch's added lines: no hits |
| Trust boundaries | patterns: operator (`repoRoot/.reviewignore` with symlink/FIFO refusal, config, CLI); filenames: PR author, matched only, never interpreted | `truncation.ts:277-350`, `:182-200` |
| Input validation / regex | anchored `^…$`; metacharacters escaped; wildcards translate to bounded classes; globstar groups segment-deterministic; compiled once per pattern | `truncation.ts:143-178`; implementer probe `**/**/a/**/a/**/a/**/zz` × 80 segments ≈ 5 ms |
| Denylist direction (coverage loss) | widening is consistent, documented, visible in the coverage record; protected-paths list proposed to the operator | CHANGELOG line; bd-i4fyw; DEC-1009 |
| Pre-existing hiding path | unanchored substring match for non-wildcard patterns — not introduced here, no longer pinned, tracked | bd-ow72o; DEC-1010; test "exact pattern still matches itself" |
| Resource bounds | memo map keyed by pattern (operator-sized); per-call cost one regex test | `truncation.ts:149` |
| System Zone discipline | marker on for every landing; dist + `checksums.json`/`REPO-MAP.md` regenerated in `01a5868eb`, `63a3a9d1f`, `69bdf7680` | landing logs; `check-bb-dist-fresh.sh --check` |
| Tests of the error paths | red-first in every round (round 0: 3 red; round 1: 4 red); negatives for sibling trees, single `*`, in-segment `**` | `reviewer.md`, `engineer-feedback.md` |

## Findings

- **MEDIUM** (confidence: medium) `.claude/skills/bridgebuilder-review/resources/core/truncation.ts:198` — the dot-agnostic retry applies to every wildcard pattern (accepted with mitigation), so on Node ≥ 22 a broad `**/*.yml` now also excludes `.github/workflows/*.yml` (and `**/*.json` excludes `.claude/settings.json`, `.vscode/…`). Failure: when an operator tuned a broad pattern under the native dot-file rule, then CI workflows or agent settings leave the review set without a configuration change. Disposition: the Node < 22 fallback always behaved this way and `.reviewignore` implies gitignore semantics; the coverage record lists every excluded file with its reason; the CHANGELOG line (audit round, `69bdf7680`) tells operators to check broad patterns; a protected-paths list that wildcards cannot remove is bd-i4fyw for the operator to decide (DEC-1009).
- **MEDIUM** (confidence: high) `.claude/skills/bridgebuilder-review/resources/core/truncation.ts:195` — non-wildcard patterns match as an unanchored substring (`filename.includes(pattern)`), pre-existing and tracked. Failure: when a PR author names a file `src/grimoires/backdoor.ts`, then the default `grimoires/` pattern hides it from the review set. Not introduced by this sprint; the round-0 test that pinned the over-match (`x/.loa-version.json.bak`) was reduced to the exact match in the audit round so the fix is not blocked; bd-ow72o P2 (anchor: trailing `/` → segment-anchored prefix, else exact filename or basename) (DEC-1010).
- **LOW** (confidence: medium) `.claude/skills/bridgebuilder-review/resources/core/truncation.ts:171` — several `*` inside one segment (`*.*.*.*`) back-track polynomially against a PR-author-controlled filename (accepted). Failure: when a pattern carries five or more literal separators between stars and a filename holds hundreds of that separator, then the match stalls for seconds. Bounded by the 255-byte segment and `[^/]*` not crossing `/`; tolerable for the wildcard counts real patterns use. A wildcard-per-segment cap can ride along with bd-ow72o.

## Dissent dispositions (2 MEDIUM, 1 LOW)

- Dot-led widening of broad patterns → MEDIUM accepted with mitigation (CHANGELOG sentence landed; bd-i4fyw; DEC-1009).
- Unanchored substring match → MEDIUM pre-existing, pin dropped (`69bdf7680`), bd-ow72o (DEC-1010).
- In-segment backtracking → LOW accepted.

## Rejected dissent payloads

None.

## Round 2 — post-approval (Bridgebuilder round on PR #1299, head `84c328455`)

Bridgebuilder's round raised two MEDIUM (disputed) payloads with one root — brace and bracket-class patterns (`**/*.{json,md}`, `**/*.[jt]s`) still miss dot-led paths while the CHANGELOG stated the fix unconditionally — and two LOWs (the Node < 22 branch keeps simplifiedGlobMatch so the two runtimes still differ for single-`*` patterns; the test recomputed the native-glob detection and duplicated an import). Accepted in `84c328455`: the limitation is named in the helper's doc comment and the CHANGELOG and pinned by a test; `hasNativeGlob` is exported and reused by the test's skip; no matcher behaviour change; dist rebuilt, manifests regenerated under the marker. Not changed: routing the Node < 22 branch through the new helper (outside the observed failure; a note on bd-ow72o's neighbourhood for whoever anchors the substring match). Verdict unchanged.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":2,"low":1},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-bug-278","ts":"2026-10-26T01:20:00Z"} -->
