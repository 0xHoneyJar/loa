# Implementation Report — sprint-bug-246 (bug 20260924-1f9d91, bead `bd-n7v3`)

**Sprint**: sprint-bug-246 — `check-permissions.sh` (preflight P2) reads only `.claude/settings.json` and treats deny entries as allowed
**Branch**: `fix/cycle-125-followups` (from `main` `5f4a58a5`, `v2.0.0-rc.2`; after sprint-bug-245)
**Triage**: `grimoires/loa/a2a/bug-20260924-1f9d91/triage.md` · **Plan**: `grimoires/loa/a2a/bug-20260924-1f9d91/sprint.md`

## Executive Summary

The run-mode permission check (preflight P2) read a single file, `.claude/settings.json`, and decided by grepping the file's text, so run-mode rules that Claude Code actually honours — approved into `.claude/settings.local.json` (the file Claude Code writes on approval) or set in `~/.claude/settings.json` — were invisible, and a pattern that appeared only inside a `deny` array counted as allowed. `check-permissions.sh` now evaluates the three layers Claude Code evaluates, as JSON arrays, with deny winning in any layer, the existing base-wildcard rule kept (for allow and deny alike, without letting a narrower deny cover a generic requirement), the consulted files and the denied rules named in both outputs, and a `--root <dir>` argument so it can be pointed at any project. Exit codes keep their meaning. `run-preflight.sh` P2 names the layers and the deny rule in its detail and fix text. No new configuration key.

Red → green: the nine cases of the new `tests/unit/check-permissions.bats` all failed on the pre-fix tree (`scratchpad/bug246-red.tap`: `not ok 1..9` — no `--root`, single file, text grep) and pass now (`scratchpad/bug246-green2.tap`, 9/9); `run-preflight.bats` (15) and `settings-permissions.bats` stay green (`scratchpad/bug246-green.tap`: 87 ok of 88 before the CP-4 expectation was aligned with deny-wins reporting, then 9/9 for the suite alone).

## AC Verification (sprint.md)

### Bug is no longer reproducible: rules in any layer are effective; a deny entry never counts as allowed and a deny rule in any layer reports the rule as denied with its file
- **Status**: ✓ Met
- **Evidence**: the checker builds the layer list `~/.claude/settings.json`, `<root>/.claude/settings.json`, `<root>/.claude/settings.local.json` (`.claude/scripts/check-permissions.sh:161`) and reads `permissions.allow` / `permissions.deny` from each existing, well-formed file as `rule<TAB>file` lines via `jq` (`:164-174`); for every required rule the deny lists are consulted first (`:200-211`, exact or base wildcard through `rule_covers`, `:146-153`) and a hit is recorded as `denied` with the denying rule and file (`:210`), otherwise the allow union decides found/missing (`:212-219`). E2E on this machine (real layers): `check-permissions.sh --json` → `success true, total_found 16, total_missing 0, total_denied 0, settings_files [~/.claude/settings.json, .claude/settings.json, .claude/settings.local.json]`; a scratch root whose 16 rules live only in `settings.local.json` → exit 0; the same root with `Bash(git push:*)` denied in the scratch `HOME` file → text output `Bash(git push:*)  denied by Bash(git push:*)  in …/home/.claude/settings.json`, `Run Mode pre-flight check: FAILED`; `run-preflight.sh --unattended` on this machine → `[PASS] P2 allow-rules: run-mode allow rules effective across ~/.claude/settings.json, .claude/settings.json, .claude/settings.local.json (deny wins)`.

### Failing test proves the fix
- **Status**: ✓ Met
- **Evidence**: red record `scratchpad/bug246-red.tap` (`not ok 1` … `not ok 9`); green `scratchpad/bug246-green2.tap` (`1..9`, 9 ok). Cases: `tests/unit/check-permissions.bats:28` (CP-1 control: project file, 16 found, `settings_files` names it), `:38` (CP-2 rules only in `settings.local.json` → exit 0), `:47` (CP-3 rules only in the user file → exit 0), `:55` (CP-4 a pattern only inside `deny` is never found; it is reported as denied), `:62` (CP-5 deny in the local file, then in the user file: exit 1, `denied[0].{rule,by,file}`, text names the file), `:80` (CP-6 base wildcard covers subcommands for allow; `Bash(git:*)` in deny denies all nine git rules; a narrower deny denies nothing), `:96` (CP-7 no file in any layer → exit 2, `settings_files []`, `--quiet` silent), `:105` (CP-8 malformed file skipped with `WARN`, never allows; two malformed files → exit 1), `:117` (CP-9 `--help` names the layers and `--root`; unknown option → exit 2). Isolation: every case uses `--root <temp>` and a temp `HOME`; the repository's settings files are never read.

### No regressions in existing tests
- **Status**: ✓ Met
- **Evidence**: `tests/unit/run-preflight.bats` 15/15 and `tests/unit/settings-permissions.bats` green in the same run (`scratchpad/bug246-green.tap`); PF-1b / PF-2 still drive P2 through the stub `check-permissions.sh` in `LOA_PREFLIGHT_HELPERS_DIR` and still match `fix:.*check-permissions.sh` (`.claude/scripts/run-preflight.sh:130`); `bash -n` clean on both scripts; `repo-map-gen.sh --validate` consistent; `tools/check-prompt-budget.sh` unchanged (no skill text touched).

