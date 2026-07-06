# Runbook: Per-Stage Model Tiering (cycle-116 D3)

> bead: `bd-c116-d3-tiering` · Wave-2 item D3 · flag default: **OFF**
>
> This runbook explains the per-stage tier-routing opt-in shipped in cycle-116
> D3, why it exists, how to run the empirical A/B that gates flipping it, and
> the evidence + risk you must respect before you do.

## TL;DR

- A new **default-off** flag `advisor_strategy.stage_routing.flatline_scorer`
  lets the Flatline **score** stage route through the `advisor_strategy`
  role/skill resolver instead of a hardcoded `--model` pin.
- **Default (false) is byte-identical to pre-D3 dispatch.** Proven by
  `tests/integration/d3-flatline-scorer-compat.bats`.
- The whole idea rests on PR #885's finding that the cheap *executor* tier is
  UNSAFE — **for Bridgebuilder REVIEW, which is NOT the same task as scoring.**
  D3 measured scoring directly (see [The A/B result](#the-ab-result-cycle-116)).
- Regardless of the A/B outcome, **the flag stays false** until an operator
  decides otherwise with a `Tier-Change-Evidence:` citation.

## Why this exists: five config surfaces, one governs dispatch

Loa has accreted several parallel model-selection mechanisms. Knowing which one
actually drives a call is the whole game:

| # | Surface | Consulted when… | Drives real dispatch? |
|---|---------|-----------------|-----------------------|
| 1 | `.claude/defaults/model-config.yaml::agents.<skill>.model` | caller omits **both** `--model` and `--role` | only on the bare agent-binding path |
| 2 | `.loa.config.yaml::skill_models.<skill>.<role>` | Bridgebuilder Node/TS resolver | BB tool only; **unpopulated** in this repo |
| 3 | `.loa.config.yaml::advisor_strategy` | caller passes `--role` **and** omits `--model` (`cheval.py:1069`) | yes — **but structurally dormant** (see below) |
| 4 | `.loa.config.yaml::flatline_protocol.models.*` / `code_review.model` / `security_audit.model` | Flatline/scoring dispatch | **yes — this is what actually runs today** |
| 5 | `.loa.config.yaml::workload_tier_map` (cycle-112) | nothing | **no** — informational calibration memory only |

### `advisor_strategy` is dormant in production

`advisor_strategy.resolve()` only fires from `cheval.py:1069`
(`if getattr(args,"role",None) and not args.model:`). Every production dispatch
site passes `--model` explicitly and none passes `--role`
(`flatline-orchestrator.sh` `call_model`, `model-adapter.sh`,
`hitl-jury-panel-lib.sh`, `red-team-model-adapter.sh`). So `defaults`,
`per_skill_overrides`, and `tier_aliases` are all loaded, validated — and never
consulted. D3 wires exactly **one** stage (flatline-scorer) into this path,
behind the opt-in flag, so the mechanism finally has a real-traffic consumer.

### `advisor_strategy` vs `workload_tier_map` — why both exist

They look redundant (both map a skill → an advisor/executor tier) but play
different roles:

- **`advisor_strategy`** is the **live mechanism**. Flip its flag + set a
  `per_skill_override` and dispatch changes.
- **`workload_tier_map`** is **informational memory** — the empirically-observed
  safe tier per skill with an `evidence_ref`, guarded by a CI drift gate
  (`workload-tier-map-drift.yml`) requiring a `Tier-Change-Evidence:` trailer.
  It has **zero dispatch consumers** (cycle-112 PRD NFR-Compat-1; Phase B
  consumption never landed). Consult it to *decide* a `per_skill_override`
  value; it will not change routing on its own.

D3 deliberately did **not** deprecate `workload_tier_map` — it stays as the
evidence ledger the `advisor_strategy` decisions should cite.

## The dormancy side-finding: `agents.flatline-scorer.model: cheap` is a dead comment

`.claude/defaults/model-config.yaml:911-914` binds `flatline-scorer` to the
`cheap` tier (Sonnet 4.6) with a cycle-114 FR-13 comment claiming scoring is
demoted to Sonnet for cost. **This is never live.** The scorer's real
cross-scoring calls are `flatline-orchestrator.sh:1498-1535`
(`call_model "$secondary_model" score …` / `"$primary_model"`), and `call_model`
pins `--model` explicitly to the primary/secondary models (today `opus` /
`gpt-5.5`, advisor-class). So:

- `--dry-run --agent flatline-scorer` (bare binding) resolves `claude-sonnet-4-6` — the "cheap" claim.
- but the orchestrator never uses that path; it passes `--model opus`/`gpt-5.5`.

The demotion the config comment advertises has **never executed**. D3's flag is
the first time that intent becomes mechanically actionable — and even then, only
if the operator ALSO sets `per_skill_overrides.flatline-scorer: executor`
(see [How to flip it](#how-to-flip-the-flag)). This drift is documented here and
in `grimoires/loa/NOTES.md`; it is a documentation-vs-behavior gap, not a
behavioral bug, so it is intentionally **not** a KF entry.

## How the wiring works

`flatline-orchestrator.sh::call_model()` builds the cheval argv. D3 added one
branch (and one cached flag reader `is_stage_routing_scorer_enabled`):

```
if [[ "$mode" == "score" ]] && is_stage_routing_scorer_enabled; then
    args+=(--role implementation --skill flatline-scorer)   # advisor_strategy resolves
else
    args+=(--model "$model_override")                       # pre-D3: unchanged pin
fi
```

- **flag false (default):** argv is byte-for-byte pre-D3 — `--model` pin, no
  `--role`. Only `mode == score` is ever eligible; review/skeptic/dissent are
  untouched.
- **flag true:** score-mode drops `--model` and passes `--role implementation
  --skill flatline-scorer`, so `cheval.py:1069`'s role gate fires and
  `advisor_strategy.resolve(role="implementation", skill="flatline-scorer", …)`
  picks the tier.

With no `per_skill_override`, that resolves to the `implementation` role default
(`advisor`) → `claude-opus-4-8`. So **flipping the flag alone does not demote to
the cheap tier** — it routes through the resolver, which by default keeps the
scorer on an advisor-class model. This is the safe-by-construction property: the
flag can't silently downgrade quality.

## Evidence: what PR #885 actually tested (and what it did NOT)

The canonical evidence (`memory:feedback_advisor_benchmark.md`, "2026-05-16
refinement"; the manual A/B in the never-committed
`/tmp/executor-tier-validation.md`) found:

> On PR #885, the executor tier was **6× cheaper** but **missed 1
> HIGH_CONSENSUS finding** and produced **−60% total findings** → **executor is
> UNSAFE for Bridgebuilder REVIEW.**

**Read the task boundary carefully.** #885 tested **Bridgebuilder review** — an
open-ended generative critique task. It did **NOT** test structured
scoring/triage. Do not cite #885 as evidence about flatline-scorer; scoring is a
constrained 0-1000 rubric task with a very different failure surface. That gap is
exactly why D3 ships its own scoring A/B rather than assuming #885 generalizes.

## The A/B runbook

Two harnesses, two shapes:

1. **`tools/advisor-benchmark.sh`** (cycle-108) — full-sprint git-worktree
   replay. Right tool for whole-sprint A/B. Signature-gated to cycle-108
   baselines; do **not** reuse its gate for a new cycle.
2. **`tools/stage-tier-benchmark.sh`** (cycle-116 D3) — single repeated model
   call per tier per trial. Right tool for a single-stage A/B like scoring.
   Emits `outcomes.jsonl` in the exact shape `advisor-benchmark-stats.py`
   consumes (`{sprint_sha, tier, idx, score, outcome, stratum}`;
   `sprint_sha` repurposed as a batch id).

### Run the single-call harness (dispatch smoke / dry-run)

```bash
# dry-run: plan + synthetic outcomes, no API calls
tools/stage-tier-benchmark.sh --dry-run --agent flatline-scorer --trials-per-tier 3

# live dispatch with a scorer hook (see the pytest for the scoring shape)
tools/stage-tier-benchmark.sh \
  --agent flatline-scorer --skill flatline-scorer \
  --prompt-file <improvements.json> \
  --tiers advisor,executor --trials-per-tier 5 \
  --cost-cap-usd 3 --score-cmd 'my-scorer.sh'
```

### Run the gold-set A/B (the real quality measurement)

```bash
LOA_RUN_LIVE_TESTS=1 ANTHROPIC_API_KEY=sk-ant-… \
  python3 -m pytest tests/replay/test_d3_flatline_scorer_tier_ab.py -v
# results + stats-ready outcomes.jsonl land under:
#   grimoires/loa/cycles/cycle-116-quality-per-token/d3-flatline-scorer-ab/
python3 tools/advisor-benchmark-stats.py \
  --outcomes <that outcomes-*.jsonl> --score-key score --output report.md
```

Gold set: `tests/fixtures/stage-tier-benchmark/flatline-scorer-gold.json` — 6
hand-labeled findings spanning the rubric bands; the metric is the fraction of
findings whose `would_integrate` matches the human label.

**Cost honesty (NFR-P3 / cycle-112 ATK-A6):** the MODELINV envelope has no
`tokens_input/output` fields and partial pricing coverage; the harness discloses
"coverage 0%" when `.run/historical-medians.json` is absent rather than printing
a false-precise number. The gold A/B is ~1.5K-input × 10 calls — well under the
$3 cap in practice.

## The A/B result (cycle-116)

Run `outcomes-20260706T021647Z` (10 trials, `LOA_RUN_LIVE_TESTS=1`,
`ANTHROPIC_API_KEY`; advisor=`anthropic:claude-opus-4-8`,
executor=`anthropic:claude-sonnet-4-6`):

| tier | n | mean would_integrate agreement |
|------|---|-------------------------------|
| advisor (opus-4-8) | 5 | **0.90** |
| executor (sonnet-4-6) | 5 | **0.90** |

Paired bootstrap (`advisor-benchmark-stats.py`): **mean_delta = 0.0**, 95% CI
**[−0.10, +0.10]** → **INCONCLUSIVE**.

**Interpretation.** Unlike #885's BB-review result (−60% findings on executor),
the scoring task shows **no measurable advisor advantage** on this gold set — the
cheaper Sonnet tier agreed with the human labels at the same 90% rate as Opus.
But the CI straddles zero and n is small (5 trials × 6 findings), so this can
neither confirm executor-is-worse nor affirm equivalence. It is **promising, not
proven**.

**Verdict: flag stays FALSE.** Per the cycle-116 lead decision, D3 records this
for a future operator decision and does not flip the flag. To flip it
responsibly, first grow the gold set (more findings, more trials) until the CI
resolves to a PASS (advisor ≥ executor) or a clean equivalence, then follow the
steps below with the outcomes file as your `Tier-Change-Evidence:` citation.

## How to flip the flag

Only after the A/B resolves (not INCONCLUSIVE) and you accept the risk:

```yaml
advisor_strategy:
  per_skill_overrides:
    flatline-scorer: executor        # the actual demotion
  stage_routing:
    flatline_scorer: true            # enable the score-mode routing
```

Run `tests/integration/d3-flatline-scorer-compat.bats` and
`python3 -m pytest tests/unit/test_advisor_strategy_loader.py` first. Note the
NFR-Sec1 hard-pin: `per_skill_overrides` can never demote a skill in
`audited_review_skills` (or any `role: review|audit` skill) to executor — the
loader rejects it (`advisor_strategy.py` §4). flatline-scorer is `role:
implementation`-eligible, so it is legitimately demotable; review/audit stages
are not.

## Risk: KF-002 / KF-003 (empty-content exposure)

`grimoires/loa/known-failures.md` (KF-003, ~L60 and L327-347) records that live
edits to `code_review.model` / `security_audit.model` between
`claude-opus-4-7` and `gpt-5.5-pro` **directly caused and absorbed
empty-content incidents**. Lesson: **changing a stage's pinned model changes its
empty-content exposure profile.** Any stage you wire into per-stage tiering that
shares a provider/model family with a review/audit path inherits this risk.
flatline-scorer's default-false + advisor-default resolution keeps it on the
same class of model it uses today, so the flag as shipped adds no new exposure;
the exposure appears only when you actively demote to executor. Do not chase an
empty-content wall with retries — route through the KF entry.

## Files

- `tools/stage-tier-benchmark.sh` — single-call A/B harness
- `tests/unit/stage-tier-benchmark.bats` — harness arg/dry-run/cost-cap tests
- `tests/replay/test_d3_flatline_scorer_tier_ab.py` — live gold-set A/B (gated)
- `tests/fixtures/stage-tier-benchmark/flatline-scorer-gold.json` — hand-labeled gold
- `tests/integration/d3-flatline-scorer-compat.bats` — default-off byte-parity proof
- `.claude/scripts/flatline-orchestrator.sh` — `call_model` branch + flag reader
- `.claude/data/schemas/advisor-strategy.schema.json` — `stage_routing` property
- `.loa.config.yaml` / `.loa.config.yaml.example` — flag + worked example
