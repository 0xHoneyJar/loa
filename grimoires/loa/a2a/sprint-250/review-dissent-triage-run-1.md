# sprint-250 review dissent run 1: triage

- **Run.** `d785fc9a` (base `2fcd4af8`), 2026-10-06T06:51Z–08:01:19Z, 14 chunks. Every chunk was two-voice [codex-headless, claude-headless]. Envelope: `adversarial-review.json`, merged from `adversarial-review-<chunk>.json`.
- **Findings.** 63 in total: 8 BLOCKING, 55 ADVISORY. 59 came from claude-headless and 4 from gpt-5.5-pro.
- **Rejected payloads.** None. Every `rejected_summary` is empty and `rejected_count` is 0. The four `adversarial-rejected-review-{g-gate,k1-kernel,k2-kernel,m1-pins}.jsonl` sidecars are empty (0 bytes), so there is nothing to hand-triage.
- **Verification.** Two independent Opus 5.5 verifiers checked every premise read-only against the code: `review-dissent-run-1-verifier-A.md` (n1–32) and `-B.md` (n33–63).

## Verdict counts

| Set | REAL | DOC | REFUTED | DECLINED |
|---|---|---|---|---|
| A (n1–32) | 4 | 2 | 10 | 16 |
| B (n33–63) | 5 | 5 | 10 | 11 |
| **Total** | **9** | **7** | **20** | **27** |

Eight findings were labelled BLOCKING: n1, n14, n20, n24, n40, n45, n46 and n50. Two hold: n20, confirmed, and n40, which is real but LOW.

Three are refuted:
- **n1:** the compat entries exist at hunk `@@ -1173 +1213`.
- **n45:** the agent-teams block is hand-maintained and unchanged against `main`.
- **n50:** `constraints.json` holds id/why objects, and IDR is 4/4.

Three are declined:
- **n14:** by design, the forward-compat patterns leave validation to dispatch.
- **n24:** SDD D-4.4's authoritative mode needs an operator opt-in.
- **n46:** the re-expansion is the Task 4.8 revert that the pre-registered rule requires.

## REAL, fixed test-first in round r250-1

| n | Defect | Fix |
|---|---|---|
| 20 / 38 | A `! grep -q` that is not the last command in a bats test can never fail it. Affected: `model-residue.bats` RES-4 (:60, :63), `hook-guard.bats:152`, `implement-gate.bats:152`. | `run ! grep` / status-checked form; red shown with the forbidden string planted |
| 29 | `check-permissions.sh` `rule_key` skips a bare `Bash` and treats `Bash(*)` as an exact rule. A host that denies Bash therefore passes the preflight. | universal key; new CP-14 table |
| 13 | The trust-scope mirror test covers 6 of the 16 Anthropic/Bedrock rows. | key list derived from the catalog |
| 15 | `model-adapter.sh` stderr `mktemp`: a failed mktemp aborts the adapter, and a timeout leaves the file behind | fallback plus cleanup |
| 39 | `_elf_future` has no margin, so a fixture expiring seconds later counts as fresh. | now + 300 s; LFF-3 |
| 40 / 41 / 42 | Grader 1.1.0 citation parser: trailer and JSON numbers counted as citations, a backtick-wrapped path bound to the previous file, comma continuation crossing newlines and dates, URLs taken as paths. | grader 1.1.1; RG-18–20; stored A/B outputs re-scored (expected delta 0) |

**Latent issue, outside the finding text (verifier B, n61 note):** the BB truncation tables have no row for the `opus` alias / `claude-opus-5-5`. Payloads between cheval's 180,000 bound and BB's 200,000 `maxInputTokens` default would therefore pass BB and then be refused by cheval. It was verified in round r250-1 and fixed there, or else recorded as a bead.

## DOC

| n | Change | Where |
|---|---|---|
| 3 | The other 5-family entries keep an unverified 2× / 1.5× `long_context` tier pending invoice confirmation. | opus-5-5 catalog comment + migration addendum (r250-1) |
| 4 | No live call has reached `claude-opus-5-5`; it falls back to `claude-opus-5`. | reviewer.md Summary (lead) |
| 36 | State the fallback when `agent-types.yaml` has no `write_capable: true` entry. | validate-skill-capabilities.sh comment, skill-invariants.md (r250-1) |
| 49 | Limit vs file size (10,240 / 10,225 B); G-2 no longer pending; residue tap 13/13. | reviewer.md (lead) |
| 53 | The CLAUDE.loa.md ≤ 9,216 B AC is marked superseded by Task 4.8. | sprint.md:142, sdd.md:79 (lead) |
| 61 | 200,000 is BB's own `maxInputTokens` default; cheval's probed bound is 180,000. | migration addendum (r250-1) |
| 63 | Confirm the host's Bedrock egress region before routing through `claude-bedrock`. | KF-040 Attempts row via `kf-write-lib.sh attempt` (append-only; the Current-workaround field is not rewritten) |

