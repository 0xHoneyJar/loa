# v2.0.0-rc.3 — Operator decisions (release candidate)

**Pre-release.** Third candidate of the 2.0 line. It carries everything in `v2.0.0-rc.2` plus two cycles: cycle-126 "full size" (every size decision derives from the resolved catalog entry; two review voices with nothing dropped; context discipline by context class; the current model generation everywhere; the implement gate tells the truth about its signal) and cycle-127 "operator decisions" (the three decisions the cycle-126 close left to the maintainer, taken under delegation and audited). Stable users can stay on `v1.196.0`; the 2.0 migration guide is `docs/migration/v2.0-model-generation-floor.md` (cycle-126 and cycle-127 addenda).

## What changed in cycle-127

| Area | What you get | Proof |
|---|---|---|
| The agy (Antigravity) route | **Opt-in, default off.** `hounfour.headless.agy_opt_in: true` — the YAML scalar written exactly `true`, in the project config you own — is required for the `gemini-headless` hop; off, cheval refuses a direct dispatch before any spawn (`INVALID_CONFIG`, `failure_class: opt_in_required`, never a breaker count), its chain walk plans around a gated hop inside a fallback chain, and the dissent, Flatline, Bridgebuilder, `run-preflight.sh` and `/loa` record the voice as *not planned* rather than failed. One routing predicate in bash, Python and TypeScript (`.claude/scripts/lib/agy-gate-lib.sh`, `loader.routes_to_agy`, `readAgyGate`) with one adversarial conformance table (quoted/truthy spellings, odd tags, aliases, merge keys, cwd-planted files, foreign-owned or writable configs). Why: the prompt travels on `agy`'s argv, and a host without `agy` degraded every multi-model verdict. | `tests/unit/agy-gate-conformance.bats`; the Bridgebuilder pass on #1275 ran **2/2 voices, APPROVED quality** where #1274 ran DEGRADED 2/3 on the same host |
| Claude Opus 5.5 effort | **`high` by default.** Typed `params.default_effort` in the catalog schema; cheval resolves effort once (caller > catalog > legacy `extra.effort` > none) and carries it to every hop; MODELINV records `effort_source` / `effort_effective` (adapter-derived). The vendor default `medium` had silently cost every `opus` caller a reasoning level at the cycle-126 retarget. | `cheval invoke --model opus --dry-run` → `effort: high (catalog default)`; `test_effort_wire_conformance.py` |
| Opus 5.5 input ceiling | **180,000 → 936,000**, measured 2026-10-07 through the headless CLI on Bedrock (needle-verified accepts up to 972,887 input tokens, the CLI pre-flight rejecting at the 1,000,000 window); written `operator_set` with structured provenance (`probe_outcome: partial`, `sample_size: 5`, `measured_input_tokens`). The review found and fixed a *units gap*: the bound is in provider-measured tokens while every pre-dispatch estimate under-counts the Opus 4.7+ tokenizer ≈1.4–1.8× — calibrated entries now ask the provider's free `count_tokens` from half the bound, Bridgebuilder's budget for a measured-unit calibration is (bound − 20,000) ÷ 1.8 = 508,000, and a calibration measured on a foreign transport may be tightened by a verified observation on the HTTP route. | `grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json`; `test_ceiling_calibrated_count.py`, `test_ceiling_calibration_transport.py` |
| The ceiling probe | `tools/ceiling-probe-live.py --transport claude-headless`: the adapter's own argv, needle verification, fair charging (CLI-local rejections cost nothing; 1.25× cache-write rate in the pre-flight), throttle markers win over context markers, token-limit backoff that waits out the minute, full-diagnostic classification, record kept on interrupt, process-group kill, operator strings validated and the written YAML re-parsed before it replaces the catalog, `--write-partial-as-operator-set` for a vouched partial bound. | `test_ceiling_probe_cli_transport.py` (fail-closed: the fake is the only binary) |
| Headless size verdicts | The CLI's own "Prompt is too long" / `~N tokens (limit M)` rejection is the context-limit class (not walked, no breaker count) — unless a throttle marker is present: one `is_throttle_message()` rule serves the adapter and the probe, so Bedrock's "Too many tokens, please wait" is a rate limit (retried, then walked). | `test_claude_headless_context_limit.py` + the probe/adapter conformance test |

## What you may notice after upgrading

- **A Google voice that used to fail now does not run.** On a host without `agy` (or with the opt-in off) the dissent, Flatline and Bridgebuilder plan two voices and report full quality; `/loa` Providers says `google · agy: opt-in (disabled; hounfour.headless.agy_opt_in)`. Opt in only where `agy` is installed and OAuth-authed, knowing the argv exposure.
- **Your opt-in "does not take".** Only the scalar `true` opts in; a quoted `"true"`, `yes`/`on`/`True`, an alias or a merge key reads off with one WARN naming the key. A config you do not own, that others can write, or that a group other than your user-private group can write is ignored with one WARN — a umask-002 checkout on an Ubuntu user-private-group host still opts in; on a shared-group host `chmod 644 .loa.config.yaml`.
- **`opus` thinks harder.** `--effort` overrides per call; the catalog's `params.default_effort` per entry.
- **Larger prompts reach Opus 5.5.** Up to 936,000 provider-measured tokens on the HTTP route with an exact count above half the bound; Bridgebuilder's generated budget for the entry is 508,000 estimated tokens (from 160,000). On the headless route the CLI's own pre-flight is the backstop.
- **The probe tool refuses odd operator strings** (`--host-route`, `--cli-model`, a CLI version with control characters) before it spends anything.

Migration guide: `docs/migration/v2.0-model-generation-floor.md` (cycle-126 and cycle-127 addenda). Decisions: `grimoires/loa/sdd.md` (cycle-127, archived with the cycle) and NOTES § Decision Log 2026-10-07.

## Breaking

One configuration key is added: `hounfour.headless.agy_opt_in` (default `false`). Hosts that relied on the `gemini-headless` hop must set it `true` — the route is otherwise *not planned* (not failed). No key is removed or renamed. Every rc.1/rc.2 switch keeps its meaning.

## Operator steps

1. Merge PR #1275 (title keeps `cycle-127`); the pipeline prepares `v2.0.0-rc.3` with `prerelease: true` (the `[2.0.0-rc.3]` heading is already in place).
2. Inspect the candidate per `grimoires/loa/runbooks/post-merge-candidates.md`, publish with `--publish … --approve-sha256`, confirm **Pre-release** on GitHub.
3. `gh release edit v2.0.0-rc.3 --prerelease --notes-file grimoires/loa/reports/release-notes-2.0.0-rc.3.md`.

## Soak and exit criteria

Unchanged from rc.1 (`grimoires/loa/reports/release-notes-2.0.0-rc.1.md`): two weeks minimum, ≥ 2 downstream mounts through the migration guide, no CRITICAL/HIGH rc issue open for 14 consecutive days, a recorded `live-floor-check.yml` pass, then the `## [2.0.0]` promotion. Open follow-ups: bd-c2rd (estimator calibration), bd-n6lk (Bedrock adapter effort), bd-y49y (payload-schema drift), bd-rbkz (probe refactor), bd-ugmi (agy stdin transport re-probe; base-ref config on PR review).