### Fix addresses root cause (not just symptoms)
- **Status**: ✓ Met
- **Evidence**: the checker evaluates the *effective* permission set the way Claude Code does (layers `:161`, JSON arrays `:170-173`, deny-wins `:200-211`) rather than one file's text; exit codes and the JSON's original fields are unchanged (`:236-249`, `settings_path` kept for older consumers) and the new fields are additive (`total_denied`, `denied[]`, `settings_files`); the text remedy tells the operator which file to edit and which deny to remove (`:284-286`). No per-repository workaround, no relaxed exit code.

## Tasks Completed

| Task | Status | Where |
|------|--------|-------|
| 1 Failing tests | done | `tests/unit/check-permissions.bats` (CP-1..CP-9) |
| 2 Fix | done | `.claude/scripts/check-permissions.sh` (rewritten: layers, jq arrays, deny-wins, `--root`, `denied` + `settings_files`, `usage()`); `.claude/scripts/run-preflight.sh:15-17` (header), `:105` (P2 detail), `:130` (P2 fix text) |
| 3 Docs + record | done | `CHANGELOG.md` `[Unreleased]` › Fixed; `check-permissions.sh` header and `--help`; REPO-MAP + `.checksum` sidecar + `.claude/checksums.json` regenerated together; this report |

## Technical Highlights

- **Claude Code's own semantics, nothing invented.** Union of allow rules across the three layers; deny wins in any layer; the existing base-wildcard match (`Bash(git:*)` covers `Bash(git checkout:*)`) kept and applied symmetrically to deny — and only symmetrically: a deny for a specific dangerous form (`Bash(rm -rf /:*)`) has a different base pattern and does not deny the generic `Bash(rm:*)` requirement (CP-6), which is what keeps this repository's 62 shared deny rules from tripping the check.
- **Arrays, not text.** `jq -r '(.permissions.allow // [])[]? | select(type == "string")'` per file; a file `jq` rejects is skipped with a `WARN` on stderr and contributes nothing in either direction (CP-8) — the old text grep would have matched a rule inside a comment, a deny list or an unrelated string.
- **Exit codes are the contract.** 0 / 1 / 2 keep their meaning; `2` now means "no settings file in any layer" (all three named in the error), so preflight P2's pass-through is unchanged.
- **Reports name what they read.** `settings_files[]` in JSON and "Settings files consulted" in text; every denied rule carries the denying rule and file, so the operator edits the right file.

## Testing Summary

| Suite | Result |
|-------|--------|
| `tests/unit/check-permissions.bats` (new) | 9/9 (all 9 red before the fix) |
| `tests/unit/run-preflight.bats` + `tests/unit/settings-permissions.bats` | green (no change) |
| E2E on this machine | `--json` success with three files consulted; scratch local-only root passes; scratch user-level deny reported; preflight P2 PASS |

## Known Limitations

- Managed/enterprise policy settings are not read (not readable by design); a rule denied there is not visible to this checker.
- Only the `Bash(<cmd>:*)` rule grammar the checker has always understood is matched; other permission-rule forms Claude Code accepts (e.g. `Bash(git *)`) are neither counted as allowing nor as denying, exactly as before.
- `HOME` is the standard location of the user file; the checker does not read `CLAUDE_CONFIG_DIR`-relocated settings.

## Verification Steps

```bash
bats tests/unit/check-permissions.bats tests/unit/run-preflight.bats
.claude/scripts/check-permissions.sh --json | jq '{success, total_denied, settings_files}'
.claude/scripts/run-preflight.sh --unattended | grep P2
```

## Files Changed

`.claude/scripts/check-permissions.sh`, `.claude/scripts/run-preflight.sh`, `tests/unit/check-permissions.bats` (new), `CHANGELOG.md`, `grimoires/loa/REPO-MAP.md` + `.checksum`, `.claude/checksums.json`, `grimoires/loa/ledger.json` (bugfix cycle registration).

## Round 1 — review fixes

- **Runtime (lead, MEDIUM).** The first submission forked a `sed` per (rule × required) comparison — 10.8 s on this machine's ~480 rules. Rules are now loaded once into associative maps (`.claude/scripts/check-permissions.sh:165`, `:174-181`), the base pattern comes from parameter expansion (`base_pattern_of`, `:147-151`) and each decision is an O(1) lookup (`:213-228`): 0.06 s on the same machine. CP-10 (`tests/unit/check-permissions.bats:127`) guards it: 500 allow + 100 deny rules in under two seconds.
- **Shape of the `permissions` block (dissent ADVISORY, LOW).** A scalar `permissions` / `allow` / `deny` used to abort the checker under `set -e`; the per-file shape predicate (`:169`) now covers all three and the reads are guarded (`:177`, `:181`) — such a file is skipped with a `WARN`. CP-8 extended with both shapes (two `WARN`s, the user-file rules still pass).
- **Empty-array guard (LOW).** The consulted-files loop uses `${consulted[@]+"${consulted[@]}"}` (`:263`).
- Suites after the round: `check-permissions.bats` 10/10 + `run-preflight.bats` 15/15 (`scratchpad/bug246-r1.tap`, 24 ok); REPO-MAP + sidecar + checksums regenerated.

## Post-audit — Bridgebuilder pass on PR #1270

- **FIND-003 LOW (fixed).** `--quiet` still printed the malformed-settings `WARN`; diagnostics now go through `warn()`, which `--quiet` silences (exit code unchanged); CP-8 asserts an empty output under `--quiet` with a malformed file.

