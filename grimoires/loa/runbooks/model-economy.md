# Model-Economy Runbook (cycle-112 Phase A)

> **Status:** Phase A (Activate). Phase B (consumption) and Phase C (closed-loop
> optimization) are tracked separately.
> **Cycle:** cycle-112-empirical-model-economy
> **Audience:** Loa operators triaging cost vs. quality across model dispatch.
> **Skill family:** `tools/model-economy-roll-up.sh`, `/loa status --economy`,
> `.loa.config.yaml::workload_tier_map`, `.github/workflows/workload-tier-map-drift.yml`

---

## 1. How to read the roll-up

The roll-up shows model-dispatch activity over a window, broken down per
`(skill, model)` cell. Run it with:

```bash
tools/model-economy-roll-up.sh --window 30d
# or equivalently:
/loa status --economy
```

### Header

```
Model-Economy Roll-Up — last 30d (since 2026-04-17T...)
Source: .run/model-invoke.jsonl (808 envelopes)
Coverage: skill attribution 0% (D-6 follow-up) · cost 29% · verdict_quality 48%
```

- **`since`** — the UTC lower bound of the window (inclusive).
- **`Source`** — path to the MODELINV JSONL log being aggregated, with the
  count of envelopes within the window.
- **`Coverage`** — the three load-bearing partial-coverage signals:
  - `skill attribution N%` — fraction of envelopes carrying the `skill` /
    `calling_primitive` / `phase` / `role` / `tier` field. Today this is
    **0%** because no dispatch entrypoint passes attribution; D-6 is the
    Phase A.1 follow-up that wires it.
  - `cost N%` — fraction of envelopes carrying BOTH `pricing_snapshot`
    AND `capability_evaluation` (the joint requirement to compute cost
    today). On the live log this is ~29-35%.
  - `verdict_quality N%` — fraction of envelopes carrying a
    `verdict_quality` block.

### Per-row columns

| Column | Meaning |
|--------|---------|
| **Skill** | The `calling_primitive` / `skill` value. Today: always `(unattributed)` (see §1.coverage). |
| **Model** | `final_model_id` (which model actually answered, after any fallback walk). |
| **Runs** | Total envelopes bucketed to this `(skill, model)` cell. |
| **Cost/run** | Mean cost across **priced** runs only. Rows without cost data show `—`. A `*` suffix indicates input-side-only cost (D-7 will lift this caveat). |
| **p95-latency** | 95th-percentile `invocation_latency_ms`. `—` when zero runs had a latency value. |
| **VQ-healthy** | Percentage of runs that are `verdict_quality.status == APPROVED AND chain_health == ok` (SDD §3.3 nested gate). `—` when zero runs had `verdict_quality`. |
| **`⚠ degraded`** | Marker. Fires when `verdict_quality_distribution.DEGRADED + verdict_quality_distribution.FAILED >= 2` for the row. |

### Worked example (from live log, 30d window)

```
Skill          Model                          Runs    Cost/run   p95-latency   VQ-healthy
(unattributed) openai:gpt-5.5-pro              68     $1.31 *      289666ms     100%
(unattributed) anthropic:claude-opus-4-7      374     $0.07 *       87139ms      77%  ⚠ degraded
(unattributed) google:gemini-3.1-pro-preview   95     $0.03 *       56470ms      56%  ⚠ degraded
(unattributed) openai:gpt-5.5                  67     $0.04 *       60123ms      85%  ⚠ degraded
(unattributed) anthropic:claude-headless       69     —            296914ms     100%
```

How to read:
1. **Most expensive** = `openai:gpt-5.5-pro` at $1.31/run × 68 runs ≈ $89 over the window.
2. **Worst VQ-healthy** = `google:gemini-3.1-pro-preview` at 56% (signals degradation).
3. **Highest-latency** = `anthropic:claude-headless` at p95 297s (long-running task class — expected for headless).
4. **Most-trafficked** = `anthropic:claude-opus-4-7` at 374 runs (the workhorse model this cycle).

### Coverage caveats (Phase A reality)

Read the coverage line first. Three known gaps:

1. **Skill attribution is 0%.** All rows show `(unattributed)` because no
   dispatch entrypoint passes `calling_primitive` into the MODELINV writer
   today. **D-6 follow-up** (Phase A.1) wires it. Until then, the roll-up
   shows MODEL-level economy, not per-skill economy.
