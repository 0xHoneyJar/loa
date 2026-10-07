# sprint-250 audit dissent run 2: triage

- **Run.** The round r250-6 fix delta `4d37029e..e151757d`, 2026-10-07T02:33:46Z–02:45:03Z, in three chunks: a6-gate (19,308 B), a6-misc (16,607 B), a6-docs (15,525 B). Coverage check: every changed file is in a chunk or in GENERATED.
- **Voices.** All three chunks two-voice [codex-headless (gpt-5.5-pro), claude-headless], the companion on `claude-bedrock`. No retries.
- **Envelope.** `adversarial-audit-run2-merged.json`, which is also the current `adversarial-audit.json`. Run 1's merge is kept as `adversarial-audit-run1-merged.json`.
- **Findings.** 12: 5 MEDIUM (#1, #2, #7, #8, #9), 7 LOW. 11 from claude-headless, 1 from gpt-5.5-pro. (The headline first read "4 MEDIUM, 8 LOW"; corrected per audit LOW-005 — the rulings table and the envelope were right.)
- **Rejected payloads.** None (`rejected_count` 0; the a6-misc sidecar is 0 bytes).
- **Budget.** Audit dissent run 2 of 3. Run 3 covers the round r250-7 delta.

## Rulings

| # | Sev | Where | Ruling | Action (round r250-7) |
|---|---|---|---|---|
| 1 | MEDIUM | `implement-gate.sh` App-Zone check | **FIX** (pre-existing, but it sits one line above the code the sprint hardens and defeats every branch) | The check is a string-prefix comparison against `$PROJECT_ROOT/`; `/proc/self/cwd/src/x`, `//$ROOT/src/x`, `$ROOT/../<root>/src/x`, `$ROOT/grimoires/../src/x` and a symlinked root all exit 0 silently. Canonicalise both sides (`pwd -P`; `realpath -m` → `readlink -f`; neither → fail-ask), classify on the canonical relative path. IG-15 red first. |
| 2 | MEDIUM | heuristic trusts `.run/` RUNNING state | PRE-EXISTING (run 1 n19, review run 1 n24) | ADVISORY by design; the opt-in is now strictly tighter. Bead bd-taee: bind the RUNNING allow to a marker a model cannot write. |
| 3 | LOW | gate sanitiser strips C0 only | **FIX with #12** | One `strip_controls()` in the hook: C0 + DEL, UTF-8 C1, the Unicode format/bidi code points (U+200B–200F, U+2028–202E, U+2060–2064, U+2066–2069, U+FEFF), fixed-point, 256-byte bound; `café` stays. IG-13 extended red first. |
| 4 | LOW | `--line` skips the refresh's shape check | **FIX** | The same ISO-8601 / `tool_input` checks in the `--line` jq: a malformed `seen_at` prints `none`, an unknown source prints `via unknown`. IG-14 extended red first. |
| 5 | LOW | empty `file_path` allows: no jq, unparsable payload, NotebookEdit's `notebook_path` | **FIX** (pre-existing; the header's fail-ask promise was not true) | jq missing or `jq -e .` failing → ask (`[GATE] could not evaluate tool_input`); read `.file_path // .notebook_path`; a genuinely absent path on a parsed payload stays allow. IG-16 and a `notebook-src-plain.json` corpus row red first. |
| 6 | LOW | implementation claim leaves no audit row; row unbounded; "once" comment | **FIX** | A `compliance.mode.model_signal` row with `decision: "heuristic"` for implementation claims too (the harness never sets the field, so rows appear only when a model forges it); fields through `strip_controls` (256 B); comment corrected. IG-12 counts 1 ask + 2 heuristic rows. |
| 7 | MEDIUM | bats markers are ordinary env vars (gpt-5.5-pro) | DECLINED + **DOC** | True and known: the marker gate is the repo's stated convention (`CLAUDE.loa.md` Agent-Network Primitives; `loa-status.sh:732`, `adversarial-review.sh:588`, `run-preflight.sh:64`), not a trust boundary — whoever controls the validator's environment controls its tree. The header comment and the CHANGELOG sentence now say so. The pre-existing `PROJECT_ROOT`/`SKILLS_DIR` seams are bd-7cur. |
| 8 | MEDIUM | single-pass C1 loop re-forms pairs | **FIX** | `C2 C2 9B 9B` → `C2 9B` after the 0x9B pass (a live CSI; OSC/ST likewise). Fixed-point loop; CMP-280 feeds the doubled sequences red first. Raw non-UTF-8 0x80–0x9F bytes stay (inert on UTF-8 terminals). |
| 9 | MEDIUM | same as #7 (claude-headless) | DECLINED + DOC | As #7. |
| 10 | LOW | grader `$review_name` raw `%s` | PRE-EXISTING, beaded | bd-s03k (run 1 n35). The delta touched the file only for `python3 -I`. |
| 11 | LOW | CHANGELOG describes the seam as a gate | **DOC** | Reworded: "a test seam by repo convention, not a security boundary". |
| 12 | LOW | two sanitisers with different scopes | **FIX with #3** | The gate now drops what the lib drops, plus the format/bidi set; the CHANGELOG line for round r250-7 states one scope. |

