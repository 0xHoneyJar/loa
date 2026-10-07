# Implementation Report — Sprint 4 (Final): Residue, registry, probes, docs and E2E (cycle-126, global sprint 250)

**Cycle:** cycle-126 full-size · **PRD:** FR-4 + G-1 … G-5 · **SDD:** §1.5 (D-4.1 … D-4.5) · **Plan:** `grimoires/loa/sprint.md` Sprint 4
**Implementer:** Opus 5.5 subagent (Tasks 4.1–4.6) and the lead (4.7, 4.8, E2E) under `/run sprint-plan`, unattended · **Epic:** bd-qgsn
**Commits:**
- `a9ecda08`: Tasks 4.1–4.6.
- `e612fa2d`: Task 4.8 grader 1.1.0 and the folded LOWs.
- `98d8a486`: RES-7.
- `bf988a43`: the pre-registered A/B revert.
- `fd8aaae3`: Task 4.7 — the license-fixture freshness guard, the stale tests and the cheval `--help` text.
- `d785fc9a`: E2E records (the CHANGELOG figure, KF-034 recurrence, KF-040).
- `17291942`: review round r250-1 (`review-dissent-triage-run-1.md`).
- `4b347efc`: review round r250-2 — the Bridgebuilder input budget follows the resolved model (alias rows and the clamped trigger).
- `64c2eb09`: review round r250-3 (`review-dissent-triage-run-2.md`) — grader parser classes, the Pass 2 budget assertion, the adapter trap and WARN, the 3,600 s margin, `Bash(:*)`, and `run -1 grep`.
- `27ff5a4b`: review round r250-4 (`review-dissent-triage-run-3.md`) — grader 1.1.2: the URL look-back no longer crosses a line break, linear time; MA-10 covers the chained EXIT handler.
- `39bfff76`: review feedback round 1 (`engineer-feedback.md`) — CHANGELOG lines for the BB alias budget clamp, universal Bash rules, grader 1.1.2 and the east-of-UTC license fixtures; the migration guide names `Bash(:*)` and the `opus` effort-default caveat; the headless adapter docstring example binds `opus`/`cheap` to the 5-family. 
- `db49cd32`: the SDD amendment after D-4.1/D-4.3 (the `opus` → `claude-opus-5-5` retarget, bd-2fti, the effort caveat and the loa-aleph deviation) and the matching sprint.md Task 4.9 row.
- `4d37029e`: review round 2 APPROVED (Fable, 0/0/1/4) — Sprint 4 checkmarks; the SDD cost row and ceiling example follow the D-4.1 amendment (round-2 Observation 2).
- `e151757d`: audit round r250-6 (`audit-dissent-triage-run-1.md`) — the implement gate's ask reaches Claude Code and authoritative mode is tighten-only; `AGENT_TYPES_FILE` bats-gated; C1 controls dropped from the log sanitiser; `python3 -I -`; exact beta-header check; literal trust-scope pins; printable-ASCII evidence line.
- `ee8fb582`: audit round r250-7 (`audit-dissent-triage-run-2.md`) — the gate classifies canonical paths and fails closed on unparsable payloads, missing jq, uncanonicalisable paths and `notebook_path`; every forged claim leaves a row; one `strip_controls`; fixed-point C1 strips; `--line` shape checks.
- `005b9105`: audit round r250-8 (`audit-dissent-triage-run-3.md`) — both path forms, lowercased matching, trust-input asks, `cwd`-relative resolution, raw `jq -a` audit rows, the wider strip set, jq-built asks; the lib's copy cut before its fixed point, the same strip set, UTF-8 validation; the validator's `--agent-types-file` seam replaces the env variable.
- `e170de3d`: post-audit round r250-9 (`auditor-sprint-feedback.md` MED-001, LOW-002/003/004) — the gate's root never follows the process cwd (IG-21); all three heuristic state files must be fresh (IG-22); `python3 -I -` in the Flatline orchestrator's configured-model heredoc and the companion suite (FOPI-1–3); the hooks reference describes the wired gate (W6). ledger.json marks sprint 250 completed.
- `8675d7c5`: round r250-10 — PR #1274 CI (the `grep -P` lint hit and three raw `sha256sum` sites in `adversarial-review.sh`; the evals fixture copy of `golden-path.sh`) and audit addendum LOW-006 (the freshness window bounds both directions; `sprint-plan-state.json` goes through `_ig_fresh`; IG-22 extended).

## Summary

