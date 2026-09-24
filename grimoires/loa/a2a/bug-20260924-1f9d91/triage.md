# Bug Triage: `check-permissions.sh` (run preflight P2) reads only `.claude/settings.json` — it ignores `.claude/settings.local.json` and `~/.claude/settings.json`, and a pattern that appears only in a `deny` array counts as allowed

## Metadata
- **schema_version**: 1
- **bug_id**: 20260924-1f9d91
- **classification**: logic_bug (wrong input set and text-grep matching in a preflight predicate)
- **severity**: medium
- **eligibility_score**: 3
- **eligibility_reasoning**: Reproducible steps with exact output (+2): a project whose run-mode allow rules live only in `.claude/settings.local.json` (the file Claude Code writes when the operator approves rules; gitignored) gets `check-permissions.sh` exit 1 / `total_missing 16` and therefore preflight `P2 FAIL` and `P1 FAIL` for `acceptEdits`/`default`; a pattern placed only under `permissions.deny` in `.claude/settings.json` is reported as found. Reviewer finding with file:line (+1): cycle-125 sprint-243 review round 1 MEDIUM (`grimoires/loa/a2a/sprint-243/engineer-feedback.md:31`, `run-preflight.sh:99-107,120-124`, `check-permissions.sh:19,152-153`), deferred to bead `bd-n7v3`. No disqualifier: no new configuration key or surface — the script reads the settings files Claude Code already reads, in Claude Code's own precedence.
- **test_type**: unit
- **risk_level**: medium
- **created**: 2026-09-24T01:22:00Z

## Reproduction
### Steps
1. In a temp root `R`, write `R/.claude/settings.json` = `{"permissions":{"allow":[],"deny":[]}}` and `R/.claude/settings.local.json` = `{"permissions":{"allow":["Bash(git checkout:*)","Bash(git commit:*)","Bash(git push:*)","Bash(git branch:*)","Bash(git add:*)","Bash(git status:*)","Bash(git diff:*)","Bash(git rev-parse:*)","Bash(git show-ref:*)","Bash(gh:*)","Bash(gh pr:*)","Bash(mkdir:*)","Bash(rm:*)","Bash(cp:*)","Bash(mv:*)","Bash(bash:*)"]}}`; run `check-permissions.sh --root R --json` (today the script has no `--root`; copy it under `R/.claude/scripts/` to make it read `R`).
2. Write `R/.claude/settings.json` = `{"permissions":{"allow":[],"deny":["Bash(rm:*)"]}}` (no local file) and run the script again.
3. Write the 16 rules under `permissions.allow` of `$HOME/.claude/settings.json` (a temp `HOME`), leave the project files empty, run again.
4. Put the 16 rules in `R/.claude/settings.json` `allow` and `"Bash(git push:*)"` in `R/.claude/settings.local.json` `deny`; run again.

### Expected Behavior
- Step 1: exit 0 — Claude Code merges `settings.local.json` over `settings.json`; the rules are effective.
- Step 2: `Bash(rm:*)` is **missing** (and reported as denied), never found: a deny entry is not an allow entry.
- Step 3: exit 0 — user-level `~/.claude/settings.json` allow rules apply to every project.
- Step 4: exit 1 with `Bash(git push:*)` listed as **denied** — a deny rule in any layer wins over an allow rule in any layer (Claude Code semantics), so the run cannot push unattended.
- In every case the JSON names the settings files that were consulted.

### Actual Behavior
- Step 1 (observed 2026-09-24, copy of the script under a temp root): exit 1, `"total_missing": 16`, `"settings_path": ".../.claude/settings.json"` — `SETTINGS_FILE` is the single project file (`check-permissions.sh:19`) and `allow_list=$(cat "$SETTINGS_FILE")` (`:152-153`). On this repository the checker happens to pass (the shared file carries 15 of the 16 rules and a base wildcard covers the last), while `defaultMode: bypassPermissions` and 8 of the rules live in `.claude/settings.local.json`, which the checker never opens: a mount whose rules were approved into the local file (the file Claude Code writes on approval) gets `P2 FAIL`, and the acceptEdits/default branch of P1 fails with it.
- Step 2: `Bash(rm:*)` is reported **found**: `check_permission` greps the raw file text for `"Bash(rm:*)"` (`:118`, `:128`), and the deny array is part of that text.
- Step 3: exit 1, 16 missing — the user file is never opened.
- Step 4: exit 0 — deny arrays are never evaluated.

### Environment
Linux 6.16, bash 5, jq 1.7; repository at `fix/cycle-125-followups` from `main` `5f4a58a5` (`v2.0.0-rc.2`); this machine: `.claude/settings.json` (allow 381, deny 62, no `defaultMode`), `.claude/settings.local.json` (gitignored; `defaultMode: bypassPermissions`, 8 of the 16 run-mode rules), `~/.claude/settings.json` (`defaultMode: auto`, deny 19, allow 0); `check-permissions.sh --json` today: `success: true, total_found: 16` from the shared file alone.