## REFUTED / DECLINED

The verifier tables give the one-line evidence for each finding. The recurring classes are:
- **Mislabelled hunks** (n5, n23).
- **Declared prerequisites:** yq and jq; CI pins yq v4.52.4.
- **SDD D-4.4's advisory opt-in** for the implement gate (n24, n25).
- **Fields with no consumer** in platform-features (n27, n31, n32).
- **Pre-existing behaviour** outside the sprint diff (n16, n17).
- **Hardening suggestions** where nothing is wrong today (n11, n12).

## Round r250-1 outcome (`17291942`)

- All nine REAL items are fixed, each red first. The same `! grep` class was also found and fixed in `flatline-max-tokens.bats` FMT-6 and `protocol-refs-resolve.bats` PR-3.
- **License fixtures: n39 led to the real root cause.** `generate_test_licenses.py` read a naive UTC time as local, so on this UTC+11 host every JWT `exp` was 11 hours early.
  - LFF-4 runs the generator under `TZ=Australia/Sydney` and was red first (delta −39,600 s).
  - LFF-5 regenerates any fixture older than the generator.
  - This corrects the Task 4.7 root cause recorded in reviewer.md.
- **Grader 1.1.1.** All 16 stored A/B runs re-score with 0 detection change, so the Task 4.8 gate result stands.
- **Suites after the round**, serial, with ok / not ok / skip counted:

  | Suite | ok | not ok | skip |
  |---|---|---|---|
  | model-adapter | 8 | 0 | 0 |
  | check-permissions | 14 | 0 | 0 |
  | implement-gate | 11 | 0 | 0 |
  | hook-guard | 8 | 0 | 0 |
  | model-residue | 7 | 0 | 0 |
  | license-fixture-freshness | 5 | 0 | 0 |
  | flatline-max-tokens | 6 | 0 | 0 |
  | protocol-refs-resolve | 4 | 0 | 0 |
  | eval-recall-grader | 20 | 0 | 0 |
  | skill-capabilities | 35 | 0 | 0 |
  | cycle-124-anthropic-catalog | 14 | 0 | 0 |
  | bug-881 | 7 | 0 | 0 |
  | repo-map-gen | 6 | 0 | 0 |
  | gen-bb-registry-codegen | 33 | 0 | 0 |
  | test_license_validator | 35 | 0 | 1 (pre-existing "missing jq" skip) |
  | test_constructs_loader | 27 | 0 | 0 |
  | test_pack_support | 28 | 0 | 0 |
  | cycle-124-effort-flag | 10 | 0 | 0 |
  | flatline-model-validation | 20 | 0 | 0 |
  | adversarial-review-normalise | 67 | 0 | 0 |
  | test_trust_scopes (pytest) | 33 passed, 279 subtests | — | — |

- **The latent BB budget gap** (the `opus` alias has no truncation row, and the trigger compares against the raw `maxInputTokens`) is round r250-2.

## Round r250-2 outcome (`4b347efc`)

The BB input-budget gap is now **fixed**.
- **Generator.** `gen-bb-registry` emits the catalog's provider-qualified aliases as `GENERATED_MODEL_ALIASES`; `opus` maps to `claude-opus-5-5`. Bare, unknown and self-map targets are dropped.
- **Lookup.** `truncation.ts` resolves an alias before the budget lookup.
- **Trigger.** Both `reviewer.ts` trigger sites compare against `effectiveInputBudget`.
- **Red first:**
  - the progressive-truncation alias budget test;
  - the reviewer budget clamp ×4: single- and two-pass, each with `opus` and `claude-opus-5-5`, for an estimate of about 184K against 160K;
  - codegen T13 ×4.
- **Green:**
  - codegen 37/37;
  - the catalog suite 14/14;
  - the dist drift gate 8/8;
  - input-size-consumers 4/4;
  - BB npm 764/765. The one failure is `persona.test`, KF-036, identical on HEAD.
- **Residual, documented:** an operator alias overlay in `.loa.config.yaml` is not reflected. Dot-form compat aliases fall to the conservative 100K default row.
