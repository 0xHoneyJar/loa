# Sprint 258 — Task 1.0 toolchain readiness (recorded 2026-10-14T16:00Z by the lead)

| Item | Value | Note |
|---|---|---|
| Claude Code CLI | 2.1.299 (`claude`, via `~/.local/bin/claude-fallback`; `CLAUDE_CODE_USE_BEDROCK=1`, `AWS_REGION=us-east-1`) | executor ids `global.anthropic.claude-opus-5-5` (implementer), `global.anthropic.claude-fable-5-1` (gates); arm spend is real Bedrock dollars |
| codex CLI | 0.137.0 | cross-model dissent voice (`codex-headless`) |
| Docker | 26.1.5, daemon reachable by this user (`docker ps` ok; group `docker`) | container executor (SDD D-4.9); image built at apply time from `evals/harness/Dockerfile.ablation` |
| Unprivileged user namespaces | refused (`unshare -Urm` → Operation not permitted) | the namespace containment option is unavailable; the container is the one containment |
| Python | 3.13.5, pytest 9.0.2 | hidden tests, `ablation-report.py` (stdlib) |
| Node | 22.22.2 | Bridgebuilder dist only |
| bats | 1.13.0 at `~/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats` (not on PATH) | run under `bash -c`, never list a file twice |
| yq / jq / git | yq v4.44, jq 1.7, git 2.x | |
| Host | 8 CPUs, 30 GB RAM, 981 GB free on `/` | concurrency 3 planned for the batch |
| Pinned source for the arms | the Sprint 258 completion commit (rc.5 `4d69c3c4` + the #1267 mount fix); the plan commit is `252501b4` | `.claude/` delta vs `4d69c3c4` recorded in every manifest (DEC-0392) |
| `v2.0.0-rc.5` tag | fetched (`4d69c3c4`, not an ancestor of main) | |
| Breakers at kickoff | `google/http_api` OPEN 2415 h (pre-existing; the Google voice is not planned on any arm, `agy_opt_in` unset) | preflight P4 WARN |
| Beads | br 0.2.6; `br create --parent` fails on this DB (`no such column: last_child in table child_counters`); JSONL needs `--flush-only --force` once per burst (KF-022 recurrence 5) | tasks carry `epic:<id>` labels |
| Record branches | `origin/record/cycle-126..129-a2a` reachable | review-catch record fixtures already approved (cycle-129) |
| Cost ledger at kickoff | USD 76.44 since 2026-10-13 (cycle-129), 0 on 2026-10-15; planning Flatline ×3 to be read from the ledger at the first spend post | `evals/harness/spend.sh --since 2026-10-14T13:50:00Z` once it exists |
