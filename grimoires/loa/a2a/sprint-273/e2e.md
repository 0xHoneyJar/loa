# Sprint 273 — Task 2.E2E: End-to-End Goal Validation

Scope (sprint.md Task 2.E2E): G-8 parts — pricing sentinel bats, descriptor bats, egress denial bats or quarantine row, supervisor bats, grader 1.4 fixtures, policy row fields — and G-1 (bead closures), each against the evidence path the PRD names. Validated by the lead on the integrated cycle branch at the Sprint 273 pin `50881e6f4`, 2026-10-24.

| Goal part | PRD measure | Evidence path | Result |
|---|---|---|---|
| G-8 fail-closed pricing | `price_for`/`price_events` print `ERR` and return non-zero on every C-6 condition; zero prices pass | `evals/tests/session-exec.bats` SE-2 … 5, SE-8 … 10, SE-15 (18 of 25 red first); `blind-session.bats` BS-12 (refuses to launch, no CLI call, no out dir, no row); `pipeline-run.bats` PR-c133-2 … 5 | PASS (214/214 with ablation-grade on the integrated tree) |
| G-8 descriptor close to the limit | a descriptor above 65535 and above a lowered soft limit closed in the child | SE-17 … 22 (SE-20 fd 70000 inside `loa-ablation:258 --ulimit nofile=200000`; SE-22 simulated fallbacks) | PASS |
| G-8 egress blocked at the container | container bats: allowlisted succeeds; github.com, raw, gitlab, direct IP, IPv6, redirect, CONNECT port, external DNS, host gateway, DNS rebinding, misconfigured proxy fail; denials attributed — or a dated quarantine row | `evals/tests/egress-proxy.bats` EGR-1 … 12 on this host: `~/.cache/loa/cycle-133/tests/s2d2-egress-bats.log` 20/20; `grimoires/loa/reports/ablation-2.0/self-check-c133.txt` 49/49; no quarantine row | PASS (real suite, no quarantine) |
| G-8 restartable batches | supervisor bats incl. lock, orphan reconciliation, atomic rows | `evals/tests/batch-supervisor.bats` BSV-1 … 13 (BSV-13 end to end: SIGKILLed driver, one resume, every run id rowed once) | PASS |
| G-8 grader 1.4 | the two shapes re-graded benign; every other 1.3.8 fixture identical | `evals/tests/ablation-grade.bats` AG-c133-1 … 5; `evals/tests/fixtures/grader-1.4/regress.sh` (396 pairs, 12 differ = the new tests); the 517-directory re-grade (two intended cells) | PASS |
| G-8 refusal policy registered | policy recorded before execution; `refusal_policy_applied` and `attempt` on every row | `evals/tests/refusal-policy.bats` RP-R1 (MANIFEST before execution), RP-1, RP-2, RP-R2; `evals/harness/ablation-row.sh:800` | PASS |
| G-1 bead closures | every Sprint 2 bead closed with the commit and test named | `br show`: bd-9ioz6 bd-wqaj4 bd-g2c5i bd-rz0wh bd-jat0z bd-161zz bd-ombvn bd-xr3uq bd-o3a5h bd-qxwrm bd-um8ol bd-bupym bd-r9abp bd-yvjew bd-ijxuk bd-vpc6b (16 closed); bd-kddde stays open for shapes 3–6 (recorded) | PASS |

CI: "Shell Tests" green on the A+B+C head `0a983650b` (run 40066562822); the run on the D3+D2+pin head follows the push of `50881e6f4` and is recorded in the review. Not in Sprint 2's E2E scope: the seeder dry-run (G-8 last part, Sprint 274), G-4 … G-7.
