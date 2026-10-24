# Security analysis working file — cycle-133 Sprint 273 (global 273) audit, 2026-10-24

Scope: `git diff eb029df47 c3b059cf3` restricted to code: `evals/harness/lib/{session-exec,batch-supervisor,egress-proxy}.sh`, `blind-session.sh`, `pipeline-run.sh`, `run-ablation.sh`, `ablation-grade.sh` 1.4.0, `ablation-row.sh` 1.6, `spend.sh`, `Dockerfile.{proxy,ablation}`, `evals/analysis/c132/{reproduce.sh,record_lite.py,judge_defects.py,tests/synth.py}`, the two drivers under `reports/review-catch-c132/scripts/`, `.claude/defaults/model-config.yaml` (`egress_hosts[]`) + lockfile, `.claude/data/schemas/model-config-v3.schema.json`, `evals/suites/ablation-2.0.yaml`, `tools/check-no-swallowed-jq.sh`; the operational artefacts (the pin `50881e6f4`, the self-check, the egress suite run, the extracted D2 patch).

## Recon — untrusted sources (trust level)

| # | Source | Trust | Reaches |
|---|---|---|---|
| S1 | session transcripts (`events.jsonl`) written by the model CLI in the sandbox | UNTRUSTED (model + CLI) | the python meter (`price_events`, `unmetered_tail`) → cost.json, the spend row, the watchdog decision |
| S2 | the model-config pricing table / `LOA_EVAL_PRICING_JSON` | operator config | `price_for` (ERR on null/negative/non-finite) |
| S3 | the sandbox's environment at exec (`PASS_KEYS`, `SECRET_KEYS`) | operator environment; secrets | `ENV_SHIM` (keeps exactly the named keys; closes every fd > 2) |
| S4 | `MANIFEST.json`, `STATUS.json`, `supervisor/{state,args}.json`, `.jobs/*.pgid` | runner-written state | the supervisor's resume argv, kill targets, retry accounting |
| S5 | `docker ps` names, `docker network inspect` output | docker daemon | `stop_containers` (exact prefix), the egress pre-flight |
| S6 | `providers.<p>.egress_hosts[]` in model-config.yaml; the allowlist file | operator config (System Zone, lockfile-pinned) | tinyproxy filter; `HOST_RE` refusal |
| S7 | DNS answers for allowlisted names; redirect targets; CONNECT host:port from the sandbox | UNTRUSTED network / sandbox agent | tinyproxy filter + the sidecar's netfilter after resolution |
| S8 | `registration.txt` parsed by the drivers; `--manifest`/flags | tracked file / operator | whitelist parse (shell code refused), `BASH_SOURCE` roots |
| S9 | the record's `sandbox-manifest.json` symlink targets, lite files, `pr/` files | record (public branch) | `record_lite.py` verify-path hashing; unsafe target → Mismatch |
| S10 | judge `labels.json` (model output), packets | UNTRUSTED model text | `judge_defects.py` sample_id binding; grade-loaded validity |
| S11 | `runs.jsonl` rows (incl. `metering`, `cap_usd`) | runner-written | `spend.sh` totals (unmetered rows charged at the cap) |
| S12 | grader inputs: agent transcripts with heredocs and `/home` probes | UNTRUSTED agent text | the two 1.4.0 exemption shapes (guards: PR-native token, no network line, no unquoted substitution; `findmnt`/`df`/`mountpoint` only) |

## Recon — dangerous sinks

| # | Sink | Guard |
|---|---|---|
| K1 | the budget gate / spend totals | fail-closed pricing (`ERR` → refuse or stop); an unmetered attempt charged at the cap (round 2); `spend.sh` dedup by `(run_id, batch)` |
| K2 | `kill` of process groups by the supervisor | boot id first (stale state after a reboot is removed, nothing signalled); start ticks for the runner pid; `.jobs` groups on the same boot only |
| K3 | `docker rm -f` by the supervisor | docker name filter AND an exact `loa-abl-<batch>-` prefix check |
| K4 | the `systemd-run` unit environment (visible in `systemctl show`) | PATH, HOME and `LOA_*`/`EVAL_*` names not matching KEY/TOKEN/SECRET/PASSWORD/CREDENTIAL — env-borne model credentials are therefore absent (functional gap documented; bd-vcc5s) |
| K5 | sandbox egress | `--internal` network, `--dns 0.0.0.1`, proxy variables, tinyproxy exact-hostname allowlist, `ConnectPort 443`, netfilter after resolution (private/loopback/link-local/CGNAT/reserved rejected, tcp 443 to public IPv4 only, IPv6 dropped), the image's unresolvable proxy default; the runner refuses a container batch with a blocked arm without a live block (the bats escape needs two conditions) |
| K6 | the exec'd model CLI's environment and descriptors | `ENV_SHIM` keeps exactly `PASS_KEYS`; secrets travel by name only (`<set>` in captures); `assert_secret_keys` before any write |
| K7 | the relaunch under `rerun-once` (paid) | one immutable hard-linked record; the 3-attempt limit; the full per-run cap once more (worst-case overshoot one cap per refused in-flight trial, documented) |
| K8 | the live sample in `reproduce.sh` (paid) | gated on engine rc 0 AND a matched environment; no `--live-anyway` |
| K9 | file writes by the drivers | roots from `BASH_SOURCE`; `registration.txt` whitelist; `REG_SHA` check |
| K10 | the record branch (public) | untouched this sprint; `record_lite.py` never writes into `evals/results` |
| K11 | `model-config.yaml` (System Zone) | lockfile checksum + v3 schema (now admits `egress_hosts`), `check-knob-readers`, checksums.json |

