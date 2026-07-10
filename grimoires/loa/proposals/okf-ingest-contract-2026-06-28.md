# OKF Ingest Contract — parse-soft / promote-strict

**Status:** Contract (doc only — no code until a real external OKF feed exists).
**Cycle:** OKF/ICM adoption (2026-06-28). **Source:** PR #1155 analysis (rec #12) + grounding brief.

## Scope
This contract governs what loa MUST do **if** it ever ingests an external [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) bundle (e.g. from another fleet repo via the L5 cross-repo path). There is **no OKF ingest path today** (grep-confirmed); building one now would manufacture a dormant, unused security surface — exactly the build-ahead pattern this cycle is removing from L4. So this is a contract, not code.

## The rule: parse-soft, promote-strict
- **Parse-soft** — when reading an OKF bundle, tolerate its broken links / missing optional fields (OKF SPEC §5.3/§9 says consumers MUST). Do **not** reject the bundle for being OKF-conformant-but-thin.
- **Promote-strict** — never promote an unverified claim from an ingested bundle into a *grounded* loa artifact (GT, lore, known-failures). Anything that crosses into loa's grounded corpus must clear loa's normal grounding checks (cite `file:line`, evidence). OKF fail-soft tolerance stops at the ingest boundary; see `.claude/rules/zone-state.md` (OKF non-adoption rule).

## Required boundary handling (when implemented)
An ingest implementation MUST:
1. Route through the existing untrusted-content boundary — `cross-repo-status-lib.sh` (argv-not-stdin; `MAX_ENTRIES` JSON-blowup cap; `context-isolation-lib.sh` / `structured-handoff-lib.sh` sanitize-at-surfacing helpers).
2. Wrap every concept body as `<untrusted-content source="okf">` and never interpret it as instructions.
3. Emit exactly one `audit_emit` envelope at the ingest boundary recording "unverified external OKF bundle consumed; fields NOT validated against loa schemas."
4. MUST NOT import OKF §9 fail-soft tolerance into any loa decision-gating path.

## Why this reinforces the posture
The parse-soft/promote-strict split is the correct reconciliation of OKF's fail-soft consumption with loa's fail-closed grounding (analysis §7, tension 2): the bundle is read leniently, but nothing untrusted is ever promoted to truth without verification — loa's grounding contract is reinforced, not breached.
