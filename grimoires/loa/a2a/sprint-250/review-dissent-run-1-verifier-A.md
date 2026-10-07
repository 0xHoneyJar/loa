# r250 dissent triage, set A (32 findings): cycle-126 Sprint 4, `2fcd4af8..d785fc9a`

Verifier: read-only Opus 5.5 subagent, 2026-10-06. Every premise was checked against `d785fc9a` (`git show` / `git diff 2fcd4af8..d785fc9a`) and, where a claim was behavioural, with a probe under `/tmp` (no repo writes, no model calls). Two findings (5, 23) come from a mislabelled pseudo-hunk: the YAML hunks attributed to `cheval.py` are `model-config.yaml`'s, and the T5 hunk attributed to the persona is `tests/integration/cycle099-tier-groups-defaults.bats:191-217`.

| n | voice | severity | verdict | one-line reason |
|---|---|---|---|---|
| 1 | claude-headless | BLOCKING | REFUTED | `model-config.yaml` hunk `@@ -1173,6 +1213,8 @@` adds `"claude-opus-5-5"` and `"claude-opus-5.5"` → `anthropic:claude-opus-5-5` to `backward_compat_aliases`. |
| 2 | claude-headless | ADVISORY | REFUTED | `.loa.config.yaml.example:961-962` was edited (`cheap: "anthropic:claude-sonnet-5"`, `opus: "anthropic:claude-opus-5-5"`), and the diff includes that hunk. |
| 3 | claude-headless | ADVISORY | DOC | True: the 5.5 entry's comment cites the vendor's statement that 4.6+ gets 1M at standard pricing. The same catalog still has `long_context` 2.0×/1.5× tiers (`verified: false`) on fable-5-1/fable-5/opus-5/sonnet-5 (lines 408/465/562/772). The contradiction is not stated anywhere. |
| 4 | claude-headless | ADVISORY | DOC | True that no live call used `claude-opus-5-5` (G-1 went through headless → fable-5-1), and reviewer.md does not say so. The temperature half is refuted: `claude-sonnet-4-6` was already `temperature_supported: false`, so `cheap` behaves the same. |
| 5 | claude-headless | ADVISORY | REFUTED | Pseudo-hunk mislabel. The real `cheval.py` diff (`--help` text at line 2929) and the `base.py` comment are in the range, and the YAML hunks belong to `model-config.yaml`. |
| 6 | claude-headless | ADVISORY | REFUTED | `gemini-3.1-pro-preview` has `capabilities: [chat, thinking_traces]` and `fallback_chain: [google:gemini-2.5-pro, google:gemini-headless]`. RES-5 asserts `thinking_traces`. |
| 7 | claude-headless | ADVISORY | REFUTED | `aliases.claude-sonnet-5: "anthropic:claude-sonnet-5"` already exists (the cycle-120 bare alias). The generated maps carry `["claude-sonnet-5"]="claude-sonnet-5"` (MODEL_IDS), and no 5.5 Sonnet exists. |
| 8 | claude-headless | ADVISORY | DECLINED | yq v4 (mikefarah) is a declared hard prerequisite (README.md:45, INSTALLATION.md:32), `bats-tests.yml:150` installs a pinned v4.52.4, and `gen-bb-registry-codegen.bats:36` skips without yq. The literal `opus → claude-opus-5-5` pin lives in c124-1.3-1, gen-adapter-maps:44, MA-1 and RES-1, as the report says. |
| 9 | claude-headless | ADVISORY | REFUTED | The adapter validates with exactly `_BETA_HEADER_RE.match(item)` (`anthropic_adapter.py:174`), and the regex is `^…$`-anchored (line 82). A missing schema path raises KeyError, so the test fails loudly rather than going silent. |
| 10 | claude-headless | ADVISORY | DECLINED | MODEL_IDS self-maps for every alias are already covered by `test_model_registry_parity.py::test_generated_aliases_match_python_resolution` (iterates every `aliases` + `backward_compat_aliases` key) and by the `gen-adapter-maps.sh --check` CI drift gate. |
| 11 | claude-headless | ADVISORY | DECLINED | The posture is correct today: the catalog's `claude-headless.extra` has only `cli_model`, and the adapter passes `--tools ""` and `--permission-mode plan`. The row's notes disclose the `allowed_tools` dependency, and per the migration addendum the rows have no runtime effect unless `context_filtering` is on. It is a hardening suggestion only. |
| 12 | claude-headless | ADVISORY | DECLINED | Hypothetical: the HEAD file has 25 unique row keys and no duplicates. A duplicate-key loader is general registry hardening, out of Sprint 4 scope. |
| 13 | claude-headless | ADVISORY | REAL (low) | `test_current_generation_rows_mirror_the_4_7_scopes` pins 6 keys. The migration addendum states that every Anthropic entry has 4.7's scopes, but 10 Anthropic/Bedrock rows are unpinned (all currently match; verified). |
| 14 | gpt-5.5-pro | BLOCKING | DECLINED | By design: the forward-compat patterns admit unlisted ids and leave validation to dispatch (`flatline-orchestrator.sh:558-562` comment; the old pattern already took `[-.]`). `claude-opus-5.5` resolves (compat alias). `claude-fable-5.1` fails at cheval with a clear `INVALID_CONFIG: Unknown alias` (dry-run verified). Not BLOCKING. |
| 15 | claude-headless | ADVISORY | REAL (low) | `model-adapter.sh:655-659`: the new `mktemp` has no cleanup trap, and under `set -euo pipefail` (line 33) a failing `mktemp` now aborts the adapter before the model call. The old `2>/dev/null` path had neither problem. |
| 16 | claude-headless | ADVISORY | DECLINED | Pre-existing: the base discarded all stderr (`2>/dev/null`), and LOW-001's scope was the agy WARN passthrough only. Surfacing a failure tail is a feature request. |
| 17 | claude-headless | ADVISORY | DECLINED | `aliases.reviewer` is `openai:gpt-5.5`, so the default stays cross-family. The `gpt`/`opus` labels and the OPENAI_API_KEY usage text are pre-existing (base lines 211, 404). Re-pointing `reviewer` is an operator choice. |
| 18 | claude-headless | ADVISORY | REFUTED | When the generated maps are absent, unmapped names (`cheap`, `gpt-5.5`) pass through raw to cheval (`flatline-orchestrator.sh:992`), and cheval resolves them from the catalog. The model-adapter comment is accurate: every 4.x row equals `backward_compat_aliases` (`claude-opus-4-6` → `anthropic:claude-opus-4-7`, verified). red-team's "(cycle-082)" note is historical, not contradictory. |
| 19 | claude-headless | ADVISORY | REFUTED | The catalog serves `providers.bedrock.models.us.anthropic.claude-opus-4-8`, and RES-4 asserts that. |
| 20 | claude-headless | BLOCKING | REAL | `model-residue.bats:60,63`: a non-final `! grep -q` cannot fail a bats test (bash exempts `!` from errexit/ERR). A probe proved a mid-test `! grep` on a matching file passes. The same defect sits at `hook-guard.bats:152` and `implement-gate.bats:152`. |
| 21 | claude-headless | ADVISORY | DECLINED | Vendor-sourced and documented: the catalog comment cites the pricing page (cache hit 0.05× = $0.20), and `test_anthropic_catalog_floor.py` lists `claude-opus-5-5: 200_000` under `CACHE_READ_EXCEPTIONS` with the citation (fable-5-1 is already a 0.025× exception). It cannot be refuted offline. |
| 22 | claude-headless | ADVISORY | REFUTED | `gemini-2.5-pro` is still a served catalog model (`providers.google.models`) and an alias, and cheval lists it as available. |
| 23 | claude-headless | ADVISORY | REFUTED | Pseudo-hunk mislabel: T5 lives in `tests/integration/cycle099-tier-groups-defaults.bats`. The persona file is 30 lines of prose with one changed line (28/30). |
| 24 | gpt-5.5-pro | BLOCKING | DECLINED | By design (SDD D-4.4: "Authoritative mode requires `implement_gate.mode: authoritative` in `.loa.config.yaml`"). The gate is ADVISORY (hooks-reference §implement-gate.sh). The heuristic path is equally model-forgeable through `.run/sprint-plan-state.json` RUNNING + `plan_id`, so this sprint did not widen the gate, and the old selector (`.run/platform-features.json`) was model-writable too. |
| 25 | claude-headless | ADVISORY | DECLINED | Same as 24. The claimed lost audit event is refuted: the removed `compliance.mode.change` emit was dead code (`previous_mode` was assigned the empty `compliance_mode` inside the `-z` branch, so `[[ -n "$previous_mode" ]]` never held). |
| 26 | claude-headless | ADVISORY | DECLINED | yq v4 is a hard prerequisite, and a missing or failing yq degrades toward heuristic, which asks (the safe direction). |
| 27 | claude-headless | ADVISORY | DECLINED | No consumer reads `detected_at`/`harness_signal`/`schema_version`: the gate no longer reads the file, and `/loa` runs `--line`, which reads only `active_skill_seen_at`/`_source`. Nothing invokes the refresh path automatically. |
| 28 | claude-headless | ADVISORY | DECLINED | CI installs pinned yq v4.52.4 (`.github/workflows/bats-tests.yml:150-154`), so the yq-gated cases run there. |
| 29 | claude-headless | ADVISORY | REAL | Probe: `allow: ["Bash"]` → exit 1 (should be 0). `allow: <all 16> + deny: ["Bash"]` → exit 0, and the same for `deny: ["Bash(*)"]` (should be 1). `rule_key` (`check-permissions.sh:162-173`) drops bare `Bash` and keys `Bash(*)` as exact `=*`. The gap is pre-existing, but this sprint rewrote the grammar and the addendum claims Claude Code parity. |
| 30 | claude-headless | ADVISORY | DECLINED | jq is a hard prerequisite (README.md:45), and no consumer distinguishes an absent file from `harness_signal: false` (see 27). |
| 31 | claude-headless | ADVISORY | DECLINED | A leftover schema-1 file is read by nothing: the gate stopped reading `active_skill_available`, and `--line` prints only the evidence fields. The window closes after at most 1 h. |
| 32 | claude-headless | ADVISORY | DECLINED | It self-heals: the gate's once-guard keys on the absence of `active_skill_seen_at` (`implement-gate.sh:42`), so a lost record is re-recorded on the next lead payload. The refresh path has no automatic caller, so the race needs a manual run. |

