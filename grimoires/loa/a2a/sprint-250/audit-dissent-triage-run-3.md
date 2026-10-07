# sprint-250 audit dissent run 3: triage

- **Run.** The round r250-7 fix delta `e151757d..ee8fb582`, 2026-10-07T03:08:41Z–03:22:42Z, in two chunks: a7-gate (23,161 B), a7-misc (18,253 B). Coverage check: every changed file is in a chunk or in GENERATED.
- **Voices.** Both chunks two-voice [codex-headless (gpt-5.5-pro), claude-headless], the companion on `claude-bedrock`. No retries.
- **Envelope.** `adversarial-audit-run3-merged.json`, which is also the current `adversarial-audit.json`. Runs 1 and 2 are kept as `adversarial-audit-run{1,2}-merged.json`.
- **Findings.** 13: 6 MEDIUM, 7 LOW. 12 from claude-headless, 1 from gpt-5.5-pro.
- **Rejected payloads.** None (`rejected_count` 0; the a7-misc sidecar is 0 bytes).
- **Budget.** This is audit dissent run 3 of 3 — the last allowed for this sprint. Round r250-8's fixes are reviewed by the Fable audit, not by a fourth run.

## Rulings

| # | Sev | Where | Ruling | Action (round r250-8) |
|---|---|---|---|---|
| 1 | MEDIUM | gate: physical canonicalisation only | **FIX** (a tighten-only regression of round r250-7) | An inside-out symlink (`src/` → outside the root; `src/cfg.ts` → `../real.ts`) canonicalises outside the patterns and is allowed where the textual test asked. Compute both the physical and the logical (no-symlink) root-relative forms and OR them. IG-17 red first. |
| 2 | MEDIUM | gate: case-sensitive patterns | **FIX** | `$ROOT/Src/index.ts` is `src/index.ts` on case-insensitive filesystems. Match a lowercased copy — tighten-only elsewhere. Corpus row `write-Src-plain.json`; IG-15 `LIB/x.js`. |
| 3 | MEDIUM | gate: its own trust inputs are freely writable | **FIX** | `.run/state.json`, `.run/sprint-plan-state.json`, `.run/simstim-state.json`, `.run/platform-features.json`, `.run/audit.jsonl`, `.loa.config.yaml` written through the same tool exit 0 silently. Ask on either form matching one of them and append a `compliance.state_write` row, before the App-Zone test. IG-18 red first. bd-taee stays for the unforgeable RUNNING marker. |
| 4 | LOW | `strip_controls` blocklist gaps; byte cut splits UTF-8 | **FIX with #5** | Add U+00AD, U+061C, U+180E, U+206A–206F, U+FFF9–FFFB, U+FE00–FE0F, U+E0001/U+E0020–E007F; drop an incomplete trailing sequence after the cut. Audit rows via `jq -nca`. |
| 5 | LOW | the row stores the stripped claim | **FIX** | `implement`+U+200B logged as `implement … ask`, which the header calls impossible. Rows now carry the raw value (256-byte cut) through `jq -a`, so the row reads `implement​`; stderr keeps the stripped copy. IG-13 extended. |
| 6 | LOW | relative paths resolve from `PROJECT_ROOT`, the harness from the payload's `cwd` | **FIX** | Resolve from `.cwd` when present. IG-19 red first. |
| 7 | LOW | `emit_ask` `printf %s` with no escaping | **FIX (hardening)** | `jq -nc --arg r` when jq is present; the printf literal only on the jq-missing branch. All call sites are fixed strings today. |
| 8 | MEDIUM | fixed-point loop is O(n) passes on `C2^k 9B^k` (gpt-5.5-pro) | **FIX with #12** | Cut `top_path_log` to 256 bytes before the loop. CMP-281 (20,000-byte input under `timeout 5`). |
| 9 | MEDIUM | `prepare_content` splitter: quoted `diff --git "a/…"` headers and invalid-UTF-8 headers fold into the preceding file's chunk | PRE-EXISTING | Not touched by cycle-126 beyond the stderr copy. Real: with git's default `core.quotePath=true` any non-ASCII path takes this branch. Bead bd-d7kx (P2). |
| 10 | MEDIUM | the lib's copy drops C0/C1 only; no length cap | **FIX** | Port the gate's sequence set into the lib's loop; the 256-byte cut from #8. CMP-282 (U+202E, U+2066; `café` passes). |
| 11 | LOW | raw 8-bit 80–9F bytes survive in C locale | **FIX** | After the loop, validate UTF-8 with `iconv`; on failure replace every byte ≥ 0x80 with `?`. CMP-283. |
| 12 | LOW | same cost class as #8 | **FIX with #8** | — |
| 13 | LOW | the bats-marker seam is documentation, not mechanics | **FIX** | Replace the `AGENT_TYPES_FILE` env seam with an explicit `--agent-types-file` flag and ignore the variable entirely; ambient environment can no longer redirect the allowlist. SC-T-AGENT-8/9/10 follow. |

