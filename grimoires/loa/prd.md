# PRD: Lore Promoter — HARVEST phase consumer

**Cycle**: cycle-060 (simstim full-gates exercise)
**Issue**: [#481](https://github.com/0xHoneyJar/loa/issues/481)
**Parent vision**: RFC-060 `/spiral` autopoietic meta-orchestrator (pending)
**Date**: 2026-04-13
**Version**: 1.0

---

## 1. Problem Statement

`post-pr-triage.sh` (shipped v1.73.0) queues PRAISE-severity findings from post-PR Bridgebuilder reviews to `.run/bridge-lore-candidates.jsonl`. The queue is write-only — there is no consumer. Candidates accumulate indefinitely without ever landing in `grimoires/loa/lore/patterns.yaml`, where they would feed future `/architect` and Bridgebuilder runs as reusable pattern context (consumed by the v1.75.0 `core/lore-loader.ts`).

This is **Gap 1 of the HARVEST phase** identified in the autopoietic spiral design: findings are produced but don't close the loop back into reusable context for subsequent cycles. The framework's pattern-recognition muscle generates output at cost, but the output isn't retained for future benefit.

### Concrete evidence
- Schema: `.claude/data/trajectory-schemas/bridge-triage.schema.json` (PRAISE action = `lore_candidate`)
- Producer: `post-pr-triage.sh:143-252` writes to queue on every PRAISE finding
- Consumer: none exists
- Current queue state: empty in this branch, but 40 PRAISE-action decisions have been logged across PRs #100/#469/#471 per `bridge-triage-stats.sh` output — meaning the queue *would* have accumulated 40 candidates if the trajectory had produced them. The queue mechanism is real and active.
- Downstream: `grimoires/loa/lore/patterns.yaml` has 1 manually-curated entry (`governance-isomorphism`) — every additional entry today requires hand-authoring

> Sources: [#481](https://github.com/0xHoneyJar/loa/issues/481), `grimoires/loa/context/lore-promoter-vision.md`, `post-pr-triage.sh:143-252`, `bridge-triage-stats.sh` output

## 2. Goals & Success Metrics

| # | Goal | Metric | Target |
|---|------|--------|--------|
| G1 | Vetted PRAISE candidates reach `patterns.yaml` | Script exists, runs end-to-end against real queue | Binary |
| G2 | Promotion is safe against prompt-injection | Injection-pattern scan + field length limits | All candidates sanitized before promotion |
| G3 | Re-runs are idempotent | Running promoter twice doesn't duplicate entries | Binary — `diff` on output yaml is empty on 2nd run |
| G4 | Provenance preserved | Every promoted entry carries `source: {pr, finding_id, promoted_at}` | 100% of entries |
| G5 | Two modes: interactive + threshold | `--interactive` prompts per candidate; `--threshold N` auto-promotes patterns seen ≥N times | Both modes BATS-covered |
| G6 | No new dependencies | Uses only `bash`, `jq`, `yq`, `gh` (optional) | Binary |

**Non-goals:**
- Automated lore *deprecation* (stale entries — separate future problem)
- Lore versioning beyond timestamp provenance
- Cross-repo lore federation (single-repo scope)
- ML-based pattern clustering (threshold-counting sufficient for MVP)
- Retroactive harvesting of missed candidates from trajectory logs (separate script if needed)

## 3. User & Stakeholder Context

**Primary user**: Loa framework maintainer running the promoter periodically (e.g., after 5+ PRs have accumulated PRAISE findings). Curates `patterns.yaml` growth. Reviews candidates before they influence future prompts.

**Secondary users**:
- **Future Bridgebuilder sessions**: consume promoted lore via `grimoires/loa/lore/patterns.yaml` (wired v1.75.0)
- **Future `/architect` sessions**: reference lore when making architectural decisions
- **Downstream Loa consumers** (dozens of projects per user's note): inherit the promoted patterns when they pull framework updates

**Persona priorities**: framework maintainer is primary; the tool should be SAFE by default (interactive mode default, not auto-promote).

## 4. Functional Requirements

### FR-1 — Script surface (ubiquitous)
The system shall provide `.claude/scripts/lore-promote.sh` accepting:
- `--queue PATH` (default: `.run/bridge-lore-candidates.jsonl`) — input queue path
- `--lore PATH` (default: `grimoires/loa/lore/patterns.yaml`) — output lore file
- `--interactive` (default) — prompt per candidate with Accept/Reject/Skip options
- `--threshold N` — auto-promote patterns that recur across ≥N distinct PRs
- `--dry-run` — show what would be promoted without writing
- `--help` — usage text + exit codes

### FR-2 — Promotion policy (ubiquitous)
Every promoted entry MUST:
1. Conform to the `LoreEntry` schema in `grimoires/loa/lore/patterns.yaml` (fields: `id`, `term`, `short`, `context`, `source`, `tags`)
2. Carry a `source` field with keys `pr`, `finding_id`, `bridge_iteration`, `cycle`, `promoted_at` (ISO-8601 UTC)
3. Have `id` generated from term via slugify (reproducible, URL-safe)
4. Have all free-text fields sanitized per FR-5

### FR-2.1 — ID generation (Flatline PRD blocker #2 — accepted)
Generating `id` from `term` alone creates collision risk (different terms can slugify to the same id; case/punctuation variance). Collision policy:
1. Base `id` = slugify(term) — lowercase, `[a-z0-9-]+`
2. If the slug already exists in `patterns.yaml`, append `-<short-hash>` where hash = first 6 hex chars of sha256(full candidate content including PR number)
3. Hash inclusion means the same *content* always slugifies the same way, but different content with the same term disambiguates automatically
4. Unit test: two candidates with identical `term` but different `context` must produce distinct ids

### FR-3 — Interactive mode (event-driven)
When `--interactive` is set AND at least one candidate exists:
```
CANDIDATE [n/total]: [term]
Source: PR #X, finding F1, cycle-NNN
Short: [short text ≤ 160 chars]
Context: [context text ≤ 1000 chars]
Tags: [comma-separated]

[A]ccept / [R]eject / [S]kip / [E]dit / [Q]uit?
```
- Accept: promote to `patterns.yaml`, mark queue entry as `promoted: true`
- Reject: mark queue entry as `rejected: true` with timestamp
- Skip: leave queue entry unchanged (review later)
- Edit: deferred to future cycle (see Scope §6). In MVP, `E` prints "edit mode not yet implemented — use Accept/Reject/Skip" and returns to the prompt
- Quit: exit 0, preserving any decisions made so far

### FR-4 — Threshold mode (conditional)
When `--threshold N` is set:
- For each unique `term`, count distinct `pr_number` values in the queue
- If count ≥ N, auto-promote without prompting
- Otherwise, the candidate is skipped (left in queue for future runs)
- Output: summary of what was auto-promoted + what was below threshold

### FR-5 — Sanitization (ubiquitous, security-critical)
Before any free-text field is written to `patterns.yaml`:
- Strip ANSI escape sequences
- Strip null bytes and control characters (except tab/newline/CR)
- Enforce length limits: `term` ≤ 80 chars, `short` ≤ 200 chars, `context` ≤ 1500 chars
- Scan for known injection patterns (from `.claude/data/injection-patterns.yaml` if exists, else hardcoded baseline):
  - `"Ignore previous instructions"`
  - `"You are now"` / `"From now on"`
  - Prompt role markers (`"system:"`, `"user:"`, `"assistant:"` at line start)
  - HTML/markdown meta markers that could affect downstream rendering
- On any match: REJECT the candidate with a clear error, log to trajectory, never write to yaml

### FR-6 — Idempotency (ubiquitous)
Re-running the promoter MUST NOT:
- Duplicate entries (check by `id` before append)
- Re-prompt the user for candidates already decided (`promoted: true` or `rejected: true` in queue)
- Lose provenance on re-runs (source fields preserved)

### FR-7 — Graceful degradation (event-driven)
When the queue file does not exist: print "no candidates queued" to stderr, exit 0, no output.
When the queue contains zero unprocessed candidates: print "no new candidates", exit 0.
When `patterns.yaml` is absent: create it with an empty YAML array + file header comment.
When a candidate is malformed: skip with stderr warning, do not fail the whole run.

### FR-8 — Provenance (ubiquitous)
Every promoted entry's `source` field includes:
```yaml
source:
  pr: 469
  finding_id: "F1"
  bridge_iteration: "PR #469 pass 2"
  cycle: "cycle-060"
  promoted_at: "2026-04-13T14:30:00Z"
```

## 5. Technical & Non-Functional Requirements

### NFR-1 — Zero new dependencies
Uses only `bash`, `jq`, `yq`, `gh` (optional for issue-linking). All already Loa hard prereqs.

### NFR-2 — Performance
For ≤1000 candidates in queue, script completes within 5 seconds in threshold mode and within 30 seconds in interactive mode (dominated by human decision latency).

### NFR-3 — Safety (Flatline PRD blockers #1, #3, #4 — accepted)
- **Crash-consistent two-phase write order** (promote-then-mark):
  1. Write new entry to `patterns.yaml.tmp` (atomic)
  2. Rename `.tmp` → `patterns.yaml`
  3. Append `{decided_at, id, action: "promoted"}` marker to queue-decisions journal (`.run/lore-promote-journal.jsonl`)
  4. ONLY after journal append succeeds, update the queue entry's `promoted: true` marker
  Crash between steps 2-4 → next run detects via journal replay (find `promoted: true` in yaml but no queue marker → idempotent, safe) OR (marker in journal but not queue → resume from queue update)
- **File locking** on `patterns.yaml` writes and `.run/bridge-lore-candidates.jsonl` reads/writes using `flock(1)` with a 10s timeout. Abort with clear error if lock cannot be acquired — prevents two concurrent promoter runs from racing.
- **JSONL mutation model**: never rewrite the queue file in place. Instead append decisions to `.run/lore-promote-journal.jsonl`. The queue file is effectively read-only after initial write by `post-pr-triage.sh`; promoter reads it + the journal to determine which entries remain undecided. This eliminates partial-write corruption on the queue.
- Write-ahead pattern for `patterns.yaml`: write to `.tmp` then `mv` atomically
- Never deletes queue entries (only journals decisions)
- Respects `patterns.yaml` being under version control — writes preserve formatting where possible

### NFR-4 — Security (key concern; Flatline PRD blocker #6 — partially accepted)
- **Defense in depth, not single-layer**: FR-5 pattern scan is the first layer. Additional layers:
  1. Pattern scan (FR-5)
  2. Length limits (FR-5) — caps blast radius of any injection that passes pattern scan
  3. Structural validation (YAML schema conformance) — injection attempts that violate schema are rejected
  4. **Provenance gating**: auto-promotion requires the source PR to be MERGED to main (not just opened), verified via `gh pr view --json state`. Pending/closed-without-merge PRs are treated as untrusted.
  5. Human-review default: interactive mode is the default; threshold auto-mode requires explicit `--threshold N` with `N ≥ 2` floor
- `--threshold` mode default MUST NOT enable auto-promotion below the floor (hardcoded minimum of 2 distinct merged-PRs)
- Logs every promotion/rejection decision to `grimoires/loa/a2a/trajectory/lore-promote-YYYY-MM-DD.jsonl` AND to `.run/lore-promote-journal.jsonl` (the crash-consistency journal)
- **Honest limitation**: no sanitization layer is complete. A sufficiently motivated adversary can craft PRAISE-shaped content that passes all layers. The interactive default plus merge gating plus length limits raise the bar substantially but do not eliminate the threat. Documented as Known Limitation in the SDD.

### NFR-5 — Zone compliance
- System Zone write: `.claude/scripts/lore-promote.sh` (authorized at cycle-060 scope)
- State Zone writes: `grimoires/loa/lore/patterns.yaml`, `grimoires/loa/a2a/trajectory/lore-promote-*.jsonl`
- State Zone reads: `.run/bridge-lore-candidates.jsonl`
- No App Zone interaction

## 6. Scope & Prioritization

### MVP (this cycle)
- FR-1, FR-2, FR-3 (interactive mode), FR-5 (sanitization), FR-6 (idempotency), FR-7 (degradation), FR-8 (provenance)
- BATS tests covering: interactive promote, reject, skip, edit, quit; idempotency; malformed candidate; injection rejection; empty queue; missing yaml auto-create
- Docs: inline usage header + run-bridge SKILL.md cross-reference

### Stretch
- FR-4 (threshold mode) — include if sprint budget allows, otherwise defer

### Out of scope
- Lore deprecation workflow
- Retroactive trajectory harvesting
- Cross-repo federation
- `--edit` full round-trip editing UX (MVP can stub with a warning "edit mode requires manual review")

## 7. Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Malicious PR author crafts adversarial PRAISE to influence future prompts | Low | High | FR-5 sanitization; interactive default; min-2-PRs floor for auto |
| Duplicate lore entries from re-runs | Medium | Low | FR-6 idempotency check on `id` |
| `patterns.yaml` format drift over time | Low | Medium | Schema validation on each write; FR-2 schema conformance |
| Queue grows unbounded | Low | Low | Informational only — future cycle can add rotation |
| User review fatigue (many candidates) | Medium | Medium | Threshold mode (FR-4) bypasses review for high-confidence patterns |
| Breaking change to lore schema in future | Low | High | Versioning deferred to future cycle; current schema is stable since v1.42.0 |

**Dependencies**:
- `post-pr-triage.sh` (shipped v1.73.0) — produces the queue
- `core/lore-loader.ts` (shipped v1.75.0) — consumes `patterns.yaml`
- `grimoires/loa/lore/patterns.yaml` (single existing entry: `governance-isomorphism`)

---

### Sources
- [#481](https://github.com/0xHoneyJar/loa/issues/481) — tracking issue
- `grimoires/loa/context/lore-promoter-vision.md` — vision doc (authored during discovery prep)
- `post-pr-triage.sh:143-252` — producer logic
- `.claude/data/trajectory-schemas/bridge-triage.schema.json` — queue entry schema
- `grimoires/loa/lore/patterns.yaml` — output format (existing manually-curated entry as schema anchor)
- v1.79.0 [release](https://github.com/0xHoneyJar/loa/releases/tag/v1.79.0) — established HARVEST phase pattern via `bridge-triage-stats.sh`