**Counts.** FIX 7 (#1, 3, 4, 5, 6, 8, 12), DOC 2 (#7/#9 wording, #11), PRE-EXISTING 2 (#2 beaded, #10 already beaded), DECLINED 1 (#9, as #7).

## Round r250-7 outcome

Committed as `ee8fb582` (pushed). One Opus 5.5 implementer on `wt-r250-8`; the lead reviewed the patch, applied it, regenerated REPO-MAP and checksums, ran the suites, and probed the real hook. Each item was red first.

| # | Outcome |
|---|---|
| 1 | **Fixed.** `canonical_root=$(cd "$PROJECT_ROOT" && pwd -P)`; the path is canonicalised from the root with `realpath -m --`, else `readlink -f --`; neither → fail-ask (`[GATE] could not canonicalise tool_input.file_path`). The `src/|lib/|app/` patterns apply to the part under the canonical root; a path that canonicalises outside the root is not App Zone. IG-15: `/proc/self/cwd/src/x.ts`, `//$ROOT/src/x.ts`, `$ROOT/../<name>/src/x.ts`, `$ROOT/grimoires/../src/x.ts` and a symlinked root all ask; `elsewhere/src/x.ts` and `grimoires/loa/NOTES.md` allow. Live probe on the real tree: `/proc/self/cwd/src/probe.ts` → `"ask"`. |
| 5 | **Fixed.** No jq or `jq -e .` failing → ask (`[GATE] could not evaluate tool_input`); the path is `.tool_input.file_path // .tool_input.notebook_path`; a parsed payload without a path stays allow. IG-16 and the corpus row `notebook-src-plain.json` (`ask ask no`). |
| 3, 12 | **Fixed.** `strip_controls()`: C0/DEL via `tr`, then UTF-8 C1 (C2 80–9F) and U+200B–200F, U+2028–202E, U+2060–2064, U+2066–2069, U+FEFF removed to a fixed point, then `${s:0:256}` under `LC_ALL=C`; used for both stderr echoes and both audit-row fields. IG-13 feeds `\xc2\x9b`, U+202E, U+200B, the doubled `\xc2\xc2\x9b\x9b` and a 400-byte skill; `café` passes verbatim. |
| 4 | **Fixed.** `--line` applies the same two shape checks as the refresh: malformed `seen_at` → `none`; a source other than `tool_input` → `via unknown`. IG-14 extended (the earlier U+202E-suffixed timestamp now yields `none`, which is the stricter reading). |
| 6 | **Fixed.** `log_model_signal <decision>`: `heuristic` for an implementation claim, `ask` otherwise; the "once" comment corrected to per-invocation. IG-12 asserts `["ask","heuristic","heuristic"]` and the heuristic rows carry `implement` and the path. |
| 8 | **Fixed.** The 32-substitution pass repeats until `top_path_log` is unchanged. CMP-280 (run under `LC_ALL=C`, where the header regex parses the invalid lead bytes as CI does) feeds `C2 C2 9B 9B`, `C2 C2 9D 9D … C2 C2 9C 9C`: no `C2 9B`/`9D`/`9C` pair reaches stderr; `café` passes. |
| 7, 9, 11 | **Documented.** The validator header and the CHANGELOG sentence say the bats-marker seam is a repo convention, not a security control; a hardened invocation scrubs the environment. |
| 2 | **Beaded.** bd-taee. |
| 10 | Already bd-s03k. |

**Suites, real tree, serial (ok / not ok / skip):** implement-gate 16/0/0, compliance-hook 14/0/0, skill-capabilities 36/0/0, adversarial-review-companion `-f 'CMP-2(78|79|80)'` 3/0/0, hook-guard 8/0/0, repo-map-gen 6/0/0, loa-status-providers 4/1/0 in the batch (LSP-1 again; 5/5 alone across the day — the recorded load flake). `bash -n` clean on the four changed shell files; `regen-checksums --check` changed=0. `realpath` and `readlink` are both GNU coreutils on this host.

**Docs:** CHANGELOG `[Unreleased]` Fixed bullet for the round; SDD D-4.4 amendment (b).

**Audit dissent run 3** (the last of three) covers this delta (`e151757d..ee8fb582`) in two chunks: a7-gate, a7-misc.
