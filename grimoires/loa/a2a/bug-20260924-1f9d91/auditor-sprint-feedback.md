APPROVED - LET'S FUCKING GO

# Security & Quality Audit — sprint-bug-246: `check-permissions.sh` (preflight P2) reads only `.claude/settings.json` and treats deny entries as allowed

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1 lead acting as gate; independent input: cross-model security dissent gpt-5.5-pro over the diff only, no context file — `adversarial-audit.json`, status `clean` ("no findings met the BLOCKING/ADVISORY bar"), 0 findings, 0 schema-rejected payloads, `verdict_quality.status APPROVED`, `chain_health ok`)
**Date:** 2026-09-24
**Scope:** `1bf1c173` + the review round-1 fixes over `b364c9dd` — `.claude/scripts/check-permissions.sh` (rewritten), `.claude/scripts/run-preflight.sh` (P2 text), `tests/unit/check-permissions.bats` (new, 10 cases), CHANGELOG
**Prerequisite:** `engineer-feedback.md` reads `All good` (review round 1, trailer consistent: 0/0/1/3, `excluded: 0`; the MEDIUM and two LOWs resolved in that round)
**Methodology:** sources → sinks over the diff (1A/1B), independent dissent (1C), five-category pass (Security, Architecture, Code Quality, DevOps; Blockchain n/a)

---

## Executive Summary

The change widens what a read-only checker reads (three settings files instead of one), moves matching from file-text grep to JSON-array lookups, and adds deny-wins. It writes nothing, executes nothing from the files it reads, and every value it prints comes from files the operator already trusts Claude Code to read. The security-relevant direction is the right one: a deny rule that Claude Code would enforce is now visible before an unattended run instead of stalling it mid-flight, and a pattern inside a deny array can no longer masquerade as an allow. Two LOW hygiene notes below, neither blocking. **APPROVED.**

**Overall Risk Level:** LOW

---

## Phase 1A/1B — Sources and sinks in the diff

| # | Source (trust) | Sink | Guard on the path | Status |
|---|---|---|---|---|
| S1 | `--root <dir>` (operator argv) | path composition for the two project files (`check-permissions.sh:159`) | value required (`:113`); files only read; no globbing | SAFE |
| S2 | `HOME` (environment) | path of the user file (`:159`) | `${HOME:-/nonexistent}`; read-only | SAFE |
| S3 | settings file bytes (operator- / repo-controlled JSON) | `jq -e` shape predicate (`:169`), `jq -r` rule extraction (`:177`, `:181`) | a non-object, or a non-array `allow`/`deny`, is skipped with a `WARN` and contributes nothing; reads `\|\| true`-guarded so `set -e` never turns a bad file into an abort (CP-8) | SAFE |
| S4 | rule strings | associative-array keys (`:176`, `:180`) and equality lookups (`:213-228`) | no `eval`, no pattern matching on rule content, no command execution; a rule is only ever compared for string equality | SAFE |
| S5 | rule strings / file paths | text output (`log`, `:270-282`) and JSON (`jq -R`, `:229-241`) | JSON strings are built with `jq -R` (properly escaped); text is echoed | LOW — see L-1 |
| S6 | required-rule table (script constant) | `base_pattern_of` (`:147-151`) | parameter expansion only | SAFE |
| S7 | preflight P2 (`run-preflight.sh:105`, `:130`) | detail/fix strings | constant text; exit code pass-through unchanged (PF-2) | SAFE |

## Findings

### L-1 — LOW (confidence: high) `.claude/scripts/check-permissions.sh:229-241` — a tab inside a rule or a path would shift the `denied[]` fields

`denied_lines` are `rule<TAB>by<TAB>file` and the JSON is built with `split("\t")`. A `--root` path (operator argv) or a rule string containing a literal tab would split into extra fields; the record is still valid JSON, just mis-labelled. Rule strings are `Bash(...)` patterns and paths with tabs are not a realistic operator input; the text output is unaffected. Not blocking; the cheap hardening is to emit each denied record with `jq -n --arg rule --arg by --arg file` instead of a tab join — noted for the next touch of this file.

### L-2 — LOW (confidence: medium) `.claude/scripts/check-permissions.sh:270-282` — rule strings are echoed verbatim to the operator's terminal

A settings file under repository control can carry arbitrary bytes in a rule string; the text report prints missing/denied rules as-is (the previous version did the same). A terminal-escape payload in a repository's `.claude/settings.json` would render in the operator's terminal when the check fails. Same class as every other Loa report that prints repository-controlled strings; the JSON path is escaped. Not blocking.

## Category pass

| Category | Notes |
|---|---|
| Security | Read-only; no secrets, no network, no privilege change; deny-wins narrows what unattended runs are told they may do. Shape validation + guarded reads mean a hostile settings file can only remove itself from the evaluation, never add permissions. |
| Architecture | Mirrors Claude Code's own layering and precedence; exit codes and the JSON's original fields unchanged, new fields additive; `--root` mirrors `run-preflight.sh --root`. Associative arrays are an existing dependency (47 framework scripts incl. `run-preflight.sh`; `bash-version-guard.sh` exists), so no new portability floor. |
| Code Quality | O(1) lookups (0.06 s vs 10.8 s before the review fix; CP-10 guards it), empty-array guards, `usage()` heredoc; the helper is fork-free. |
| DevOps | REPO-MAP + sidecar + checksums regenerated together; CHANGELOG `[Unreleased]` entry; `--help` and the header document the layers, deny-wins and exit codes. |

## Documentation audit

`check-permissions.sh` header and `--help` name the three layers, deny-wins, the wildcard rule and the exit codes; `run-preflight.sh` header and P2 text name the layers and the deny rule; CHANGELOG `[Unreleased]` › Fixed describes the change and the unchanged contracts; `reviewer.md` lists the scope boundaries (managed policy, other rule grammars, `CLAUDE_CONFIG_DIR`).

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":2},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-bug-246","ts":"2026-09-24T02:12:00Z"} -->