**Counts:** REAL 4 (13, 15, 20, 29) · DOC 2 (3, 4) · REFUTED 10 (1, 2, 5, 6, 7, 9, 18, 19, 22, 23) · DECLINED 16 (8, 10, 11, 12, 14, 16, 17, 21, 24, 25, 26, 27, 28, 30, 31, 32). Of the 3 BLOCKING findings, 1 is REAL (20); 1 and 14 are refuted or declined, and 24 is declined.

---

## REAL 20: vacuous `! grep` assertions (BLOCKING → fix)

**Evidence.**
- `tests/unit/model-residue.bats:60`: `! grep -q 'claude-opus-4-7' …/hitl-jury-panel/SKILL.md`. It is not the last command of RES-4.
- `tests/unit/model-residue.bats:63`: `! grep -q 'claude-3-5-sonnet' …/alternative-model.md`. Not last.
- Same class, also added this sprint:
  - `tests/unit/hook-guard.bats:152`: `! grep -q "PreToolUse hook" "$err"`, followed by two more greps, so it is vacuous.
  - `tests/unit/implement-gate.bats:152`: the `.loa.config.yaml.example` check. Line 153 is final, so only 153 is effective.
- Probe: a bats test containing `echo hello >f; ! grep -q hello f; true` reports `ok`.
- Mitigation that does not cure it: RES-6 covers `model: claude-opus-4-7$` and `claude-3-5-sonnet` under `.claude/data`. The RES-4 lines themselves still can never go red, and the hook-guard (d) assertion has no backstop.

