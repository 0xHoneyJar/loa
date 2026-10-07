# Sprint 251 — audit dissent run 1 — verifier F (findings n31–n60)

Verifier: Opus 5.5, read-only. Judged against HEAD `58f87195` (r251-3). Audited diff `6f6cc8a6..d12bdfab`.
Probe: `write_catalog_operator_set` run on a temp copy of the live catalog (`/tmp/tmp.e7hhCffgPm`), output re-loaded with `yaml.safe_load`. No model calls, no live probe.

Probe result (n52):

```
host_route="x\n        effective_input_ceiling: 1", cli_model="opus"       -> loaded effective_input_ceiling = "1, opus); see ceiling_calibration.reprobe_trigger."
host_route="bedrock", cli_model="opus\n        effective_input_ceiling: 1" -> loaded effective_input_ceiling = "1); see ceiling_calibration.reprobe_trigger."
host_route="x # y: z", cli_model='op"us', cli_version='2.1 "x"\n: y'    -> effective_input_ceiling 900000 (safe: single-line `#`/`:`/quotes stay inside the comment; cli_version is json.dumps-quoted)
```

No `yaml.safe_load` / schema check runs after the write (`tools/ceiling-probe-live.py` has none).

| n | sev claimed | verdict | sev assigned | evidence | fix shape |
|---|---|---|---|---|---|
| 31 | LOW | REAL (test hygiene) | LOW | `tests/test_effort_catalog_default.py:176-183` deny-lists three names; PATH keeps a real `claude`, so a regressed `--dry-run` that walks to the headless hop would spawn it with host creds | set `CLAUDE_HEADLESS_BIN` to a non-existent sentinel and a minimal PATH in `_dry` |
| 32 | LOW | DECLINED (pre-existing pattern) | LOW | identity-patching `redact_payload_strings` is the repo's MODELINV-capture idiom (20 test files); effort fields are not under `_REDACT_FIELDS` (`loa_cheval/audit/modelinv.py:213-220`), so the real redactor is identity for them | — |
| 33 | MEDIUM | DECLINED (recorded decision D-3.10 + C1) | — | nothing new beyond the decision: entry is `transport: claude-headless` (`model-config.yaml:509`) → `is_foreign_transport_calibration` lets HTTP observations tighten it (`routing/ceiling.py:116-124,164`); count_tokens from 0.5×bound (`:522,577-585`); no beta header is needed (vendor 1M at standard pricing, catalog comment `:476-478`); `probe_outcome: partial` is visible | — |
| 34 | LOW | REFUTED | — | runtime guard exists: invalid `params.default_effort` WARNs and is ignored, never reaches the wire (`cheval.py:963-984`); tested `tests/test_effort_catalog_default.py:117-128` (`ultra`, `HIGH`, 3, True, list, None) | — |
| 35 | LOW | REAL (schema hardening) | LOW | `ceilingCalibration` has no if/then; `probe_outcome` optional (`model-config-v3.schema.json:308-311`); writer enforces partial⇒operator_set (`ceiling-probe-live.py:524-528`) and caps cli_version at 120 chars (`:268`) | if/then: `method: probed_headless` ⇒ `transport: claude-headless` and `probe_outcome` required; `maxLength` on cli_* |
| 36 | LOW | DECLINED | LOW | placeholder creds only (`test_effort_wire_conformance.py:65-68`); an uncaptured transport `pytest.fail`s (`:77-86`); streaming disabled by env | optional socket guard |
| 37 | MEDIUM | DECLINED (documented C7 trade-off) | LOW | `warn` path `ceiling.py:592-596`; cheval is a local operator CLI, not an exposed service; the provider enforces the real limit; a 400/413 context-limit is typed non-walkable and recorded as an observation that tightens the next call (`cheval.py:2236-2241`, `anthropic_adapter.py:370-374`) — risk is one rejected upload | — |
| 38 | MEDIUM | PARTLY REAL | LOW | envelope claim REFUTED: `as_envelope` carries `basis`, `calibrated`, `observed`, `calibration_transport` (`ceiling.py:494-502`). Writer is cheval only, from HTTP 400/413 context-limit text; CLI hops are never recorded (`cheval.py:2234-2241`, r251-2 K8). Lock is symlink/owner/inode-checked (`ceiling.py:369-389`); data file is not owner-checked, but a writer to `.run/` can equally edit `.loa.config.yaml`. Direction is fail-closed only (tighten → preempt), never a bypass. REAL residue: no plausibility floor, `observed=1` wedges the route (`ceiling.py:164`) | in `observed_for`/`input_bound`, ignore observations below a floor (e.g. < 0.1×context_window) and above context_window |
| 39 | LOW | REFUTED | — | `parse_context_limit` runs only behind `is_context_limit_message` and not-throttle (`claude_headless_adapter.py:562-570`; HTTP: status 400/413 + marker); the CLI hop's verdict is not persisted (`cheval.py:2236`) | — |
| 40 | LOW | REAL (DOC/nit) | LOW | committed `grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json` has `/home/merlin/...` twice (`cli_bin`, `argv[0]`); no credentials, no ARNs, no key shapes (grep 0) | record `~`-relative path |
| 41 | LOW | DECLINED (dup n37) | LOW | same `warn` path; the ratio-scaled preempt is a reasonable future refinement, not a defect | — |
| 42 | MEDIUM | REFUTED | — | same as n39: HTTP-only persistence, marker-gated; "only tightens" is the design | (floor: see n38) |
| 43 | LOW | REAL | LOW | `_cli_bin()` returns bare `"claude"` (`ceiling-probe-live.py:233-234`) and it is recorded verbatim (`:1072,1075`) | record `shutil.which(cli_bin)` |
| 44 | LOW | DECLINED | — | PATH emptied and bin asserted to be the fake (`test_ceiling_probe_cli_transport.py:253-255`) | — |
| 45 | LOW | REAL (dup n52) | LOW | cli_version part REFUTED: first line, `[:120]`, json.dumps-quoted (`:268,574`). host_route/cli_model newline injection REAL (probe above) | see n52 |
| 46 | LOW | REAL (nit) | LOW | raw `os.kill(p, 9)` on PIDs read from a pidfile (`test_ceiling_probe_cli_transport.py:912-917`); reuse window is seconds | check `/proc/<pid>/cmdline` holds the script before killing |
| 47 | MEDIUM | REAL (dup n52) | LOW | `--host-route` and `--cli-model` flow raw into the provenance comment | see n52 |
| 48 | LOW | REAL (dup n35) | LOW | `probe_outcome` optional in schema | see n35 |
| 49 | LOW | DECLINED (DOC) | LOW | `detail` capped at 300 chars (`:303`); live record has `error: null`, `interrupted: null`; the operator reviews a record before committing it | — |
| 50 | LOW | REFUTED | — | module-scoped autouse `_no_real_cli` points `CLAUDE_HEADLESS_BIN` at a non-existent sentinel (`test_ceiling_probe_cli_transport.py:115-123`); test asserts it (`:976,986`) | — |
| 51 | MEDIUM | DECLINED (same trust model, pre-existing) | — | the adapter already runs the env-selected `CLAUDE_HEADLESS_BIN` with the full environment (`claude_headless_adapter.py:211,279`); the Bedrock wrapper route needs the AWS credentials; whoever sets the env already holds them | — |
| 52 | MEDIUM | REAL | LOW (must-fix: silent corruption of a tracked default, cheap) | provenance comment interpolates `route` (= host_route unless it names bedrock) and `cli_model` raw (`ceiling-probe-live.py:553,585-587`); a newline overrides `effective_input_ceiling` in the loaded YAML (probe above); `cli_model` on the real write is `_resolved_cli_model`, so ambient `ANTHROPIC_DEFAULT_OPUS_MODEL` also feeds it (`:243-245,1100`); no post-write re-parse. REFUTED parts: `calibrated_at` is internal (`started_at` / record now, `:844,1052`), `transport` is never caller-supplied, no code reads a record file back | in `_main_cli`, before the dry run, refuse host_route / cli_model (resolved) / cli_version containing any control char (`\r`, `\n`, `\x00`-`\x1f`) or over 200 chars (exit 2, nothing spent); in the writer, `yaml.safe_load` the result and assert the model block's ceilings equal `written` before returning; test with a newline host route |
| 53 | LOW | REFUTED | — | wait clamped `min(wait, _RETRY_WAIT_CAP_S − waited)` (`:810`), so inf → cap; `retry_after_s` is dropped from the sample (`:977-979`) | — |
| 54 | LOW | DECLINED (dup n51) | — | trust model as n51; provenance part is n43 | see n43 |
| 55 | MEDIUM | REFUTED | — | `_route_env` is a 3-key allowlist, the Bedrock switch recorded as presence only (`:255-259`); argv carries no credential (`build_headless_argv`); committed record: region, prefix, `true` | — |
| 56 | LOW | REAL (robustness; trusted source) | LOW | `json.loads` accepts `Infinity` (verified); `int(inf*1e6)` raises OverflowError in `_charge` (`:781-782`), which runs outside the attempt try (`:965`) — the paid attempt goes uncharged and the outer handler (`:1026`) ends the run. TypeError part REFUTED: `_measured` sums ints only (`:275-281`) | `math.isfinite` and `0 <= x <` sane cap in `_classify_unguarded` before storing cost |
| 57 | LOW | REAL (dup n52) | LOW | dry run passes `cli_model=cli_arg`, no `cli_version` (`:853-855`); real write passes `record["cli_model"]` (resolved) and `cli_version` (`:1100`) | fold into the n52 fix: validate the resolved values and dry-run with the same kwargs |
| 58 | LOW | REAL | LOW | first step `ratio is None` → `est_micro` from filler × 1.0 (`:914-920`) while the tokenizer measures ≈1.8×; the pre-flight worst-case line is understated the same way (`:869-876`). Live run did not overshoot ($19.10 estimate on a $20 cap, $12.74 CLI-reported) | use a prior of 1.8 for the estimate only until a step measures; say so in the pre-flight line |
| 59 | LOW | DECLINED (pre-existing, documented) | — | agy argv exposure predates this sprint; this sprint makes the route default-off | — |
| 60 | LOW | DECLINED (pre-existing design, out of scope) | — | every dissent key is read from the project tree; the opt-in is project-config-only by recorded decision; worth a bead for base-ref config on PR review | bead, not this sprint |

## Must-fix

1. **n52 (with n45, n47, n57).** Newline injection into the catalog through `--host-route` / `--cli-model` / `ANTHROPIC_DEFAULT_OPUS_MODEL`. Fix shape: reject control characters and over-long values in `_main_cli` before the dry run, dry-run with the resolved kwargs, re-parse the written text and assert the ceilings before `os.replace`.

## Should-fix (cheap, non-blocking)

- n56 finite-number guard on CLI-reported cost.
- n58 1.8 prior for the first step's budget estimate.
- n38 plausibility floor on observations.
- n43 / n40 record the resolved binary path, `~`-relative.
- n35 / n48 schema if/then for `probed_headless`.
- n31 sentinel `CLAUDE_HEADLESS_BIN` in `_dry`; n46 cmdline check before kill.

r251-3 changed none of the code in these findings. It touched only the throttle rule, which n39 and n42 rely on: the CLI-shape parse sits behind `is_context_limit_message` and not-throttle.
