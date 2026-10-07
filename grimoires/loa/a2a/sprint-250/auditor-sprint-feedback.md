# Sprint 4 Security Audit Feedback (cycle-126, global sprint 250)

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1, unattended `/run sprint-plan`, audit round 1)
**Date:** 2026-10-07
**Sprint Reference:** grimoires/loa/sprint.md — Sprint 4 (Final) "Residue, registry, probes, docs and E2E" (FR-4, SDD §1.5 D-4.1 … D-4.5 with the 2026-10-06/07 amendments), global 250 via `ledger.json`
**Implementation Report:** grimoires/loa/a2a/sprint-250/reviewer.md
**Tree audited:** `feature/cycle-126-full-size` at `005b9105`; sprint diff `2fcd4af8..005b9105` (16 commits, 113 files, +3,756 / −666); the round r250-8 delta `ee8fb582..005b9105` (13 files, +502 / −156) has no dissent run behind it and was read in full; working tree clean before and after this pass.
**Prerequisites:** `engineer-feedback.md` opens with "All good", trailer `review APPROVED 0/0/1/4, excluded 0`. `adversarial-review.json` carries `metadata.type review`, `metadata.model gpt-5.5-pro`, head `64c2eb09`, two two-voice chunks, `rejected_count 0`. `adversarial-audit.json` is the run-3 merge (byte-identical to `adversarial-audit-run3-merged.json`): `type audit`, `sprint_id sprint-250`, head `ee8fb582`, `model gpt-5.5-pro`, `degraded false`, 13 findings, `rejected_count 0`. Guardrails pre-check (`guardrails-orchestrator.sh --skill auditing-security --mode interactive --file …`): `WARN` (high-risk skill, interactive mode), PII 0 redactions, injection score 0 — proceed. Integrity: `integrity_enforcement` is unset (default warn); the three shell files round r250-8 changed hash to their `checksums.json` entries (`71f0c9fd…`, `11930d71…`, `a053809a…`) and pass `bash -n`.

---

## Verdict: APPROVED - LET'S FUCKING GO

---

## Executive Summary

