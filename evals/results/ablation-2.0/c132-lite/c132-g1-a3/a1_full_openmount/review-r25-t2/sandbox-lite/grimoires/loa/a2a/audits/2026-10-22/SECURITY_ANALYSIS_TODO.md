# Security analysis working file — sprint-1 audit (PR in pr/, 2026-10-22)

Scope: `pr/head.diff` (12 files, +719/-164). `security-audit-scope.sh --json` over `pr/head/` found 0 sources / 0 sinks / 0 auth files (its heuristics target web apps; the change is a bash + embedded-Python eval harness), so the recon below is manual.

## Sources (untrusted or semi-trusted entry points)

| # | Source | Trust | Reaches | Status |
|---|--------|-------|---------|--------|
| S1 | `$CREDS_HOME/.codex/auth.json` (operator's host file) | operator-owned, read by `make_home` (pipeline-run.sh:627-642) and the pre-flight (run-ablation.sh:810-826) | JSON parse → per-run copy / exp comparison | SAFE (paths only in argv, `python3 -I`, no token value printed); residual: access_token still mounted into the agent container (pre-existing) — see feedback Observations |
| S2 | JWT payload of `tokens.access_token` (unsigned, decoded base64url) | semi-trusted (operator file) | `exp` → `int()`, `time.gmtime()` (run-ablation.sh:829-830) | PARTIAL — out-of-range exp crashes the pre-flight generically (LOW) |
| S3 | suite file `caps.run_usd_by_type` (evals/suites/ablation-2.0.yaml:37) | repo-controlled | `suite_kind_cap` (run-ablation.sh:500-507) → `--max-run-usd`, spend charges | PARTIAL — `//` swallows false/null; zero accepted (LOW ×2) |
| S4 | MANIFEST.json `caps.*` on `--resume` (run-ablation.sh:449-452) | harness-written | caps | SAFE (usd_ok checked) |
| S5 | agent sandbox tree (untrusted, copied to `grading/final`) | untrusted | `remove_colliding` walk + `os.unlink` (ablation-grade.sh:1090-1099), `.colliding-removed.txt` write (1100-1101) | CONFIRMED defect (over-broad deletion, HIGH); unlink confined to the grading copy, `followlinks=False`, symlinks unlinked not followed |
| S6 | `--types` CSV (run-ablation.sh:565) | operator | jq select | SAFE (fix verified) |
| S7 | `--run-cap`, `--concurrency` | operator | caps / horizon divisor | SAFE (validated 361, 366) |

## Sinks

| # | Sink | Guard | Status |
|---|------|-------|--------|
| K1 | `os.open(dst, O_WRONLY|O_CREAT|O_TRUNC, 0o600)` + `json.dump` (pipeline-run.sh:637-641) | fresh per-run HOME, 0700; `rm -f` on failure | SAFE |
| K2 | `os.unlink(p)` in the grading copy (ablation-grade.sh:1098-1099) | only files found under `tree`; never the sandbox (AG-35 asserts) | SAFE as a sink; the selection rule is the defect |
| K3 | `refuse "$CODEX_REFUSE"` → REFUSED.txt (run-ablation.sh:840) | message carries ISO times and the auth.json path only | SAFE (host path disclosure is informational) |
| K4 | `pipeline-run.sh --max-run-usd <cap>` (run-ablation.sh:1186) | `cap_for` from validated caps | SAFE |
| K5 | MANIFEST.json `codex_preflight` / `codex_token_exp` (run-ablation.sh:903) | exp only, no token material | SAFE (duplicate field, LOW) |

## Deferred / unable to assess

- bats suites cannot run here: `evals/` is not present in `/workspace`, the v2 task directories and `seed-*.sh` are outside `pr/`.
- codex CLI refresh policy (does it refresh on `last_refresh` age?) — not verifiable offline; recorded as a low-confidence MEDIUM.
