# Security analysis working file — sprint-1 audit (task review-r24), 2026-10-21

Scope: `pr/head.diff` (17 files). Trust model: the agent under evaluation (Claude Code inside the
container) is UNTRUSTED; its transcripts (`transcripts/events-*.jsonl` tool_use inputs) and its
sandbox tree are attacker-controlled data that the grader and runner read. The operator, the
suite files, MANIFEST.json/STATUS.json and the rows file are trusted state.

## Sources (untrusted entry points)

| # | Source | Trust | Reaches | Status |
|---|--------|-------|---------|--------|
| S1 | Bash `command` / Read / Grep / Glob / Write fields in `transcripts/events-*.jsonl` | untrusted (agent) | `check_value` regexes (`ablation-grade.sh:1395-1455`), `strip_heredocs` (`:1380-1383`) | CONFIRMED — ReDoS in HEREDOC; evasion of outside_path/hidden via stripping, quote parity, `/.`, home prefix |
| S2 | `meta/pipeline.json` | harness-written (pipeline-run.sh) | `drift_check`, `final_status`, `is_pipeline_transport_failure` | SAFE (jq/python readers; label regex-gated) |
| S3 | `transcripts/stderr-<label>.log` | CLI stderr (agent cannot write) | `ARMS_TRANSPORT_RE` grep | SAFE (documented boundary; label `^[A-Z][A-Z0-9]{0,15}$`) |
| S4 | CLI args of run-ablation.sh | operator | path construction, jq --arg | SAFE (regex validation at `:307-351`) |
| S5 | MANIFEST.json / STATUS.json on --resume | trusted state (self-written) | SUITE_ROOT, SUITE_FILE, ROWS, IMAGE, RUN_CAP | SAFE — IMAGE/RUN_CAP not re-validated but self-written |
| S6 | runs.jsonl rows / MANIFEST.json dirs for ablation-report.py | trusted state | json.loads; schema checks | SAFE (type checks; symlink refusal) |
| S7 | suite YAML | trusted | `yq -o=json` via subprocess list | SAFE |

## Sinks

| # | Sink | Status |
|---|------|--------|
| K1 | `HEREDOC.sub` regex with nested quantifier under re.S (`ablation-grade.sh:1377`) | CONFIRMED CWE-1333 — exponential on unterminated heredoc; no timeout around `contamination()`; runner grade step has no timeout (`run-ablation.sh:996`), `.pgid` removed before grading (`:1031`) so the watchdog never covers it |
| K2 | `kill -TERM -- "-$p"` from `.pgid` files (`run-ablation.sh:933-942`) | SAFE (self-written pids), but `.jobs/` removed before groups are confirmed dead → duplicate-launch guard bypass on resume (MEDIUM) |
| K3 | `cat "$rowf" >> "$ROWS"` under flock (`:1069-1074`) | SAFE |
| K4 | `write_out` (`ablation-report.py:1052-1059`) | SAFE (islink check; TOCTOU accepted) |
| K5 | `setsid nohup "$SCRIPT_DIR/run-ablation.sh" "${child[@]}"` (`:388`) | SAFE (own args) |
| K6 | `git worktree add --detach "$TREE" "$SRC_FULL"` (`:636`) | SAFE (SRC_FULL = rev-parse output) |
| K7 | `"$DOCKER_BIN" run --rm --network none "$IMAGE" claude --version` (`:651`) | SAFE (IMAGE regex) |

## Deferred / scope limits
- `pipeline-run.sh`, `freeze.sh`, `took-effect.sh`, `seed-corpus-from-record.sh`, `spend.sh`, `fingerprint.sh` are outside the diff; their contracts are taken from the headers.
- `run-ablation.bats`, `ablation-grade.bats`, `ablation-row.bats` cannot run here (collaborators and the frozen suite absent); verified by reading. The grader contamination functions were extracted and executed directly (`/tmp/audit-harness/`).
