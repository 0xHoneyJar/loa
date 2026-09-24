All good

Observations documented and non-blocking. See Observations below.

# sprint-bug-246 Review Feedback — round 1

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1 lead acting as gate; independent input: cross-model dissent gpt-5.5-pro through the `codex-headless` voice over the sprint diff plus the triage as context — `adversarial-review.json`, status `reviewed`, 1 ADVISORY finding (resolved in-round, below), 0 schema-rejected payloads, `verdict_quality.status APPROVED`, `chain_health ok`)
**Date:** 2026-09-24
**Bug:** 20260924-1f9d91 — `check-permissions.sh` (preflight P2) reads only `.claude/settings.json` and treats deny entries as allowed · **Bead:** `bd-n7v3` · **Plan:** `grimoires/loa/a2a/bug-20260924-1f9d91/sprint.md`
**Implementation Report:** `grimoires/loa/a2a/bug-20260924-1f9d91/reviewer.md`
**Range:** `1bf1c173` + this round's fixes over `b364c9dd` — `check-permissions.sh` (rewritten), `run-preflight.sh` P2 text, new `tests/unit/check-permissions.bats`, CHANGELOG, regenerated REPO-MAP + sidecar + checksums

---

## Overall Assessment

The bug is real and reproduced with fixtures (and half-visible on this very machine, where `defaultMode` and eight of the sixteen run-mode rules live in the gitignored `settings.local.json` the old checker never opened). The rewrite evaluates the effective permission set the way Claude Code does and keeps every contract the preflight relies on.

- **Three layers, JSON arrays, deny wins.** `.claude/scripts/check-permissions.sh:159` lists the user, shared and machine-local files; `:169` validates each file's shape before use; `:174-181` load `permissions.allow` / `permissions.deny` as rule → first-file maps; `:213-228` decide per required rule — deny (exact or base wildcard, any layer) first, then the allow union. The base-wildcard rule is applied symmetrically and *only* symmetrically, so a narrower deny such as a specific dangerous `rm` form does not deny the generic requirement (CP-6) — which is why this repository's 62 shared deny rules do not trip the check.
- **Contracts kept.** Exit codes 0/1/2 keep their meaning (`2` = no settings file in any layer, all three named); the JSON keeps `success / total_required / total_found / total_missing / found / missing / settings_path` and adds `total_denied / denied[] / settings_files` (`:242-252`); `run-preflight.sh` P2 still passes the exit code through and its fix text still names the script (PF-2 unchanged, 15/15).
- **Tests first, isolated.** Nine cases red on the pre-fix tree (`scratchpad/bug246-red.tap`), ten green now (`scratchpad/bug246-r1.tap`, with `run-preflight.bats` in the same run: 24/24); every case uses `--root <temp>` and a temp `HOME`, so the repository's settings are never read.
- **E2E.** On this machine `--json` → `success true`, three files consulted, `total_denied 0`; a scratch root with rules only in `settings.local.json` passes; a scratch user-level deny of `Bash(git push:*)` is reported with its file; `run-preflight.sh --unattended` → `[PASS] P2 … effective across ~/.claude/settings.json, .claude/settings.json, .claude/settings.local.json (deny wins)`.
- **Karpathy.** No new configuration key; `--root` mirrors `run-preflight.sh --root`; managed-policy files and other rule grammars are explicitly out of scope in `reviewer.md` Known Limitations.

**Verdict:** APPROVED

---

## Observations

### 1. Runtime against real rule counts (resolved in this round)

- **MEDIUM** (confidence: high) `.claude/scripts/check-permissions.sh:146-153` (as first submitted) — `rule_covers` forked a `sed` per (rule × required) comparison; against this machine's ~480 rules the checker took **10.8 s**, and P2 runs on every `/run` preflight. Resolved in-round: rules are loaded once into associative maps (`:165`, `:174-181`), the base pattern is computed per required rule with parameter expansion (`base_pattern_of`, `:147-151`) and every decision is an O(1) lookup (`:213-228`) — **0.06 s** on the same machine. Guarded by CP-10 (`tests/unit/check-permissions.bats:127`: 500 allow + 100 deny rules in under two seconds).

### 2. Shape of the `permissions` block (dissent ADVISORY, resolved in this round)

- **LOW** (confidence: high) `.claude/scripts/check-permissions.sh:169` — as first submitted only `type == "object"` was checked for the file; a scalar `permissions` (or a scalar `allow` / `deny`) made `jq` exit non-zero inside a command substitution and, under `set -e`, aborted the checker instead of skipping the file as documented. Resolved in-round: the shape predicate covers `permissions`, `allow` and `deny` (`:169`), the reads are `|| true`-guarded (`:177`, `:181`), and CP-8 (`tests/unit/check-permissions.bats:105`) now plants `{"permissions":"x"}` and `{"permissions":{"allow":"…","deny":{…}}}` — both skipped with a `WARN`, the user-file rules still pass.

### 3. Empty-array expansion (resolved in this round)

- **LOW** (confidence: high) `.claude/scripts/check-permissions.sh:263` — the "Settings files consulted" loop iterated `"${consulted[@]}"` unguarded; empty only when every present file is malformed, and harmless on bash ≥ 4.4, but the repository's shell conventions ask for the `${a[@]+"${a[@]}"}` guard. Applied.

### 4. Scope boundaries (documented)

- **LOW** (confidence: high) — managed/enterprise policy settings are not readable and not read; other permission-rule grammars Claude Code accepts (e.g. `Bash(git *)`) are neither counted as allowing nor denying, exactly as before; `CLAUDE_CONFIG_DIR`-relocated user settings are not looked up. All three are listed in `reviewer.md` Known Limitations; none changes the run-mode contract.

---

## Next Steps

1. `/audit-sprint sprint-bug-246` — independent dissent (no context file).
2. Commit this round's fixes with the review record; then close the follow-ups PR.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":3},"excluded":0,"sprint_id":"sprint-bug-246","ts":"2026-09-24T02:05:00Z"} -->