**Counts.** FIX 12 (#1–8, 10–13), PRE-EXISTING 1 (#9, beaded).

## Round r250-8 outcome

Committed as `005b9105` (pushed). One Opus 5.5 implementer on `wt-r250-9`; the lead reviewed the patch, applied it, regenerated REPO-MAP and checksums, ran the suites, and probed the real hook. Each item was red first. With the dissent budget spent, the Fable audit reviews this delta directly.

| # | Outcome |
|---|---|
| 1 | **Fixed.** Two root-relative forms: physical (`realpath -m` → `readlink -f`, against `pwd -P`) and logical (`realpath -m -s`, else `_ig_lexical_norm`, against `pwd -L`); either matching counts. IG-17: `src` → a symlink out of the root and `lib/cfg.ts` → `../outside/real.ts` both ask, also with a `realpath` shim that refuses `-s` (the pure-bash fallback); `grimoires/loa/../loa/NOTES.md` allows. |
| 2 | **Fixed.** The patterns match `${rel,,}`. Corpus row `write-Src-plain.json` (`ask ask no`); IG-15 `$ROOT/LIB/x.js` asks. |
| 3 | **Fixed.** Before the App-Zone test, either form equal to one of the six trust inputs asks (`[GATE] write to an implement-gate trust input`) and appends one `compliance.state_write` row. IG-18: six paths ask with one row each, a relative `.run/../.run/state.json` asks, `.run/other.json` and `grimoires/loa/NOTES.md` allow with no row. Live probe on the real tree: `.loa.config.yaml` → ask and the row. |
| 4, 5 | **Fixed.** Audit rows are written with `jq -nca` from the RAW values cut to 256 bytes on a character boundary (`cut_utf8_256`), so `implement`+U+200B logs as `"implement\u200b"` beside `decision: ask`, and the C0 case logs `rev\u0007iew\r\n`; `strip_controls` (stderr only) gained U+00AD, U+061C, U+180E, U+206A–206F, U+FE00–FE0F, U+FFF9–FFFB, U+E0001, U+E0020–E007F and drops an incomplete trailing sequence after the cut (no U+FFFD when the cut would split `é`). IG-13 extended. |
| 6 | **Fixed.** A relative path resolves from the payload's `cwd` when present, else `PROJECT_ROOT`; `jq -j` plus a sentinel keeps a trailing newline in the raw value. IG-19. |
| 7 | **Fixed (hardening).** `emit_ask` builds the reply with `jq -nc --arg r` when jq is present; the printf literal remains only for the jq-missing branch. IG-20. |
| 8, 12 | **Fixed.** `_lc_safe_log_path` cuts to 256 bytes (character boundary) before the fixed point. CMP-281: a 20,000-byte `C2^k 9B^k` path under `timeout 5`, no `C2 9B` pair, the log line under 400 bytes. |
| 10 | **Fixed.** The lib's loop uses the same sequence set as the gate. CMP-282: U+202E, U+2066, U+200B, U+FEFF never reach stderr; `café` passes under `C.UTF-8`. |
| 11 | **Fixed.** After the loop, `iconv -f UTF-8 -t UTF-8` validates the copy; on failure every non-printable byte becomes `?` (without iconv: when a byte 80–9F remains). CMP-283: a bare `9B` and `C2 9B 9B` log as `src/a?2Jb.sh`; `café` passes in both locales. |
| 13 | **Fixed.** `unset AGENT_TYPES_FILE`; the explicit `--agent-types-file PATH` argument is the test seam (in `--help`; a missing path is a usage error). SC-T-AGENT-8/9 pass the flag; SC-T-AGENT-10 proves the ambient variable is ignored with and without the bats markers. |
| 9 | **Beaded.** bd-d7kx (P2). |

**Suites, real tree, serial (ok / not ok / skip):** implement-gate 20/0/0, compliance-hook 14/0/0, skill-capabilities 36/0/0, adversarial-review-companion `-f 'CMP-2(7[89]|8[0-3])'` 6/0/0, hook-guard 8/0/0, repo-map-gen 6/0/0. `bash -n` clean on the three shell files; `regen-checksums --check` changed=0. Host tools: GNU coreutils 9.7 `realpath` (so `-s` is native; IG-17 also exercises the fallback through a refusing shim), glibc 2.41 `iconv`.

**Docs:** CHANGELOG `[Unreleased]` Fixed bullet; SDD D-4.4 amendment (c).
