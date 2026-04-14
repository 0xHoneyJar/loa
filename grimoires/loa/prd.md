# PRD: Vision Registry Graduation — Query API, Lifecycle, Spiral Integration

**Issue**: #486
**Cycle**: 069
**Parent**: RFC-060 (#483, AC 3 — cross-cycle memory via Vision Registry)
**Dependencies**: cycle-067 (vision-lib.sh), cycle-068 (spiral real dispatch)
**Date**: 2026-04-14

**Flatline PRD Review (2026-04-14, 3-model consensus, 100% agreement)**:
- 5 HIGH_CONSENSUS auto-integrated (exit codes, tag mapping, seed schema, ranking AC, frontmatter schema)
- 3 blockers overridden (concurrent races — single-user model; multi-file txn — ordered writes + idempotent recovery; escaping — sanitization added)
- 2 blockers rejected (status semantics — already resolved by IMP; parsing brittleness — already resolved by IMP-008)

---

## 1. Problem Statement

The Vision Registry is an **append-only store**. Visions are captured during Bridgebuilder reviews and written to `grimoires/loa/visions/entries/vision-NNN.md`, but they are never read back programmatically. The `seed_phase()` in `spiral-orchestrator.sh` has a `full` mode path (line 515) that checks for the Vision Registry — but it immediately demotes to `degraded` because no query API exists. This means:

1. **Cross-cycle memory is text blobs**: degraded mode copies a `seed-context.md` text dump between cycles. No structure, no filtering, no relevance scoring.
2. **Visions accumulate without lifecycle**: 9 visions exist (vision-001 through vision-009), but none have been promoted to lore, archived, or rejected. `vision_check_lore_elevation()` exists but nothing invokes it in a workflow.
3. **Index drifts from entries**: the index.md table shows different content than the actual entry files (e.g., vision-001 index row says "Pluggable credential provider registry" but the file contains a spiral SEED observation). No rebuild mechanism exists.
4. **Octal arithmetic bug**: `bridge-vision-capture.sh:236` uses `printf "%03d"` to zero-pad vision IDs, but downstream bash arithmetic interprets `008`/`009` as invalid octal. The 10th vision will fail.

Graduating the Vision Registry unblocks `spiral.seed.mode: full` — replacing text-blob SEED handoffs with structured queries that filter visions by relevance to the current cycle's context.

> Source: `spiral-orchestrator.sh:515` — full mode demotion; `vision-lib.sh` — 11 functions, no CLI query interface

## 2. Goals & Success Metrics

| # | Goal | Metric | Target |
|---|------|--------|--------|
| G1 | Query visions by tag, severity, source, date, status | `vision-query.sh --tags security --status Captured` returns matching entries | Functional |
| G2 | Lifecycle management: promote, archive, reject | `vision-lifecycle.sh promote vision-003` elevates to lore + updates status | Functional |
| G3 | `seed_phase()` full mode uses registry queries | Full mode queries visions by tags derived from current cycle context | Traceable in trajectory |
| G4 | Index rebuild/reconciliation | `vision-query.sh --rebuild-index` regenerates index.md from entry files | Index matches entries |
| G5 | Octal bug fixed | Vision IDs 008, 009, 010+ created without arithmetic errors | No regression |
| G6 | No regression in existing vision/spiral tests | All existing tests remain green | 100% pass |

**Closes**: #486, RFC-060 AC 3 (cross-cycle memory via Vision Registry)

**Non-goals**: migration of degraded-mode text blobs into vision entries (per cycle-067 design decision: full mode cold-starts explicitly), UI/dashboard for visions, real-time vision streaming.

## 3. User & Stakeholder Context

**Primary user**: Loa maintainer running `/spiral --start` in full mode. The spiral's `seed_phase()` queries the Vision Registry for relevant cross-cycle insights, producing higher-quality seed context than text-blob handoff.

**Secondary user**: Loa maintainer running `/review` or Bridgebuilder reviews. Visions accumulate and can now be managed — promoted to lore patterns when they prove their worth, archived when stale, rejected when invalid.

## 4. Functional Requirements

### FR-1 — Vision Query CLI (`vision-query.sh`)

New script `.claude/scripts/vision-query.sh` wrapping `vision-lib.sh` functions:

| Flag | Type | Description |
|------|------|-------------|
| `--tags <t1,t2>` | filter | Match visions containing ANY of the specified tags |
| `--status <s>` | filter | Match visions with this status (Captured, Exploring, Proposed, Implemented, Deferred, Archived, Rejected) |
| `--source <pattern>` | filter | Grep-match against Source field |
| `--since <date>` | filter | Visions created on or after ISO date |
| `--before <date>` | filter | Visions created before ISO date |
| `--min-refs <n>` | filter | Visions with >= n references |
| `--format json\|table\|ids` | output | JSON array (default), pipe-delimited table, or newline-separated IDs |
| `--rebuild-index` | action | Regenerate index.md from entry files (G4) |
| `--count` | output | Return count of matching visions instead of listing |
| `--limit <n>` | output | Max results (default: 50) |

**Status filter grammar** (Flatline SKP-001): `--status` accepts a comma-separated list. `--status Captured,Exploring,Proposed` matches visions in any of those states. Normalized to lowercase internally. This is required by FR-3's multi-status query.

**Composability**: Filters are AND-combined. `--tags security --status Captured --since 2026-04-01` returns security-tagged visions captured since April 1st.

**Implementation**: Parse frontmatter from each `grimoires/loa/visions/entries/vision-*.md` via awk/sed (no jq dependency on markdown). For `--format json`, emit structured JSON. For `--rebuild-index`, regenerate the pipe-delimited table and statistics section.

**Exit codes** (Flatline IMP-001):

| Exit code | Meaning |
|-----------|---------|
| 0 | Success (results found, or rebuild complete) |
| 1 | No results matching filters (not an error — empty JSON array on stdout) |
| 2 | Invalid arguments (bad flag, unknown status, malformed date) |
| 3 | Parse error (corrupt entry file, quarantined — see NFR-7) |
| 4 | I/O error (permission denied, missing visions directory) |

**Frontmatter schema contract** (Flatline IMP-008): Entries MUST conform to this canonical schema:

```markdown
# Vision: <TITLE>

**ID**: vision-NNN
**Source**: <free-text source reference>
**PR**: #<number> | (omitted)
**Date**: <ISO-8601 UTC timestamp>
**Status**: Captured|Exploring|Proposed|Implemented|Deferred|Archived|Rejected
**Tags**: [comma-separated, lowercase-hyphenated]
```

Parser behavior on malformed entries: log warning, skip entry (not fail), report via exit code 3 if `--strict` flag. Non-strict mode (default) quarantines invalid entries in output as `"parse_error": true` and continues.

**Performance**: File-scan approach is fine — we have <100 visions. If this grows, a future cycle can add a JSON index cache.

### FR-2 — Vision Lifecycle CLI (`vision-lifecycle.sh`)

New script `.claude/scripts/vision-lifecycle.sh` managing lifecycle transitions:

| Command | Transition | Effect |
|---------|-----------|--------|
| `promote <id>` | Any → Implemented | Generate lore entry via `vision_generate_lore_entry()`, append to `grimoires/loa/lore/discovered/visions.yaml`, update vision status to `Implemented`, update index |
| `archive <id> [--reason <text>]` | Any non-terminal → Archived | Update vision status, add `Archived-Reason` to frontmatter, update index |
| `reject <id> --reason <text>` | Any non-terminal → Rejected | Update vision status, add `Rejected-Reason` to frontmatter (reason required), update index |
| `explore <id>` | Captured → Exploring | Update vision status, update index |
| `propose <id>` | Exploring → Proposed | Update vision status, update index |

**Transition rules**:
- Terminal states: `Implemented`, `Archived`, `Rejected` — no further transitions
- `promote` can be called from any non-terminal state (shortcut for visions that prove valuable quickly)
- `reject` requires `--reason` (prevents casual rejection without explanation)
- All transitions use `vision_update_status()` from vision-lib.sh (atomic flock-guarded writes)
- All transitions update index.md via `vision-query.sh --rebuild-index`
- **Input sanitization** (Flatline SKP-005): `--reason` text stripped of pipe `|` characters (break markdown tables), newlines (break frontmatter), and control characters. All reason text written to JSONL via `jq --arg`. Vision content flowing to YAML uses `vision_sanitize_text()` (existing allowlist extractor)

**Exit codes** (Flatline IMP-001): Same table as FR-1, plus exit code 5 for invalid transition (e.g., promoting an already-Rejected vision).

**Lore elevation on promote**:
1. Call `vision_generate_lore_entry()` to create YAML entry
2. Append to `grimoires/loa/lore/discovered/visions.yaml` via `vision_append_lore_entry()` (idempotent — checks vision_id)
3. Log `vision_promoted` trajectory event with vision_id, lore_entry_id

### FR-3 — Spiral seed_phase() Full Mode Integration

Replace the demotion fallback in `spiral-orchestrator.sh:515` with actual registry queries:

1. **Mode selection** (existing logic): read `spiral.seed.mode` from config
2. **Full mode path** (new):
   - Extract tags from current cycle context (PRD keywords, previous cycle's findings)
   - Query registry: `vision-query.sh --tags <derived_tags> --status Captured,Exploring,Proposed --format json --limit 10`
   - If zero results, fall back to cold start (not degraded) — full mode that finds nothing is still full mode
   - Build structured seed context from query results: vision ID, title, insight excerpt (first 200 chars), tags
   - Write `seed-context.md` with structured format (Flatline IMP-004):
     ```json
     {
       "mode": "full",
       "query": {"tags": ["security"], "statuses": ["Captured","Exploring"], "limit": 10},
       "visions": [
         {
           "id": "vision-009",
           "title": "Audit-Mode Context Filtering",
           "tags": ["security", "epistemic-enforcement"],
           "status": "Captured",
           "date": "2026-02-19T...",
           "insight_excerpt": "First 200 chars of ## Insight section...",
           "relevance_score": 0.8
         }
       ],
       "total_bytes": 1234,
       "budget_bytes": 4096,
       "truncated": false
     }
     ```
   - Log `seed_full` trajectory event with query parameters, result count, total context bytes
3. **Tag derivation strategy** (Flatline IMP-002): Extract tags from the cycle's HARVEST sidecar (`cycle-outcome.json`) if available. Deterministic mapping:

   | HARVEST category | Vision tag |
   |-----------------|------------|
   | `security` | `security` |
   | `architecture` | `architecture` |
   | `performance` | `performance` |
   | `reliability` | `reliability` |
   | `testing` | `testing` |
   | `code-quality` | `code-quality` |
   | `documentation` | `documentation` |
   | (unmapped) | Skipped with warning log |

   Fallback: use configured default tags from `.loa.config.yaml` (`spiral.seed.default_tags`). If HARVEST sidecar has no `findings[].category` fields, fall back to default tags.
4. **Context budget**: 4KB max for seed context (same as degraded mode). If query results exceed budget, prioritize by: (a) tag overlap score via `vision_match_tags()`, (b) recency.

**Design decision** (cycle-067): full mode cold-starts explicitly. No degraded→full reconciliation. If a cycle ran in degraded mode and produced a `seed-context.md` text blob, switching to full mode ignores it and queries the registry fresh.

### FR-4 — Octal Bug Fix

`bridge-vision-capture.sh:236`:

**Current** (buggy):
```bash
vision_id=$(printf "vision-%03d" "$local_num")
```

Where `local_num` is derived from filename parsing that can produce zero-padded strings like `009`.

**Fix**: Force base-10 interpretation before arithmetic:
```bash
local_num=$((10#$local_max + 1))
vision_id=$(printf "vision-%03d" "$local_num")
```

This ensures `009` is parsed as decimal 9, not invalid octal.

### FR-5 — Index Rebuild Mechanism

`vision-query.sh --rebuild-index`:

1. Scan all `grimoires/loa/visions/entries/vision-*.md` files
2. Parse frontmatter from each (ID, Title from `# Vision:` header, Source, Status, Tags)
3. Read ref count from `vision_record_ref()` data (or default 0)
4. Regenerate `grimoires/loa/visions/index.md` with:
   - Schema version comment
   - Pipe-delimited table sorted by ID
   - Accurate statistics section (count by status)
5. Atomic write via `vision_atomic_write()`

**Idempotent**: Running rebuild twice produces identical output.

### FR-6 — Config Extensions

New config keys in `.loa.config.yaml`:

```yaml
vision_registry:
  enabled: true                     # Graduate from false to true
  # ... existing keys unchanged ...

spiral:
  seed:
    mode: "full"                    # Graduate from "degraded" to "full"
    default_tags: ["architecture", "security"]  # Fallback tags when no HARVEST context
    max_seed_visions: 10            # Max visions in seed context
```

## 5. Technical & Non-Functional Requirements

| NFR | Requirement |
|-----|-------------|
| NFR-1 | Zero new dependencies (bash/jq/awk/sed only) |
| NFR-2 | All file mutations via `vision_atomic_write()` (flock-guarded) |
| NFR-3 | All JSON construction via `jq --arg`/`--argjson` (no heredoc interpolation) |
| NFR-4 | Query script completes in <2s for 100 vision entries |
| NFR-5 | Lifecycle transitions logged to trajectory JSONL |
| NFR-6 | Index rebuild is idempotent |
| NFR-7 | Vision entry frontmatter parsing tolerant of minor format variations |

## 6. Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Frontmatter parsing fragility | Medium | Medium | Strict format validation via `vision_validate_entry()`, rebuild normalizes |
| Tag derivation produces irrelevant matches | Medium | Low | Cold-start fallback if zero results; context budget limits noise |
| Index rebuild overwrites manual edits | Low | Low | Index is generated, not hand-edited; rebuild is the source of truth |
| Full mode produces worse seed than degraded | Low | Medium | Trajectory logging enables comparison; can revert to degraded via config |

**Dependencies**: vision-lib.sh (cycle-067, stable), spiral-orchestrator.sh (cycle-068, merged), bridge-vision-capture.sh (existing).

## 7. Acceptance Criteria

- [ ] `vision-query.sh` filters by tag, status, source, date, min-refs and returns correct results
- [ ] `vision-query.sh --format json` emits valid JSON array
- [ ] `vision-query.sh --rebuild-index` regenerates index.md matching actual entry files
- [ ] `vision-lifecycle.sh promote` creates lore entry and updates status to Implemented
- [ ] `vision-lifecycle.sh archive` and `reject` update status with reason tracking
- [ ] Terminal states (Implemented, Archived, Rejected) block further transitions
- [ ] `reject` requires `--reason` flag
- [ ] `seed_phase()` full mode queries registry and builds structured seed context
- [ ] Full mode with zero query results falls back to cold start (not degraded)
- [ ] Seed context respects 4KB budget with tag-overlap + recency prioritization
- [ ] Ranking: visions with higher tag overlap score appear before lower (Flatline IMP-007)
- [ ] Truncation: when results exceed 4KB budget, lowest-ranked visions are dropped (not truncated mid-entry)
- [ ] Seed context JSON validates against the schema defined in FR-3
- [ ] Octal bug fixed: vision IDs 008, 009, 010+ work correctly
- [ ] Index statistics are accurate after rebuild
- [ ] All existing vision/spiral tests pass
- [ ] New tests cover query filtering, lifecycle transitions, full-mode seed, octal edge case
- [ ] Sub-agent review + audit APPROVED
- [ ] PR merged to main

### Sources

- `.claude/scripts/vision-lib.sh` (11 functions, query/lifecycle foundation)
- `.claude/scripts/bridge-vision-capture.sh:236` (octal bug)
- `.claude/scripts/spiral-orchestrator.sh:504-561` (seed_phase mode switch)
- `grimoires/loa/visions/` (9 existing entries, drifted index)
- `.loa.config.yaml:83-97` (vision_registry + spiral config)
- `grimoires/loa/lore/discovered/visions.yaml` (lore elevation target)
