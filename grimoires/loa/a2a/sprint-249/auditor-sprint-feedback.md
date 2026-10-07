# Sprint 3 Security Audit Feedback (cycle-126, global sprint 249)

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1, `/audit-sprint sprint-3`)
**Date:** 2026-10-06
**Sprint Reference:** grimoires/loa/sprint.md — Sprint 3 "Context discipline and instruction diet" (FR-3, SDD §1.4 D-3.1 … D-3.3) and the new Task 4.8
**Implementation Report:** grimoires/loa/a2a/sprint-249/reviewer.md (Tasks 3.2–3.5, round s3-1a)
**Tree audited:** `feature/cycle-126-full-size` at `24fc1c7d`; sprint diff `f4531477..24fc1c7d` (60 files, +2,886 / −2,543); cycle base `2079e719`
**Prerequisites:** `engineer-feedback.md` opens with "All good" and its trailer reads `review APPROVED 0/0/1/5, excluded 0`; `adversarial-review.json` parses and carries `metadata.type: review`, `metadata.model: gpt-5.5-pro`, `metadata.head: 41b783a1`, 7 `merged_from_chunks`, 33 findings, `rejected_count 0`. The guardrail pre-check (`guardrails-orchestrator.sh --skill auditing-security --mode interactive --file …`) proceeded. The cross-model **audit** dissent is the lead's and was running from this checkout during this audit: `adversarial-audit.json` does not exist yet (a moved-aside `.prev` and the first chunk, `adversarial-audit-h-hook.json`, do) — I did not run it and did not wait for it; § "Dissent status" below.

---

## Verdict: APPROVED - LET'S FUCKING GO

---

## Executive Summary

Sprint 3 adds a SessionStart hook that records the context class, a `/loa` line that shows it, a two-class thresholds table that the ten skills' `context_discipline` include now cites, a diet of the always-loaded surface (five reference protocols moved behind stubs, `CLAUDE.loa.md` 10,225 → 9,199 B, twelve constraint rationales tightened), and one sentence in place of three skills' line-count parallelism choreography. I read the hook, `hook-guard.sh`, both settings files, `loa-status.sh`'s display function, the constraints diff, the `CLAUDE.loa.md` diff, the include, the protocol table, the five stubs against the moved originals, the three skills' diffs and their resources, the two edited bats suites, the replay report, the adjudication records and the grader source — not the reports alone — and I ran the sprint's own suites here (context-class 13/13, prompt-budget 9/9, skill-includes 7/7, hook-wiring 10/10, protocol-refs-resolve 3/3, dead-recall-relabel 6/6), the three AC lints (`generate-skill-includes.sh --check` current; `check-prompt-budget.sh` exit 0 at 9,199 B / 131,164 B; `generate-constraints.sh --dry-run` zero diff lines; `marker-utils.sh verify-hash` VALID) and twelve hook probes in `mktemp -d` roots.

**The diet removed no enforcement text.** Mechanically: the 17 `| NEVER … | / | ALWAYS … | / | MUST … |` rule cells of `CLAUDE.loa.md` are byte-identical before and after (`diff` of the extracted first columns is empty); `constraints.json` is identical once every `why` key is deleted (`jq walk(del(.why))` on both revisions, `diff` empty); the section headers are identical; the C-PROC-001 rationale still names implement-gate's fail-ask, the `disallowed-tools` strip, the adversarial gates and the Bash-path gap (`CLAUDE.loa.md:52`); no SKILL.md, hook, include or `CLAUDE.loa.md` names a moved protocol (repo grep: the only non-stub consumers are `check-loa.sh:386`, three tests, and the pointer rows), and each stub keeps what those tests pin (`recommended-hooks` §4, the session-continuity tier table, the constructs-integration path). The three skills lost a size-classification heuristic and a "MUST split at LARGE" line — workload choreography, not a control; the `REFERENCE.md` size tables and the `assess-*.sh` helpers remain for a lead who wants numbers.

