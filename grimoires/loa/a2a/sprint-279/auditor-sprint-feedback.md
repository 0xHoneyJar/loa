APPROVED - LET'S FUCKING GO

# sprint-279 (cycle-135 Sprint 1) — Security Audit (Paranoid Cypherpunk Auditor), round 1

**Auditor:** lead (Fable 5.1) · **Head audited:** `b02459e5a` on `feature/cycle-135-review-coverage` (contract `a2960b963`; landing A `4f926bcfd` `e6ba40f96`, B `46237970c` `625c5a901` `189741489`, C `ba454a74f`; round 1 A `8d22e449a`, B `04b552529`, C `74ff045cf`, lead `9300f9b3d` `b02459e5a`) · **Review:** `engineer-feedback.md` (All good, round 2) · **Scope:** the sprint diff `a2960b963..b02459e5a` without `dist/`, `checksums.json`, REPO-MAP, `decisions.yaml`, `ledger.json` — 28 files, +2944 / −251.

## Summary

The sprint narrows what a pull request can hide from its own review and widens what the review can see, and every new surface it opens is bounded. The exclusion matcher is one grammar with no native fallback, so a Node-version split cannot reopen the substring path. Protected paths can be removed only by a root-anchored name or the full path, the base branch's `.reviewignore` and review-scope keys govern on a pull request, and a failed base read keeps the deny list and blocks the merge rather than silently widening. The new provider read is one allowlisted `gh api` shape pinned to a 40-hex head sha, size-checked against the envelope's own `size`, bounded in bytes, count and time, and stopped on a repeating refusal. No secret, credential or shell path is introduced. Approved.

## Checklist

| Area | Finding |
|---|---|
| Secrets | None introduced; the contents read sends no headers and uses the ambient `gh` auth as the existing listing does; no token touches logs (the WARN texts print keys and pattern lists, never values from the environment). |
| Auth / authz | Trusted-config precedence extended to the review-scope keys (`applyTrustedReviewScope`, wired in `main.ts`): a PR head cannot set `protected_paths: []`, widen `exclude_patterns`, disable `fetch_missing_patches` or raise `max_content_fetches`; `--exclude` stays the operator's argv. Drift is warned, not refused — these keys change scope, not identity, and a refusal would block every review of a PR that legitimately edits them (DEC-1045). |
| Input validation | `getFileContent`: owner/repo segments validated, `ref` must be 40-hex, `maxBytes` a non-negative integer, envelope fields type-checked, `encoding` must be `base64`, decoded length must equal `size`, `size > maxBytes` → `too_large` before decoding; `readBaseReviewignore`: sha must be 40-hex (never an option), `ls-tree` mode must be a regular blob, 10 s timeout, 1 MiB cap, never throws; patterns: trimmed, one leading `./` or `/` stripped, negation / escapes / extglob / nested braces rejected with a WARN and match nothing; classifier: fixed regexes, type from a closed set. |
| Injection | Every subprocess is `execFileSync` with an argument array (`git`, `gh`, `yq`) — no shell; the yq program is a module constant; the `gh api` path is built from validated segments and URL-encoded path components under the existing allowlist; the regex matcher is compiled from a constrained grammar (segment-wise `*`, `?`, `**`, one-level braces, classes) so a crafted pattern cannot inject regex metacharacters. |
| Data exposure | Content of a PR head reaches the model exactly as patch text already did (same trust class, untrusted data); `.reviewignore` and the scope keys come from the base, so the PR cannot hide a file from its own review; protected-kept and omitted entries name the pattern, so hiding is visible in the coverage record. |
| Resource bounds | Content reads: ≤ `max_content_fetches` (default 20), 120 s deadline from the first read, each bounded by the bytes the planner has left after the GitHub and synthesized patches ahead (no wasted call), `maxBuffer` sized for the base64 envelope with `size` authoritative; a RATE_LIMITED / FORBIDDEN / 401 / 403 refusal aborts the remaining reads; `.reviewignore` reads: 10 s and 1 MiB; the selection runs at most twice per attempt. |
| Fail-closed behaviour | Base `.reviewignore` unreadable → the checkout copy still applies, `base_unavailable`, `reviewignore_unavailable` pushed as a fetch-side degraded reason → `incomplete_coverage` blocks the merge (DEC-1043); invalid trusted `protected_paths` / `exclude_patterns` → config error; invalid `fetch_missing_patches` → WARN + default; `--type housekeeping` to the orchestrator → exit 1 with the HINT line; the simple-release guard is an allowlist (`bugfix` or `other`), so an unknown classifier value prepares nothing. |
| Error handling | Per-file outcomes are a closed enum (`binary` `too_large` `error` `skipped_cap` `deadline` `budget` `aborted`), recorded in `omitted[].fetch`; a 404 or malformed envelope stays per-file; `postReview` posts body text only — no inline anchor can reference a line GitHub cannot resolve (pinned). |
| Supply chain | No new dependency; `path.matchesGlob` and the Node < 22 fallback removed; dist rebuilt from source with the manifest hash checked; `checksums.json` 2078 entries match; REPO-MAP consistent. |
| Tests | Every behaviour change above was red first (A 29 → 0, B 8 → 0 at the round-1 shas; round 0 likewise) and `npm test` is 1243/1243 three times under load; bats PCT-T28…T40, HK-T1/T2, PMWG-T1…T8 (actionlint rc 0 via docker on the lead host), PMOT-T1/T2; CPU-time guardrails take the minimum of three samples (bd-oglcu). |