**Fix.**
1. Rewrite the four lines as `run ! grep -q …` (`implement-gate.bats` already declares `bats_require_minimum_version 1.5.0` at line 17; add it to `setup()` in model-residue.bats and hook-guard.bats), or use `run grep -q …; [ "$status" -eq 1 ]`.
2. Optionally add a lint that greps `tests/**/*.bats` for a non-final `^\s+! ` line.

**Red first.** Insert `claude-opus-4-7` into a copy of hitl-jury-panel/SKILL.md, or point `$R` at a fixture tree. Today RES-4 passes. After the fix it fails. Likewise make `$err` contain "PreToolUse hook" for hook-guard (d).

## REAL 29: bare `Bash` / `Bash(*)` unmodelled in the permission grammar

**Evidence.**
- `.claude/scripts/check-permissions.sh:164` returns 1 for anything not `Bash(…)`, so bare `Bash` is skipped in both allow and deny.
- For `Bash(*)` the body `*` matches neither `*":*"` nor `*" *"`, so it becomes the exact key `=*`.
- Probe `/tmp/cpprobe.sh` (temp HOME and root): `allow ["Bash"]` → rc 1; all 16 allows + `deny ["Bash"]` → rc 0; all 16 + `deny ["Bash(*)"]` → rc 0.
- The deny direction is the dangerous one: preflight passes, then the unattended run stalls at the first prompt.
- The gap is pre-existing (the base used exact-string match too). But SDD D-4.5 requires "generic denies cover every subcommand", and the migration addendum says the preflight "reads permission rules the way Claude Code does".

**Fix.**
1. In `rule_key`, map a trimmed `Bash`, and a body that is exactly `*` after trimming, to a universal key (e.g. `RULE_KEY="ALL"`).
2. In `main`, check `deny_by[ALL]` first (it denies every requirement), then the existing key/base checks, and treat `allow_by[ALL]` as satisfying every requirement.
3. The header grammar comment and the addendum each get one sentence.

**Red first.** New CP-14 table rows:
- allow `["Bash"]` → exit 0;
- all 16 + deny `["Bash"]` → exit 1 with `denied[]` naming `Bash`;
- the same with deny `["Bash(*)"]`.