- **Catalog aliases.** The catalog's `opus` now resolves to a new `claude-opus-5-5` entry: vendor-sourced 1M input / 128K output, $4/$20. Its ceiling is a conservative 180K, marked `loa:shortcut`; raising it needs the operator-only live probe. `cheap` resolves to `claude-sonnet-5`. No live call has reached `claude-opus-5-5` yet: the G-1 call went headless → `claude-fable-5-1`. If the vendor refuses the id, the entry's `fallback_chain` goes to `anthropic:claude-opus-5`.
- **Generated and dependent artifacts.**
  - The bash maps, the BB registry and dist are regenerated.
  - The model-adapter, red-team-model-adapter and Flatline regexes admit the 5-family.
  - Every Anthropic catalog entry has a `model-permissions.yaml` row.
  - The previous-generation default pins in six scripts and skills are now aliases.
- **Implement gate.** `implement-gate.sh` records `active_skill` evidence. It does so in the lead session only, once, atomically, and records the field's source.
  - Research outcome (Task 4.4): the PreToolUse payload carries no harness-set skill signal that a model-authored `tool_input` cannot forge.
  - Per the plan, `implement_gate.mode: authoritative` is therefore not documented, and no `.run` file can select it. A forged-payload test pins that.
- **Other probes and checkers.**
  - `detect-platform-features.sh` reports truthfully and feeds an `Implement gate:` line on `/loa`.
  - `.claude/data/agent-types.yaml` is the write-capable agent list that `validate-skill-capabilities.sh` reads.
  - `check-permissions.sh` reads both rule grammars.
- **Docs.** The migration guide addendum, the CHANGELOG and the README are updated.
- **Grader (Task 4.8).** The recall grader is fixed test-first (bd-ewrc), and the Sprint 3 A/B is re-run on it.

## Tasks

### 4.1–4.6 (`a9ecda08`)
- **Aliases, maps and regexes.** Covered by `model-adapter.bats` MA-1–6, `model-residue.bats` RES-1–6, `flatline-model-validation.bats`, `gen-adapter-maps.bats` and `cycle-124-anthropic-catalog.bats`. `model-config-v3-schema` is 33/33 with the schema extended for the new entry fields.
- **Registry.** `model-permissions.yaml` has a row per Anthropic catalog entry, asserted by `test_trust_scopes.py` (33 passed, 269 subtests).
- **Pins.** `flatline-proposal-review`, `flatline-validate-learning`, `flatline-learning-extractor`, `red-team-pipeline`, `hitl-jury-panel` and `alternative-model` now use aliases. `deep-thinker` is `gemini-3.1-pro`.
- **Probes.**
  - `implement-gate.bats` IG-1–11, including the forged-payload case.
  - The `tests/fixtures/pretooluse-payloads/` corpus with `expected.tsv`.
  - `compliance-hook` CH-T8 no longer passes vacuously.
- **Permission grammar.** `check-permissions.bats` CP-11–13 cover both forms, mixed layers, whitespace and escaping, and the dangerous-shape fuzz set.
- **Folded beads.**
  - `validate-artifact.sh` uses here-strings (bd-8ndx).
  - `lib-content.sh` index guards and log-line control stripping (bd-pw7e LOW-002/003).
  - model-adapter passes cheval's agy WARN through (LOW-001).
  - bd-pw7e LOW-004 stays open.

### 4.8 — Recall grader 1.1.0 and the A/B re-run (`e612fa2d`; bd-ewrc)
- **Parser fixes.**
  - A leading `(` is no longer part of the cited path.
  - Comma continuations are read.
  - A bare `:N` / `head:N` / `base:N` binds to the most recently cited path, while `10:40` and `note:40` earn nothing.
  - Defects may carry `anchors[]`: D13 [776, 807] and D06 [57, 83], each verified against the fixture head.
  - `eval-recall-grader.bats` RG-11–17 were red first, and the suite is 17/17.
- **Agreement with the Sprint 3 blind adjudication** (`replay-ab-rerun-prereg.md`, scripts under `eval-scripts/`):
  - Disagreements: 38 → 11.
  - Condition (a), ≤ 1 slot per case, is **not met** on two case/arms. Both are location-vs-semantics limits, not parser drops: audit-pr-07 in both arms (+2) and audit-pr-02 in the before arm (−2).
  - This is disclosed for the review and audit to rule on.
