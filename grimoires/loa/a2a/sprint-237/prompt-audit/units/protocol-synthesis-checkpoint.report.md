# Prompt audit report — protocol `synthesis-checkpoint.md`

**Scope**: `.claude/protocols/synthesis-checkpoint.md` only (not a skill — no `resources/`). No `@constraint-generated`/`@skill-include` markers. No `tools/prompt-keeplist.txt` row matches this path.
**Target model**: Claude Fable 5.1.
**Bytes**: 15562 → 8446 (target ≤ 10893; comes in under, no residual).

Top findings: the `## 7-Step Checkpoint Process` and `## Checkpoint Flow` ASCII-art boxes (83 lines) are pure duplicated boilerplate, restated with more precision in the surrounding prose/code. The header and footer each carry a version pin that has drifted apart from the other (`1.1` vs `1.0`) — proof the pins aren't maintained.

## Findings (highest confidence first)

| Location | Evidence | Pattern | Why obsolete | Confidence | Action |
|---|---|---|---|---|---|
| L61-105 | `## 7-Step Checkpoint Process` ASCII box | 1c bullet-wall/heavy formatting; duplicated boilerplate + choreography | Restates, box-drawn, what `## Step Details` (right after) already states in prose+code — no unique contract | High | remove |
| L3 vs L444 | `Version: 1.1` / `Protocol Version: 1.0` | 1d migration-relative phrasing + Group2 version-pin history narrative | The two disagree — concrete proof, not just idiom-dating | High | remove both |
| L442-447 | Footer (`Protocol Version`, `Last Updated: 2025-12-27`, `Paradigm`) | Group2 stale date + duplicated info that drifted | Date rots by definition; `Paradigm` line duplicates L4 | High | remove |
| L257-296 | `## Checkpoint Flow` walkthrough of one passing run | 1c example over-indexing (single gold output) | Adds nothing beyond "all steps pass → `/clear` proceeds", already stated | Medium-High | remove |
| L425-431 | `## Best Practices` (5 bullets) | 1c generic virtues/strategy coaching + duplicated info | 3/5 restate trained defaults; other 2 duplicate L19 and the L39-47 table | Medium-High | remove |
| L323-340 | `### Ghost Feature Failure` box | 1c example over-indexing; near-dup of L300-321 box | Keep-list #8 doesn't apply — same shape, not disagreeing content | Medium | remove; kept L300-321 as sole illustrative example, heading generalized to cover both |
| L13 | "As of v0.11.0, ... simplified from 7 steps to 3" | 1d migration-relative phrasing | Implies a former mandatory state; state current rule only | Medium | rewrite → "The checkpoint has **3 manual steps**; Steps 1, 2, 5, and 6 are automated by the context manager." |
| L384-423 | `## Remediation Guide` "1./2./3./4." choreography | 1c step choreography for a non-fragile, non-sequential task (cite vs. mark-assumption are alternatives, not steps 3→4) | Not a fragile/exact-sequence operation | Medium | rewrite to prose+code; every command kept byte-identical |

## MUST/NEVER/ALWAYS
None present (no ALL-CAPS MUST/NEVER/ALWAYS/CRITICAL/IMPORTANT).

## Untrusted-input check
File is entirely bash/YAML/JSON/table mechanics; nothing reads as an instruction to the auditor.

## Kept despite grep-bait
✅-emoji bullets (stylistic); "Mandatory validation" (Purpose — real constraint, enforced by the Hook Integration exit-code contract, L365-382); every bash/YAML/JSON/JSONL block under Step Details/Configuration/Hook Integration (exact commands, config keys, schemas, exit codes — never cut); the Step 6 pre-existing malformed nested code-fence (L224-235), reproduced byte-exact since fixing it is outside a dated-pattern audit's mandate.

## Flagged, not edited (out of scope)
L395's `ck --hybrid … --top-k 5` may be stale: `grounding-enforcement.md:248,251` documents `--limit` as current syntax, while `session-continuity.md:135` and `goal-validator.md:246` still use `--top-k` — a repo-wide inconsistency, not a Fable-5.1 prompting pattern. Left byte-exact per the tool-contract keep rule; flagged for a separate fix.

## History rule
No `cycle-NNN`/`#NNNN`/`KF-NNN` tokens anywhere in the file — no Provenance footer needed.

## Residual
None. 15562 → 8446 bytes (45.7% cut), driven entirely by the eight named findings above, not by a length target.
