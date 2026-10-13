# Sprint 254 (cycle-128 Sprint 3), implementer F: FR-6 glossaries

Scope: sprint.md Task 3.1, Task 3.2 and the glossary part of Task 3.5 (sdd.md D-6.1 to D-6.5, §4.5, §5.3). Worktree `loa-wt-s3a`, detached at `8f7932b2`; not committed. Patch: `~/.cache/loa/cycle-128/patch-s3-f.patch`.

## Task 3.1 first step: report-only sizing run

Command: `tools/check-glossary-terms.sh --report` against the live kernel with an empty glossary (H1, context line, empty `## Language`) and an empty allowlist. Result: exit 1, 16 misses.

| Measure | Count |
|---|---|
| Unique backticked spans outside fenced code | 85 |
| Dropped by the shape `^[A-Za-z][A-Za-z0-9_-]*$` because of `/`, `.`, `:`, `(` or `--` | 64 |
| Dropped as spaced phrases or operators (`hit your session limit`, `out of extra usage`, `jq -S`, `>>`, `*_TEST_MODE=1`) | 5 |
| Kept | 16 |

Every kept token, sorted:

| Token | Kernel line | Class | Resolution after seeding |
|---|---|---|---|
| `br` | 55 | framework term | alias of **Beads** |
| `RUNNING` | 104 | framework term | alias of **Run mode** |
| `HALTED` | 104 | framework term | alias of **Run mode** |
| `JACKED_OUT` | 104 | framework term | alias of **Run mode** |
| `LOA-VERDICT` | 108 | framework term | alias of **Verdict trailer** |
| `simplicity_intensity` | 62 | false positive: config key | allowlisted |
| `full` | 62 | false positive: config value | allowlisted |
| `ultra` | 62 | false positive: config value | allowlisted |
| `TaskCreate` | 75 | false positive: Claude Code tool name | allowlisted |
| `TaskUpdate` | 75 | false positive: Claude Code tool name | allowlisted |
| `audit_emit` | 135 | false positive: library function | allowlisted |
| `audit_emit_signed` | 135 | false positive: library function | allowlisted |
| `trust_grant` | 135 | false positive: library function | allowlisted |
| `handoff_write` | 135 | false positive: library function | allowlisted |
| `cycle_invoke` | 135 | false positive: library function | allowlisted |
| `soul_validate` | 135 | false positive: library function | allowlisted |

Tokens the heuristic should drop: none beyond what it already drops. Each of the 11 false positives was reviewed before it entered the allowlist. Each is a code identifier with no working meaning to define. The six snake_case function names could be dropped by excluding `_`, but `JACKED_OUT` needs `_` to survive, so the shape stays as specified and the names stay allowlisted. The allowlist landed at 11 entries, matching the D-6.2 prediction, and each line carries a `# reason`.

Final live run: kept 16, defined 0, alias 5, allowlisted 11, missing 0, allowlist 11 of 30, no WARN. The kernel's framework terms happen to appear in backticks only as aliases. The definitions themselves cover the D-6.1 list for the planning skills and for review.

## Deliverables

- **Framework glossary** `.claude/loa/GLOSSARY.md`: 33 entries, the full D-6.1 list plus Circuit breaker and Fog of war. Seven `_Aliases_:` lines and six `_Avoid_:` lines. Implementation-free: the validator raises no path or extension WARN.
- **Project glossary** root `GLOSSARY.md`: Cycle, Record branch, Zone marker. Its context paragraph says the planning skills create it lazily at the project root in other projects.
- **Allowlist** `.claude/data/glossary-allowlist.txt`: 11 entries, one reason each.
- **Checker** `tools/check-glossary-terms.sh [--kernel] [--glossary] [--allowlist] [--json] [--report]`: exit 0, 1 or 2 per §5.3. A miss line names the token, its kernel line and all three fixes. A stale allowlist entry WARNs, and so does a redundant one that the glossary already resolves. Display paths are repo-relative.
- **CI** `.github/workflows/check-glossary-terms.yml`: runs on pull_request and push to main, guarded on `github.repository == '0xHoneyJar/loa'`. `actions/checkout` is pinned to `34e114876b0b11c390a56381ad16ebd13914f8d5`, the SHA the prompt-budget workflow uses. One gate step runs the checker and validates both glossaries, followed by the positive control (`tests/fixtures/glossary/miss/` must exit 1) and the negative control (`ok/` must exit 0).
- **Validator** `validate-artifact.sh --type glossary`: the type was added to the header, the usage text, the `--type` case list, the error message and the dispatch case, the same way map and spike were. `validate_glossary` sits after `validate_spike`, and no G-owned line is touched. The PII scan is reused.
- **Skill sentences (D-6.5)**:
  - `discovering-requirements`: a new `**Terms (Phases 1-7)**:` paragraph after Phase 4 anti-inference.
  - `designing-architecture`: the sentence follows the prototype sentence in Phase 2.
  - `riding-codebase`: §1.2 was compressed, then gained the both-glossaries read.
  - `reviewing-code/resources/REFERENCE.md`: the row goes at the end of Code Quality, just above `### Testing`.