**The hook is safe but its detection is not yet true on this host.** Never-block holds under every input I tried (dangling flags, closed stdin, open stdin without `timeout`, a 32 MiB payload in 0.8 s, `.run` a file, `.run` unwritable, a record symlinked to `/etc/hostname` — replaced, target intact); the `--line`/`--json`/record sinks carry only the `[A-Za-z0-9._:-]` id; the write is `mktemp` + `mv -f`; through `hook-guard.sh` the payload reaches the hook and stdout is empty. Two mediums remain, both functional, neither a security defect: (1) the id shape this host's harness actually emits — the live record in this repository reads `model=global.anthropic.claude-opus-5-5 context_window=null basis=default` — is not resolved, so a Bedrock-backed 200K session gets the `long` class; (2) the hook fires on every SessionStart source (`matcher ""`; `once` is documented as ignored in settings files) and the harness omits `model` after `/clear` and on conversation recovery, so a correct `standard` record is overwritten with `long/default` mid-session. Both have a one-screen fix and a test shape; neither reaches the one-way rule.

**Replay A/B.** I rule independently and **concur** with the review's waiver (option a), with three conditions of my own added below.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 2 |
| Low | 4 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

None.

---

## Medium/Low Priority Issues

### [MED-001] The model id shape this host's harness emits is not resolved — a Bedrock-backed 200K session runs the `long` thresholds
- **Severity:** MEDIUM · **Confidence:** high (mechanism probed; the id shape is the one in this repository's live record)
- **File:** `.claude/hooks/session-start/loa-context-class.sh:89` (`m="${m#anthropic:}"; m="${m#openai:}"; m="${m#google:}"` — the only normalisation), `:90-93` (alias then exact-key lookup), `:48-50` (`_print_line` for `long` prints no model); `.claude/defaults/model-config.yaml` (the only ≤ 200K entries are `claude-sonnet-4-5-20250929` and `claude-haiku-4-5-20251001`; the only Bedrock-shaped aliases are the `us.anthropic.…-v1:0` family — no `global.`, `eu.`, `apac.` or bare `anthropic.` form)
- **Issue:** The Claude Code hooks reference lists `model` on the SessionStart input ("the active model identifier … can be omitted"), and the record this session's own SessionStart wrote at the repository root is `long` / `basis=default model=global.anthropic.claude-opus-5-5 context_window=null ts=2026-10-05T21:34:04Z` — the harness supplied a model and the hook could not place it. Probe table (scratch root, `--json`): `global.anthropic.claude-haiku-4-5-20251001-v1:0` → `long/default`; `anthropic.claude-haiku-4-5-20251001-v1:0` → `long/default`; `global.anthropic.claude-sonnet-4-5-20250929-v1:0` → `long/default`; `claude-haiku-4-5` → `long/default`; only `us.anthropic.claude-haiku-4-5-20251001-v1:0` (an explicit alias) and the bare dated id resolve to `standard/model`. For the 5-family this is harmless (`long` is right); for a 200K model reached through a Bedrock global or regional inference profile — the shape this operator's `claude-bedrock` fallback uses — the skills follow 150K-session / 30K-file thresholds inside a 200K window. Before this sprint that session ran the standard thresholds, so for that population the sprint loosens discipline tenfold, silently: the `long` line names no model, so `/loa` cannot distinguish "no model seen" from "model seen, unresolved". SDD D-3.1's fail-to-`long` is for *unknown* ids; the two known 200K models under their production id shape are not what it accepted. The AC "a 200K session model selects `standard`" is met only for the synthetic bare id CC-3/CC-4 feed the hook.
- **Fix:** normalise before the catalog hop — strip a leading inference-profile segment (`^(global|us|eu|apac|[a-z]{2}(-[a-z0-9]+)*)\.anthropic\.` and `^anthropic\.`) and a `-v[0-9]+:[0-9]+$` suffix, then fall back to the longest catalog model key that is a prefix of the remainder; or add the `global.`/`eu.`/`apac.` alias rows beside the `us.` ones. Print the unresolved id in the `long` line (`long (default; model global.anthropic.… unresolved)`). Pin with a CC case fed the live record's shape: `global.anthropic.claude-haiku-4-5-20251001-v1:0` → `standard/model`, `global.anthropic.claude-opus-5-5` → `long/model` (not `default`).
- **Reference:** CWE-684 Incorrect Provision of Specified Functionality — https://cwe.mitre.org/data/definitions/684.html

### [MED-002] A SessionStart re-fire without a `model` overwrites a correct `standard` record with `long/default`
- **Severity:** MEDIUM · **Confidence:** high on the mechanism (code, wiring and the harness docs agree); not live-triggered here (I cannot `/clear` a session from this audit)
- **File:** `.claude/settings.json:514` and `.claude/hooks/settings.hooks.json:45` (both SessionStart blocks have `matcher: ""` — every source: startup, resume, clear, compact, fork — and `"once": true`); `.claude/hooks/session-start/loa-context-class.sh:97` (`CLASS="long"; BASIS="default"` whenever no env and no model), `:112-118` (the record is written unconditionally on every run)
- **Issue:** The hooks reference states that `once` is "only honored for hooks declared in skill frontmatter; ignored in settings files and agent frontmatter", and that SessionStart's `model` "can be omitted, for example after `/clear` or when a session is restored through conversation recovery, so check for the field before reading it". The hook does neither: `once` is inert where it is declared, so the hook runs on each SessionStart event, and when the payload carries no `model` the selection falls to `long/default` and `:112-118` replaces whatever the record held. Scenario: a `claude-haiku-4-5-20251001` session starts → `standard/model`; the user runs `/clear` (or the session is recovered) → the hook fires with no `model` → the record becomes `long/default`; every skill loaded afterwards reads `long` thresholds in a 200K window, and `/loa` shows "long (default; …)" with no trace that a `standard` record was replaced. This is a single-session defect, distinct from the declined "one record per checkout / mid-session `/model`" items (A#14, B#2, B#32), and it would survive a MED-001 fix. Collateral: the CHANGELOG, `hooks/README.md`, `hooks-reference.md` and CC-8 describe a "once" behaviour that does not occur; CC-8 asserts the inert key.
- **Fix:** write only when the new basis is at least as strong as the recorded one (`env` ≥ `model` > `default`): with no env override and an empty `MODEL`, if `.run/context-class` already reads `basis=model` (or `basis=env`), print and exit without writing — the hook already parses that line at `:58-62`. Drop the `once` key (or document it as inert) and let CC-8 assert the matcher instead. Pin with a CC case: write a `standard/model` record, run the hook with an empty payload (`{"source":"clear"}`), assert the record still reads `standard`.
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [LOW-001] The alias target is interpolated into the second yq expression unsanitised — a catalog alias controls the class through expression injection
- **Severity:** LOW · **Confidence:** high (demonstrated); the precondition is write access to the System Zone, which already yields code execution through the hook itself
- **File:** `.claude/hooks/session-start/loa-context-class.sh:90-93` — `target="$(yq eval ".aliases.\"$m\"" …)"`, `m="${target#*:}"`, then `yq eval "[.providers[].models.\"$m\".context_window | select(. != null)] | .[0]"`
- **Issue:** `MODEL` is whitelisted to `[A-Za-z0-9._:-]` at `:83` before the first hop, but the alias value read back from the catalog is not re-whitelisted before the second. Probe (scratch root, `--catalog` a crafted file with `evil: 'p:x" | {"y": {"context_window": 100}} | ."y'`): `--model evil --json` → `{"class":"standard","basis":"model","model":"evil","context_window":100}` — the alias text ran as yq and chose the class; the same string through `--model` is stripped to `xy:context_window:100.y` and resolves to nothing (the first hop is closed, CC-6). mikefarah yq v4 (v4.44.1 here) also exposes `load()`/`strenv()`, so the hop can read files, but the result is consumed only if it matches `^[0-9]+$` — a one-bit oracle plus class control. The catalog is `.claude/defaults/model-config.yaml` (System Zone, listed in `checksums.json`) and `--catalog` is argv from tests only, so no external input reaches this hop; defence in depth. The lead's in-flight audit dissent chunk `adversarial-audit-h-hook.json` reports the same hop as its one LOW (`DISS-C-001`); I concur with its severity.
- **Fix:** after `:91`, `m="${m//[^A-Za-z0-9._:-]/}"; [[ -n "$m" ]] || { echo ""; return 0; }` — or avoid interpolation altogether: `M="$m" yq eval '[.providers[].models[strenv(M)].context_window | select(. != null)] | .[0]'`.
- **Reference:** CWE-917 Improper Neutralization of Special Elements used in an Expression Language Statement — https://cwe.mitre.org/data/definitions/917.html

### [LOW-002] The protocol's "never load a > 1,000-line file whole" edge case was not made class-scoped (PRD FR-3.1) and now contradicts the `long` row of its own table
- **Severity:** LOW · **Confidence:** high
- **File:** `.claude/protocols/tool-result-clearing.md` § Edge Cases item 2 — "**Single large file** (>1000 lines): never load whole; `Read` with offset/limit, synthesize only the relevant ≤50 lines" (unchanged from `f4531477`; the sprint diff touches only the thresholds table and the Related list); `grimoires/loa/prd.md:143` — "the 'never load a >1,000-line file' edge case becomes class-scoped"
- **Issue:** Under the default `long` class the same file's table now permits a full-file load up to 30,000 tokens (`:17`), and the include tells the ten skills "long … 30K full file"; a 1,000-line source file is roughly 10–15K tokens, so the edge case forbids what the table allows. A model following the edge case under `long` extracts where it could read; one following the table ignores the edge case. The PRD asked for the scoping explicitly and neither AC 2 nor the review checked it.
- **Fix:** "(> 1,000 lines under `standard`, > 10,000 under `long` — or above the class's full-file row)". One line; `check-prompt-budget.sh` has 28 KB of protocol headroom.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-003] `/loa` writes `.run/context-class` when no record exists — a status command writes state that C-TEAM-003 reserves for the lead
- **Severity:** LOW · **Confidence:** high (mechanism); negligible impact (one word, sanitised meta, atomic, idempotent)
- **File:** `.claude/scripts/loa-status.sh:870-876` (`bash "$hook" --show`), `.claude/hooks/session-start/loa-context-class.sh:67` (`[[ "$MODE" == "show" ]] && MODE="line"` when no record) and `:112-118` (the write); `reviewer.md:126` records the choice as deliberate
- **Issue:** `CLAUDE.loa.md` Agent Teams: "MUST only let team lead write to `.run/` state files". A teammate's `/loa` in a fresh checkout (no SessionStart record — e.g. a worktree) writes `.run/context-class`. The content is harmless and the write atomic, so this is the letter of the rule, not a data-loss path — but a status command that writes is the kind of exception that gets copied.
- **Fix:** in `--show` with no record, compute and print without writing (a `WRITE=0` flag around `:112-118`); the SessionStart hook stays the only writer. CC-7's second half changes from "writes `long`" to "prints `long`, writes nothing".
- **Reference:** CWE-710 Improper Adherence to Coding Standards — https://cwe.mitre.org/data/definitions/710.html

