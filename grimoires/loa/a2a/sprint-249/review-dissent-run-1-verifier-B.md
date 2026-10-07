# r249 dissent triage, batch B (18 findings): `f4531477..41b783a1` (cycle-126 Sprint 3)

Verified read-only against HEAD 41b783a1 and base f4531477. The hook was run only in `mktemp -d` roots. `tests/unit/context-class.bats` passed 9/9 and `tests/unit/prompt-budget.bats` passed 9/9.

| n | voice | severity | verdict | one-line reason |
|---|---|---|---|---|
| 1 | claude-headless | ADVISORY | REAL (low) | `--model`, `--root` or `--catalog` as the last argument makes the hook loop forever (`timeout 3` → exit 124). No shipped caller does this, but the header promises it "never blocks" |
| 2 | claude-headless | ADVISORY | DECLINED | SDD §1.4.1/§97 specify one repo-level `.run/context-class` by design. Per-session keying is a follow-up, not a defect |
| 3 | claude-headless | ADVISORY | REAL (low) | Without a `timeout` binary (macOS without coreutils) the payload read fails silently and a Haiku-4.5 payload is classified `long (default)`. Reproduced. The repo already ships `compat-lib.sh` (timeout → gtimeout fallback) for this case |
| 19 | gpt-5.5-pro | BLOCKING | REFUTED | `generate-constraints.sh` has no `agent_teams_constraints` section (SECTIONS, lines 18–30), so there is nothing to regenerate. The block is byte-identical to base, and `c020-teamcreate` was a static label there too. The real issue is a pre-existing generator gap, covered under 21 |
| 20 | claude-headless | BLOCKING | REAL (gate) | AC "no gold case loses recall" fails on the pre-registered measure (5 cases) and also on the adjudicated one (audit-pr-02 1.000 → 0.963). The ablation tested only the include. Needs a recorded reviewer/auditor decision, not a code change. Merged with 24 and 28 |
| 21 | claude-headless | ADVISORY | DOC | True: the 5 C-TEAM `why` edits render nowhere, because the generator lacks the section and GB-1 cannot see it. The report and CHANGELOG say "twelve rationales tightened… re-rendered", but only 7 render |
| 22 | claude-headless | ADVISORY | DECLINED | Fail-to-`long` is the specified design (SDD §1.4.1 line 77; open question line 142). The fallback is recorded and shown (`basis=default`) |
| 23 | claude-headless | ADVISORY | DOC | (b) is real: the bare `tool-result-clearing.md` escapes `protocol-refs-resolve.bats` (it matches only `protocols/<name>.md`). Restore the 18-byte prefix. (a) is declined: the routing clause does not fit (planning-sprints has 32 B headroom), and the NOTES template carries per-section `Update at:` comments |
| 24 | claude-headless | BLOCKING | REAL (gate) | Same gate failure as 20. Also true: the CHANGELOG entry says nothing about the A/B outcome. Merged with 20 |
| 25 | claude-headless | ADVISORY | DECLINED | The 9,216 B cap is the SDD D-3.2 ratchet (old 10,240 minus the PRD KPI's 1,024 B). The always-on protocols WARN (131,078 > 114,688) is cosmetic: it is not a failure, and the old tier fired on every run too |
| 26 | claude-headless | ADVISORY | DECLINED | The charging rule has only ever charged SKILL.md → `resources/` reads. No protocol read (moved or not) was ever charged, and the protocol budget is a set total. Today no SKILL.md or CLAUDE.loa.md names `protocols/reference/` at all. A follow-up lint at most |
| 27 | claude-headless | ADVISORY | DECLINED | Same design as 22. The "no record that the class was a fallback" premise is false: the record holds `basis=default model=… context_window=null`, and `/loa` prints `Context: long (default; … LOA_CONTEXT_CLASS=standard for a ≤200K model)` |
| 28 | claude-headless | BLOCKING | REAL (gate) | Same gate failure as 20. One sub-premise is wrong: the ablation contradicts "the implicated change is the include" (graded ablate ≤ after on review-pr-02, review-pr-05 and audit-pr-05). Merged with 20 |
| 29 | claude-headless | ADVISORY | DOC | `ride.md:339-340` still says "attention budget" and "Yellow threshold (5k tokens)". Pre-existing text, but this diff made 5k disagree with the default `long` class (50K accumulated) |
| 30 | claude-headless | ADVISORY | REFUTED | Both size tables exist (`auditing-security/resources/REFERENCE.md:293-300`, `reviewing-code/resources/REFERENCE.md:175-183`). `parallel_threshold` is SKILL.md frontmatter (auditing-security:42 = 2000, reviewing-code:43 = 3000, implementing-tasks:17 = 3000), not a config key |
| 31 | claude-headless | ADVISORY | DECLINED | Same design as 22 and 27. SDD §1.4.1 fixes `long` as the default and the floor is the 1M generation (PRD G-3) |
| 32 | claude-headless | ADVISORY | DECLINED | Same as 2: a repo-scoped record by SDD. The subagent and mid-session `/model` cases are real limits worth a follow-up bead, not a defect in this diff |
| 33 | claude-headless | ADVISORY | DECLINED | The README's install path merges all of `settings.hooks.json`, which registers the hook (line 45), so the failure mode is false. The "Files → Active" table was already a stale subset at base (it omits implement-gate, zone-write-guard, run-state-surface, kf-surface…) |

**Counts:** REAL 5 (1, 3 as code; 20/24/28 as one gate issue) · DOC 3 (21, 23, 29) · REFUTED 2 (19, 30) · DECLINED 8 (2, 22, 25, 26, 27, 31, 32, 33).

---

## REAL

### 1: dangling value flag makes the hook loop forever

- **Evidence:** `.claude/hooks/session-start/loa-context-class.sh:32-34` uses `--root) ROOT="${2:-}"; shift 2 ;;` (and the same for `--model` and `--catalog`). With `$# == 1`, `shift 2` fails and shifts nothing. There is no `set -e` (line 24 is `set -uo pipefail`), so `while [[ $# -gt 0 ]]` spins on the same `$1`.
- **Reproduction (temp root):** `timeout 3 bash loa-context-class.sh --root $T --line --model </dev/null` → exit 124, and nothing is written to `.run`.
- **Reach:** no shipped caller passes a dangling flag. The hook-guard wiring passes no args, and `loa-status.sh:873` passes `--show`. That is why this is low.
- **Fix:** guard each value case, e.g. `--model) [[ $# -ge 2 ]] || break; MODEL="$2"; shift 2 ;;`. Do the same for `--root` and `--catalog`.
- **Test that fails first:** a CC case running `run timeout 5 bash "$HOOK" --root "$T" --model`, asserting `status -eq 0` and that `.run/context-class` reads `long`. Today it exits 124.

### 3: no `timeout` binary means the payload model is silently ignored

- **Evidence:** line 70 is `payload="$(timeout 2 cat 2>/dev/null || true)"`. A missing `timeout` is swallowed, so the payload is empty and the class falls to `long` with basis `default`. The repo's own portability helper, `.claude/scripts/compat-lib.sh:365-397` (timeout → gtimeout → fallback), exists for this macOS case. The suite's `stat -f %m` fallback (CC-7) shows macOS is a supported host.
- **Reproduction:** PATH limited to symlinks for bash, cat, jq, yq, git, sed, tr, grep, cut, mkdir, mktemp, mv, rm, date, dirname and head, with no `timeout`. Then `echo '{"model":"claude-haiku-4-5-20251001"}' | bash loa-context-class.sh --root $T --line` prints `Context: long (default; …)`. With `timeout` present, the same payload prints `Context: standard (model, claude-haiku-4-5-20251001; …)`.
- **Fix:** `if command -v timeout >/dev/null 2>&1; then payload="$(timeout 2 cat 2>/dev/null || true)"; elif command -v gtimeout >/dev/null 2>&1; then payload="$(gtimeout 2 cat 2>/dev/null || true)"; else payload="$(cat 2>/dev/null || true)"; fi`. Plain `cat` is acceptable as the last resort because the harness closes SessionStart stdin. Alternatively, a bash `read -t 2 -d ''` loop needs no external binary.
- **Test that fails first:** a CC case that builds a PATH dir without `timeout` (the symlink trick above) and asserts that a Haiku payload yields `standard`/`basis=model`.

### 20 / 24 / 28: the replay A/B acceptance criterion is unmet (gate issue, one finding)

- **Facts, all confirmed in `grimoires/loa/a2a/sprint-249/replay-ab.md`:**
  - The pre-registered gate fails on 5 cases.
  - The adjudicated column still loses on audit-pr-02 (1.000 → 0.963; the D06 miss is in run 4605c788 t2).
  - The report itself says "Decision: the change is not reverted… a disclosed deviation from the pre-registered remedy".
  - `sprint.md:144` (`- [ ] Replay A/B: no gold case loses recall`) is unticked.
  - The CHANGELOG sprint-249 entry does not mention the A/B outcome.
- **Sub-premises:**
  - 20 is correct that the ablation (c9b7bdc0) restored only the include. The other components (protocol moves, the CLAUDE.loa.md diet, the rationale cuts, the Phase −1 wording) were never ablated. replay-ab.md's "do not touch how a finding is cited" is an assertion, not a measurement.
  - 28's "the implicated change is the include (3K → 30K)" is contradicted by the same ablation. Graded ablate is at or below after on review-pr-02 (0.833), review-pr-05 (0.833) and audit-pr-05 (0.833).
  - 24's "same model family" adjudicator: the adjudicator was Opus 5.5 per replay-ab.md. The implementer's model is not recorded in the repo artefacts I read.
- **Why REAL and not REFUTED:** the AC is literally unmet under both measures. The resolution belongs to the reviewer and auditor, as the report itself invites. The implementer report cannot settle it.
- **Minimal resolution (no code needed):**
  1. The reviewer and auditor record an explicit decision in their feedback files. Either (a) a waiver naming the one adjudicated D06 slot on audit-pr-02 (1 of 27; ablate 0.944 is also below before), with bd-ewrc as the binding follow-up, or (b) apply the remedy.
  2. Add a one-clause note of the A/B outcome and the bd-ewrc dependency to the CHANGELOG sprint-249 entry.
  3. If (a) is not accepted, follow 20's option (b): component ablations at n=9 on the five cases.
- **Test that fails first:** it already exists. `~/.cache/loa/cycle-126-dissent/s3-pooled.py` exits 1 on the graded column. bd-ewrc's `eval-recall-grader.bats` cases (a leading `(`, continuation `:N` citations, multi-anchor D13) are the tests that must go red, then green, before a re-baselined A/B can turn the gate green honestly.

---

## DOC

### 21: the five C-TEAM rationale edits render nowhere

- **Evidence:**
  - All five C-TEAM constraints declare `layers: [{target: "claude-loa-md", section: "agent_teams_constraints"}]`.
  - `generate-constraints.sh` SECTIONS (lines 18–30) lists process_compliance_never/_always, task_tracking_hierarchy, merge_constraints and the skill sections, but no `agent_teams_constraints`.
  - So the block at `CLAUDE.loa.md:101-108` is hand-maintained under a "DO NOT EDIT — generated from .claude/data/constraints.json" marker. It is byte-identical at f4531477 and HEAD.
  - GB-1 (`generate-constraints.sh --dry-run`) cannot see it.
  - 7 of the 12 tightened rationales render (C-PROC-001, the TaskCreate row, review/audit, the /run row, /bug eligibility, Read-before-Write, /spiraling). The 5 C-TEAM rationales do not.
- **Minimal wording fix:** `reviewer.md:35` and the CHANGELOG should read "twelve constraint rationales are tightened in constraints.json (seven render into the NEVER/ALWAYS tables; the Agent Teams block is not generator-rendered)".
- **Follow-up (pre-existing gap, out of this sprint's scope):** add an `agent_teams_constraints|.claude/loa/CLAUDE.loa.md|claude-loa-md-table.jq|…` SECTIONS row. Rendering the new, longer `why` text would cost CLAUDE.loa.md bytes it does not have (17 B headroom), so either add a short-why variant or keep the block hand-maintained and change its marker.

### 23: the include's bare protocol name escapes the reference lint

- **Evidence:**
  - The include now says `` `tool-result-clearing.md` ``; base said `` `.claude/protocols/tool-result-clearing.md` ``.
  - `tests/unit/protocol-refs-resolve.bats:22` matches only `protocols/[A-Za-z0-9_-]+\.md`, so the bare name is unlinted.
  - The name is not ambiguous today: `find .claude -name tool-result-clearing.md` returns one file.
- **Fix:** restore the `.claude/protocols/` prefix (+18 B in each of the ten skills). The tightest is planning-sprints at 16,352/16,384 B, which would become 16,370 and still fit. Then run `generate-skill-includes.sh --write`.
- **Part (a) declined:** the routing clause (~45 B more) would breach planning-sprints. The NOTES.md template already carries `<!-- Update at: decision made… -->` under `## Decision Log` and `<!-- Update at: technical debt… -->` under `## Technical Debt` (`.claude/templates/NOTES.md.template:32-49`).

### 29: `/ride` still quotes the old 5k threshold

- **Evidence:** `.claude/commands/ride.md:339-340` reads "4. Monitor attention budget (advisory, not blocking)" and "5. Trigger Delta-Synthesis at Yellow threshold (5k tokens)". This text is unchanged by the diff, although the diff edited line 328 of the same file.
  - `context-engineering.md:24` records attention-budget zones as "deleted (cycle-121)".
  - Before this sprint, 5k matched the only (standard) accumulated threshold. After it, the default `long` class is 50K.
- **Fix:** replace both lines with one: "Synthesise to NOTES.md at the accumulated threshold for the class in `.run/context-class` (`.claude/protocols/tool-result-clearing.md`)."