The two deny cases are red today.

## REAL 13: trust-scope mirror test pins 6 of 16 Anthropic rows

**Evidence.**
- `.claude/adapters/tests/test_trust_scopes.py:362` pins only opus-5-5, opus-5, sonnet-5, fable-5-1, opus-4-8 and bedrock opus-4-8.
- The migration addendum (`docs/migration/v2.0-model-generation-floor.md`, the "Opus 5.5 is the `opus` alias" bullet) says every Anthropic entry, direct or Bedrock, has the same trust scopes as `claude-opus-4-7`.
- All 16 rows currently match (verified). But for 10 of them (fable-5, sonnet-4-6, sonnet-4-5, haiku-4-5, headless, opus-4-6, and bedrock opus-4-7/sonnet-4-6/haiku), a widened scope would pass CI.

**Fix.** Derive the key list from the catalog, reusing `served` from `test_every_anthropic_catalog_entry_has_a_row`, and assert that `trust_scopes`/`trust_level`/`execution_mode`/`capabilities` equal the 4.7 reference for every served key. Use an explicit allow-list for any intended difference (there are none today).

**Red first.** In a temp copy of the registry, set `anthropic:claude-headless.trust_scopes.data_access: high`. The current test passes; the new one fails.

## REAL 15: model-adapter stderr temp file has no cleanup and a new failure mode

**Evidence.** `.claude/scripts/model-adapter.sh:655-659` together with `set -euo pipefail` at line 33:
- `err_file="$(mktemp …)"` is a plain assignment, so a failing `mktemp` (full or read-only TMPDIR) aborts `main` before cheval runs. That is a regression: the previous `2>/dev/null` had no TMPDIR dependency.
- `rm -f` runs only on the normal path, so a caller timeout kill (Flatline / red-team / jury per-panelist timeouts) leaves `model-adapter-stderr.*` holding cheval's stderr in TMPDIR.

**Fix.**
- Use `err_file="$(mktemp …)" || err_file=""`.
- When `err_file` is empty, redirect to `/dev/null` and skip the grep and the rm. Never `rm -f` a `/dev/null` fallback.
- Add `trap 'rm -f -- "$err_file"' EXIT` right after a successful `mktemp`. `main` exits the process, so EXIT is appropriate.

**Red first.** A model-adapter.bats case with the existing MODEL_INVOKE shim (as MA-4) and `TMPDIR=/nonexistent`:
- today: exit non-zero with a mktemp error, and the shim argv is never written;
- after the fix: exit 0, and the shim is invoked.

A second case: the shim sleeps, the test sends `kill -TERM` to the adapter, and no `model-adapter-stderr.*` remains in a private TMPDIR.

## DOC 3: the long-context tier is contradicted inside the catalog

**Evidence.**
- `.claude/defaults/model-config.yaml:470-479`: the `claude-opus-5-5` comment quotes the vendor, "Claude 4.6 and later models … include the full 1M token context window at standard pricing", and concludes "so no long_context tier".
- Lines 405-412, 462-468, 562 and 772 keep `long_context` (threshold 200000, 2.0×/1.5×, `verified: false`) on fable-5-1, fable-5, opus-5 and sonnet-5, all 4.6-and-later.
- `metering/pricing.py:61-66` applies those multipliers. Today the 180K ceiling keeps requests below the threshold.
- Which side is right needs vendor or invoice confirmation. The contradiction itself is a documentation defect.

**Fix (text).**
- In the opus-5-5 comment, after "so no long_context tier", append: "(the 5-family entries above keep their `verified: false` reference tier until an invoice settles which reading holds; tracked in <bead>)".
- In the migration addendum bullet "… and no long-context tier", add: "(the other 5-family entries keep an unverified 2×/1.5× tier above 200K pending invoice confirmation)".
- File a bead to reconcile after the operator checks an invoice.

## DOC 4: no live call has exercised the new `opus` target

**Evidence.**
- reviewer.md:14 says "vendor-sourced 1M input / 128K output, $4/$20".
- The only real call was G-1 (reviewer.md:100, `claude-headless` → `claude-fable-5-1`). `claude-opus-5-5` has dry-run and unit coverage only.
- If the vendor rejects the id, `opus` walks its chain to `claude-opus-5` ($5/$25), and only the log shows it.

**Fix (text).** At the end of reviewer.md:14, append: "No live dispatch has used `claude-opus-5-5` yet. The id, the adaptive-thinking wire shape and the pricing are vendor-doc sourced and covered by dry-run plus unit tests. A refused id falls back to `claude-opus-5` (logged in MODELINV). A one-call smoke with `--model opus` is an operator action." Optionally add the same sentence to the migration addendum's Opus 5.5 bullet.