- **Re-run** (`replay-ab-rerun.md`; rule pre-registered 2026-10-05T23:25Z, run launched 23:26Z).
  - Three cases hold at 27/27: review-pr-02/05 and audit-pr-03.
  - Two cases lose on the grader measure: audit-pr-02 goes 27 → 25 and audit-pr-05 goes 27 → 24.
  - On blind adjudication those two are 26 and 27. The four slots the grader missed but the adjudicator found are citation-location misses, not parser drops.
  - The gate fails, so the ablations ran:
    - rationales reverted: 27 / 26;
    - CLAUDE.loa.md trim reverted: 26 / 26.
    - Both restore before-level recall.
  - Per the rule, both are reverted in `bf988a43` (IDR-1–4, PB-4/6 red first). `CLAUDE.loa.md` is byte-identical to `main` again, and its budget goes back to 10,240 B (the file is 10,225 B).
  - The Sprint 3 AC "CLAUDE.loa.md ≤ 9,216 B" is given up for the recall gate; this is disclosed.
  - Post-revert re-run at bf988a43: audit-pr-02 27/27, audit-pr-05 26/27. **The gate passes**, and the Sprint 3 recall AC is met.
- **Condition (b).** `c9b7bdc0` is preserved as `record/cycle-126-ablate-c9b7bdc0` (pushed with the a2a record at cycle end). The Sprint 3 scripts are in `a2a/sprint-249/eval-scripts/`.

### Folded LOWs (`e612fa2d`)
- **protocol-refs-resolve.** The scan now covers `protocols/reference/` pointers. PR-4 was red on the old regex.
- **hook-guard WARN.** The text says the hook did not run and the guard failed OPEN; it no longer says "PreToolUse hook". hook-guard is 8/8.
- **Declined: reverting the KF-006 header to ≥ 6.** known-failures.md is append-only, and the correction row is the remedy.

### Residue grep (AC 1)
The literal AC grep (`claude-opus-4-`, `claude-sonnet-4-`, `gpt-4o` over scripts, skills and data) returned 153 lines at `e612fa2d`, and every line was classified below. It returns 152 at `fd8aaae3`, after RES-7 fixed the one non-excepted line (`e2e/g4-residue-grep.txt`).

| Class | Lines | Verdict |
|---|---|---|
| Generated from the catalog (`generated-model-maps.sh`, BB `*.generated.ts`) | 97 | excepted (catalog) |
| `model-permissions.yaml` rows for previous-generation entries the catalog still serves | 13 | registry, not a default |
| Bash compatibility maps (`model-adapter`, `flatline-orchestrator`, `red-team-model-adapter`): legacy pins → a served id | 19 | backward compatibility; `opus` itself agrees with the catalog (RES-2) |
| `aliases-legacy.yaml`, the frozen pre-cycle-095 kill-switch snapshot | 2 | by design ("Do NOT hand-edit") |
| BB `truncation.ts` legacy rows | 4 | data for pinned old ids |
| Format examples in comments, help and schema descriptions (`lib-provider-parse`, `model-resolver`, `substrate-*`, `red-team-model-adapter` help, trajectory schemas, operator-detection, cost-budget-enforcer, `alternative-model` "MAY swap", BB comments, the learning-extractor's "retired gpt-4o-mini" note) | 16 | illustrate the id form; not defaults |
| `loa-aleph/SKILL.md:34` | 1 | Aleph is untouched by policy |
| **`flatline-readiness.sh:259`, the operator recommendation's pin example** | 1 | **fixed**: now `anthropic:claude-opus-5-5`, RES-7 red first |
| Python scripts and a schema description, outside the recorded grep's file set (review round 2, Observation 3): `lib/model-overlay-hook.py:407,410` (a design-note docstring showing the emitted bash form), `lib/model-config-migrate.py:259` (the migrator's reasoning-class prefix matcher, a compat matcher for entries the catalog still serves), `loa-migrate-model-config.py:326` (a migration help string), `lib/model-resolver.py:370` (a docstring example of the `aliases:` block), `trajectory-schemas/model-error.schema.json:53` (a schema `description` example); the lead's wider sweep of `*.py`/`*.json`/`*.ts` outside generated, dist and test files adds `budget-record-call.payload.schema.json:42` and `model-resolver-output.schema.json:63` (schema examples) and the BB comments `adapters/index.ts:64`, `core/multi-model-pipeline.ts:50` (KF-010 note; a reasoning-class example) | 9 | examples and a compat matcher; none a default, none described as current |