## Investigate pass — results

- S1→K1: every parse failure, unknown model, null/negative/non-finite price, invalid token, usage-less completed turn → `ERR` → refuse before launch / stop with `metering_incomplete`; an attempt with activity but no usage → failure charged at the cap (round 2). Zero prices pass. 1,565 real transcripts agree with the old meter byte for byte. OK.
- S3→K6: `ENV_SHIM` builds the child environment from `PASS_KEYS` only, closes every descriptor above 2 except `LOA_KEEP_FDS` (strictly parsed), falls back to `closerange(3, hard)` split around kept fds; a key-shaped pass-through not in `SECRET_KEYS` refuses. Residual: `SECRET_KEY_PATTERN` covers KEY/TOKEN/SECRET/PASSWORD/PASS/CREDENTIAL/AUTH — `PASS_KEYS` today holds only region/profile/model names plus the Bedrock bearer token (listed). OK.
- S4→K2: `reclaim` compares the boot id before anything; `ident_alive` compares `/proc` start ticks before `kill_group` on the runner pid; `.jobs/*.pgid` groups are killed on the same boot without ticks (LOW, bd-sf7uf). A reboot removes stale `.lock/.jobs` and signals nothing. OK.
- S5→K3: `docker ps --filter name=^prefix` then `[[ "$n" == "$prefix"* ]]` — `b1` cannot remove `b10`'s containers. OK.
- K4: the scrub is correct for a visible unit environment; the consequence (no env-borne credentials under systemd mode) is undocumented → MEDIUM observation, bead bd-vcc5s; this host runs setsid mode. The smoke (Sprint 274) runs on this host.
- S6/S7→K5: `HOST_RE` admits lower-case hostnames only (no wildcards, no IP literals, ≤ 200 entries); tinyproxy `FilterDefaultDeny` + `FilterType fnmatch` over exact names; `ConnectPort 443`; the netfilter rules reject every private/loopback/link-local/metadata/CGNAT/reserved IPv4 after resolution and drop IPv6 — DNS rebinding, direct IPs in every spelling, the host gateway, external DNS, plain HTTP and a misconfigured proxy all fail in EGR-1 … 12 (20/20 on this host) and the pin's self-check (49/49). The proxy never terminates TLS (no private CA). The `--test-allow-addr/--test-add-host` escape needs `LOA_EGRESS_TEST_MODE=1` AND bats. Residual (LOW): whether the model CLI honours `HTTPS_PROXY` is irrelevant to enforcement — the internal network has no route out; the variable only makes the allowed path work.
- S8→K9: the whitelist parse refuses shell code and unknown tokens (five refusal cases, nothing executed); roots from `BASH_SOURCE`; the red run that escaped the worktree (B's incident) is exactly the class now closed (DEC-0894).
- S9: verify-path hashing bypasses the cache; an unsafe symlink target is a Mismatch, never dropped (the grader counts `pr/` symlinks). OK.
- S10: labels without the key's `sample_id` are refused; `aggregate --results-root` required; validity decided with grades loaded. OK.
- S11→K1: unmetered rows charged `max(cost, cap_usd)` and counted separately; anonymous rows (no run_id) deduplicated by content across files — identical anonymous rows carry timestamps, so a legitimate multiplicity has no producer (DISS-002 demoted). OK.
- S12: the two exemptions are narrow (report writes to `.md/.markdown/.txt` by `cat`/`tee` with a PR-native token and no network line or unquoted substitution; `findmnt`/`df`/`mountpoint /home` only); 396 pairs and 517 directories differ only in the intended cells. OK.
- K7: the record is written once (hard link; a failed link logs and does not relaunch); the limit of 3 attempts; the overshoot bound documented in the README. OK.
- K11: `model-config.yaml` edits need the lockfile bump and a schema that admits the key — both done in `fb54d7947` after CI caught them (the lesson is in the Sprint 3 conventions).
- Secrets in the branch: the Sprint 272 `detect-secrets` pass covered the branch; this sprint adds no credential literal (the egress tests use a local stub; the self-check uses CONNECT probes only). The pin's self-check log names hosts and status codes, no credential.