Sprint 4 retargets the previous-generation ids (catalog `opus` → `claude-opus-5-5`, `cheap` → `claude-sonnet-5`, maps, regexes, registry rows, pins), hardens the implement gate through three audit rounds (the ask now reaches Claude Code, authoritative mode is tighten-only, paths are canonicalised in two forms, the gate's own trust inputs ask, audit rows are raw and ASCII-escaped), ports the same sanitiser discipline into `lib-content.sh`, replaces the validator's environment seam with an explicit flag, fixes the recall grader test-first and re-runs the Sprint 3 A/B under a pre-registered rule. I read the gate, the lib function, the validator's argument parser, the hook wrapper, the settings matcher, the corpus, the catalog entry, the registry row, the adapter regex and the three dissent triages against the code, not the reports; I ran the sprint's own suites here (implement-gate 20/20, compliance-hook 14/14, hook-guard 8/8, skill-capabilities 36/36, companion CMP-278–283 6/6, serial) and probed the gate and the lib in `mktemp -d` roots.

**No critical or high issue is open at HEAD.** One MEDIUM is open and it is the one worth the lead's next hour: the gate roots its zone test on the hook process's working directory (`PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"`), and the Claude Code hooks reference states that this directory follows Claude's `cd`. From a subdirectory, an absolute-path Write to `src/x.ts` or to `.loa.config.yaml` is allowed silently (probed: four cases), which is the same class and impact as run-2 finding 1 and run-3 finding 3 that the lead rated MEDIUM and fixed. The root derivation predates the sprint, so this is not a regression, but round r250-7's "outside the root is not App Zone" rule made it decisive, and no IG case exercises the default path (every case sets `PROJECT_ROOT`). The fix is one line plus one test. Five LOWs: the display sanitisers are blocklists with known gaps, the operator-facing hooks reference still calls the gate an unwired prototype, one sprint-touched script keeps `python3 -` without `-I`, two of the three heuristic state files have no freshness or plan-id check (bd-taee detail), and the run-2 triage headline miscounts its own findings.

**The round r250-8 delta holds.** Every item the lead listed was verified in the code and by running or probing it; the fail-ask paths are enumerated below with the one fail-open path (MED-001). The six disclosures are ruled on explicitly; all six are accepted.

**Post-audit round r250-9 (`e170de3d`) closed MED-001 and LOW-002 … LOW-005 — see the addendum before the trailer. Open at HEAD: LOW-001 (bead bd-4iit) and LOW-006 (a freshness residual found while verifying the fix).**

**Security Issues Found:**
| Severity | Open at `e170de3d` (the trailer) | Found at `005b9105` (round 1) |
|----------|----------------------------------|-------------------------------|
| Critical | 0 | 0 |
| High | 0 | 0 |
| Medium | 0 | 1 |
| Low | 2 | 5 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

None.

---

## Medium/Low Priority Issues

### [MED-001] The gate roots its zone test on the hook process's cwd, which follows Claude's `cd`; from a subdirectory an App-Zone or trust-input Write is allowed silently — CLOSED in round r250-9 (`e170de3d`), see the addendum

- **Severity:** MEDIUM · **Confidence:** high
- **File:** `.claude/hooks/compliance/implement-gate.sh:133` — `PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"`, consumed by `canonical_root`/`logical_root` at `:216-217`, the root-relative forms at `:244-245`, the trust-input case at `:256-269` and the App-Zone case at `:277-288`.
- **Issue:** The hook is wired as `"$(git rev-parse --show-toplevel)"/.claude/hooks/hook-guard.sh … implement-gate.sh` (`.claude/settings.json:586`) with no `PROJECT_ROOT` in its environment, so the root is the process's cwd. The Claude Code hooks reference (code.claude.com/docs/en/hooks, read 2026-10-07) says: "`${CLAUDE_PROJECT_DIR}` stays put: it still points at the project root where the session started … cwd follows Claude: the cwd field in the hook's input JSON is the worktree root after Claude enters a worktree, and the new directory after Claude runs `cd`", and defines the common `cwd` field as "Current working directory when the hook is invoked". The gate's own comment at `:188-189` records the same ("cwd follows `cd` in the Bash tool") and round r250-8 resolves relative paths from it — but keeps the root on `$(pwd)`. Nothing in the repo fences `cd` (block-destructive-bash has no `cd` row), and the Bash tool's cwd persists between calls.
- **Probe** (mktemp root, `PROJECT_ROOT` and `RUN_DIR` unset, as in production; absolute paths):

  | hook cwd | file_path | decision |
  |---|---|---|
  | `<root>` | `<root>/src/x.ts` | ask |
  | `<root>/src` | `<root>/src/x.ts` | **allow** |
  | `<root>/grimoires` | `<root>/src/x.ts` | **allow** |
  | `<root>/src` | `x.ts` (relative, payload `cwd: <root>/src`) | **allow** |
  | `<root>/src` | `<root>/.loa.config.yaml` | **allow**, no `compliance.state_write` row |

  With the cwd a subdirectory, both root-relative forms fall outside "the root", so `rel_forms` is empty, the trust-input loop never runs and `is_app_zone` stays false. `RUN_DIR` moves with the wrong root too, so the heuristic would read `<root>/src/.run/` if it got that far.
- **Impact:** fail-open of the ask the sprint spent three rounds making mechanical, and of the new trust-input ask (disclosure 6 below: the friction the lead accepted is not even uniform). Bounded by: the gate is ADVISORY (`ask`, never `block`); the Bash write path is an accepted gap (CLAUDE.loa.md C-PROC-001 row, hooks-reference); the heuristic's RUNNING trust is bd-taee. Pre-sprint the same wrong root gave the same allow (`2fcd4af8` `:62-66`: "Absolute path that doesn't start with PROJECT_ROOT — … don't match against App Zone patterns"), so this is not a regression. Same class and impact as run-2 finding 1 (`/proc/self/cwd/src/x` reached App Zone unseen) and run-3 finding 3 (trust inputs freely writable), both rated MEDIUM by the dissent and the lead and fixed; MEDIUM, not HIGH, on that calibration. Sibling hooks do not share the defect: `zone-write-guard.sh:161-162` and `notes-size-guard.sh:29-30` root on the script's location, `team-role-guard-write.sh:60` on `git rev-parse --show-toplevel`; none uses `$(pwd)`.
- **Fix:** root on the harness's project directory, then the script location:

  ```bash
  PROJECT_ROOT="${PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)}}"
  ```

  (`git rev-parse --show-toplevel` is an equivalent third rung; settings.json already relies on it. In a linked worktree it yields the worktree root, which is the right root for that session.) Add IG-21, red first: `PROJECT_ROOT`/`RUN_DIR` unset, hook cwd `$ROOT/src`, `CLAUDE_PROJECT_DIR=$ROOT`, payload `cwd: $ROOT/src`: absolute `$ROOT/src/x.ts` → ask; `$ROOT/.loa.config.yaml` → ask plus one `compliance.state_write` row in `$ROOT/.run/audit.jsonl`; and the same two with the hook cwd at `$ROOT` and `CLAUDE_PROJECT_DIR` unset, so the default derivation is exercised at least once in the suite. Update the header (`:26-35`) and the SDD D-4.4 amendment list.
- **Reference:** CWE-706 Use of Incorrectly-Resolved Name or Reference — https://cwe.mitre.org/data/definitions/706.html; CWE-284 Improper Access Control — https://cwe.mitre.org/data/definitions/284.html.

### [LOW-001] The stderr sanitisers remain blocklists; invisible code points outside the set still reach the operator's terminal — OPEN, bead bd-4iit

- **Severity:** LOW · **Confidence:** high
- **File:** `.claude/hooks/compliance/implement-gate.sh:71-96` (`_IG_STRIP_SEQS`) and `:121-131` (`strip_controls`); `.claude/scripts/lib-content.sh:181-194` (`_lc_log_seqs_init`).
- **Issue:** Probe (authoritative, claim `review`): path `src/a<U+034F><U+2800><U+3164><U+1D173>b.py` — the combining grapheme joiner, the braille blank, the Hangul filler and a musical-symbol format character — reaches stderr with all four intact (bytes `315 217`, `342 240 200`, `343 205 244`, `360 235 205 263`). Also absent from both arrays: U+115F/U+1160, U+FFA0, U+1BCA0–1BCA3, U+110BD, U+110CD, U+13430–1343F and every `Mn` combining mark. The audit row is faithful (`jq -a`, IG-13), so the record is right; the display copy is what an operator reads at the moment of the prompt.
- **Fix:** invert the display copy to an allowlist (`LC_ALL=C tr -cd '[:alnum:][:punct:] '` keeps every ASCII name readable and turns anything else into its absence, or `printf %q` for a reversible form); or generate the two arrays once from `unicodedata` (`Cf` is 170 code points in Unicode 15) rather than extending them finding by finding. Keep the two sanitisers one function in one lib so they cannot drift again.
- **Reference:** CWE-150 Improper Neutralization of Escape, Meta, or Control Sequences — https://cwe.mitre.org/data/definitions/150.html.

### [LOW-002] The operator-facing hooks reference still describes the gate as an unwired prototype — CLOSED in round r250-9 (`e170de3d`)

- **Severity:** LOW · **Confidence:** high
- **File:** `.claude/loa/reference/hooks-reference.md:187` ("PreToolUse (opt-in, UNWIRED by default) | Write/Edit | … ADVISORY FR-7 prototype … parked; wire manually") and `:201-230` (Write/Edit only, heuristic only, "Installation: Merge into `~/.claude/settings.json`", decision matrix with no trust-input or fail-ask rows); `.claude/settings.json:586` wires the hook through `hook-guard.sh` on `Write|Edit|MultiEdit|NotebookEdit`.
- **Issue:** Nothing in the reference mentions the dual mode, the `hookSpecificOutput.permissionDecision: ask` shape, the fail-ask contract, NotebookEdit, the trust-input asks or the `compliance.*` audit rows. Three audit rounds amended the SDD and the CHANGELOG but not this file (not in the sprint diff; last touched at `36b71e4e`). This is the skill's documentation-audit red flag "auth changes without security documentation" applied to a fence: the operator who reads the reference believes the gate is parked.
- **Fix:** rewrite row `:187` and section `:201-230` from the hook header (`implement-gate.sh:3-56`): wired by default, matcher, modes, fail-ask paths, trust inputs, the audit events, MED-001's root rule once fixed.

### [LOW-003] One sprint-touched script still runs `python3 -` without `-I` — CLOSED in round r250-9 (`e170de3d`)

- **Severity:** LOW · **Confidence:** high
- **File:** `.claude/scripts/flatline-orchestrator.sh:582` — `PYTHONPATH="$SCRIPT_DIR/../adapters" python3 - "$PROJECT_ROOT" "$1" <<'PY'`.
- **Issue:** The n32/n39 class the sprint fixed in the grader, `check-prompt-budget.sh` and five tests: with `python3 -`, `sys.path[0]` is the cwd, so a `yaml.py`/`json.py` written to the project root — a non-App-Zone path the gate allows silently — is imported before the stdlib (RG-27 showed a planted module forging `pass: true`). The sprint changed this file (model defaults) and left this site; the six `python3 -` heredocs in `tests/unit/adversarial-review-companion.bats:628,1178,2696,4248,4440,4824,5669` are test code of the same shape. Pre-existing; bead.
- **Fix:** this site sets `PYTHONPATH`, which `-I` would discard (it implies `-E`), so either `python3 -P -` (3.11+: drops the cwd entry from `sys.path`, keeps `PYTHONPATH`) or `-I -` with the adapters directory passed as an argument and `sys.path.insert(0, …)` inside the heredoc. The bats sites take `-I -` directly.
- **Reference:** CWE-427 Uncontrolled Search Path Element — https://cwe.mitre.org/data/definitions/427.html.

### [LOW-004] Two of the three heuristic state files grant the allow with no plan id or freshness check (bd-taee detail) — CLOSED in round r250-9 (`e170de3d`), residual LOW-006 in the addendum

- **Severity:** LOW · **Confidence:** high
- **File:** `.claude/hooks/compliance/implement-gate.sh:399-415`.
- **Issue:** `simstim-state.json` `phase == implementation` and `state.json` `state == RUNNING` return 0 with none of the integrity checks `sprint-plan-state.json` gets at `:368-392` (a `plan_id`, a `last_activity` under 24 h). A stale `state.json` from a run that never jacked out keeps allowing App-Zone writes indefinitely; the hooks-reference decision matrix (`:209-216`) reads as if "Stale (>24h) → ask" applied to every state file. The Bash path to write any of the three is unfenced (accepted gap). Pre-existing, ADVISORY by design; the sprint's trust-input ask (IG-18) covers the Write tool only.
- **Fix:** fold into bd-taee: apply the staleness check to all three files now (cheap, tighten-only), and bind the allow to a marker a model cannot write when that bead lands.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html.

### [LOW-005] The run-2 triage headline miscounts its own findings — CLOSED in round r250-9 (`e170de3d`)

- **Severity:** LOW · **Confidence:** high
- **File:** `grimoires/loa/a2a/sprint-250/audit-dissent-triage-run-2.md:6` — "**Findings.** 12: 4 MEDIUM, 8 LOW."
- **Issue:** The rulings table below it has 5 MEDIUM (#1, #2, #7, #8, #9) and 7 LOW, and `adversarial-audit-run2-merged.json` agrees (`MEDIUM 5, LOW 7`). The rulings are right; the headline is wrong, and this ledger is what the record branch will carry.
- **Fix:** one-line edit before the record-branch push (the directory is gitignored until then).

---

## Round r250-8 (`ee8fb582..005b9105`), audited without a dissent run

The three-run budget was spent on runs 1–3, so this delta has only this reading behind it. What I verified and how:

- **Both path forms** (`implement-gate.sh:193-245`): `_ig_lexical_norm` traced (drops empty/`.`, pops on `..`, never follows a link, dense array so `unset 'out[last]'` is safe); `_ig_under_root` handles root `/`; physical = `realpath -m` → `readlink -f` against `pwd -P`, logical = `realpath -m -s` → the normaliser against `pwd -L`; either form matching counts. IG-17 passes here (symlinked `src/`, symlinked `lib/cfg.ts`, and the `realpath` shim that refuses `-s` forces the fallback). Round r250-7's regression (inside-out symlinks allowed) is closed.
- **Case folding** `${rel,,}` (`:244-245`): tighten-only on case-sensitive filesystems; corpus row `write-Src-plain.json` (`ask ask no`) and IG-15 `LIB/x.js` pass. Lowercasing is locale-dependent only for non-ASCII, which the patterns never contain.
- **Trust inputs** (`:256-269`): evaluated before the App-Zone test on both forms; the six names are exact root-relative matches, so `.run/other.json` and `grimoires/**` stay silent; the row is `jq -nca` from `audit_file_path` (raw, cut on a character boundary). IG-18 passes (six asks, six rows, the relative `.run/../.run/state.json`, two silent allows). The lead's live probe row is in `.run/audit.jsonl` (`2026-10-07T03:54:54Z compliance.state_write …/.loa.config.yaml`) — read, not written. A symlink into a trust input is caught by the physical form; a hard link is not (no fix possible at this layer; note only). The defect is MED-001: with the wrong root none of this runs.
- **Relative paths from `cwd`** (`:218-225`): `.cwd` is a harness field (not under `tool_input`), `| strings` rejects a non-string, a relative `base_dir` is itself rooted; IG-19 passes.
- **`cut_utf8_256`** (`:101-116`): walks back at most four bytes from the 256-byte cut, drops a lead byte whose sequence the cut left short, drops stray continuation bytes after a complete character, and the all-continuation tail; `printf -v` keeps a trailing newline (the `jq -j` + sentinel at `:159-164` preserves it into the raw value). Bash internals honour `local LC_ALL=C` (verified `${#é}` = 2 inside such a function). IG-13's split-`é` case passes.
- **`strip_controls`** (`:121-131`): cut first, then `tr -d` C0/DEL, then the sequence array to a fixed point (each sequence starts with a lead byte, so byte-wise deletion never lands inside another character); the gaps are LOW-001.
- **`emit_ask`** (`:63-69`): `jq -nc --arg r` when jq exists; the printf literal only on the no-jq branch, whose reason is a fixed string; IG-20 passes.
- **`log_model_signal`** (`:314-322`): `jq -nca`, raw claim and raw path cut to 256 bytes → every non-ASCII code point `\uXXXX`; jq 1.7 replaces invalid UTF-8 in `--arg` with U+FFFD, so a bare 8-bit byte cannot reach the row raw. IG-13 pins `implement​` beside `decision: ask`.
- **Fail-ask paths, enumerated:** no jq or unparsable payload (`:151-155`), path not readable by jq (`:159-163`), root or path uncanonicalisable (`:235-239`). **Allow paths:** a parsed payload with no `file_path`/`notebook_path` (`:167-169`, by design — the harness rejects such a Write anyway), and the wrong-root case (MED-001). The heuristic ask at `:430` is a literal with a fixed reason; the bats `decision()` reader rejects a top-level `decision`.
- **`hook-guard.sh`** wraps the gate (`settings.json:586`): fails OPEN only on a `bash -n` failure (by design, #1180); the gate parses (`bash -n` clean).
- **`lib-content.sh` `_lc_safe_log_path`** (`:195-220`) and `_lc_log_seqs_init` (`:181-194`): cut to 256 bytes before the fixed point (CMP-281: 20,000-byte `C2^k 9B^k` under 5 s), the tail fix traced (a short lead is dropped; an all-continuation tail is dropped; a stray continuation after a complete character survives to the iconv step and is then replaced — correct), the same sequence set as the gate (CMP-282), `iconv -f UTF-8 -t UTF-8` validation with `tr -c '[:print:]' '?'` on failure (CMP-283). I also probed the no-iconv fallback with a real `grep` under `C.UTF-8` and `C`: a bare `9B` → `src/a?2Jb.sh` in both. One portability note: `local LC_ALL=C` is **not** exported to the `tr`/`grep`/`iconv` children (verified: `env` inside such a function shows no `LC_ALL`); harmless on GNU tools (byte-wise `tr`, `grep` handled the raw-byte bracket under UTF-8 here), but `LC_ALL=C grep …` would pin it.
- **`validate-skill-capabilities.sh`** (`:30-73`, `:117-135`): `unset AGENT_TYPES_FILE` before argument parsing; `--agent-types-file` with no value → exit 2 with usage; the path flows only into `[[ -f ]]` and `yq eval`; names are regex-checked `^[A-Za-z0-9_-]+$`; the empty/unparsable fallback is `general-purpose` only. SC-T-AGENT-8/9/10 pass (10 proves the ambient variable is ignored with and without the bats markers). The `PROJECT_ROOT`/`SKILLS_DIR` env seams remain (bd-7cur, pre-existing).
- **Suites, real tree, serial** (`env -u CLAUDE_HEADLESS_BIN -u AWS_BEARER_TOKEN_BEDROCK bats …`): implement-gate 20/20, compliance-hook 14/14 (CH-T8–T10), hook-guard 8/8, skill-capabilities 36/36, adversarial-review-companion `-f 'CMP-2(7[89]|8[0-3])'` 6/6. No eval, no model call, no `br`, no `.run/` write.

---

## The checklist focus items, verified

- **Secrets:** a pattern scan over the +3,756 added lines of the sprint diff (Anthropic/OpenAI/AWS/GitHub/Google/Slack key shapes, PEM headers, `*_API_KEY=`/`AWS_BEARER_TOKEN_BEDROCK=` with a literal, bearer tokens) returns nothing. The catalog entry carries no key material; `.run/` and `a2a/` are gitignored. Credential checks in the diff are presence-only.
- **The gate as a fence:** fail-ask vs fail-open enumerated above; what a model-authored payload can still do: claim any `active_skill` (tighten-only now — IG-12), write the three heuristic state files through Bash (bd-taee, LOW-004), and defeat the zone test by changing directory (MED-001).
- **Hook output contract:** both ask sites (`:65`, `:430`) emit `hookSpecificOutput.permissionDecision: ask`; allow is silent exit 0; no top-level `decision`.
- **Path canonicalisation:** physical OR logical, lowercased, relative via `cwd` — verified above; MED-001 is the open case.
- **Log/terminal injection:** stderr copies through `strip_controls`/`_lc_safe_log_path`; audit rows raw through `jq -a`; LOW-001 for the remaining display gaps.
- **Test-seam gating:** `--agent-types-file` only; verified above.
- **Registry row:** `.claude/data/model-permissions.yaml:207-219` `anthropic:claude-opus-5-5` — `trust_level: high`, every trust scope `none`, `context_access.security: redacted` (mirrors the 4-7 row; `test_trust_scopes.py:360/368`).
- **Catalog entry:** `.claude/defaults/model-config.yaml:470-510` — vendor-sourced 1M/128K, `probed_ceiling 180000` with `ceiling_calibration.source: conservative_default` and the `loa:shortcut` marker, `fallback_chain` `claude-opus-5` → `claude-sonnet-5` → `claude-headless` (within-company), `beta_headers []`, `temperature_supported false`; `aliases.opus` `:1109`, `cheap` `:1106`.
- **`python3 -I -`:** `evals/graders/recall-vs-defects.sh:80`, `tools/check-prompt-budget.sh:50`, IDR-3, LFF-1/3/4, RES-5; RG-27 pins the mechanism; residue LOW-003.
- **Beta-header regex:** `.claude/adapters/loa_cheval/providers/anthropic_adapter.py:85` `^[a-z0-9]+(-[a-z0-9]+)*-[0-9]{4}-[0-9]{2}-[0-9]{2}$` applied with `fullmatch` at `:177` — `[0-9]` is ASCII-only and `fullmatch` refuses a trailing newline that `$` alone would accept.
- **Recall grader as the A/B instrument:** 1.1.2, `-I`, RG-11–27; ruling under disclosure 2.

---

## Disclosures, ruled

1. **Sprint 3 AC "CLAUDE.loa.md ≤ 9,216 B" given up under the pre-registered rule — accepted.** The rule (`replay-ab-rerun-prereg.md`, 2026-10-05T23:25Z) preceded the run (23:26Z); the gate failed on the grader measure, the ablation isolated both components, both were reverted (`bf988a43`), the file is byte-identical to `main` and the limit is `main`'s own 10,240 B; the post-revert re-run passes. FR-3.3 (no recall regression) outranks FR-3.2's byte target, and a pre-registered rule honoured against the author's preference is the right kind of evidence. Not a security matter. The ordering remains unprovable from version control until the record branch is pushed (review Observation 4, carried): push it at cycle end as the proof.
2. **Adjudication condition (a) unmet on two case/arms — accepted.** The two misses are citation-location disagreements (audit-pr-07 both arms +2, audit-pr-02 before arm −2), not parser drops, disclosed before the ruling; the gate decision was taken on the grader measure, the stricter instrument, and the grader under-counts relative to the blind adjudicator — the conservative direction. Condition (b) (`record/cycle-126-ablate-c9b7bdc0`, scripts under `a2a/sprint-249/eval-scripts/`) is met; condition (c) is discharged by the passing re-run. The gap stays recorded in `replay-ab-rerun.md` for the next grader revision.
3. **`implement_gate.mode: authoritative` undocumented — accepted.** FR-4.4's condition (document only if a harness-provided, unforgeable signal exists) is unmet by Task 4.4's research; the branch is tighten-only (IG-12) so the undocumented key can only add asks; IG-11 pins the absence from `.loa.config.yaml.example`, `docs/` and `README.md`.
4. **LSP-1 load flake — accepted as recorded.** Not a security path; `ok 3158` in the full run at `db49cd32`; fails only in back-to-back batches, 5/5 alone.
5. **Pre-existing defects as beads, not fixes — accepted**, with the lists in the three triages (bd-z5yw, bd-lemw, bd-7cur, bd-mt9c, bd-gm9p, bd-muk5, bd-6x75, bd-s03k, bd-2rhn, bd-w8lj, bd-x2rp, bd-taee, bd-d7kx; comments on bd-ugmi, bd-j8v1). I add three bead candidates (LOW-001, LOW-002, LOW-003) and one fold (LOW-004 → bd-taee). MED-001 is a fix, not a bead: one line and one test.
6. **The trust-input ask prompts on the lead's legitimate Write-tool edit of `.run/sprint-plan-state.json` or `.loa.config.yaml` — accepted.** That friction is the control; tighten-only. Note that it is not uniform: from a subdirectory the ask is silently absent (MED-001).

---

## Review observations, confirmed (not re-tallied)

The review trailer's `excluded` is 0, so `excluded_confirmed` is 0. Review MED 1 (authoritative mode trusted a model-authored field) is **resolved** by round r250-6's tighten-only rule — `implement-gate.sh:323-336`, IG-12 passes here. Review LOW 2 (two derived SDD lines) resolved at `4d37029e`; LOW 3 (`.py` residue outside the recorded grep), LOW 4 (pre-registration ordering), LOW 5 (sibling 5-family long-context tier) stand as carried, not re-tallied.

---

## Dissent record

| Run | Range | Chunks | Voices | Findings | Rejected | Triage |
|---|---|---|---|---|---|---|
| 1 | `2fcd4af8..db49cd32` | 16 | 16/16 two-voice [codex-headless, claude-headless] | 51 (4 HIGH, 12 MEDIUM, 35 LOW) | 0 | `audit-dissent-triage-run-1.md`; verifiers A/B |
| 2 | `4d37029e..e151757d` | 3 | 3/3 two-voice | 12 (5 MEDIUM, 7 LOW) | 0 | `audit-dissent-triage-run-2.md` |
| 3 | `e151757d..ee8fb582` | 2 | 2/2 two-voice | 13 (6 MEDIUM, 7 LOW) | 0 | `audit-dissent-triage-run-3.md` |

Every chunk in the three merged envelopes lists `voices_succeeded_ids ["codex-headless","claude-headless"]`; `rejected_count` is 0 in each; the companion is `independent`. Run 1's four HIGHs were declined or fixed as tightenings (n5 declined, n13 tracked bd-ugmi, n17 fixed tighten-only, n27 fixed) — I read the verifier evidence and concur with each ruling. Round r250-8 (`ee8fb582..005b9105`) has no run behind it and is covered by the section above.

---

## Notes, not tallied

- **macOS without GNU coreutils:** BSD `realpath` has no `-m`, and `readlink -f` (macOS 12.3+) needs the parent to exist, so every Write into a not-yet-existing directory asks. Fail-ask, tighten-only, by design; worth one sentence in the migration guide ("install coreutils or expect asks on new directories").
- **`*/lib/*` matches `.claude/scripts/lib/*.sh`** (probed: ask) — tighten-only, pre-existing.
- **Authoritative mode logs a `compliance.mode.fallback` row on every App-Zone write without a claim** (`:338-353`); the harness never sets the field, so the row fires on every such write — noise, pre-existing.
- **The guardrails orchestrator maps an unrecognised `--mode` to `BLOCK/error`** (I first passed `--mode run`); fail-closed on its own error is correct and not this sprint's.
- **Hard links** into a trust input are invisible to both path forms; no fix at this layer.

---

## Scope limits

- No `documentation-coherence-*` report exists for sprint-250 under `grimoires/loa/a2a/subagent-reports/`; documentation verified by hand: CHANGELOG `[Unreleased]` lines for rounds r250-6/7/8 (`:43-46`), SDD D-4.4 amendments (a)(b)(c) and the D-4.1/D-4.3 amendment, `sprint.md` Task 4.9, the migration-guide addendum; the hooks reference is stale (LOW-002).
- No model call of any kind was made (no `adversarial-review.sh`, cheval, `claude -p`, Bridgebuilder, agy, gemini, and no WebFetch summariser — the hooks reference was fetched with `curl` and grepped). The dissent record is the three merged envelopes.
- MED-001's premise (the hook process cwd follows `cd`) rests on the Claude Code hooks reference text quoted above and the gate's own comment at `:188-189`, plus `mktemp -d` probes with the cwd set by hand; I did not exercise a live `cd` + Write in this session (this agent thread's cwd resets between Bash calls, and my writes were limited to this file, the marker and the index). The 5,775 Bash rows in `.run/audit.jsonl` all record the root as cwd, so the live log neither confirms nor refutes it.
- Probes ran in `mktemp -d` roots only; `.run/audit.jsonl` was read, never written; `git status` clean before and after; the five permitted suites ran serially.
- Trajectory logging to `a2a/trajectory/` skipped under the lead's write restriction.

---

## Rubric (sprint surface)

SEC-IV 4 (payload parsed with jq, paths canonicalised twice, names regex-checked; MED-001 is the one input the gate trusts without checking — its own cwd), SEC-AZ 4 (the gate is advisory by design; tighten-only holds), SEC-CI 5 (nothing secret touches this sprint), SEC-IN 4 (display copies are blocklists — LOW-001; records are faithful), SEC-AV 5 (never-block holds; `hook-guard` parse-guard; fail-ask mechanical except MED-001), CQ-TC 4 (20 red-first IG cases, 6 CMP cases, 3 SC cases; the production root derivation is untested — IG-21), CQ-DC 3 (the hooks reference contradicts the wiring — LOW-002), DEVOPS-AC 4 (checksums and REPO-MAP regenerated per round; the full unit run classified to the case).

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added — pattern scan over the sprint diff additions: none; the catalog entry and the registry row carry no key material
- [x] Input validation on all new entry points — payload: `jq -e .` then `jq -j` with a sentinel; path: two canonical forms against two roots; `cwd`: `| strings`; validator flag: `[[ -f ]]` + `yq eval` + name regex; gap: the hook's own cwd as root (MED-001)
- [x] Authentication required where needed — n/a (no credential, no network in the delta)
- [x] No injection paths from untrusted input — `emit_ask` and every audit row built by jq; stderr through the sanitisers (LOW-001 gaps are display-only)
- [x] Error handling doesn't leak — the fixed-string asks; `2>/dev/null` on every jq read; hook never exits non-zero
- [x] Tests cover security paths — IG-12–20, CH-T8–10, SC-T-AGENT-8–10, CMP-278–283 all red first per the triages and green here; gap: IG-21 (MED-001)

---

## Rejected dissent payloads

None — `adversarial-audit.json` (the run-3 merge) reads `rejected_summary []`, `rejected_count 0`, `rejected_sidecars ["grimoires/loa/a2a/sprint-250/adversarial-rejected-audit-a7-misc.jsonl"]`, and that file is 0 bytes; runs 1 and 2 (`adversarial-audit-run{1,2}-merged.json`) also read `rejected_count 0` on every chunk. The seven audit sidecars beside this file — `adversarial-rejected-audit-{g-gate,m1-pins,m2-pins,p2-platform,r-perms,a6-misc,a7-misc}.jsonl` — and the five review sidecars — `adversarial-rejected-review-{g-gate,k1-kernel,k2-kernel,m1-pins,v-eval}.jsonl` — are each 0 bytes (`ls -la`), no row.

---

## Next Steps

1. **Approved on the one-way rule** (0 critical / 0 high). I write the `COMPLETED` marker and the index row; the lead updates `ledger.json`, `.run/sprint-plan-state.json` and beads from this report.
2. **Before the cycle PR:** MED-001 (one line at `implement-gate.sh:133` + IG-21 + the header and SDD D-4.4 sentence) and LOW-005 (one line in the run-2 triage). Both are an hour's work and the first keeps three rounds of hardening honest.
3. **Beads:** LOW-001 (allowlist display copy, one shared sanitiser), LOW-002 (hooks reference rewrite), LOW-003 (`python3 -I`/`-P` at `flatline-orchestrator.sh:582` and the seven bats sites); fold LOW-004 into bd-taee.
4. **Cycle end:** push the a2a record branch (disclosure 1's proof), then `/ship`.

---

## Post-audit addendum (round r250-9, `e170de3d`, 2026-10-07)

**Tree:** `feature/cycle-126-full-size` at `e170de3d` (HEAD, pushed; working tree clean). Delta `005b9105..e170de3d`: 14 files, +301 / −146 — the gate (+39 / −7), `hooks-reference.md`, `flatline-orchestrator.sh`, four suites plus one new, CHANGELOG, SDD D-4.4 amendment (d), REPO-MAP + `.checksum`, `checksums.json`, `ledger.json` (the lead's status write). Read in full. Suites run here, serial, `env -u CLAUDE_HEADLESS_BIN -u AWS_BEARER_TOKEN_BEDROCK`: implement-gate 22/22, compliance-hook 14/14, hook-wiring 10/10, flatline-orchestrator-python-isolation 3/3, hook-guard 8/8, adversarial-review-companion CMP-13/32/188/198/244/270 + CMP-278–283 12/12; 0 skips. `bash -n` clean on the gate and the orchestrator; gate, orchestrator and hooks reference hash to their `checksums.json` entries. No dissent run (budget spent), no model call, no `br`, no `.run/` write; probes in `mktemp -d` roots only, nothing deleted.

| Item | Status at `e170de3d` | Verified how |
|---|---|---|
| MED-001 — root from `$(pwd)` | **Closed** | `implement-gate.sh:136-139`: `PROJECT_ROOT`, else `CLAUDE_PROJECT_DIR`, else `$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)`; the process cwd is never consulted; `RUN_DIR` follows. IG-21 green (three legs). My probes, `PROJECT_ROOT`/`RUN_DIR` unset: the real hook from `<root>/src` with `CLAUDE_PROJECT_DIR=<root>` → `src/x.ts` ask, `.loa.config.yaml` ask + row; a copy three levels under a temp root (the script-location rung) from `<root>/src`, from `<root>` and from `/tmp` → ask on all three; a relative `x.ts` from `<root>/src` → ask; two `compliance.state_write` rows in `<root>/.run/audit.jsonl`, no `.run` under `<root>/src`. Real tree, the hook as wired, no root variable, cwd `<repo>/tests`: `<repo>/src/probe2.ts` → ask with the `[ADVISORY]` line. Before r250-9 that same call would have allowed for a second reason: the live `.run/state.json` is `RUNNING` with `last_activity 2026-09-25` and the live `simstim-state.json` is `implementation` from 2026-05-23 — both now read as stale (LOW-004 was live in this repository). |
| LOW-002 — hooks reference | **Closed** | `hooks-reference.md:187` row: PreToolUse, `Write/Edit/MultiEdit/NotebookEdit`, `hook-guard.sh compliance/implement-gate.sh`, the ask semantics; §implement-gate.sh rewritten from the header: wired by default in both settings files, the output contract, the path and root rule, the modes, a freshness table, the decision matrix (fail-ask rows, trust inputs, the authoritative claim), the audit events, the accepted gaps (Bash path, bd-taee, a direct `/implement`). hook-wiring W6 pins the row to both settings files and drops the gate from `PARKED_HOOKS`; 10/10. |
| LOW-003 — `python3 -` | **Closed** | `flatline-orchestrator.sh:583-585`: `python3 -I - "$SCRIPT_DIR/../adapters" "$PROJECT_ROOT" "$1"` with `sys.path.insert(0, sys.argv[1])` and the argv indices shifted; `SCRIPT_DIR` is absolute (`:50`); no `PYTHONPATH=` left. The seven companion heredocs take `-I`. FOPI-1 (shape), FOPI-2 (a planted `json.py` / `yaml.py` never imported, exit non-zero, no `forged`), FOPI-3 (alias and catalog resolution still work with a decoy present) 3/3; the six CMP tests whose heredocs changed pass. |
| LOW-004 — freshness on all three state files | **Closed, one residual (LOW-006)** | `_ig_fresh` (`:369-381`): empty, unparsable or non-numeric → stale; `state.json` reads `.timestamps.last_activity // .updated_at`, `simstim-state.json` `.timestamps.last_activity`; IG-22 green. Probes against the real hook: 25 h → ask, fresh → allow, no timestamp → ask, `.updated_at` → allow, `not-a-date` → ask, a numeric timestamp → ask, 23 h 58 m → allow. The compliance-hook helpers now stamp `last_activity`, so CH-T* keep exercising the allow path. |
| LOW-005 — run-2 headline | **Closed** | `audit-dissent-triage-run-2.md:6` reads "5 MEDIUM (#1, #2, #7, #8, #9), 7 LOW" with a correction note naming this audit. |
| LOW-001 — display sanitisers are blocklists | **Open** | bead bd-4iit; unchanged in the delta, by agreement. |

### [LOW-006] Freshness residuals: a future-dated timestamp is fresh forever, and the sprint-plan branch still passes an absent or unparsable one

- **Severity:** LOW · **Confidence:** high
- **File:** `.claude/hooks/compliance/implement-gate.sh:380` — `(( last_epoch > 0 && now - last_epoch <= 86400 ))`; and `:393-411`, the pre-existing sprint-plan branch (`if [[ -n "$last_activity" ]]` … `if [[ $now -gt 0 && $last_epoch -gt 0 ]]`).
- **Issue:** Probed with the real hook via `CLAUDE_PROJECT_DIR`: `state.json` RUNNING with `last_activity` 48 h ahead, or `2099-01-01T00:00:00Z` → allow; `simstim-state.json` 48 h ahead → allow; `sprint-plan-state.json` RUNNING + `plan_id` with no timestamp, with `not-a-date`, or 48 h ahead → allow (that branch skips its check when the timestamp is absent or fails to parse). The 24 h rule therefore bounds the past only, and the three branches disagree on absent/unparsable. The hooks-reference table is accurate for sprint-plan-state (it promises only "over 24 h asks"); the SDD amendment (d) sentence "all three heuristic state files require a `last_activity` under 24 h" overstates it. Same trust class as bd-taee (a Bash writer can stamp anything), so LOW and tighten-only to fix.
- **Fix:** bound both directions in `_ig_fresh` — `(( last_epoch > 0 && now - last_epoch <= 86400 && last_epoch - now <= 86400 ))` — and route the sprint-plan branch through `_ig_fresh` so absent/unparsable is stale there too; extend IG-22 with a future-dated leg per file and an absent-timestamp leg for sprint-plan-state; align the SDD sentence. Test-author note: GNU `date -d` parses `yesterday` (exactly 24 h: boundary allow) — use `not-a-date` for the unparsable leg.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html.

**Other checks on the delta.** `ledger.json`: sprint 250 `status: completed`, `completed 2026-10-07T04:47:07Z`. CHANGELOG `[Unreleased]` Fixed bullet for r250-9 names MED-001 / LOW-002 / LOW-003 / LOW-004 and IG-21 / IG-22 / FOPI. SDD D-4.4 amendment (d) is one sentence (the overstatement is noted under LOW-006). REPO-MAP and its `.checksum` regenerated. Nothing in the delta touches secrets, the catalog, the registry, the adapters or the dissent envelopes.

**Open counts at `e170de3d`:** 0 critical / 0 high / 0 medium / 2 low (LOW-001 bd-4iit; LOW-006). The trailer carries the open counts; the table at the top keeps the found-at-`005b9105` column for the record. Verdict unchanged: APPROVED - LET'S FUCKING GO. The `COMPLETED` marker written at round 1 stands; LOW-006 is a bead or a one-line follow-up at the lead's discretion, not a gate.

---

*Generated by Paranoid Cypherpunk Auditor Agent (Fable 5.1), unattended `/run sprint-plan`, audit round 1; addendum after round r250-9*

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":2},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-250","ts":"2026-10-07T05:25:00Z"} -->