### Audit round r250-6 (`e151757d`; audit dissent run 1, 51 findings, none at HIGH)
Rulings are in `audit-dissent-triage-run-1.md`; verifier evidence in `audit-dissent-run-1-verifier-{A,B}.md`. Changes, each red first:
- **n20 — the gate's ask reaches Claude Code.** Both `implement-gate.sh` ask sites now emit `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":…}}`; the former top-level `{"decision":"ask"}` is undefined in the PreToolUse contract (`decision` admits approve|block) and was validated away, so the App-Zone ask was never applied. `implement-gate.bats` `decision()` and CH-T8/T10 read the new shape only.
- **n17/n18/n21 (+ Fable round-1/2 MED 1, bead bd-8sxh) — authoritative mode is tighten-only.** A model-authored `active_skill` claim never grants an allow: an implementation claim falls through to the heuristic, a non-implementation claim asks and writes one `compliance.mode.model_signal` row; `file_path`/`active_skill` are stripped of control characters before stderr and the row. `expected.tsv` authoritative column: three `allow` → `ask`; IG-12 proves strictly-tighter under a RUNNING state; IG-13 pins the stripping. CH-T8 now defers an `implement` claim to the heuristic.
- **n24 — `/loa` evidence line.** Printable ASCII only; the refresh keeps `active_skill_seen_at` only as ISO-8601 UTC and `active_skill_source` only as `tool_input` (IG-14).
- **n27 — `AGENT_TYPES_FILE`.** Honoured only under the bats markers (SC-T-AGENT-10); bead bd-7cur for the pre-existing `PROJECT_ROOT`/`SKILLS_DIR` seams.
- **n30 — log sanitiser.** UTF-8 C1 controls (C2 80–C2 9F) are dropped by a portable bash loop; `café` passes (CMP-279).
- **n32/n39 — `python3 -I -`** in the recall grader, `check-prompt-budget.sh`, IDR-3, LFF-1/3/4 and RES-5; RG-27 plants a forging `json.py` in the invoker's cwd (it yielded `pass: true` before).
- **n1/n4 — beta headers.** `_BETA_HEADER_RE` is the schema's pattern string with ASCII digits, applied with `fullmatch`; the V3 case now also asserts the converse (schema-rejected ⇒ adapter-rejected, incl. a trailing newline and Arabic-Indic digits).
- **n7 — trust scopes.** The reference row's capabilities (all False) and `security: redacted` are pinned literally.
- **n48 (DOC)** — KF-040 Attempts row via `kf-write-lib.sh`. **Beads** for the pre-existing items: bd-z5yw (n10, P2), bd-lemw (n8, P2), bd-7cur, bd-mt9c, bd-gm9p, bd-muk5, bd-6x75, bd-s03k, bd-2rhn, bd-w8lj, bd-x2rp; comments on bd-ugmi (n13/14/41) and bd-j8v1 (n51).
- **Suites, real tree, serial:** implement-gate 14/0/0, compliance-hook 14/0/0, skill-capabilities 36/0/0, eval-recall-grader 27/0/0, prompt-budget 9/0/0, instruction-diet-revert 4/0/0, license-fixture-freshness 5/0/0, model-residue 7/0/0, model-config-v3-schema 33/0/0, CMP-278/279 2/0/0, repo-map-gen 6/0/0; adapters pytest `-k 'anthropic or beta or thinking or trust or full_size'` 396 passed; `regen-checksums --check` changed=0; `check-prompt-budget.sh` exit 0.

### Audit round r250-7 (`ee8fb582`; audit dissent run 2 on the r250-6 delta, 12 findings, none above MEDIUM)
Rulings in `audit-dissent-triage-run-2.md`. The MEDIUM that mattered was pre-existing but adjacent: the App-Zone test compared text against `$PROJECT_ROOT/`, so a non-canonical spelling (`/proc/self/cwd/src/x`, `//root/src/x`, `root/../name/src/x`, a symlinked root) reached an App-Zone file with no ask. Now both sides are canonicalised and the gate fails closed when it cannot read or resolve the payload (IG-15/16, a NotebookEdit corpus row); every model-authored `active_skill` claim under the opt-in leaves one `compliance.mode.model_signal` row (IG-12); one `strip_controls` copy for stderr and the audit row (C0, C1, format/bidi, fixed point, 256 B — IG-13); the lib's C1 strip is a fixed point too (CMP-280); `--line` applies the refresh's shape checks (IG-14). The bats-marker seam is documented as a convention, not a boundary. Bead bd-taee tracks binding the heuristic's RUNNING allow to a marker a model cannot write.
- **Suites:** implement-gate 16/0/0, compliance-hook 14/0/0, skill-capabilities 36/0/0, CMP-278/279/280 3/0/0, hook-guard 8/0/0, repo-map-gen 6/0/0; `regen-checksums --check` changed=0.

