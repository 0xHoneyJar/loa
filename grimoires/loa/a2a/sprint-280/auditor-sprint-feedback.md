APPROVED - LET'S FUCKING GO

# sprint-280 (cycle-136 Sprint 1) — Security Audit (Paranoid Cypherpunk Auditor), round 1

**Auditor:** lead (Fable 5.1) · **Head audited:** `be35c3ac6` (+ docs `91e099c55`) on `feature/cycle-136-bridgebuilder-followups` (contract `3982334a0`; A `4e81a0df5`→`90b259222`, `eb2dac6b9`→`be35c3ac6`; B `92b8ab78f`→`66c35c9c4`, `52e988057`→`5d5080b69`, `613ffad95`→`63f6d1ae3`, `b695008fc`; lead `81ef8f47d`, `f46e8879e`) · **Review:** `engineer-feedback.md` (All good, round 2) · **Scope:** the sprint's source diff `3982334a0..be35c3ac6` for the scaffold library and the Bridgebuilder skill (sources, tests, reference doc; dist/checksums/REPO-MAP regenerated) — 101 KB · **Dissent:** one `adversarial-review.sh --type audit` run over that diff (2/2 voices, consensus, chain ok; the sprint's third and last permitted run) — 4 LOW payloads, dispositioned below.

## Summary

The sprint narrows two fail-open surfaces and widens the review's reach without opening a new one. The scaffold reads a downstream operator's CI workflow with one structure-driven awk pass and never rewrites anything it cannot identify as exactly one single-line job-level legacy guard; the rewrite is symlink-refusing, re-read-verified, same-directory temp file + `mv -f`, mode-preserving, and every failure is a WARN with return 0. The base `.reviewignore` read reaches the provider only when the clone lacks the base commit, through the existing allowlisted contents shape at a 40-hex sha against the target repository, with the 1 MiB bound; a 404 widens coverage only after an access probe proves the ref readable; every other outcome keeps the fail-closed degrade (DEC-1043); the outcome is cached per base sha including failures. FR-5 never installs a PR head's invalid scope value: the key is left unset and deferred, the trusted value or the default replaces it, and a configuration still carrying a deferral is refused before the review. The stats suffix removal leaves one structured carrier for the excluding pattern. No secret, credential, shell string or new network shape is introduced. Approved.

## Checklist

| Area | Finding |
|---|---|
| Secrets | None introduced; the contents reads send no headers and use the ambient `gh` auth; every WARN/INFO operand is JSON-quoted and bounded (`boundedForLog`), never an error body or an env value. |
| Auth / authz | The access probe (D-2.6) closes the one place a 404 could have widened coverage on an authorization gap; FR-5 keeps the trusted source authoritative for the scope keys (head values are deferred, never installed) and `assertNoDeferredScopeKeys` refuses a configuration that skipped the hand-off (wired in `main.ts`, call order pinned). |
| Input validation | Scaffold: regular readable non-symlink target, J and C read from the file, block scalars tracked, exactly one single-line candidate, plain-scalar continuation = multi-line (round 1 HIGH), normalisation bounded to the two shipped texts; `.reviewignore`: 40-hex base sha, `cat-file -e` exit status, same line rules as the local read, `size`-checked envelope; FR-5: `exclude_patterns` gains a list-of-strings shape check. |
| Injection | Every subprocess is `execFileSync` with argument arrays under `LC_ALL=C`; the awk program is a constant inside single quotes; the rewrite builds the new line from awk-generated fields and never evaluates file content; the coverage marker escapes `--` inside its JSON payload so a PR-controlled file name cannot close the HTML comment (`.claude/skills/bridgebuilder-review/resources/core/paged-fetch.ts:644`). |
| Data exposure | The base `.reviewignore` comes from the target repository at the PR base sha, never from the fork or the head; `none` still runs the checkout check so a PR-added copy is reported, not applied; the probe reads one byte of a file that exists at the base. |
| Resource bounds | One contents call per base sha per run (two with the probe), cached incl. failures; the existing 30 s `gh` timeout and 1 MiB bound; the scaffold check is one awk pass over one file; the rewrite writes one temp file. |
| Fail-closed behaviour | Scaffold: anything not exactly one single-line legacy guard is silent / refused, return 0; `.reviewignore`: `other`, API errors, failed probe, add-only PRs → `base_unavailable` + merge-blocking degrade (DEC-1043); FR-5: deferral refused if not replaced; `exclude_patterns` scalar → named config error locally. |
| Error handling | Closed outcome sets (`BaseRead` classes, fetch outcomes); a failed content read names the file and outcome once per file per attempt; `deadline` / `budget` / `skipped_cap` / `aborted` stay silent (pinned). |
| Supply chain | No new dependency; dist rebuilt from source with the manifest hash checked; `checksums.json` 2080 entries match; REPO-MAP consistent; one new test fixture file (the real pre-cycle-135 workflow). |
| Tests | Every behaviour change red first (A 16 → 0 and 9 → 0, both `red-test-check` VERIFIED; B 68/44/38 red lines → green, `red-green-npm` green ×3; B's round-1 pins green by design, stated); `npm test` 1323/1323; bats 44/44; busybox awk 38/38; mutation on the continuation guard kills exactly T36/T37. |

## Dissent

One audit-type run over the whole sprint diff (the third permitted run; the first two were the review's A and B diffs). 2/2 voices, consensus, chain ok: 4 LOW payloads — two accepted as observations below (filed), one accepted as a test-pin follow-up, one refuted with evidence.

## Observations

- **LOW** (confidence: medium) `.claude/scripts/lib/scaffold-post-merge-workflow.sh:126` — the awk record joins its fields with the US separator and the seventh field is the raw trailing comment of the candidate line, so a comment containing a 0x1F byte shifts the following fields. Failure: when a downstream workflow's `simple-release` `if:` line carries a `# comment` with an embedded 0x1F byte then the parsed `norm` is wrong and a genuine legacy guard stays silent or a WARN fires on a customised one, while the rewrite path still refuses because the re-read line cannot match the shifted `raw`.
- **LOW** (confidence: medium) `.claude/scripts/lib/scaffold-post-merge-workflow.sh:176` — the symlink refusal covers only the final path component; the fixed relative target's directory is not checked. Failure: when `.github/workflows` or `.github` is a committed symlink in the repository being mounted then the temp file and the `mv -f` operate inside the link target, as the pre-existing fresh-install path already does.
- **LOW** (confidence: low) `.claude/skills/bridgebuilder-review/resources/__tests__/paged-fetch-coverage.test.ts:60` — the byte-budget case shows a protected workflow file recorded `byte_budget` / `reviewable: true` but asserts nothing about `degraded` or `mergeBlockedReason` for it. Failure: when a refactor stops a reviewable `byte_budget` omission from degrading the record then a PR author who front-loads large files under a path that sorts before `.github/` can push a protected workflow past the budget without blocking the merge, and the suite stays green.

## Rejected dissent payloads

- LOW "the coverage marker may let a PR-controlled file name containing `-->` close the HTML comment; HIGH if unescaped": refuted with evidence — `.claude/skills/bridgebuilder-review/resources/core/paged-fetch.ts:644` replaces every `--` inside the JSON payload with `-\u002d`, so no `-->` can appear in the marker; the voice itself marked it unverified.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":3},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-280","ts":"2026-10-27T02:39:01Z"} -->
