# Reviewer concerns — sprint-1 (PR: cycle-129 sprint-256)

Scope: `pr/head.diff` (68 files). Base vs head under `pr/base/`, `pr/head/`.

## Verified so far

- Fence corpus (tests/fixtures/fence-corpus/run-corpus.sh) on the head tree: benign 89/89, dangerous 142/142 with the heredoc classifier on; knob-off reproduces the pre-change misses (D122, D123, D127, D131, D136, D141) as documented.
- profile-lib.bats 17/17, lint-invariants.bats 9/9, implement-gate.bats mode matrix IG-24..33 pass on the head tree (jq 1.6, yq v4.40.5).
- CLAUDE.loa.md is 9,189 B under the new 9,445 B cap; generate-skill-includes --check and validate-constraints are clean; check-knob-readers is clean.

## Concerns to probe

1. `.claude/scripts/run-checkpoint.sh` cmd_derive: `--arg label` → `$label` is a jq keyword; jq 1.6 refuses to compile ("unexpected label"), so `derive`, `mark` and the post-`write` refresh fail with exit 3 on jq 1.6. jq 1.7.1 accepts it. Repo has no stated jq floor; ledger-lib.sh already uses `$label`.
2. `run-checkpoint.sh` fb_parse: `jq -e 'type == "object"' <<<"$pj"` with an EMPTY `$pj` (file without a LOA-VERDICT trailer) exits 0 on jq 1.6 (4 on 1.7), so `--argjson p ''` aborts fb_parse; the documented no-trailer fallback hash is unreachable on 1.6 (RCR-7 fails there).
3. `karpathy-surgical-diff-check.sh` now forks `run-checkpoint.sh read --json` (and through it `br show`) on every Write/Edit; latency per write vs. the removed perf caches.
4. Heredoc classifier `_bdb_hd_same_line_exec` does not see a target consumed inside `$(cat f)` (`eval "$(cat f)"`, `bash -c "$(cat f)"`) on a later line: body dropped. Body segments kept only for the fence-verb list; `cp/mv/ln/sed -i/tee` into `.claude/` (FR-SZ rules) are not on it.
5. `implement-gate.sh` deny mode: position is "known" from `derived_at` freshness alone; a cache whose `.state` is RUNNING but `last_activity` stale (>24 h) denies rather than asks. Intended?
6. `derive --write` rewrites `.state` on every checkpoint; `/run sprint-N` (state.json only) never gets a derived position (documented gap).
7. guard-yield.bats GY-1/GY-3/GY-8 fail against the guard-yield.sh in this checkout (which post-dates the PR: "sprint-256 audit MEDIUM-A2" comment); cannot verify in this environment.
8. profile-floor.bats PF-5 fails here because adversarial-review-gate.sh's yq expression is python-yq syntax and the installed yq is mikefarah v4 — gate exits 0; environment skew, not PR code.
