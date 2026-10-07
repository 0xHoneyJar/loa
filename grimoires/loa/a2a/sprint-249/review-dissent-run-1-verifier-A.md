# r249 dissent triage, set A (15 findings): cycle-126 Sprint 3, `f4531477..41b783a1`

Verified read-only against HEAD `41b783a1` and base `f4531477`. Bats is not on PATH on this host, so no bats were run. The premises were checked by grep, read and a direct hook probe.

| n | voice | severity | verdict | one-line reason |
|---|---|---|---|---|
| 4 | claude-headless | ADVISORY | DOC | The stub's "keeps … its anchors stable" overstates: constructs-integration keeps only the H1. No `#fragment` link into any moved file exists, so nothing breaks. |
| 5 | gpt-5.5-pro | BLOCKING | REFUTED | citations.md is intact. The diff is a one-line repoint (`git diff` shows 1+/1−). The hunk shown belongs to helper-scripts.md, so the tool mislabelled it. |
| 6 | claude-headless | ADVISORY | DECLINED | The gate-failure facts are true and disclosed in reviewer.md and replay-ab.md for review/audit to rule on. The "format regression from the protocol move" premise is refuted (see §12). |
| 7 | claude-headless | ADVISORY | REFUTED | Same mislabelled hunk as n=5. citations.md has the Word-for-Word protocol intact, and only line 227 changed. |
| 8 | claude-headless | ADVISORY | DOC | Same overstatement as n=4. A fragment link would not be caught, but none exists (repo-wide grep finds 0). The §4 duplicate is pinned only at the stub path. |
| 9 | claude-headless | ADVISORY | REFUTED | update.sh `generate_checksums` uses a recursive `find .claude -type f`, and checksums.json lists all 5 `protocols/reference/*.md`. mount symlinks the whole `.claude/protocols` dir. |
| 10 | claude-headless | ADVISORY | REFUTED | The session-continuity stub has no threshold number. The reference's Yellow line (:123) was repointed to the class table. Only the example `tokens: 5000` remains, covered in n=16. |
| 11 | gpt-5.5-pro | BLOCKING | REFUTED | Mislabelled hunk again, this time the session-continuity stub. citations.md is intact. |
| 12 | claude-headless | BLOCKING | DECLINED | The AC is unmet as pre-registered, and SDD §1.4.3 says a drop "blocks the sprint". That is already disclosed as a deviation for review/audit. The causal premise is refuted: the review/audit skills never load the moved protocols, and the before arm shows the same citation forms. |
| 13 | claude-headless | ADVISORY | DECLINED | `long` by default is SDD D-3.1 by design. A known ≤200K model (e.g. claude-haiku-4-5-20251001, incl. the Bedrock id) resolves to `standard` (probed). Only unknown/absent ids fall to `long`, and `LOA_CONTEXT_CLASS` overrides. |
| 14 | claude-headless | ADVISORY | DECLINED | True: the class is computed once at SessionStart, and one file per checkout means last writer wins. No harness event exists for `/model`, and per-checkout `.run/` is a general limitation. The env override is the escape hatch. |
| 15 | claude-headless | ADVISORY | REFUTED | The run-mode resume directive is in CLAUDE.loa.md "Run Mode Recovery" and post-compact-reminder.sh:170-183. `br sync --flush-only` is in beads-integration.md:212/338. No skill or hook directs reading session-continuity.md. |
| 16 | claude-headless | ADVISORY | DOC | Unqualified standard-class numbers remain at reference/trajectory-evaluation.md:226 (`tokens_estimated > 2000`) and at skills/implementing-tasks/context-retrieval.md:108 (`>2000 tokens`). A reader under `long` gets 2K where the protocol says 20K. |
| 17 | claude-headless | ADVISORY | REFUTED | Mislabelled hunk (same as n=11). citations.md is intact. |
| 18 | claude-headless | ADVISORY | DOC | The stub's Level 2 (`notes-guard.sh read --file F --section <H>`) contradicts the reference copy's Level 2 (`ck --hybrid …`, :97/:105-107). The flags do exist (notes-guard.sh:11,19-21,56), so that sub-claim is refuted. |

**Counts:** REAL 0 · DOC 4 (n=4, 8, 16, 18) · REFUTED 7 (n=5, 7, 9, 10, 11, 15, 17) · DECLINED 4 (n=6, 12, 13, 14)

---

## DOC findings

### n=4 / n=8: the stub sentence overstates anchor stability

Evidence:
- `.claude/protocols/constructs-integration.md` and `.claude/protocols/trajectory-evaluation.md` at HEAD are a single H1 plus the pointer sentence, so every H2 is gone from the old path.
- `.claude/protocols/helper-scripts.md` adds one "Quick index" line beyond that.
- The sentence "this stub keeps the old path and its anchors stable" appears in all five stubs.
- reviewer.md is more precise: the stubs keep "the anchors existing tests grep: recommended-hooks §4 and the session-continuity notes-guard recipes".

What would break: a `recommended-hooks.md#…` or `constructs-integration.md#…` link would land on a stub without its section. No such link exists today. A repo-wide `grep -rnoE '(constructs-integration|helper-scripts|trajectory-evaluation|recommended-hooks|session-continuity)\.md#'` returns 0 hits. protocol-refs-resolve checks paths only.