### [LOW-004] The parallelism sentence cites `parallel_threshold`, a number with no unit, no reader, and values that disagree with the size tables the pointers cite
- **Severity:** LOW · **Confidence:** high; documentation only
- **File:** `.claude/skills/auditing-security/SKILL.md:162` / `:42` (`parallel_threshold: 2000`), `.claude/skills/implementing-tasks/SKILL.md:223` / `:17` (3000), `.claude/skills/reviewing-code/SKILL.md:202` / `:43` (3000); `.claude/scripts/skills-adapter.sh:173` (the only mention of the key outside skills — a comment); `auditing-security/resources/REFERENCE.md:298-300` (SMALL < 2,000 / MEDIUM 2,000–5,000 / LARGE > 5,000 "MUST split")
- **Issue:** "Parallelise (`parallel_threshold`) when the scope warrants; the lead decides" points the lead at a frontmatter integer whose unit is unstated and which nothing mechanical reads; for `auditing-security` the value (2,000) is the table's SMALL/MEDIUM boundary, not its split boundary (5,000). Not a lost guard — the removed text was a heuristic — but the one sentence that replaced it should say what the number is.
- **Fix:** "(`parallel_threshold` lines of in-scope source; size table in `resources/REFERENCE.md`)" or drop the parenthetical; align the three frontmatter values with the tables or remove them.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

