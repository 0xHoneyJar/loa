# Flatline record — cycle-124 PRD (Sprint 1 Task 1.10)

Source: `grimoires/loa/prd.md` §11 (rounds) and §9 (arbiter decisions). Cohort on this host: opus via claude-headless + gpt-5.5 via codex-headless; the gemini tertiary was tier-blocked (KF-018) and disabled in both `.loa.config.yaml` keys after round 2. Cross-scoring stayed `degraded` in every round that reached Phase 2, so no blocker ever became HIGH_CONSENSUS — the lead acted as arbiter and every decision is recorded, not assumed.

## Rounds

| Round | Cohort | Outcome | What was integrated |
|---|---|---|---|
| 1 (01:26Z) | opus + gpt-5.5; tertiary failed | DEGRADED 2/3, Phase 2 skipped, exit 6; opus 18 improvements (7 HIGH), gpt 10 (4 HIGH) | 24 items verbatim into FR-1…FR-10, NFR-8, §7 (atomic units, MODELINV compatibility) |
| 2 (01:50Z) | same; tertiary still counted as planned via `hounfour.flatline_tertiary_model` | DEGRADED 2/3, exit 6; opus 15 (6 HIGH), gpt 10 (4 HIGH) | 23 items: G-1 wording, FR-2 API-constraint citation, `--temperature` handling, ledger resolver rules |
| 3 (02:15Z) | opus + gpt-5.5, 2/2; Phase 2 ran | voices 2/2, `scoring_degraded: true`, exit 6; 0 HIGH_CONSENSUS, 7 BLOCKERs (705–870), 16 medium | all 7 blockers resolved by lead decision (below) |
| 4 (02:35Z) | 2/2; cross-scoring degraded again | 0 HIGH_CONSENSUS, 5 BLOCKERs (705–790), 23 medium | headless enforcement, repair depth retained on unenforced voices, `schema_enforced` ratio measurement, credential-gated `live-floor-check.yml` |
| 5 (02:55Z, final) | opus review rejected by content qualification (`normalization_failed`: non-JSON on the 90 KB document — the KF-023 shape this cycle addresses) → 1/2 | DEGRADED, Phase 2 skipped, exit 6; gpt 8 improvements (3 HIGH) | all 8 integrated (reference ownership, AC-3.5 matrix wording, rollback data path) |

## Arbiter decisions (PRD §9)

| # | Question | Decision |
|---|---|---|
| Q1 | No Anthropic HTTP credential on the host | implement + unit-test everything; commit live scaffolds; AC-1.3 / AC-4.3 are the single operator blocker with exact commands; never borrow the Claude Code OAuth token (KF-020 class) |
| Q2 | Thinking flag shape | `params.thinking_adaptive: true`, schema-typed; absent = byte-identical body |
| Q3 | `max_tokens` default scope | Anthropic hops only; other providers keep the 4096 literal (golden bodies) |
| Q4 | Where the KF-002 gate lives | v3 `effective_input_ceiling: 180000` (probed, streaming) on every Anthropic HTTP entry; 36K non-streaming wall becomes `_LEGACY_TRANSPORT_INPUT_WALL` |
| Q5 | Schema enforcement on unenforced voices | per-hop `structured_json` capability gate; claude-headless via `--json-schema`; repair loop kept at depth on the unenforced branch (Sprint 2) |
| Q6 | `MODE_TO_AGENT["dissent"]` names a non-existent skill dir | recorded; fixed only if the dissent site is edited, else KF + separate `/bug` |
| Q7 | Same-issue circuit-breaker hash | hash of the derived `{verdict,counts}`; prose recipe kept as the labelled fallback (coarser ⇒ trips sooner ⇒ HALT) |
| Q8 | 10-PR fixture set absent | built in Sprint 3 from this repo's own `fix(...)` commits |
| Q9 | NOTES token measurement | bytes / 3.5 |
| Q10 | Sonnet 5 pricing mismatch | corrected to the reference ($2 / $10); flagged in the evidence file for the probe |
| Q11 | Protocols ≤ 140 KB unreachable this cycle | hard per-file budgets; total fails at 200 KB, warns at 140 KB — deviation reported for operator decision |
| Q12 | Confidence filter for coverage-first review | severity-aware, one-way, mechanical; `critical` never excludable; audit gate confirms `excluded_confirmed` |
| Q13 | Runtime kill switch for the new wire keys | `LOA_CHEVAL_LEGACY_WIRE=1` — pre-cycle body byte-for-byte; a backstop, not the rollback (which is `git revert`) |

## What Sprint 1 changed against these decisions

- Q4/Q13 landed as designed (`f5ea53f4`, `e14198a1`, `a421334a`). One addition: the legacy-wire switch also restores the 4096 output default, because a "pre-cycle body" that still asked for 64K would not be the pre-cycle body (NOTES Decision Log 2026-09-17).
- Q1 held: no live call was made; `tests/replay/test_cycle124_live_floor.py` + `.github/workflows/live-floor-check.yml` carry the assertions.
- Q7 landed in Task 1.7 with a stricter cross-check than the PRD prose (exit 2 always denies — SDD version; recorded).
