# Security Analysis TODO

**Audit ID**: audit-2026-07-18-sprint-bug-227
**Schema Version**: 1.0
**Scope**: `d75f5b60...2051b754` (sprint-bug-227)

## Flagged Sources (Pass 1)

| ID | File:Line | Type | Trust | Description | Status |
|----|-----------|------|-------|-------------|--------|
| SRC-001 | `.claude/scripts/flatline-orchestrator.sh:319` | model output | UNTRUSTED | Cheval `.content` enters normalization and schema qualification | SAFE — normalized and schema-validated before quorum |
| SRC-002 | `.claude/adapters/loa_cheval/verdict/aggregate.py:471` | file input | TAINTED | Per-voice JSON envelope read by the aggregator CLI | SAFE — full canonical schema and invariant validation |
| SRC-003 | `.claude/scripts/flatline-orchestrator.sh:641` | environment | SEMI-TRUSTED | Test/concurrency output-directory override | SAFE — operator-owned process environment; no privilege boundary |
| SRC-004 | `.claude/scripts/flatline-orchestrator.sh:1953` | CLI argument | UNTRUSTED | Phase participates in output path construction | SAFE — allowlisted at lines 2069-2077 before any output invalidation/write |

## Flagged Sinks (Pass 1)

| ID | File:Line | Type | Risk | Status |
|----|-----------|------|------|--------|
| SINK-001 | `.claude/scripts/flatline-orchestrator.sh:654` | file deletion | Path traversal | SAFE — production phase allowlist dominates the sink |
| SINK-002 | `.claude/scripts/flatline-orchestrator.sh:736-753` | file publication | Evidence integrity | CONFIRMED — atomic per write, but default path is shared by same-phase concurrent runs |
| SINK-003 | `.claude/scripts/flatline-orchestrator.sh:731-733` | stderr log | Information disclosure / log injection | CONFIRMED — schema-library messages may include rejected model values |
| SINK-004 | `.claude/adapters/loa_cheval/providers/cursor_headless_adapter.py:305-317` | subprocess | Command/tool abuse | SAFE — argv list, isolated cwd, ask mode, sandbox enabled, no force/yolo |

## Taint Paths (Pass 2)

| ID | Source | Sink | Hops | Sanitized | Status |
|----|--------|------|------|-----------|--------|
| PATH-001 | SRC-001 | quorum participation | `.content` → normalize → agent schema → qualified cohort | YES | SAFE |
| PATH-002 | SRC-002 | aggregate publication | JSON parse → canonical schema → single-voice invariants → status reconciliation → atomic write | YES | SAFE |
| PATH-003 | SRC-004 | SINK-001/SINK-002 | `--phase` → allowlist → path helper | YES | SAFE; invalid `../escape` exits 1 before sink |
| PATH-004 | rejected model value | SINK-003 | schema error `.message` → CLI stderr → orchestrator log | NO | CONFIRMED; LOW |
| PATH-005 | concurrent same-phase run | SINK-002 | phase-global target → invalidate/write/read | PARTIAL | CONFIRMED; MEDIUM |

## Cross-Request Flows

No database, HTTP, authentication, authorization, PII, cryptocurrency-key, or cross-request persistence path is introduced by this sprint. The only cross-run surface is the phase-global consensus artifact called out in PATH-005.

## Circuit Breaker

The implementation diff is 974 added/changed lines, below the 2,000-line sequential-audit threshold. All flagged paths were traced; none remain pending.