On the n=8 sub-claim: §4 "Memory Injection Hook" is duplicated. It appears in the stub (lines 6-8) and in `reference/recommended-hooks.md:310-312`, and the Provenance note at :524-526 refers to it. `tests/unit/dead-recall-relabel.bats:12,28-31` pins only the stub path. A drift between the two copies would therefore go uncaught, but nothing reads the reference copy's §4 mechanically.

Minimal fix (wording):
- Change the sentence in all five stubs to "this stub keeps the old path resolvable" (or "keeps the old path and the sections tests pin").
- Optionally, drop §4 from the reference copy, or add a pointer there, so that only one copy carries the pinned text.

### n=16: unqualified standard-class thresholds left in reachable text

Evidence:
- `.claude/protocols/reference/trajectory-evaluation.md:226` reads "apply Tool Result Clearing if `result_count > 20` or `tokens_estimated > 2000`". This is unchanged from base. The same file's :300 was repointed to the class table, but :226 was not.
- `.claude/skills/implementing-tasks/context-retrieval.md:108` reads "After heavy searches (>20 results or >2000 tokens)". This file was edited this sprint: the `standard`-class qualifier was added only above the table at :193, not at :108.
- The example values `tokens: 5000` in reference/session-continuity.md:131 and `"tokens":5000` in reference/trajectory-evaluation.md:305 are sample log entries. They are cosmetic only, but they now describe the standard class.
- The live protocol, `tool-result-clearing.md:15`, says single search = 2,000 (standard) / 20,000 (long, default).

Misled reader: an implementing-tasks agent following context-retrieval.md Phase 3, under the default `long` class, clears at 2K instead of 20K.

Minimal fix:
- Replace both `> 2000` mentions with "above the single-search row of `.claude/protocols/tool-result-clearing.md` for the session's context class".
- Optionally, annotate the two example entries as `standard`-class samples.

Test: a grep lint, for example a CC-10 in `tests/unit/context-class.bats`, asserting that `grep -rnE 'tokens_estimated > 2000|>2000 tokens'` over `.claude/protocols` and `.claude/skills/*/{context-retrieval,impact-analysis}.md` is empty. It is red at HEAD.

### n=18: the stub and the reference disagree on Level 2 recovery

Evidence:
- The stub `.claude/protocols/session-continuity.md` table defines Level 2 as `notes-guard.sh read --file F --section <H>` (`--index` lists them).
- `reference/session-continuity.md:97` defines Level 2 as "~200-500 tokens | Task needs historical context | `ck --hybrid` for specific decisions", and :105-107 gives the recipe `ck --hybrid "…" grimoires/loa/ --top-k 3 --jsonl`.
- Base `f4531477` had only the ck form, so the stub introduced a second definition.
- The flags exist in `.claude/scripts/notes-guard.sh` (`read [--full | --index | --section SPEC] [--file PATH]`, :11, :19-21, :56).

Minimal fix: one definition. Either:
- set the stub's Level 2 row to the reference text (`ck --hybrid` for specific decisions, with `notes-guard.sh read --section <H>` when ck is absent); or
- update reference :97/:105-107 to the notes-guard recipe the stub uses.

The notes-template test (`tests/unit/notes-template.bats:268-273`) pins only the Level 1/3 strings, so either choice keeps it green.

---

## Notes on the DECLINED findings (for review/audit)

**n=6 / n=12, the replay gate.**
- The facts are true and already in `grimoires/loa/a2a/sprint-249/reviewer.md` (AC section) and `replay-ab.md`:
  - the gate fails on 5 cases;
  - missed slots went from 5 to 10 out of 144;
  - the remedy was not applied;
  - the adjudicated measure still loses one D06 slot on audit-pr-02.
- SDD §1.4.3 states "a recall drop on any gold case blocks the sprint". The decision to accept the deviation belongs to `/review-sprint` and `/audit-sprint`, not to this triage. This is a gate ruling, not a code defect.
- The dissent's causal claim, that the protocol move or the stubs changed citation format, does not hold:
  - (a) At base, the only reference from the review/audit skill trees to any moved file is a "Related" pointer in `skills/reviewing-code/impact-analysis.md:500`. No SKILL.md, CLAUDE.loa.md or include loads them.
  - (b) The `(`-in-path miss also occurs in the before arm (replay-ab.md: "That is the before arm's only review-pr-05 miss").
  - (c) The ablation of the include does not restore graded recall.
- Not ablated: the CLAUDE.loa.md trim and the constraints-rationale rewrite, both of which are in the prompt. The review/audit may want to note that.

**n=13.**
- Probed with `loa-context-class.sh --model <id> --json` in a scratch root:
  - `claude-haiku-4-5-20251001` → standard (model, 200000);
  - `us.anthropic.claude-haiku-4-5-20251001-v1:0` → standard;
  - `claude-haiku-4-5` and `haiku` → long (default). The catalog has no such alias.
- The fail-open applies only to unknown or absent ids, which matches SDD D-3.1. An optional nit is a `haiku` / `claude-haiku-4-5` alias in the catalog.

**n=14.** True as stated. Out of scope: there is no re-fire event for model switches, and the single-writer `.run/` file per checkout is pre-existing. An optional one-line DOC note in tool-result-clearing.md ("the record reflects the session-start model; set `LOA_CONTEXT_CLASS` after a `/model` switch") would close it.
