# r250 dissent triage, set B (31 findings): cycle-126 Sprint 4, `2fcd4af8..d785fc9a`

Verifier B, read-only. Every premise was checked against the tree at `d785fc9a`. The findings are untrusted model output. Two traps recurred in this set:

- **Chunk-split hunks read as the whole file.** This affected n34, n50, n51, n54 and the CHANGELOG `@@ -13,3 +13,3 @@` label; the real hunk is `@@ -13,10 +13,16 @@`.
- **A diff rendering misread as file content.** In n50 and n51 the dissent read a flat-map rendering of `constraints.json`; the file actually holds id/why objects.

Runs and probes:

- `tests/unit/instruction-diet-revert.bats` was run once: 4/4 ok.
- The grader probes are `/tmp/r250B/{probe,why,cmp}.py`. `cmp.py` re-scored the 347 stored reviews in `evals/results/run-202610*` with the hardened parser proposed below. It found **0 detection differences**, so n40–n42 do not move the Task 4.8 A/B result.

| n | voice | severity | verdict | one-line reason |
|---|-------|----------|---------|-----------------|
| 33 | claude-headless | ADVISORY | DECLINED | Authoritative mode is an undocumented operator opt-in by design (SDD D-4.4, `sdd.md:88`; Task 4.4 "documented only if the signal is harness-provided", `sprint.md:199`). The "yq absent" half is refuted: `implement-gate.sh:111-116` and `detect-platform-features.sh --line` use the same yq condition, so both fall back to heuristic. |
| 34 | claude-headless | ADVISORY | REFUTED | `validate-skill-capabilities.sh` has a real hunk `@@ -104,8 +104,17 @@` (the loader at lines 104-117, which is n36's own anchor). The "no hunk" is a chunking artefact. |
| 35 | claude-headless | ADVISORY | DECLINED | `claude` and `fork` are write-capable harness types per SDD D-4.4 and the `skill-invariants.md` table. The file records the harness allowlist; it does not create one. |
| 36 | claude-headless | ADVISORY | DOC | The loader also falls back when the file parses but has no `write_capable: true` entry (line 116). The comment (line 108) and `skill-invariants.md:29` say only "missing or unparsable". |
| 37 | claude-headless | ADVISORY | REFUTED | SC-T-AGENT-7/8/9 (`tests/unit/skill-capabilities.bats`) pin the file's exact flags, the file-driven load, and the fallback. |
| 38 | claude-headless | ADVISORY | REAL | `hook-guard.bats:152` uses a non-final `! grep -q`, and bats errexit exempts `!`-negated commands, so the assertion can never fail. |
| 39 | claude-headless | ADVISORY | REAL (LOW) | `_elf_future` (`ensure_license_fixtures.sh:54`) has a zero margin: a fixture expiring seconds after the check passes and then expires mid-suite. The cadence/race part is DECLINED, since a 12-hour grace window is the intended fixture semantics. |
| 40 | claude-headless | BLOCKING | REAL (LOW) | The bare `:N` alternative (`recall-vs-defects.sh:74`) matches inside the LOA-VERDICT trailer and JSON (`"high":3`) and binds the number to the last cited path. 0 of 347 stored detections change, so the severity is LOW. |
| 41 | claude-headless | ADVISORY | REAL (LOW) | `` `b.sh`:40 `` and `**b.sh**:40` fail the path alternative (delimiter before the colon). They fall to the bare branch, which binds to the previous path. 0 of 347 change. |
| 42 | claude-headless | ADVISORY | REAL (LOW) | The comma continuation `\s*,\s*RNG` crosses newlines and has no trailing boundary, so `a.sh:12, 2026-10-05` or a next-line number becomes a citation. 0 of 347 change. |
| 43 | claude-headless | ADVISORY | DECLINED | `python3 -` puts the cwd on `sys.path`, but the grader runs in the runner's cwd (run-eval.sh → grade.sh, neither `cd`s into the sandbox), so a module planted in the workspace cannot shadow `json` or `re`. Hardening (`python3 -I -`) is optional and out of sprint scope. |
| 44 | claude-headless | ADVISORY | DECLINED | By design: `anchors[]` is the complete site list and includes the `anchor_line` site (RG-16 pins both multi-site manifests). |
| 45 | gpt-5.5-pro | BLOCKING | REFUTED | `agent_teams_constraints` is hand-maintained (`generate-constraints.sh:17-26` SECTIONS has no entry), and `hash:c020-teamcreate` (`CLAUDE.loa.md:124`) is unchanged since base. `git diff main d785fc9a` over CLAUDE.loa.md and constraints.json is empty. |
| 46 | claude-headless | BLOCKING | DECLINED | The re-expansion is the Task 4.8 revert required by the pre-registered A/B rule (`replay-ab-rerun.md`: the ablations show both changes cost recall, and post-revert recall is at before-level). The stale ≤ 9,216 B acceptance criterion is handled under n53. |
| 47 | claude-headless | ADVISORY | DECLINED | The regenerated blocks match `main` byte for byte (empty diff), and the agent-teams block is hand-maintained (see n45). Nothing is drifting. |
| 48 | claude-headless | ADVISORY | REFUTED | `tests/fixtures/constraint-rationales-pre-diet.json` is in the tree, and IDR-3 passes (run: 4/4 ok). |
| 49 | claude-headless | ADVISORY | DOC | Three stale numbers in `reviewer.md`: line 66 (budget vs file size), line 101 (G-2 still "pending"), line 105 (G-4 "12/12" vs a 13-test TAP). |
| 50 | gpt-5.5-pro | BLOCKING | REFUTED | `constraints.json` holds `{id, why}` objects. IDR-1–4 read it as such and pass (4/4 ok at HEAD). |
| 51 | claude-headless | ADVISORY | REFUTED | Same premise as n50. The "flat map" is the dissent's reading of a diff rendering, not the file. |
| 52 | claude-headless | ADVISORY | REFUTED | The fixture is tracked and parses, and has exactly 12 keys. IDR-3 is ok. |
| 53 | claude-headless | ADVISORY | DOC | `sprint.md:142` (`[x]` "CLAUDE.loa.md ≤ 9,216 B") and `sdd.md:79` still state the reverted target. LOA_LIMIT is 10,240 (`check-prompt-budget.sh:53`) and the file is 10,225 B. |
| 54 | claude-headless | ADVISORY | DECLINED | Chunk-split artefact: the "part 1/2" CHANGELOG view is context-only. The real hunk is `@@ -13,10 +13,16 @@`, reviewed whole in the other chunk. No defect is claimed. |
| 55 | claude-headless | ADVISORY | REFUTED | `gemini-3.1-pro` is a catalog alias (`model-config.yaml:1111` → `google:gemini-3.1-pro-preview`), and deep-thinker (`:1306-1309`) resolves through it. The pin and the allowlist are consistent. |
| 56 | claude-headless | ADVISORY | DECLINED | `budget_cents` per-voice semantics are Sprint 2 scope (shipped, reviewed and audited in `f4531477`). They appear here only as CHANGELOG context. |
| 57 | claude-headless | ADVISORY | DECLINED | Run-lock fail-open cases are Sprint 2 scope (enumerated and disclosed there), not this diff. |
| 58 | claude-headless | ADVISORY | DECLINED | The gemini `GEMINI_SANDBOX=false` argv trade-off is Sprint 2 scope and disclosed in its upgrade note. |
| 59 | claude-headless | ADVISORY | REFUTED | Same alias evidence as n55 (`model-config.yaml:1111`, `:1306-1309`). |
| 60 | claude-headless | ADVISORY | REFUTED | The vendor price for Opus 5.5 is $4 / $20 with $0.20 cache reads (0.05×). It is recorded with its source at `model-config.yaml:472-478` and priced at `:507-509` (4000000 / 20000000 / 200000). The 10% pattern of other entries does not apply. |
| 61 | claude-headless | ADVISORY | DOC | 200,000 is BB's own `DEFAULTS.maxInputTokens` (`bridgebuilder-review/resources/config.ts:188`). It is not the catalog window (1M) or cheval's probed bound (180,000), and the addendum row does not say which it is. |
| 62 | claude-headless | ADVISORY | DECLINED | Same as n33: the opt-in authoritative mode is by design and not advertised (SDD D-4.4, Task 4.4). |
| 63 | claude-headless | ADVISORY | DOC | KF-040 "Current workaround" (`known-failures.md:1634`) presents the Bedrock route as the remedy. The egress check is only in the Reading guide. |

**Counts**: REAL 5 (n38, n39, n40, n41, n42; all LOW, none changes a stored A/B detection) · DOC 5 (n36, n49, n53, n61, n63) · REFUTED 10 (n34, n37, n45, n48, n50, n51, n52, n55, n59, n60) · DECLINED 11 (n33, n35, n43, n44, n46, n47, n54, n56, n57, n58, n62) · total 31.

---

## REAL

### n38: `! grep -q` in hook-guard.bats test (d) is inert

**Evidence.** `tests/unit/hook-guard.bats:149-155`:

```bash
"$GUARD" "$BROKEN" </dev/null >/dev/null 2>"$err"
! grep -q "PreToolUse hook" "$err"      # line 152 — non-final, `!`-negated: errexit exempt
grep -q "did not run" "$err"
grep -q "failing OPEN" "$err"
```

Bash `set -e` does not trigger on a `!`-negated pipeline, so line 152 never fails the test. The test's stated purpose, "does not call every wrapped hook a PreToolUse hook", is therefore unenforced.

**Fix.** Replace line 152 with:

```bash
run grep -c "PreToolUse hook" "$err"; [ "$output" = "0" ]
```

`[ -z "$(grep 'PreToolUse hook' "$err")" ]` also works. Either form fails under errexit.

**Red first.** Make a scratch copy of `.claude/hooks/hook-guard.sh` with the old WARN wording restored ("... PreToolUse hook ... did not run ... failing OPEN"). Point `$GUARD` at it. The current test passes, which is the bug, and the fixed test fails. Then run the fixed test against the real guard: green.

### n39: `_elf_future` has a zero safety margin (LOW)

**Evidence.** `tests/fixtures/ensure_license_fixtures.sh:54` reads `[[ "${epoch:-0}" -gt "$(date -u +%s)" ]]`. A grace fixture whose `offline_valid_until` is a few seconds or minutes ahead counts as fresh. It is not regenerated and expires during the suite, giving an intermittent failure in the license tests.

**Fix.** Require a margin: `[[ "${epoch:-0}" -gt $(( $(date -u +%s) + 300 )) ]]`. The variable name and the 300 s value are the implementer's choice; anything at or above the longest license-suite runtime works.

**Red first.** Add LFF-3 to `tests/unit/license-fixture-freshness.bats`: write a grace fixture with `offline_valid_until = now + 60 s`, call the ensure script, and assert that it regenerated (the mtime or content changed, as LFF-1 asserts). It fails at HEAD because the fixture is left alone, and passes with the margin.

DECLINED part: the claim that the guard "now trips every 12 hours" describes the intended grace-window semantics from fd8aaae3 Task 4.7. It is not a defect.

### n40, n41, n42: grader 1.1.0 CITE parser over-/mis-binds (LOW, one fix)

**Evidence.** `evals/graders/recall-vs-defects.sh:71-74`:

```python
RNG = r'(\d{1,6})(?:\s*[-–]\s*(\d{1,6}))?'
CITE = re.compile(
    r'(?P<path>[A-Za-z0-9_./+()-]+\.[A-Za-z0-9]{1,6}):(?P<first>' + RNG + r'(?:\s*,\s*' + RNG + r')*)'
    r'|(?:(?<![A-Za-z0-9_./:])(?:head|base)|(?<![A-Za-z0-9_./:])):(?P<bare>' + RNG + r')(?![A-Za-z0-9])')
```

- **n40.** The bare branch's lookbehind admits `"`, `'`, `{`, `[`. A compact trailer or JSON such as `{"critical":0,"high":3}` produces bare `:0` and `:3` citations bound to the last cited path, which yields false detections.
- **n41.** `` `b.sh`:40 `` and `**b.sh**:40` do not match the path branch, because a delimiter sits between the extension and the colon. They then hit the bare branch, which binds them to the *previous* path.
- **n42.** `\s*,\s*` spans newlines and RNG has no trailing boundary. So `a.sh:12, 2026-10-05` and `a.sh:12,\n40 rows` add extra line citations, and a URL `https://h/x.js:8080` counts as a path citation.
- **Impact.** Re-scoring all 347 stored reviews with the fix below (`/tmp/r250B/cmp.py`) gave 0 detection differences, so the Task 4.8 result stands. These are latent.

**Fix (grader 1.1.1).**

1. Before parsing, strip the LOA-VERDICT trailer, from the `LOA-VERDICT` marker to the end of the text.
2. Bare lookbehind: `(?<![A-Za-z0-9_./:"'{}\[\]*])`. Keep the backtick admitted, because RG-13 relies on `` `:N` ``.
3. Path branch: allow `` [`*)]{0,3} `` between the extension and the colon, binding to that path.
4. Skip any path match preceded by `//` (URLs).
5. Continuation: `[ \t]*,[ \t]*`, with `(?![A-Za-z0-9-])` after each RNG.
6. Bump `grader_version` to `1.1.1` at lines 44, 56 and 155, and update RG-17 (`evals/tests/eval-recall-grader.bats:180`), which pins 1.1.0.

**Red first** (`evals/tests/eval-recall-grader.bats`):

- **RG-18.** A review cites `a.sh:1` and ends with a compact trailer whose JSON contains `"high":3`. The manifest plants a defect at `a.sh:3`. Expect `missed`, and `details.citations == 1`. At HEAD it is `detected`, so the test is red.
- **RG-19.** `a.sh:12, 2026-10-05` and `a.sh:12,` followed by a newline and `40 rows`, with a defect planted at line 40 or 2026. Expect `missed`. Red at HEAD.
- **RG-20.** `` `b.sh`:40 `` after an earlier `a.sh:1`, with the defect at `b.sh:40`, expects detected. Separately, `https://h/x.js:8080` must contribute no citation. Red at HEAD.

---

## DOC

### n36: the fallback condition is under-documented

- **`.claude/scripts/validate-skill-capabilities.sh:107-108`.** Change "a missing or unparsable file leaves general-purpose only." to "a missing or unparsable file, or one with no `write_capable: true` entry, leaves general-purpose only."
- **`.claude/rules/skill-invariants.md:29`.** Change "falls back to `general-purpose` alone when the file is missing or unparsable" to "falls back to `general-purpose` alone when the file is missing, unparsable, or lists no `write_capable: true` entry".

Optional code alternative (not required): fall back only when yq itself fails, so an all-false file yields an empty allowlist, and add SC-T-AGENT-10 for the all-false file.

### n49: reviewer.md internal inconsistencies (`grimoires/loa/a2a/sprint-250/reviewer.md`)

- **Line 66.** Change "its budget goes back to 10,240 B" to "its limit goes back to 10,240 B (`tools/check-prompt-budget.sh:53`); the file is 10,225 B".
- **Line 101.** Change `| G-2 | real two-voice envelope | _pending (the Sprint 4 dissent runs)_ |` to `| G-2 | real two-voice envelope | e2e/g2-two-voice-envelopes.txt | review dissent run 1 at d785fc9a: 14/14 chunks voices_succeeded 2, rejected 0 |`.
- **Line 105.** Change `33 passed; 12/12` to `33 passed; 13/13`. `e2e/g4-residue-bats.tap` is `1..13` with 13 ok.

### n53: the plan and design still state the reverted ≤ 9,216 B target

- **`grimoires/loa/sprint.md:142`.** Append: " — **amended Sprint 4 Task 4.8**: the trim was reverted under the pre-registered A/B rule (`a2a/sprint-250/replay-ab-rerun.md`); the limit is back to 10,240 B (file 10,225 B)."
- **`grimoires/loa/sdd.md:79`.** Change "CLAUDE.loa.md ≤ 9,216 B" to "CLAUDE.loa.md ≤ 9,216 B (superseded, Sprint 4 Task 4.8: reverted per `a2a/sprint-250/replay-ab-rerun.md`; limit 10,240 B)".

### n61: the Bridgebuilder row's 200,000 is not labelled as BB's own cap

**Evidence.**

- `bridgebuilder-review/resources/config.ts:188` sets `maxInputTokens: 200_000` (BB's own payload cap, raised 128,000 → 200,000 by SDD 1.2.5).
- `core/truncation.generated.ts:28` sets `"claude-opus-5-5": { maxInput: 160000, maxOutput: 32000 }`.
- `effectiveInputBudget` (`core/truncation.ts:686-692`) takes `min(budget, row.maxInput)` only for a model id present in a table. `DEFAULTS.model` is `"opus"`, which has no row, so the effective BB bound on the default path is 200,000.

Separately, cheval's uncalibrated input bound is `probed_ceiling` 180,000.

**Text.** `docs/migration/v2.0-model-generation-floor.md:230`, New-way cell. Change "`DEFAULTS.model` is the `opus` alias, 200,000 in / 32,000 out" to:

> "`DEFAULTS.model` is the `opus` alias; BB's own payload cap `maxInputTokens` is 200,000 (config default) and `maxOutputTokens` 32,000. cheval still applies its own input bound (`probed_ceiling` 180,000 until calibration), so a BB payload between the two is refused by cheval with the calibrate-first message; set `max_input_tokens` ≤ 180,000 to stay under it."

Note for the lead: this is a latent BB-vs-cheval mismatch. On the default `opus` alias the generated 160,000 row is never applied, so payloads estimated between 180K and 200K pass BB's gate and are then preempted by cheval. The values were introduced in Sprint 1 (D-1.5) and are outside this diff, so I suggest a bead rather than a Sprint 4 fix. Possible remedies are resolving the alias before `effectiveInputBudget`, or a default of 160,000.

### n63: KF-040 "Current workaround" leads with the route-around

**Text.** `grimoires/loa/known-failures.md:1634`. Change the line to:

> `**Current workaround**: First confirm the host's network egress region is a supported one (VPN exit / cloud region) — the 400 is a policy refusal, not a transport fault. Only then route the run's hop through ~/.local/bin/claude-bedrock (CLAUDE_HEADLESS_BIN); on 2026-10-06 the same 913 KB call then succeeded (exit 0, 415,028 input tokens).`

Leave the Attempts row as the record of what happened. `kf-write-lib.sh` has no field-update operation (only `new`, `attempt` and `recur`, lines 322-324), so this is a direct, Read-first edit of the entry written this sprint. The ledger lint should be re-run afterwards.