2. **Cost coverage is partial (~29-35%).** A row needs BOTH `pricing_snapshot`
   AND `capability_evaluation.estimated_input_tokens` for the cost math. Rows
   without cost show `—`. **D-7 follow-up** (Phase A.1) wires output-token
   capture to make cost full-spectrum (today: input-side only, marked `*`).
3. **`verdict_quality` coverage is ~48%.** Not all dispatch sites set the
   envelope yet. Rows without `verdict_quality` data show `—` in the
   VQ-healthy column.

**The output is honest about its gaps.** Do not infer from a `—` that a
cell is "fine"; it means "no signal in the underlying data".

---

## 2. When to consider a tier change

Tiers map skills to model classes:

| Tier | Models | When to use |
|------|--------|-------------|
| **advisor** | gpt-5.5-pro, claude-opus-4-7, gemini-3.1-pro-preview | Workloads where quality dominates: review, audit, planning, adversarial dissent. |
| **executor** | gpt-5.5, claude-sonnet-4-6 | Workloads where cost dominates and quality floor is well-established: simple implementation, rote refactors. |
| **headless** | claude-headless, codex-headless, gemini-headless | Long-running task-only flows where reasoning depth isn't load-bearing. |

### Quality floors (operating principles)

Some skills carry hard quality-floor requirements that cannot be downgraded
without empirical evidence:

| Skill class | Floor | Source |
|-------------|-------|--------|
| Review (`/review-sprint`, `reviewing-code`) | **advisor** | `memory:feedback_advisor_benchmark.md` — PR #885 A/B showed executor missed 1 HC + 60% fewer findings |
| Audit (`/audit-sprint`, `auditing-security`) | **advisor** | Same evidence — audit shares review's reasoning class |
| BB review (`bridgebuilder-review`) | **advisor** | Cross-model dissent requires multi-provider diversity; executor tier degrades to single-model |
| Adversarial dissent (`adversarial-review`) | **advisor** | Dissenter must catch reviewer blind spots — quality floor non-negotiable |
| Red-team generation (`red-teaming`) | **advisor** | Creativity / adversarial generation benefits from advisor-tier reasoning |

### Signals for a tier change

Consider proposing a tier change when ALL of the following hold:

1. **30+ HEALTHY runs at the current tier in the roll-up window**, AND
2. **`verdict_quality_healthy_pct ≥ 90%` for the candidate skill+model**, AND
3. **No `⚠ degraded` marker on the candidate row**, AND
4. **Cost-per-clean-output > $X** at the current tier where the proposed lower
   tier would cut cost by >50% AND empirical evidence shows quality holds.