### Audit round r250-8 (`005b9105`; audit dissent run 3 on the r250-7 delta, 13 findings, none above MEDIUM — the last dissent run)
Rulings in `audit-dissent-triage-run-3.md`. Round r250-7's physical canonicalisation had regressed inside-out symlinks (`src/` → outside the root was now allowed where the textual test asked); the gate now ORs the physical and the logical form (IG-17), matches a lowercased copy for case-insensitive filesystems (IG-15, corpus row), asks and logs `compliance.state_write` on a write to its own six trust inputs (IG-18), resolves relative paths from the payload's `cwd` (IG-19), records raw claims with `jq -a` so a padded `implement` is visible as such (IG-13), and builds asks with jq (IG-20). The lib's stderr copy is cut before its fixed point, drops the format/bidi set and validates UTF-8 (CMP-281–283). The validator ignores the ambient `AGENT_TYPES_FILE`; `--agent-types-file` is the test seam. Finding 9 (git's quoted `diff --git "a/…"` headers fold a file's hunks into the preceding chunk — pre-existing) is bead bd-d7kx.
- **Suites:** implement-gate 20/0/0, compliance-hook 14/0/0, skill-capabilities 36/0/0, CMP-278–283 6/0/0, hook-guard 8/0/0, repo-map-gen 6/0/0; `regen-checksums --check` changed=0.

### Post-audit round r250-9 (`e170de3d`; audit round 1 APPROVED 0/0/1/5)
The Fable audit approved the sprint and asked for its one MEDIUM to land before the cycle PR: the hook derived its root from `$(pwd)`, which follows Claude's `cd`, so from a subdirectory both root-relative forms fell outside the root and an App-Zone or trust-input Write was allowed silently (a pre-sprint behaviour the three rounds had not reached). The root is now `PROJECT_ROOT` → `CLAUDE_PROJECT_DIR` → the hook's own location (IG-21 exercises the harness-dir rung from a subdirectory and the script-location rung from a subdirectory and from the root). LOW-004: `state.json` and `simstim-state.json` require a `last_activity`/`updated_at` under 24 h (IG-22). LOW-003: `flatline-orchestrator.sh`'s heredoc runs `python3 -I -` with the adapters directory from argv (FOPI-2 plants `json.py`/`yaml.py`); the companion suite's seven heredocs take `-I`. LOW-002: the hooks reference row and section describe the wired gate; hook-wiring W6 pins the row to `.claude/settings.json`. LOW-005: the run-2 triage headline corrected. LOW-001 is bead bd-4iit.
- **Suites:** implement-gate 22/0/0, compliance-hook 14/0/0, hook-wiring 10/0/0, flatline-orchestrator-python-isolation 3/0/0, flatline-model-allowlist 18/0/0, flatline-model-validation 20/0/0, flatline-max-tokens 6/0/0, the changed companion cases + CMP-278–283 12/0/0, hook-guard 8/0/0, repo-map-gen 6/0/0, protocol-refs-resolve 4/0/0; `regen-checksums --check` changed=0. Live probe: the hook invoked from a subdirectory with no `PROJECT_ROOT`/`CLAUDE_PROJECT_DIR` asks on `src/probe2.ts`.

## E2E (G-1 … G-5)
Evidence is under `e2e/`. Local legs were re-collected at `fd8aaae3` (2026-10-06T06:46Z): ceiling/retry/transport 27 passed, Flatline cap 9/9, residue + adapter bats 13/13, fence corpus 287/287, kill switch 38 passed, trust scopes 33 passed. The residue grep is now 152 lines; RES-7 removed one.

| Goal | Evidence | Result |
|---|---|---|
| G-1 | `g1-ceiling-e2e.txt`: the 600K gate, retry and transport matrix | 27 passed |
| G-1 | `g1-dry-run-fable.json` | claude-fable-5-1, max_tokens 64000 |
| G-1 | `g1-bb-registry-excerpt.txt` | 12 rows |
| G-1 | `g1-deriveTimeoutMs.txt` | 1,800,000 ms for every 5-family id |
| G-1 | `g1-flatline-cap.tap` | 9/9 |
| G-1 | real call above the ceiling: `g1-real-call.txt` (3 attempts, at `fd8aaae3`) | **Pass.** The input was 913 KB of concatenated scripts with the needle mid-document. The answer `OSPREY-7412 \| .claude/scripts/cluster-skills.sh` is exact: the needle is found and the last of 45 FILE headers is named. The call ran through `anthropic:claude-headless` (CLI transport) → `claude-fable-5-1`: exit 0 in 20 s, **415,028 input tokens** (`cache_creation_input_tokens`), 350 output tokens. MODELINV row 2026-10-06T06:41:11Z. Attempts 1 and 2 (the bare subscription CLI and `claude-fallback`) were refused with a geo 400, correctly non-retryable; that is environmental egress, new KF-040. Attempt 3 used the companion's `claude-bedrock` route. |
| G-2 | real two-voice envelope: `g2-two-voice-envelopes.txt` (review dissent run 1 at `d785fc9a`, 06:51Z–08:01Z) | **Pass.** Every one of the 14 chunks has `voices_planned 2`, `voices_succeeded 2` [codex-headless, claude-headless], the companion `independent`, and `rejected_count 0`. The merged `adversarial-review.json` carries 63 findings. |
| G-2 | the three fixtures' findings: `g2-fixtures-normalise.tap` | 67/67 ok, 0 skip (NRM-7: the repair loop also recovers the fixtures with the normaliser bypassed) |
| G-2 | `verdict-derive` failure/success pair: `g2-verdict-derive-pair.txt` | Run against the c1 envelope plus one rejected row. With no `## Rejected dissent payloads` section: INCONSISTENT, exit 1. With the section: CONSISTENT, exit 0. |
| G-3 | `g3-budget-before/after.txt` | CLAUDE.loa.md 10,225 → 10,225 B (the trim was reverted, `bf988a43`); protocols 199,593 → 131,189 B. The CHANGELOG's 131,164 B predated round s3-1b's one-line edit and is corrected. |
| G-3 | `g3-include-diff.stat` | 18 files |
| G-3 | A/B report: `replay-ab-rerun.md` | the gate **passes** after the pre-registered revert: audit-pr-02 27/27, audit-pr-05 26/27 |
| G-4 | residue table above; `g4-trust-scopes.txt`; `g4-residue-bats.tap` | 33 passed; 13/13 |
| G-5 | `g5-fence-corpus.tap` | 287/287 |
| G-5 | `g5-kill-switch.txt` | 38 passed |
| G-5 | full unit run | 6,214 tests; every failure classified (Task 4.7 below); ledgers unchanged |