## Analysis
### Suspected Files
| File | Line(s) | Confidence | Reason |
|------|---------|------------|--------|
| `.claude/scripts/check-permissions.sh` | 19, 143-153 | high | one settings file; `settings.local.json` and `$HOME/.claude/settings.json` never read |
| `.claude/scripts/check-permissions.sh` | 111-134 | high | `check_permission` greps the whole file text — a deny entry, a comment or any other string containing the pattern satisfies it; no deny evaluation |
| `.claude/scripts/check-permissions.sh` | 176-244 | medium | JSON/text output names a single `settings_path`; no `denied` list, no list of consulted files |
| `.claude/scripts/run-preflight.sh` | 99-107, 109-128 | medium | P2 passes through the script's exit code; the P2 fix text names only `.claude/settings.json` although P1 already reads the three layers in Claude Code's order |
| `tests/unit/run-preflight.bats` | 116-135 | low | PF-1b / PF-2 drive P2 through a stub `check-permissions.sh` (`LOA_PREFLIGHT_HELPERS_DIR`); unchanged, must keep passing |

### Related Tests
| Test File | Coverage |
|-----------|----------|
| `tests/unit/settings-permissions.bats` | shape of the repository's shared `.claude/settings.json` (valid JSON, allow/deny arrays, tool families) — not the checker |
| `tests/unit/run-preflight.bats` | PF-1b / PF-2: P1 depends on P2; P2 mirrors the checker's exit code (stubbed) |
| (none) | `check-permissions.sh` itself has no test file |

### Test Target
New `tests/unit/check-permissions.bats`, failing first, with a temp root passed by `--root` and a temp `HOME`:
- CP-1 all 16 rules in `.claude/settings.json` → exit 0 (control; passes today).
- CP-2 rules only in `.claude/settings.local.json` → exit 0 (fails today).
- CP-3 rules only in `$HOME/.claude/settings.json` → exit 0 (fails today).
- CP-4 a pattern present only inside a `deny` array is not found (fails today: text grep).
- CP-5 a deny rule in any layer for a required rule → exit 1, `--json` lists it under `denied` with the file that denies it (fails today).
- CP-6 the base wildcard still covers subcommands (`Bash(git:*)` satisfies `Bash(git checkout:*)`; `Bash(git:*)` in deny denies them all).
- CP-7 no settings file in any layer → exit 2; `--json` lists `settings_files` consulted; `--quiet` prints nothing.
- CP-8 a malformed settings file is skipped with a warning on stderr, never a crash (jq failure ≠ "all allowed").

### Constraints
- Claude Code semantics, nothing invented: allow rules are the union across the layers; deny wins over allow in any layer; the wildcard `Bash(<base>:*)` covers `Bash(<base> <sub>:*)` (existing behaviour, kept for allow and applied to deny).
- No new configuration key. `--root <dir>` is a plain path argument (mirrors `run-preflight.sh --root`); `HOME` is the standard location of the user file. Managed/enterprise policy files are out of scope (not readable by design).
- Matching moves from text grep to jq array evaluation; a non-JSON file is skipped with a warning (never treated as allowing everything).
- Exit codes keep their meaning: 0 all required rules effective; 1 missing or denied; 2 no settings file found in any layer. JSON keeps `success/total_required/total_found/total_missing/found/missing` and adds `denied` and `settings_files` (additive).
- `run-preflight.sh` P2 detail/fix text names the layered files; P1 logic unchanged; PF-1b/PF-2 stubs unchanged.
- `.claude/` edits under the framework marker; regenerate REPO-MAP (+ `.checksum`) and `checksums.json` together; no skill text changes (budgets untouched).

## Fix Strategy
1. `check-permissions.sh`: build the layer list `[$HOME/.claude/settings.json, $ROOT/.claude/settings.json, $ROOT/.claude/settings.local.json]` (existing files only; exit 2 when none), read `permissions.allow[]` and `permissions.deny[]` from each with `jq -r` (skip a file jq rejects, warn), and evaluate each required rule: `denied` when an exact or base-wildcard match exists in any deny list (record the file); else `found` when a match exists in any allow list; else `missing`. Text and JSON output name the consulted files and the denied rules; the remedy text names `.claude/settings.local.json` for machine-local approval. Add `--root <dir>`.
2. `run-preflight.sh`: P2 detail names the layered files; the fix text says "add the listed Bash(...) allow rules to .claude/settings.local.json (machine-local) or .claude/settings.json (shared), and remove any deny rule that covers them".
3. Tests as listed; docs: `cost`-unrelated — the run-mode resource that documents preflight P2 (`.claude/skills/run-mode/resources/*`) gets a one-line note only if it names the single file (check; budgets).

### Fix Hints
Structured hints for multi-model handoff (each hint targets one file change):

| File | Action | Target | Constraint |
|------|--------|--------|------------|
| `.claude/scripts/check-permissions.sh` | fix | layered settings (`$HOME` user, project, project-local), jq array matching, deny-wins, `--root`, `denied` + `settings_files` in output | exit codes unchanged; base-wildcard rule kept |
| `.claude/scripts/run-preflight.sh` | fix | P2 detail/fix text names the layered files and the deny rule | P1 logic and the helper seam unchanged |
| `tests/unit/check-permissions.bats` | add | CP-1..CP-8 with `--root` and a temp `HOME` | failing first; no writes outside the temp root |