Conversely, an **immediate tier UPGRADE** is warranted when:
- A skill on executor tier shows `⚠ degraded` marker in the window, OR
- `verdict_quality_healthy_pct < 80%`, OR
- Operator memory captures a regression at the current tier (e.g., the
  PR #885 A/B finding).

Phase A does NOT consume the `workload_tier_map` automatically (that's
Phase B). Tier changes today are operator-visible documentation; the
codification is the value, not the mechanical enforcement.

---

## 3. How to justify a tier change in a PR body

The CI drift gate (`.github/workflows/workload-tier-map-drift.yml`) gates
`workload_tier_map` mutations on a trailer in the PR body.

### Trailer formats (one or both required)

#### Option A: empirical evidence

```
Tier-Change-Evidence: PR-NNN A/B benchmark — <one-line summary of finding>
```

Example:
```
Tier-Change-Evidence: PR-885 A/B (executor tier missed 1 HC + 60% fewer findings)
```

The format is informal but the trailer **must begin a line** with
`Tier-Change-Evidence:`. The regex enforced in CI is `^Tier-Change-Evidence:`.

#### Option B: operator approval

```
Operator-Approval: @<github-handle> in <reference>
```

Example:
```
Operator-Approval: @janitooor in NOTES.md decision log 2026-05-17
```

Use Option B when:
- The change is forced for non-quality reasons (e.g., a stop-gap to clear
  a budget alert that can't wait for A/B testing).
- The change is part of an operator-led structural refactor (e.g.,
  consolidating two skills' tier entries).

The trailer **must begin a line** with `Operator-Approval:`. The regex
enforced in CI is `^Operator-Approval:`.

### Both trailers are acceptable

A PR may carry both `Tier-Change-Evidence:` AND `Operator-Approval:`.
The gate counts trailers via `grep -c "^..."`; presence of either passes.

### What the gate does NOT validate

Phase A gates on **trailer presence**, not content. The gate cannot
verify that the evidence cited actually exists or supports the conclusion.
Phase A.1+ may add content validation (e.g., a Phase A.1 follow-up could
parse the trailer and assert the cited PR has ≥N HEALTHY runs in the
roll-up). For now, trailer presence + operator review of the PR body is
the entire enforcement surface.

---

## 4. What triggers the drift gate

### Trigger paths

The workflow runs on changes to ANY of:

- `.loa.config.yaml`
- `.claude/data/schemas/workload-tier-map.schema.json`
- `.github/workflows/workload-tier-map-drift.yml`
- `tools/audit-workload-tier-map.sh`

### Subtree projection (R-3 false-positive mitigation)

The gate uses `yq eval '.workload_tier_map' .loa.config.yaml` to extract
the relevant subtree, then `diff -q` against the same projection from the
base ref. **Harmless reformatting elsewhere in `.loa.config.yaml`** (e.g.,
adding a comment to `advisor_strategy:`) does **NOT** trip the gate
because the projection isolates only the `workload_tier_map` slice.

Specifically harmless edits:
- Comments added to other sections
- Whitespace changes outside `workload_tier_map`
- Reordering of unrelated top-level keys
- Adding/removing entirely unrelated config sections

Edits that DO trip the gate:
- Any addition, removal, or modification of an `entries.<skill>` block
- Any change to `defaults.tier`
- Any change to `schema_version`
- Any rename of a key within the `workload_tier_map` tree

### Branch protection

The workflow MUST be added to the **required status checks** for `main`
in GitHub repository settings. Phase A documents this in the runbook;
the enforcement is operator action (cannot be self-set via PR — branch
protection is a repo admin operation).

If branch protection isn't set, the gate still runs on every PR and
emits `::error::` annotations, but a maintainer with admin merge access
could bypass the failed check. The push-to-main path emits a
`::warning::` that surfaces the bypass in the action run log
(cycle-108 admin-bypass-detection pattern).

### Audit tool (`tools/audit-workload-tier-map.sh`)

Independent of the drift gate, the exhaustiveness audit can be run
locally:

```bash
tools/audit-workload-tier-map.sh           # human-readable
tools/audit-workload-tier-map.sh --json    # machine-readable
```

Exit codes:
- `0` — exhaustive coverage (every detected dispatching skill has an entry)
- `1` — missing entry (use CI gate as well — this script gates exhaustiveness, drift gate gates evidence)
- `4` — schema violation
- `2` — invalid args

The CI workflow runs this audit as a step BEFORE the trailer-enforcement
step, so schema violations / missing entries surface first.

---

## 5. Operating principles

The five principles from PRD §8 (verbatim from cycle-112 #925 body),
with Phase A operationalization commentary:

### 5.1 Quality floor first

> Quality (verdict_quality healthy %) is the load-bearing metric. Cost is
> the optimization dimension AFTER the quality floor is satisfied.

**Phase A operationalization**: The roll-up surfaces `VQ-healthy %` per row
WITH a `⚠ degraded` marker. Operators triaging tier-downgrade proposals
must inspect the candidate row's VQ-healthy % first; cost discussion is
gated on "VQ-healthy ≥ 90% AND no degraded marker".

### 5.2 Empirical over intuition

> Calibrations are captured as `Tier-Change-Evidence:` trailers tying back
> to specific A/B benchmarks or PR-comparison data, not as bare assertions.

**Phase A operationalization**: The drift gate enforces trailer presence
on every `workload_tier_map` mutation. The runbook's §3 format makes the
trailer self-documenting.

### 5.3 Honest about gaps

> Coverage of the underlying data is not 100%. The roll-up surfaces this
> as a coverage line (skill attribution %, cost coverage %, verdict_quality
> coverage %) and shows `—` for rows lacking data.

**Phase A operationalization**: The text and JSON outputs both surface
coverage explicitly. The schema's `coverage` block makes it programmatic.
D-6 + D-7 follow-ups will narrow these gaps without changing the surface.

### 5.4 Dispatch unchanged this cycle

> Phase A is informational only. `workload_tier_map` is read by operators,
> NOT consumed by dispatch. Phase B is the consumption cycle.

**Phase A operationalization**: NFR-Compat-1 gate
(`tests/integration/test_dispatch_unchanged.bats`) confirms `model-adapter.sh`,
`loa_cheval/providers/`, `loa_cheval/routing/`, and `loa_cheval/audit_envelope.py`
are byte-identical to `main`.

### 5.5 Provenance over polish

> Every `workload_tier_map` entry carries an `evidence_ref` pointer. Even
> default entries (no empirical override) carry `evidence_ref: "default"`,
> making the empty-state explicit.

**Phase A operationalization**: The schema's
`evidence_ref` pattern requires a recognized prefix (`memory:`, `pr:`,
`default`, `operator-decision:`, `grimoire:`, `kf:`). This forces every
entry to declare its evidence form, even when the answer is "no evidence,
this is the conservative default".

---

## Appendix: Known limitations of the Phase A roll-up

These are tracked for Phase A.1 / Phase B / Phase C follow-up; they
are NOT bugs in Phase A but documented gaps.

### A.1 D-6 — Skill attribution

**Status**: 0% coverage today. **Workaround**: All rows bucket to
`(unattributed)`. Total cost is conserved across rows (no envelopes
dropped). **Phase A.1 follow-up**: Wire `calling_primitive` /
`skill` through every dispatch entrypoint so MODELINV envelopes
carry per-call attribution.

### A.2 D-7 — Output-token cost

**Status**: `cost_input_only` is `true` on every row today. **Workaround**:
The `*` suffix in text output and `cost_input_only` flag in JSON make
the partial-coverage state visible. **Phase A.1 follow-up**: Extend
MODELINV writer + cheval providers to capture `tokens_output`
post-flight (Anthropic `usage.output_tokens`, OpenAI `usage.completion_tokens`,
Gemini `usageMetadata.candidatesTokenCount` — all already plumbed into
`.claude/adapters/loa_cheval/metering/`).

### A.3 verdict_quality coverage at ~48%

**Status**: Not all dispatch sites currently set `verdict_quality` on
their MODELINV envelopes. **Workaround**: Rows without VQ data show `—`
in the VQ-healthy column; coverage line surfaces the gap. **Improvement**:
Each new dispatch site landing in the cycle-109+ era sets the envelope;
coverage rises monotonically with merged PRs.

### A.4 Tier-map is informational only (Phase A is NOT consumption)

**Status**: `workload_tier_map` is captured but no dispatch path reads it.
**Phase B follow-up**: Skills consume the map at dispatch time; per-skill
tier ceilings get enforced; cost predictions become forward-looking, not
just backward-looking.

### A.5 No closed-loop optimization

**Status**: Tier changes are operator-driven (manual editing of
`workload_tier_map`). **Phase C follow-up**: Auto-demotion proposals
(detect skills with consistent VQ-healthy ≥ 95% on executor candidates),
auto-promotion on degradation, regression detector.

### A.6 Single-host MODELINV envelope source

**Status**: The roll-up reads `.run/model-invoke.jsonl` from the local
machine. Cross-host federation isn't supported. **Improvement (no
filed phase)**: Sync via the L5 cross-repo status reader pattern from
cycle-098.

---

## Quick reference card

```bash
# View 30-day economy
/loa status --economy

# Filter by skill substring
/loa status --economy --skill review

# Filter by model substring
/loa status --economy --model anthropic

# Window override
/loa status --economy --window 7d

# JSON for scripting
/loa status --economy --json | jq '.per_skill_model'

# Historical pricing (price against git ref's model-config.yaml)
/loa status --economy --cost-snapshot v1.157.0

# Audit workload_tier_map exhaustiveness
tools/audit-workload-tier-map.sh

# Audit + machine-readable
tools/audit-workload-tier-map.sh --json
```

### PR trailer cheat sheet

```
Tier-Change-Evidence: <PR-NNN A/B summary or memory citation>

Operator-Approval: @<handle> in <reference>
```

Either trailer alone satisfies the drift gate. Both is fine. Neither
fails CI.
