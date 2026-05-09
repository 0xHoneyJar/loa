---
title: Jeffrey Emanuel Pattern Adoption — Strategy Doc
status: scoping (no implementation yet — survey + recommendations)
created: 2026-05-09
relates_to: cycle-102-model-stability, cross-cycle infrastructure
sources: Jeffrey's posts on FrankenSQLite, agent-ergonomics, dcg; ~/.claude/skills/ inventory; Loa's existing surfaces
---

# Jeffrey Emanuel Pattern Adoption — Strategy Doc

> Jeffrey is the author of beads_rust (which Loa uses), dcg, cass, and ~70+ other agent-first skills. He moves faster than we do; this doc tracks what to adopt and how to stay current.

## TL;DR — Top recommendations

1. **Adopt the negative-evidence ledger pattern.** The single highest-leverage idea from the FrankenSQLite post. We're about to attempt many optimizations across cycle-102 Sprint 1+4 (probe-gate latency, parallel-dispatch concurrency, max_output_tokens tuning, A6 connection-pool work). Tracking dead-ends as a first-class artifact compounds. Concrete spec below.

2. **Integrate `dcg` (Destructive Command Guard).** Loa has zero dcg integration today. We have multi-agent workflows (NTM, simstim, agent-mail) where one rogue agent can wipe out shared state. Jeffrey's dcg is curl-bash-installable, ships its own ast-grep heredoc detection, has no measurable latency. Should be a `.claude/hooks/safety/` complement.

3. **Compose `beads-compliance-and-completion-verification` into `/audit-sprint`.** Loa's existing `/audit-sprint` is per-sprint. Jeffrey's compliance skill is per-bead and treats `closed` as a *claim* requiring evidence. Together they catch different defect classes: audit-sprint catches sprint-scope violations; compliance audit catches false-closed beads. Adopt as a parallel pass during cycle ship.

4. **Pre-PR scan via `ubs` (Ultimate Bug Scanner) or `multi-pass-bug-hunting`.** The user explicitly named this. Composes cleanly with the existing Bridgebuilder + `/review-sprint` flow. Highest-leverage when added to the run-bridge cycle.

5. **Skill version-pin manifest + weekly diff workflow.** Concrete sync mechanism (spec below). Without this, we'll silently miss skill updates and drift.

## Inventory — Jeffrey-authored skills present in `~/.claude/skills/`