## Dissent

No audit-type run: the three permitted runs were spent at the review gate on the three implementer diffs (A, B, C), whose payloads carried the security questions — the fail-open base read, protection defeated by floating names and the PR-head scope keys — and all three were fixed and pinned this round (DEC-1052, sprint-276 precedent). The auditor read the full sprint diff.

## Observations

- **LOW** (confidence: low) `.claude/skills/bridgebuilder-review/resources/adapters/github-cli.ts:389` — the buffer bound is derived from `maxBytes` with a fixed envelope allowance, and a buffer overflow is reported as `too_large` rather than as an envelope error. Failure: when GitHub adds metadata that exceeds the 8 KiB allowance for a file near the bound then that file is reported `too_large` and stays `no_patch` instead of being read.
- **LOW** (confidence: low) `.claude/skills/bridgebuilder-review/resources/core/truncation.ts:568` — the base read depends on the base commit being present in the clone, and a shallow CI checkout therefore degrades every review with `reviewignore_unavailable`. Failure: when an operator cannot fetch the base ref then every review of that mount is degraded until bd-9tt4b reads the base copy through the contents API.
- **LOW** (confidence: low) `.claude/scripts/post-merge-orchestrator.sh:2497` — the housekeeping refusal protects only mounts whose workflow carries the new allowlist guard or calls the orchestrator; a mount that keeps the legacy negative-list guard and the legacy job shape still prepares a candidate. Failure: when a downstream mount re-mounts without the scaffold detection in bd-akkgq then an archive merge there still prepares a spurious candidate.

## Rejected dissent payloads

None.

## Post-approval addendum (lead, `b6d0a07b4`)

After this audit the CI mirror reported the Bridgebuilder `SKILL.md` over its 16,384 B prompt budget (PB-9); the fix is documentation-only — the long-form rules moved to `resources/exclusions-and-coverage.md` behind guarded pointers (`reviewer.md` § Post-gate addendum, DEC-1053). `git diff --stat b02459e5a b6d0a07b4` touches `SKILL.md`, the new reference file, the dist manifest, `checksums.json` and REPO-MAP only; no source, test or behaviour changed, so this approval stands for `b6d0a07b4`.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":3},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-279","ts":"2026-10-26T07:08:07Z"} -->