## Task 4.7 — full `tests/unit/` run
- **Run.** Serial, at `bf988a43`, 2026-10-06T05:40Z–06:18Z, with no eval or dissent load: 6,214 tests, bats exit 1, **42 failures**. Outputs are in `~/.cache/loa/cycle-126-dissent/task47/`.
- **Ledgers.** The sha256 of `.run/model-invoke.jsonl` (`b772e81b…`) and `.run/cost-ledger.jsonl` (`7b1f7953…`) is the same before and after, so KF-033 holds.
- **Classification** (every failure):

| Class | Suites (count) | Disposition |
|---|---|---|
| Pre-existing, red on `main` too | post-merge-publication (22), semver-evidence (3) | KF-034. Setup's lightweight tag fails under the operator's global tag config ("fatal: no tag message?"). semver-evidence is a newly recorded member of the class, so KF-034 recurrence is 1 → 2 with an Attempts row. Not re-attempted. |
| **Real defect, fixed (`fd8aaae3`)** | test_license_validator (3), test_constructs_loader (2), test_pack_support (3) | `ensure_license_fixtures.sh`'s freshness guard read only `valid_license.json` (30 days). The gitignored grace fixture's 12-hour window, generated 2026-09-21, had long closed, which is why these passed in a clean worktree. The guard now also requires `grace_period_license.json`'s `offline_valid_until` to be in the future. `license-fixture-freshness.bats` LFF-1 was red first and LFF-2 pins no regeneration while fresh. After the fix the three suites are 35/27/28 ok in the real tree. **Root cause corrected in review round r250-1:** the freshness guard was only half of it. `generate_test_licenses.py` built its times from a naive `datetime.utcnow()`, and `.timestamp()` reads a naive time as local. On this AEDT (UTC+11) host, every JWT `exp` therefore landed 11 hours early, and the pro tier's 24 h grace closed 1 hour after generation. CI runs in UTC and never saw it. The fix uses aware UTC. LFF-4 runs the generator under `TZ=Australia/Sydney` and was red first (delta −39,600 s). LFF-5 makes the guard regenerate any fixture older than the generator. |
| Local state, not a defect in the tree | template-safety (1) | `grimoires/loa/visions/entries/vision-021.md` is gitignored and untracked. It is operator-local, so it was left untouched. |
| **Stale tests after intended cycle-126 changes (`fd8aaae3`)** | cycle-124-effort-flag (2), flatline-model-allowlist (2), gen-bb-registry-codegen T3 (4) | Each was updated to the intended behaviour; none was weakened. c124-1.4-1 reads the catalog's `aliases.opus` target (Task 4.1). c124-1.4-3 expects 16000 (FR-1.3). T3 derives `maxOutput` = min(32000, catalog `max_output_tokens`) (FR-1.5; the generator's `BB_OUTPUT_CAP`). The allowlist test still forbids the bare `gemini-3.1-pro`, now anchored so the listed `-preview` id does not match, and asserts that `validate_model` accepts `gemini-2.5-pro` through the forward-compat pattern. |
| **Doc defect found while classifying (`fd8aaae3`)** | — | cheval `--help` said "other providers 4096", and `base.py` carried the same pre-FR-1.3 comment. Both now state min(16000, catalog `max_output_tokens`). c124-1.4-3b was red first. |