---

## The hook, read (`loa-context-class.sh`, 127 lines) and probed

Every probe ran with `--root` in a `mktemp -d` directory; the repository tree was not touched (`git status` clean after).

| Surface | What I checked | Result |
|---|---|---|
| Untrusted payload (`:70-82`) | stdin read only when not a terminal; `timeout` → `gtimeout` → `read -r -d '' -t 2`; `jq -r` accepts `.model` / `.model_id` / `.model_name`, string or `{id,name}` object | array `["claude-haiku…"]`, number `12345`, nested `{"id":…}`, `not json`, empty, closed fd 0 — all exit 0; the array and nested forms resolve, the number falls to `long` |
| Sanitisation before yq (`:83`) | `${MODEL//[^A-Za-z0-9._:-]/}` runs before `:90` and `:93` and before the record | `clé"ude-opus-5;x` → `clude-opus-5x`; CC-6's `;rm -rf x` case green; bash 5.2 with `globasciiranges` on (this host has no non-C locale installed, so the locale leg was vacuous — pin `LC_ALL=C` around the expansion if macOS bash 3.2 is a target) |
| Second hop (`:90-93`) | alias target interpolated raw | **LOW-001** |
| Injection into the record / `/loa` (`:115`, `:48-54`, `:58-62`) | `basis` and `model` re-parsed from the record through `[a-z]*` / `[A-Za-z0-9._:-]*`; `--json` via `jq --arg`; hook mode prints nothing | CRLF record → read correctly; record `basis=env` → `Context: standard (env; …)`; through `hook-guard.sh` with a payload: `bytes_out=0`, record written |
| Symlink / TOCTOU (`:112-118`) | `mktemp` in `$ROOT/.run` + `mv -f`; `rm -f` on failure | record symlinked to `/etc/hostname` → `--show` recomputed, `mv -f` replaced the link, `/etc/hostname` intact; `.run` a symlink to another dir → the record lands in the target (pre-existing class shared by every `.run/` writer, not this sprint's); `.run` a regular file → no write, line printed, exit 0; no `.context-class.*` leftovers |
| Never-block | `set -uo pipefail` (`:24`); `[[ $# -ge 2 ]] \|\| break` (`:33-35`); the three-stage read | `--model`/`--catalog`/`--root` last → exit 0 (CC-10); `< <(sleep 30)` without `timeout` → returns (CC-13); 32 MiB payload → 0.81 s, `standard/model`; catalog `context_window: 99999999999999999999` → `long/model` (bash saturates the comparison; `--json` prints the literal) |
| Behind `hook-guard.sh` | `bash -n` then `exec`, stdin intact, args forwarded (`hook-guard.sh:56`) | confirmed; the WARN text says "PreToolUse" for a SessionStart hook (review LOW 6, stands) |
| Settings wiring | both files, behind the guard, `matcher ""`, `"once": true` (CC-8) | present in both; `once` inert per the hooks reference → **MED-002**; `hooks/README.md:22` and `hooks-reference.md:176` rows present |
| Id resolution (`:89-94`) | prefix strip + alias + exact key | **MED-001** |
| `LOA_CONTEXT_CLASS=Standard` | `:98-101` case-sensitive | ignored → `long/default` (review LOW 2, stands; folded into Sprint 4) |

`display_context_line` (`loa-status.sh:870-876`): `bash "$hook" --show < /dev/null 2>/dev/null || true`, indented two spaces, after `display_run_line` (`:674`); CC-9 drives it against a hand-written record. The only writer of `.run/context-class` is the hook (`grep` over `.claude/scripts` and `.claude/hooks`). `.run/` is gitignored (`.gitignore:85`), so no clone ships a record.

## The instruction diet, verified

- **Rule text.** `grep -E '^\| (NEVER|ALWAYS|MUST) '` over `CLAUDE.loa.md` at `f4531477` and `24fc1c7d`, first column extracted: 17 cells each, `diff` empty. `constraints.json`: `jq -S 'walk(if type=="object" then del(.why) else . end)'` on both revisions, `diff` empty — the twelve hunks are `why` only. Section headers (`grep '^#'`): identical. Golden tables re-rendered; `generate-constraints.sh --dry-run` emits zero diff lines; kernel hash `VALID`.
- **C-PROC-001 rationale** (`CLAUDE.loa.md:52`): "Fences: implement-gate.sh fail-asks Write/Edit App-Zone writes outside /implement//bug; disallowed-tools strips pure-review skills' write tools; the adversarial gates. Bash-path App-Zone writes stay review-territory." Every fence named before is named after; what went was "(accepted fence gap, same class as the spiral guard's)" and the "Mechanical stack:" label.
- **What left the always-loaded surface.** The Reference Files table (12 rows → one line, all 12 names kept), the truenames table (7 rows → one line, every command kept including `/audit-sprint`), and "memory lives in `grimoires/loa/NOTES.md`" — the Task Tracking Hierarchy row still says `grimoires/loa/NOTES.md | Observations, blockers, cross-session memory`. Nothing a fence or skill reads by path moved out of `CLAUDE.loa.md`.
- **Moved protocols.** `constructs-integration` and `recommended-hooks` byte-identical under `reference/`; `helper-scripts` 2 repointed lines; `trajectory-evaluation` 3 (the bare `> 2000` → the class row, a pointer, `delta_sync` wording); `session-continuity` 4 (Level 2 fallback and recipe, the Yellow threshold → the class row). No rule removed. Consumers outside `reference/` (repo grep over hooks, scripts, commands, skills, loa, data, templates, tests, workflows, tools): `check-loa.sh:386` (existence), `notes-template.bats:155,269`, `dead-recall-relabel.bats:12,28`, `test_constructs_e2e.bats:524` (existence) — every one satisfied by its stub (stubs 230–678 B; `recommended-hooks` keeps §4, `session-continuity` the tier table with Level 2 now agreeing with the reference). No SKILL.md names a moved file; the skill tree's one pointer (`reviewing-code/impact-analysis.md:502`) is repointed. `validate-ck-integration.sh:96` reads the moved file. `loa-eject.sh:596` and `migrate-skill-names.sh:144` glob `.claude/protocols/*.md` only — the moved files carry no `@loa-managed` marker, so eject is unaffected (reviewer.md:124, confirmed).
- **Budget tool.** `tools/check-prompt-budget.sh:53` constants `16384, 9216, 160000, 114688`; PB-4/PB-5/PB-6 pin them and PB-5 pins that `reference/` is not counted — the limits tightened, the tests tightened with them. `skill-includes.bats` tests 4–5 re-anchor the tamper string to the new include text; the DRIFT/REPAIR assertions are unchanged.
- **Pre-existing red** claimed at reviewer.md:85: `test_process_compliance.bats` greps "NEVER write application code outside of", "NEVER skip from sprint plan directly to implementation", "ALWAYS use.*run sprint-plan.*or.*run sprint-N", "ALWAYS check for existing sprint plan before writing code" — count 0 in `CLAUDE.loa.md` at `f4531477` and at `24fc1c7d`. Pre-existing, as stated.
- **The include** (494 B) names `.run/context-class`, the selection rule, both threshold rows and the full protocol path (CC-9; `protocol-refs-resolve` sees it); ten skills regenerated, `--check` current; the tightest skill is `planning-sprints` at 16,370 / 16,384 B.
- **Edge case 2** of the protocol was not class-scoped — **LOW-002**.

## The three skills' parallelism change

Removed: `auditing-security` Phase −1's `*.{ts,js,tf,py}` line count with SMALL/MEDIUM/LARGE bands; `implementing-tasks` Phase −1's `wc -l` over the planning docs with its bands; `reviewing-code` Phase −1's line count with "over 6,000 LARGE (MUST split)". Added in each: "Parallelise (`parallel_threshold`) when the scope warrants; the lead decides" plus a one-clause pointer to the existing split resource. Nothing removed was a control: no zone rule, no gate, no verdict logic, no tool restriction (`allowed-tools`/`disallowed-tools` frontmatter unchanged in all three). `<parallel_execution>` blocks keep their consolidation rules; `PARALLEL-SPLIT.md:3` and `PARALLEL-REVIEW.md:3-4` now point at `REFERENCE.md` tables that exist (`auditing-security/resources/REFERENCE.md:293-300`, `reviewing-code/resources/REFERENCE.md:175-183`). `grep 'wc -l'` over the three SKILL.md files is empty (AC 4). The one residue is **LOW-004**.

## Replay A/B (AC 3) — independent ruling: **concur** with the review's waiver, with three audit conditions

**What I verified myself.** `~/.cache/loa/cycle-126-dissent/s3-pooled.py` re-run: the table equals `replay-ab.md:25-68` line for line; the graded column loses on review-pr-02 / review-pr-05 / audit-pr-02 / audit-pr-03 / audit-pr-05 at n = 9. `adjudication.json`: 44 slot records plus `_defects`; per arm the `missed` verdicts are before `9f274235` D21 ×2 + `d84e5ef2` D18 ×1, after `4605c788` D21 ×2 + D06 ×1 (`audit-pr-02 t2`: "a safe, correctly-scoped narrowing … no problematic consequence flagged"), ablate `4c816102` D06 ×1 — three real misses per arm, D21 twice in each. Both arms carry a borderline D06 `found` on the same case (`51adc68a t3`, `4605c788 t1`), as the review says. The grader defect is in code, not asserted: `evals/graders/recall-vs-defects.sh:62` `CITE = r'([A-Za-z0-9_./+()-]+\.[A-Za-z0-9]{1,6}):(\d{1,6})…'` puts `(` and `)` in the path class, so `(base/…sh:803-811)` yields the path `(base/…` which `path_matches` (`:71-76`, strips `head/`/`base/` only as a prefix) can never match; the pattern binds one `:line` per path, so `:776,807` and bare `:703` credit nothing; `:81` reads one `anchor_line` per defect. All three mechanisms the report names, confirmed.

**Why not overturn.** The pre-registered rule is unmet, and SDD §1.4.3 says a drop "blocks the sprint". The case for enforcing it literally is that rules resist post-hoc rationalisation and that the party proposing the instrument fix is the party that failed the gate. Against it: the deviation was disclosed, not applied silently (`replay-ab.md:21`, `reviewer.md:97-106`); the instrument's defect is verifiable in source (above) and explains 38 of 44 graded misses; on a rule applied identically and blind to arm the real-miss totals are equal (3 and 3) with the same defect (D21) missed twice in each arm; the one differing slot per arm is a swap on different defects, not a directional loss; the only component with a plausible detection mechanism (the include's thresholds) was ablated and the graded loss persisted without it; the remaining un-ablated deltas are process text (the two collapsed tables, the rationales, Phase −1) in a prompt tree whose review/audit skills never load the moved protocols, and both arms ran single-model with no subagents (`reviewer.md:115`), so Phase −1 is inert for the eval. Overturning would block Sprint 3's marker until bd-ewrc lands — which is exactly Task 4.8, and nothing in Sprint 4 Tasks 4.1–4.7 depends on its outcome, while the re-run's after arm will in any case be the branch head that is proposed for merge. The review's binding conditions put the real gate (both arms on a fixed grader, n ≥ 9, before the cycle PR merges, with a component ablation and revert remedy) where it belongs, and `sprint.md:203` now carries it as Task 4.8 with the pre-merge wording. The residual risk is the review's MEDIUM (Observation 1); it stands, carried by the conditions.

