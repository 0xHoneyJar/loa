# Ponytail v4.7.0 ↔ Loa parity audit (2026-06-16)

Source: 21-agent ultracode workflow (10 capabilities × map+verify → synthesis),
grounded in /tmp/ponytail (v4.7.0) vs origin/main @ 2a88594e.

**Capability parity before this sprint: ~72%.** Loa already embodies ponytail's
load-bearing "full"-mode doctrine (PR #1067): the full 6-rung YAGNI ladder, the
reflex framing, the safety floor, the one-runnable-check, the `loa:shortcut:`
marker (= ponytail's `ponytail:`), the 5-tag taxonomy in reviewing-code, and
C-PROC-011 + MIT attribution.

## Operator decisions (AskUserQuestion, 2026-06-16)
- Approach: **(A) capability-map** — close gaps inside loa's architecture, no literal /ponytail* port (avoids duplicating reviewing-code / auditing-security / ride / loa-help).
- Intensity: **full + ultra only** — NO advise-only `lite` (it would soften the enforced YAGNI constraint, conflicting with loa's gated philosophy).

## Gaps closed by sprint-ponytail-parity
| # | Sev | Gap | Home |
|---|-----|-----|------|
| G1 | high | No `full`/`ultra` intensity dial | CLAUDE.loa.md + .loa.config.yaml.example + C-PROC-011 |
| G2 | high | No per-response output discipline (code-first, ≤3 lines, `[code] → skipped: X, add when Y`) | CLAUDE.loa.md + karpathy-principles.md |
| G3 | med | reviewing-code lacks `net: -N lines` metric + "Lean already. Ship." + never-flag-the-required-check | reviewing-code/SKILL.md |
| G4 | med | No whole-repo over-engineering (complexity-only) ranked scan | riding-codebase (`--with-simplicity`) |
| G5 | med | loa:shortcut harvest lumps with TODO/FIXME; no ceiling/upgrade/no-trigger ledger | riding-codebase debt ledger |
| G6 | low | Two ponytail Rules clauses absent (edge-case tie-break; deletion/fewest-files/shortest-diff) | CLAUDE.loa.md + karpathy-principles.md |
| G7 | low | No command surface for the new modes | folded into `/ride` flags (YAGNI: no new commands) |
| G8 | low | No explicit persona on/off + intensity toggle | subsumed by G1 (loa already applies Karpathy every turn) |

Host adapters (Cursor/Windsurf/Copilot rules, statusline hooks) = N/A: loa is its own host.