- **After `fd8aaae3`.** Every changed suite passes with 0 skips (the BB suite on the real tree's tsx): gen-bb-registry-codegen 33/33, cycle-124-effort-flag 10/10, flatline-model-allowlist 18/18, license-fixture-freshness 2/2, flatline-model-validation 20/20, model-residue 7/7, repo-map-gen 6/6. The cheval pytest subset is 49 passed, and `regen-checksums --check` reports changed=0.
- **Residual reds:** the 25 KF-034-class cases and the one local vision file. Neither is a cycle-126 regression.

## AC Verification (sprint.md)

### `grep` for `claude-opus-4-`/`claude-sonnet-4-`/`gpt-4o` used as a default or described as current in live scripts, skills and data returns nothing (catalog fallback chains and tests excepted).
- Status: `✓ Met`, under PRD FR-4's reading ("used as a default or 'current'"). The literal grep is **not** empty: it returns 152 lines at `fd8aaae3`. Every line is classified in the Residue grep table above (§ Residue grep, AC 1). No line is a default, and none describes an old id as current.
  - Generated-from-catalog rows and the bash compatibility maps are the "catalog fallback chains" that the AC's parenthesis exempts. Each compatibility-map line maps a legacy pin to a served id.
  - Registry rows for entries the catalog still serves, the frozen `aliases-legacy.yaml` snapshot, BB legacy truncation rows and format examples are neither defaults nor "current".
  - `loa-aleph/SKILL.md:34` is untouched by policy (see the SDD amendment after D-4.3).
  - The one line that was a live default (`flatline-readiness.sh:259`) was fixed by RES-7.
- Evidence: `grimoires/loa/a2a/sprint-250/e2e/g4-residue-grep.txt` (152 lines). `.claude/defaults/model-config.yaml` aliases `opus` → `claude-opus-5-5` and `cheap` → `claude-sonnet-5`.
- Test: `tests/unit/model-residue.bats:27-89` RES-1–7. RES-6 is the acceptance grep with the exception classes and RES-7 is the readiness pin; both are in `e2e/g4-residue-bats.tap` (13/13 with model-adapter).

### Every Anthropic catalog entry has a `model-permissions.yaml` row (pytest).
- Status: `✓ Met`.
- Evidence: `.claude/data/model-permissions.yaml` has one row per Anthropic and Bedrock entry the catalog serves (round r250-1 n13 closed the Bedrock mirror). `e2e/g4-trust-scopes.txt` records 33 passed.
- Test: `.claude/adapters/tests/test_trust_scopes.py:360` `test_every_anthropic_catalog_entry_has_a_row` and `:368` `test_current_generation_rows_mirror_the_4_7_scopes`.

### `implement-gate.bats`: a payload carrying `tool_input.active_skill` records `active_skill_seen_at` (lead session only; a teammate role writes nothing); the gate stays heuristic without `implement_gate.mode: authoritative`; with the opt-in, the authoritative branch passes the payload fixture corpus.
- Status: `✓ Met`. Per Task 4.4's research outcome, the opt-in key is deliberately left undocumented: no harness-set signal exists that a model cannot forge. IG-11 pins that.
- Evidence:
  - `.claude/hooks/compliance/implement-gate.sh:39-50` is the recorder: lead only, written once, atomic, with `active_skill_source`.
  - `:113-117` reads the mode from `.loa.config.yaml` only; no `.run` file can select it.
  - `:122-155` is the authoritative branch, with the heuristic fallback when the field is absent.
  - `tests/fixtures/pretooluse-payloads/expected.tsv` is the corpus (nine rows since `005b9105`, including the NotebookEdit and `Src/` shapes).
- Test: `tests/unit/implement-gate.bats` IG-1–22 (IG-12–14 added in audit round r250-6, `e151757d`; IG-15/16 in round r250-7, `ee8fb582`; IG-17–20 in round r250-8, `005b9105`; IG-21/22 in post-audit round r250-9, `e170de3d`: the root rule and the freshness of every heuristic state file):
  - IG-1 records the field;
  - IG-2 writes once;
  - IG-3 checks that a teammate or subagent writes nothing;
  - IG-4 checks the corpus;
  - IG-5 checks that a forged payload does not flip the gate;
  - IG-6 checks that the gate stays heuristic without the opt-in;
  - IG-7 checks that with the opt-in the corpus passes — since `e151757d` the authoritative column is tighten-only: a claimed implementation skill asks without a RUNNING state exactly like the heuristic, a claimed non-implementation skill always asks (`expected.tsv`);
  - IG-8 checks the fallback;
  - IG-9–11 cover detect, `/loa` and the undocumented key.
  - Also `tests/unit/compliance-hook.bats` CH-T8–T10.

### CP-11/12: `Bash(git push *)` in allow satisfies `Bash(git push:*)`, in deny denies it; CP-13: mixed forms across layers, whitespace and escaping cases, and the dangerous-shape fuzz set behave per the grammar (narrower denies never cover the generic requirement).
- Status: `✓ Met`.
- Evidence: `.claude/scripts/check-permissions.sh:167` `rule_key()` normalises both grammars: trailing `:*` and ` *` are stripped, the result is trimmed, exact stays exact, and bare `Bash`, `Bash(*)` and `Bash(:*)` map to `ALL`. Matching is deny-first.
- Test: `tests/unit/check-permissions.bats`:
  - `:151` CP-11 (allow) and `:163` CP-12 (deny);
  - `:187` CP-13 table: mixed layers, whitespace, escaping, and the dangerous-shape fuzz set, where narrower denies never cover the generic requirement;
  - `:229` CP-14, universal rules (rounds r250-1 and r250-3).
  - The suite is 14/0/0.

### Docs present; budgets green; full unit run: no new red beyond the recorded pre-existing classes; ledger hashes unchanged.
- Status: `✓ Met`. Docs present; `check-prompt-budget.sh` exits 0; the full run at `db49cd32` has no new red: 6,229 tests, 6,203 ok, 26 not ok, 130 skipped, and the 26 are exactly the recorded residual classes (25 KF-034: 22 post-merge-publication + 3 semver-evidence; 1 operator-local `vision-021.md`), a strict subset of the Task 4.7 run's 42; the ledger sha256 pairs are identical before and after.
- Evidence, docs:
  - `CHANGELOG.md:18-41`: the sprint-250 bullet, plus `39bfff76`'s alias budget clamp, universal Bash, grader 1.1.2 and east-of-UTC lines;
  - `README.md`;
  - `docs/migration/v2.0-model-generation-floor.md:224-274`, the cycle-126 addendum, including `Bash(:*)` and the `opus` effort caveat.
- Evidence, budgets: `tools/check-prompt-budget.sh` exits 0 at `39bfff76`.
  - `CLAUDE.loa.md` is 10,225 B against a limit of 10,240 B.
  - The protocols total 131,189 B against a fail limit of 160,000 B. They are above the 114,688 B WARN line, which is advisory.
  - Every SKILL.md is ≤ 16,384 B.
- Evidence, full run:
  - The Task 4.7 run at `bf988a43` is in the table above.
  - The re-run at `db49cd32` covers rounds r250-1 to r250-4 and the two docs commits; it is described under "Full unit run at `db49cd32`" below.
  - Ledger sha256 values are taken before and after each run.
- Test: `tests/unit/` in full, serial. Outputs are in `~/.cache/loa/cycle-126-dissent/task47/` and `fullrun-r6/`.

## Full unit run at `db49cd32`
- **Run.** Serial, in the real tree, 2026-10-07T00:11:00Z–00:59:01Z (48 min), with no eval or dissent load: 6,229 tests, bats exit 1, **26 failures**, 130 skips (the Task 4.7 run had 130). Outputs are in `~/.cache/loa/cycle-126-dissent/fullrun-r6/`. A first attempt at `39bfff76` (2026-10-06T11:11Z) was killed by a host reboot at test 4,166; its 22 failures to that point were the same post-merge-publication cases.
- **Ledgers.** `.run/model-invoke.jsonl` `c3c090c3…` and `.run/cost-ledger.jsonl` `a5cbd48f…` are byte-identical before and after (KF-033 holds).
- **Failures, every one classified.** The set is a strict subset of the Task 4.7 run's 42: the 16 that `fd8aaae3` fixed (license fixtures ×8, cycle-124-effort-flag ×2, flatline-model-allowlist ×2, codegen T3 ×4) stayed green, and nothing new went red.

| Class | Cases | Disposition |
|---|---|---|
| KF-034, pre-existing and red on `main` | post-merge-publication (22), semver-evidence (3) | setup's lightweight tag fails under the operator's global tag config; not re-attempted |
| Local state, not a defect in the tree | template-safety (1) | the gitignored, untracked `visions/entries/vision-021.md`; left untouched |

- **Flakes.** `ok 3158 LSP-1 human output: Providers block lists presence, hop and buckets; OPE` this run.

## Known flakes
- LSP-1 failed once in a batch run and then passed 3/3; it is a load flake. LSA-1 was the same in Sprint 3. It failed once more in the round r250-6 batch (twelve suites back to back) and passed 3/3 alone again.
