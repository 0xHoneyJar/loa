## Bridgebuilder round 2 — lead triage (head 3215c141f, `--force-full-review`)

Round 2 (`BRIDGEBUILDER_MODEL=codex-headless`, same exclusions, full review): the openai voice (gpt-5.5-pro) completed, the anthropic/claude-headless voice failed again with `PROVIDER_UNAVAILABLE` (`claude -p` timeout while three unrelated shells hold ~3 cores on the host) → verdict COMMENT, **degraded 1/2** for the second time. The sprint plan's degraded exit applies (no blocking finding open → class S, DEC-1139); KF-037 recurrence recorded with this run as evidence.

| Finding | Disposition | Evidence |
|---|---|---|
| R-001 MEDIUM `loa-kf-surface.sh:103` — byte cap under `LC_ALL=C` vs the former character cap on BSD `cut -c` | **Confirmed on BSD hosts, pre-existing since Sprint 281, waived → bd-aceil** | Sprint 281 audit MED-001 (DEC-1123) names exactly this: on GNU `cut -c` is byte-based so Linux output is byte-identical (proven by the pass's golden check); on macOS the cap changes from characters to bytes and can split a multibyte symptom — bd-aceil ("decide the byte-cap contract on BSD hosts; verify under BWK awk / BSD cut") carries it; the SessionStart surface is advisory text, not a parsed value |
| R-002 LOW `profile-lib.sh:256` — a literal `__LOA_PL_ABSENT__` config string collides with the sentinel | **Confirmed, pre-existing class, waived → bd-y5fy4** | Sprint 282 review observation 3 and audit recommendation: the `__LOA_PL_MISS__` / `__LOA_PL_STALE__` sentinels predate this cycle; FR-4 added a third; bd-y5fy4 tags the result as JSON (`{kind, value}`) and covers the literal strings in the warm-vs-live matrix |
| R-003 PRAISE `test_audit_verify_chains.py:205` — independent mutation oracles | Acknowledged | kept (DEC-1128/1129) |

No blocking finding is open after two rounds; the merge proceeds on 3215c141f with every check run green.