- **Mount surfaces (beyond the brief, flagged for the lead)**: `.claude/loa/GLOSSARY.md` was added to `lib/symlink-manifest.sh` `MANIFEST_FILE_SYMLINKS` and to the gitignore symlink lists in `mount-submodule.sh` and `mount-loa.sh`. Submodule mode links `.claude/loa/` entries one by one. Without this, a submodule-mounted project would not receive the framework glossary that D-6.1 says is mounted into every project. Standard mode already copies the whole `.claude` tree.

## Budgets

| Skill | Before | After | Limit |
|---|---|---|---|
| discovering-requirements | 15,701 | 15,887 | 16,384 |
| designing-architecture | 15,407 | 15,568 | 16,384 |
| riding-codebase | 16,346 | 16,379 | 16,384 |
| reviewing-code | 16,287 | 16,287 | 16,384 (REFERENCE.md is not charged) |

riding-codebase has 5 bytes of headroom left.

## Tests

- `tests/unit/glossary-terms.bats`: 20 cases. The live pair passes. Removing `_Aliases_: br`, or the Run mode entry, from a copy fails and names each token. The suite covers case and plural folding in both directions, aliases, separator folding, near-miss tokens, backtick, tilde and indented fences, the shape drops, an allowlist of 31 failing and 30 passing, stale and redundant WARNs with exit 0, the `--json` shape, both fixture controls, usage exits, entries outside `## Language`, the live allowlist reasons and the cap, and the 18-entry minimum.
- `tests/unit/glossary-validator.bats`: 19 cases. Both real glossaries and both fixtures validate with no WARN. A duplicate term, a duplicate alias, an over-long entry, three sentences, `_Aliases_` without an entry, a detached `_Avoid_`, a missing `## Language`, a missing H1 or context paragraph, a wrapped definition, an empty section and a bare entry each fail. A path or extension WARNs. The suite also checks `--json`, the H1 shape WARN and fenced code. The 300-character edge passes, with multibyte characters counted once.
- Mutation check on a scratch copy: nine mutations were each killed by at least one case. They removed the es plural, the s plural, the singular fold, the separator fold, case folding, the exit 1, fence tracking and the cap. The ninth was the duplicate plural fold in lookup, which survived the first time and led to the fold being kept in one place only.
- Runs with `LOA_HARNESS_CHECK=0`: glossary-terms 20/20 and glossary-validator 19/19. validate-artifact 60/60, prompt-budget 9/9, skill-capabilities 36/36, spike-validator 16/16 and symlink-manifest-agents 6/6, for 166/166 in one combined run. mount-submodule-hooks-copied also passed in an earlier batch.
- The awk programs give identical results under mawk, nawk (one-true-awk) and busybox awk.
- Other checks: `check-prompt-budget.sh` exit 0. `check-no-raw-sha256sum.sh` and `check-no-swallowed-jq.sh` OK. `validate-skill-capabilities.sh` passes 37/37 with 3 WARNs that predate this patch (eval-running, flatline-knowledge, loa-setup). `agents-md-gen.sh --check` is consistent at 51 commands; no new command was added. `bash -n` passes on both scripts. shellcheck is not installed here.

## Assumptions

- [ASSUMPTION fact] The live kernel keeps 16 backticked tokens under the D-6.2 shape: 5 framework aliases and 11 code identifiers.
- [ASSUMPTION fact] `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5` (v4.3.1) is the pin the existing workflows use.
- [ASSUMPTION fact] Submodule mode mounts `.claude/loa/` files only through the symlink manifest, so a new framework file there needs a manifest line.
- [ASSUMPTION decision] Matching also folds `-`, `_` and spaces, so `run-mode` and `run_mode` resolve to **Run mode**. The plural fold is symmetric: a singular token resolves to a plural term.
- [ASSUMPTION decision] Only entries and aliases inside `## Language` resolve tokens or count for duplicates. Other H2 sections are allowed and ignored.
- [ASSUMPTION decision] A missing allowlist file is a usage error (exit 2), never an empty allowlist. An allowlist entry is the first word of a line, and the rest after `#` is its reason.
- [ASSUMPTION decision] The checker WARNs on a redundant allowlist entry, one the glossary already resolves, in addition to the specified stale-entry WARN.
- [ASSUMPTION decision] The validator fails any non-blank line in `## Language` that is not an entry, an `_Avoid_:` or `_Aliases_:` line, or a `###` heading, so a wrapped definition cannot slip past the 300-character rule. A second `_Avoid_:` or `_Aliases_:` line for one entry, an empty annotation line and an empty `## Language` also fail.
- [ASSUMPTION decision] Sentences are counted as runs of `.`, `!` or `?` followed by whitespace; abbreviations like "e.g." count as sentence ends. Length counts characters of the definition text after `**Term**: `, not the whole line.
- [ASSUMPTION decision] A non-`# Glossary: <name>` H1 WARNs rather than fails, since D-6.4 asks only for an H1.
- [ASSUMPTION decision] The CI gate step also validates both glossaries with `--type glossary`, so a format break fails the same job.
- [ASSUMPTION decision] The framework glossary seeds Circuit breaker and Fog of war beyond D-6.1; the PRD Appendix D glossary already defines fog of war.
- [ASSUMPTION decision] The validator suite is a new file, `glossary-validator.bats`, rather than cases in `validate-artifact.bats`, to keep this patch from colliding with implementer G's seams cases.