**Audit conditions, added to the waiver record** (the lead folds them into Task 4.8; I have edited nothing):
1. **Pre-register the adjudication rule before the re-run** — including how a "framed deliberate, but raised as finding" slot scores — in the Task 4.8 report, so the re-run cannot inherit this round's post-hoc latitude. The fixed grader must also agree with the adjudication within one slot per case; if it does not, the grader is not fixed and the gate is not green.
2. **Make the ablation evidence reproducible.** `c9b7bdc0` exists only on this host. Preserve it as a patch under `grimoires/loa/a2a/sprint-249/` (or a tag on the branch) together with the `~/.cache/loa/cycle-126-dissent/` scripts the report cites (`s3-pooled.py`, `cite-probe.py`, `adjudication.json`), so a third party can rebuild the ablate arm and the table; the waiver rests on them and a host reboot clears `/tmp`-class scratch (the operator's own KF record says so).
3. **AC 3's tick stays qualified.** `sprint.md:144` reads `[x]` with the ruling beneath; keep the ruling text attached to the criterion until the Task 4.8 re-run passes, and if it fails, flip the tick back before the revert, not after.

## Dissent status

Phase 1C is the lead's for this sprint: the cross-model audit dissent was in flight from this checkout while I audited, I did not launch, re-run or wait for it (cap ≤ 3 runs/sprint; KF-037 host contention), and `adversarial-audit.json` does not exist beside this file yet — `adversarial-audit.json.prev` (3,779 B) and the first chunk envelope `adversarial-audit-h-hook.json` do. I read that chunk: `metadata.type audit`, `model gpt-5.5-pro`, `status clean`, companion `claude-headless` succeeded, `rejected_summary []`, one finding — `DISS-C-001` LOW on the unsanitised alias hop, which is my LOW-001. The lead triages the finished envelope; nothing in this file depends on it. Self-check: `verdict-derive.sh --file <this> --gate audit --review-file …/engineer-feedback.md` reports `CONSISTENT: gate=audit verdict=APPROVED` (exit 0) with the default envelope path absent, and `consistent: true` with `--envelope` pointed at the h-hook chunk; the lead should re-run it once the merged envelope lands, because its rejected rows then count against § "Rejected dissent payloads".

## Review observations, confirmed (not re-tallied)

The review trailer's `excluded` is 0, so `excluded_confirmed` is 0. Its MEDIUM (residual recall risk under the waiver) stands as written and is carried by the waiver conditions plus mine. Its LOWs stand and are already folded into Sprint 4 per `NOTES.md:59`: `LOA_CONTEXT_CLASS` case-sensitive (reproduced: `Standard` → `long/default`); `protocol-refs-resolve.bats:22` regex blind to `protocols/reference/`; the CHANGELOG's 131,078 B (measures 131,164 B here; the CHANGELOG also says "CC-1 – CC-12" where 13 cases exist); KF-006's header `≥7` against its own correction row (`known-failures.md:511` vs `:527`); `hook-guard.sh:47`'s "PreToolUse" wording.

## Scope limits

- No `documentation-coherence-*` report exists for sprint-249 under `grimoires/loa/a2a/subagent-reports/`; I verified the documentation manually: the CHANGELOG `[Unreleased]` FR-3 entry (complete, with the A/B outcome and bd-ewrc; two stale figures noted above and the "once" claim per MED-002), `hooks/README.md` and `hooks-reference.md` rows, `protocols-summary.md`'s `reference/` note and five rows, `scripts-reference.md`, `context-engineering.md`, `PROCESS.md`, the NOTES template, `ride.md:328,339-340`. No security-critical code is uncommented; no secret or internal URL entered a doc.
- Probes ran only in `mktemp -d` roots and against crafted catalogs passed by `--catalog`; no eval, provider CLI, `adversarial-review.sh` or `br` was run; the six permitted suites ran serially; `git status` is clean.
- MED-002 is argued from the hooks reference, the matcher and the code path, not from a live `/clear`; MED-001 is argued from this repository's live record and a probe table.
- The locale leg of the sanitisation probe was vacuous on this host (no `en_US.UTF-8` installed).

## Rubric (sprint surface)

SEC-IV 4 (the id is whitelisted before every sink; the alias hop is the residue — LOW-001), SEC-IN 4 (one expression-injection hop behind a System-Zone-only source), SEC-CI 5 (nothing secret touches this sprint; `.run/` ignored), SEC-AV 5 (never-block holds under every input tried), CQ-TC 4 (13 red-first cases; the production id shape and the re-fire path are untested — MED-001/002), CQ-DC 3 (edge case unscoped, `once` described as live, `parallel_threshold` unexplained, two stale CHANGELOG figures), ARCH 4 (one writer, one record, one table; the status-command write is the exception — LOW-003).

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added — none in the hook, the settings, the tests or the docs
- [x] Input validation on all new entry points — the payload id whitelisted at `:83` before yq, the record, `--line` and `--json`; the record re-parsed through character classes on `--show`; argv flags guarded against a dangling value
- [x] Authentication required where needed — n/a (no credential, no network)
- [x] No injection paths from untrusted input — the payload hop is closed (CC-6, probed); the alias hop is System-Zone-only (LOW-001, defence in depth)
- [x] Error handling doesn't leak — every failure path is `long/default` with the sanitised id in the record; hook mode prints nothing; stderr silenced
- [x] Tests cover security paths — CC-6 (sanitisation), CC-10/11/13 (never-block), CC-1 (no temp leftovers), CC-7 (`--show` never rewrites), CC-8 (wiring); gaps: the production id shape, the re-fire-without-model path, the alias hop (MED-001, MED-002, LOW-001 each name the case to add)

---

## Rejected dissent payloads

None — no `adversarial-audit.json` exists beside this file yet (the audit dissent is in flight; its first chunk `adversarial-audit-h-hook.json` reads `rejected_summary []`, `rejected_count 0`, companion `succeeded`), and no `adversarial-rejected-audit*.jsonl` sidecar exists beside this file.

---

## Next Steps

1. Sprint 3 is cleared on the one-way rule (0 critical / 0 high): after triaging the audit dissent the lead writes the COMPLETED marker and closes ledger 249.
2. Carry into Sprint 4 (none blocks the marker; MED-001 and MED-002 should land before the cycle PR — they are the difference between a class that is detected and one that is only declared): MED-001 id normalisation + the live-shape CC case; MED-002 keep-the-stronger-basis write rule + drop or document `once` + the empty-payload CC case; LOW-001 re-whitelist the alias target; LOW-002 scope edge case 2; LOW-003 `--show` never writes; LOW-004 name the unit.
3. Task 4.8 absorbs the three audit conditions on the A/B waiver (pre-registered adjudication rule and grader/adjudication agreement; the ablation commit and scripts preserved under the a2a dir; the qualified tick).

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":2,"low":4},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-249","ts":"2026-10-05T22:50:00Z"} -->