| Skill | Loa state | Relevance | Action |
|---|---|---|---|
| `beads-br` | ✅ Loa has equivalents (`.claude/scripts/beads/`, `/.claude/protocols/beads-preflight.md`) | HIGH | Consult for missing capabilities; port advanced visualizations |
| `beads-bv` | ⚠️ Loa has scripts; no graph-aware triage | HIGH | Port: bottleneck detection, dependency triage |
| `beads-compliance-and-completion-verification` | ❌ Loa has no compliance audit | **HIGH** | Adopt — composes with `/audit-sprint`; sample-mode tier for >1500 closed beads |
| `bd-to-br-migration` | ✅ Loa has migrate-to-br.sh | LOW (already handled) | Skip |
| `dcg` | ❌ **Loa has no dcg integration** | **HIGH** | Adopt — install standalone + reference Loa-side hook |
| `cass` | ❌ Loa has its own auto-memory but no session-archaeology tool | HIGH | Consider for cross-session pattern mining |
| `cass-memory` | ❌ Loa has auto-memory in `~/.claude/projects/...` but no procedural-memory layer | MED | Evaluate composition with existing memory |
| `profiling-software-performance` | ❌ no Loa equivalent | **HIGH** for cycle-102 Sprint 1+4 | Pull in when probe-latency / parallel-dispatch perf work starts |
| `extreme-software-optimization` | ❌ paired with profiling; no Loa equivalent | HIGH for cycle-102 | Same as above |
| `multi-pass-bug-hunting` | ❌ Loa has /audit-sprint but no multi-pass scan | HIGH | Adopt for pre-merge; compose with Bridgebuilder |
| `ubs` (Ultimate Bug Scanner) | ❌ no Loa equivalent | HIGH | Adopt — complements multi-pass-bug-hunting |
| `multi-model-triangulation` | ✅ Loa has Flatline (more sophisticated) | LOW | Loa already has its own implementation |
| `reality-check-for-project` | ✅ Loa has `/loa` (Golden Path) — similar surface | LOW-MED | Cross-pollinate ideas |
| `mcp-server-design` | ❌ no Loa equivalent (relevant for agent-mail integration) | MED | Consult when extending MCP integrations |
| `installer-workmanship` | ✅ Loa has mount-loa.sh | MED | Audit Loa's installer against Jeffrey's patterns |
| `library-updater` | ❌ no Loa equivalent | MED | Adopt for dependency hygiene |
| `agent-fungibility-philosophy` | ⚠️ Loa has multi-agent (Agent Teams) but no fungibility doctrine | MED | Read for design influence; not a code adoption |
| `git-stash-janitor` | ✅ Loa has `.claude/rules/stash-safety.md` | LOW | Cross-check |
| `simplify-and-refactor-code-isomorphically` | ❌ no Loa equivalent | MED | Adopt for pre-merge polish |
| `repeatedly-apply-skill` | ❌ no Loa equivalent (kaironic plateau is conceptually similar) | MED | Useful for /run-bridge depth tuning |
| `mock-code-finder` | ❌ no Loa equivalent | MED | Compose with `/audit-sprint` for pre-ship gate |
| `de-slopify` | ❌ no Loa equivalent | LOW-MED | Cross-cycle polish; useful for docs/changelogs |
| `path-rationalization` | ❌ no Loa equivalent | LOW (ops-hygiene; not Loa's domain) | Skip for now |
| `agent-mail` (composes with Loa NTM/simstim) | ✅ Loa references it | (already integrated) | Stay current with Jeffrey's updates |
| `caam` (CLI account switcher for rate-limit hopping) | ❌ no Loa equivalent | LOW | Operator-tooling; not Loa-internal |

## Patterns from posts (NOT in skill form yet)

These are described in Jeffrey's posts but I didn't find as standalone skills. Worth adopting as Loa-native patterns:

### 1. **Negative-evidence ledger** — concrete spec for cycle-102

> Source: FrankenSQLite post — "By having the agents study that negative ledger before trying the next optimization ideas, they were able to avoid dead-ends and build up strong intuition."

**Proposal: Loa-native negative ledger at `grimoires/loa/cycles/<cycle>/negative-ledger.jsonl`**

Schema (per-entry):
```json
{
  "ledger_id": "neg-cycle-102-001",
  "ts_utc": "2026-05-09T14:23:00Z",
  "cycle": "cycle-102-model-stability",
  "sprint": "sprint-1",
  "task": "T1.3",
  "what_was_tried": "string — concrete description",
  "hypothesis": "string — why we thought it would help",
  "outcome": "no_help | hurt_other_metric | reverted_for_correctness | partial_help_not_worth_complexity",
  "evidence": {
    "before_metric": "value + unit",
    "after_metric": "value + unit",
    "regression_metric": "what got worse, if anything"
  },
  "branch_or_commit": "git ref",
  "lesson": "1-2 sentence synthesis — what to NOT try next time",
  "tags": ["probe-gate", "concurrency", ...],
  "supersedes": ["neg-cycle-102-NNN"]  // optional — if this updates a prior entry
}
```

**Workflow**:
1. Sprint task starts → agent reads `negative-ledger.jsonl` (filter by sprint + tags) before designing approach
2. Agent attempts optimization → benchmarks → if didn't help OR regressed elsewhere → emits append-only entry to ledger
3. Pre-PR check: every PR with perf-class tasks (T*.optimize) MUST cite the negative-ledger consultation in the PR body
4. Cross-cycle: at cycle ship, mark each entry's `lifecycle: closed | supersedes-by-cycle-X | still-valid-pattern`

**Bootstrap for cycle-102**:
- Backfill from cycle-099 cross-runtime-parity work (some attempts that didn't pan out)
- Backfill from sprint-bug-143 archaeology (e.g., "tried jq filter rewrite first — reverted; real bug was budget starvation")
- Backfill from this session's adapter-bug surfacing (A1-A7) — A4 was an alias-divergence path; A5 is open mystery

**Tooling**:
- `.claude/scripts/lib/negative-ledger.sh` — append + query helpers
- Composes with audit envelope: emit `negative_ledger.entry` event for traceability
- Surfaces in NOTES.md tail at sprint ship via existing post-merge orchestrator

This is a 1-2 day implementation. Highly compounding return.

### 2. **End-to-end testing matrix discipline**

> Source: FrankenSQLite — "1 thread, 2 threads, 4 threads... up to 32; reads, inserts, deletes; 1K rows vs 100K rows."

Cycle-102 Sprint 4 AC-4.6 already gestures at this for parallel-dispatch (3+3 concurrent on 12-30K prompt). Could formalize as a Loa primitive:

- `tests/perf-matrix/` directory with structured workload + scaling-axis fixtures
- Workload axes: providers × concurrency × prompt-size × endpoint-family
- Pin baseline + regression thresholds per cell
- Visualize as heatmap (mirrors profiling-software-performance hotspot table)

Lower priority than negative-ledger. Worth doing during cycle-102 Sprint 4-5; not blocking.

### 3. **Agent-ergonomics audit** for Loa's own scripts

> Source: agent-ergonomics-and-agent-intuitiveness-maximization-for-cli-tools post

Jeffrey's principles applied to Loa:
- ✅ `--json` output: most Loa scripts have it
- ❌ `--robots` flag for machine-readable docs: Loa doesn't distinguish robot-docs from human-docs
- ⚠️ "Legible intent" / fuzzy parsing: most Loa scripts are strict. Worth softening for top-level skills (`/loa`, `/build`).
- ⚠️ Teaching errors with worked examples: variable across Loa scripts; some good (`golden-path.sh`), some terse
- ✅ Provenance fields: Loa's audit envelopes are MORE rigorous than provenance fields
- ✅ Stable handles: Loa uses content-addressable IDs (cycle-098)

Could run a Loa-specific ergonomics pass during a future hardening cycle. Not blocking.

### 4. **Capability narrowing** (`&Cx` context type)

> Source: FrankenSQLite — "a read-only Cx mechanically forbids write paths"

Loa's hooks (`.claude/hooks/safety/team-role-guard*.sh`) implement role-based capability narrowing for Agent Teams. Jeffrey's `&Cx` pattern is type-system-enforced (Rust). Loa is bash-enforced. Different enforcement layer, same idea. Worth noting: when Loa primitives are ported to Rust (eventually), the `&Cx` pattern becomes the natural enforcement mechanism.

## Sync mechanism — concrete proposal

Goal: stay current with Jeffrey's skill updates without manually checking 70+ skills.

**Phase 1 — Manifest + diff (low-effort, high-value)**

`grimoires/loa/jeffrey-skills-manifest.yaml`:
```yaml
schema_version: 1
last_synced_utc: 2026-05-09T15:00:00Z
adopted:
  - name: dcg
    upstream_path: ~/.claude/skills/dcg/
    upstream_repo: https://github.com/Dicklesworthstone/destructive_command_guard
    last_known_hash: <sha256 of SKILL.md>
    loa_port_status: not_started   # not_started | in_progress | adopted | superseded_by_loa_native
    loa_port_path: null
    last_review_date: 2026-05-09
  - name: beads-compliance-and-completion-verification
    ...
```

Weekly cron-equivalent (could fold into post-merge orchestrator):
```bash
.claude/scripts/jeffrey-skills-diff.sh
# 1. For each manifest entry, compute current SKILL.md hash
# 2. Compare against last_known_hash
# 3. If diff detected: emit summary to grimoires/loa/NOTES.md tail + file as a low-priority issue
```

**Phase 2 — Open-source repo tracking** (for the ones with public repos)

For dcg, beads_rust, cass — public repos. Use `gh` API:
```bash
.claude/scripts/jeffrey-repos-poll.sh
# gh api repos/Dicklesworthstone/{repo}/releases/latest
# diff against pinned version in Loa
# surface delta to NOTES.md tail
```

**Phase 3 — Skill self-update** (optional, ambitious)

For skills that are pure shell+markdown (not OSS deps), a `loa update --jeffrey-skills` command that:
1. Diffs upstream against last-pinned
2. Produces a structured changelog
3. Operator confirms merge / skip / reject per-skill
4. Adopted skills get a Loa-side wrapper at `.claude/skills/jeffrey-adapter-<name>/` that delegates

## Next-cycle scoping (NOT cycle-102)

The following could be a single follow-on cycle, after cycle-102 ships:

**Candidate name**: `cycle-104-jeffrey-pattern-adoption`

**Sprints**:
1. Negative-ledger primitive (Loa-native, lib + helper scripts + NOTES integration + audit envelope event)
2. dcg integration (curl-bash install + Loa-side hook + protocol doc)
3. beads-compliance integration (sample-mode tier; composes with /audit-sprint)
4. Sync mechanism (manifest + diff cron + repo-poll)
5. ubs / multi-pass-bug-hunting integration (composes with Bridgebuilder; pre-merge gate)

Estimated: 2-3 weeks. Each sprint independently shippable.

## Notes for future-cycle consideration

- **The negative ledger genuinely belongs in cycle-102 Sprint 1**, not a follow-on cycle — Sprint 1 is when the perf-attempt pattern starts (probe-gate latency, A1/A2 max_output_tokens tuning, A6 concurrency). Adding ledger-helper scripts as part of Sprint 1 setup is a 1-day insertion that compounds across the rest of cycle-102. **Recommendation: amend cycle-102 Sprint 1 task list with T1.0 (negative-ledger primitive)**.

- **dcg should land before any swarm session**. The next time NTM is invoked (or simstim multi-agent runs), one rogue agent can wipe state. dcg is the seatbelt. Pre-cycle-102 sprint 1: install dcg standalone + add to .claude/protocols/swarm-safety.md.

- **beads-compliance-and-completion-verification might be the right answer to P0-1**. Issue #661 (beads MIGRATION_NEEDED) is upstream-bug-blocking us. Jeffrey's compliance skill operates on the same beads database; if his skill works around #661, we may be able to leverage his code path. Worth investigating before opting for the 24h opt-out fallback.

- **Consider whether `/run-bridge` should be a thin wrapper over `repeatedly-apply-skill`** — Jeffrey's skill is conceptually our kaironic-plateau primitive. They might be unifiable. Not urgent.

## Acknowledgments

Jeffrey Emanuel's open-source work and skills site are direct inspirations for many Loa primitives. The negative-evidence ledger pattern, dcg, agent-mail, beads_rust, cass, NTM — these are all upstream of Loa or composable with it. Per the user's framing: "he is our main inspiration."

This doc exists so we can honor that influence with disciplined adoption rather than ad-hoc absorption.

---

*Filed during cycle-102 kickoff session 2026-05-09; produced in response to operator surfacing Jeffrey's posts on FrankenSQLite + agent-ergonomics + dcg. Not implementation — strategy + survey + recommendation. Next action: operator decides whether negative-ledger lands in cycle-102 Sprint 1 or in a follow-on cycle-104.*
