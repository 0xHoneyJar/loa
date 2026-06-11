# Pre-OSS-Release Issue Triage — 2026-06-10

Full-tracker triage of all open issues against the **named open-source release** goal,
run via 15-cluster adversarial workflow (every closure verdict independently
re-verified against main @ `e1d27388`). Operator: @janitooor / deep-name.

**Result: 57 open → 48 open.** 9 closed with evidence (#988 #875 #866 #868 #935 #889
resolved; #975 #872 #987 stale/duplicate/hygiene), 1 new filed (#992 secret-scanning
misconfig). 27 issues classified FIX-THIS-WAVE, bundled below into PR-sized units.

## Wave bundles (recommended execution order)

### A — CI green (the release gate)
| Item | Size | What |
|---|---|---|
| #886 | S | bats-tests.yml pip-install step (rfc8785, jsonschema, ruamel.yaml, cryptography) — kills ~22 of the 68 main-red bats failures in one PR. **Do first.** |
| #953 | M | Canonical CI-green tracker: after #886, fix-or-quarantine the ~46 residual failures cluster-by-cluster (license/registry ~16 incl. 7 spec-vs-impl product decisions, release-notes ×5, T3.3 BB fetch-gate ×5, simstim timeouts ×3, singles), then flip Shell Tests to a required check. |
| #992 | S | secret-scanning.yml: drop TruffleHog `base`/`head` inputs on push/schedule — workflow is permanently red AND scan coverage on main is silently zero. |

### B — Kernel & hook integrity (pairs naturally into one PR)
| Item | Size | What |
|---|---|---|
| #989 | S | Wire `marker-utils.sh update-hash`/`verify-hash` to CLAUDE.loa.md (machinery exists, never wired); re-stamp header off `1.94.0`/`PLACEHOLDER`. |
| #991 | S | pre-commit beads hook: run flush from `MAIN_REPO_ROOT` in linked worktrees (KF-014 → RESOLVED on merge). |

### C — Install/update paths (public first-run credibility)
| Item | Size | What |
|---|---|---|
| #986 | S | post-merge.yml fails for every submodule-mount consumer; reporter supplies CI-verified `--reconcile` fix. |
| #968 | M | Extract #842 COPY phase into shared refresh fn used by `--reconcile` + `update_submodule()`; macOS stale-hooks fix. |
| #805 | S | BB fresh-mount crash: node_modules/zod preflight or `npm ci` in mount; then close (F1-F6 already superseded by cheval substrate). |

### D — Quality-gate honesty (the "degraded run never silently passes" claim)
| Item | Size | What |
|---|---|---|
| #984+#985 | S/M | One PR: red-team-code-vs-design.sh trap-scope fix + non-empty/parseable output assertion + structured degraded record + non-zero exit. Both issues close. Add KF entry. |
| #809 | S | adversarial-review.sh:810-814 `status:"clean"` → add `status_note` qualifier. Bundle the #866/#868 cosmetic residues (stale #774 warning at flatline-orchestrator.sh:1898; missing `--phase` arg). |

### E — cheval robustness (multi-model substrate on non-happy paths)
| Item | Size | What |
|---|---|---|
| #982 | M | `run_subprocess_pgkill` in providers/base.py (doctor.py killpg pattern, 6 call sites) + pin rfc8785/jsonschema in adapters/pyproject.toml. |
| #979 | M | auth_type/dispatch_group inference for custom `.loa.config.yaml` providers (same surface as #982 — one micro-sprint). |
| #978 | S | mktemp BSD/macOS portability via compat-lib `make_temp` + sweep 4 latent non-trailing-XXXXXX templates + KF-012-style CI scanner. |

### F — Safety
| Item | Size | What |
|---|---|---|
| #969 | M | Minimal write-shrink-guard PreToolUse:Write hook (shrink-% + min-line thresholds, ask-on-trigger, audit-log). Items 2-4 of the issue split to a future cycle. |

### G — UX & docs polish
| Item | Size | What |
|---|---|---|
| #980 | S | golden-path.sh fail-loud assertion after `get_grimoire_dir` (first-run experience). |
| #749 | M | **Needs operator decision**: rename `/review` vs de-reserve (reserved-commands.yaml:123-125); then wire validate-commands.sh into CI without `\|\| true`, rm 9 tracked .pyc files. |
| #701 | S | bv (beads viewer) recommendation docs in beads-reference.md (P1 label, recommend-don't-force). |
| #684 | S | `git rm .claude/skills/riding-codebase/SKILL.md.bak` (last pre-guard tracked .bak), then close citing PR #703 guard. |
| #702 | S | Close citing cycle-111 PR #920 v1.38.0; fix the upstream-attribution nit in the hook header while closing. |

### H — Release tooling correctness
| Item | Size | What |
|---|---|---|
| #821-H | S | phase_tag remote preflight (`git ls-remote --tags`), treat push rejection as failure; split sub-G (judgment-cycle /run) to roadmap issue, then close #821. |
| #745 | S | Close citing PR #785/`d94b20d4` (already fixed, never referenced the issue). |
| #942 | S | next-bug-sprint-id.sh: scan ledger cycles[].sprints — **live footgun**: emits `sprint-bug-178` today vs cycle-114's claimed 177-179. |
| #944 | S | Option C schema-completeness bats pin (yaml keys ⊆ v2∧v3) + KF-006 → RESOLVED-STRUCTURAL. |
| #869 | S | Atomic-seeding CI job: commit-level walk over PR range (closes the schema-enum-only bypass). |
| #798 | M | BB .reviewignore from base ref, not PR-head (supply-chain shape, highest-priority BB item). |
| #810 | M | Option A only: render-time surfacing of security-dimension DISPUTED findings + fixture; defer B/C. |

## Operator decisions needed before/while executing
1. **#749**: rename `/review` Golden Path command vs de-reserve the name.
2. **#969**: confirm minimal-hook-now scope (full evidence-gated-state design → future cycle).
3. **#810**: confirm Option A only.
4. **#683**: optionally close won't-do (version-change tables are the de-facto answer).

## Deferred to cycles (real, not wave-sized)
#817 (spiral IMPL_FIX path reconciliation), #819+#822 (constructs-hygiene pair), #628
(bats sourcing pattern; pairs with #953 cleanup), #871 (admin-bypass scan; needs token
infra), #940 (assumption-gate design), #952 (Model Economy Phase B — next planned cycle),
#902 (close after spinning out activation-matrix fixture-loader + health-journal log
residuals; shipped otherwise).

## Keep as roadmap
#456/#457/#458 (constructs-UX trio), #682/#683 (RFCs), #784 (private-repo coord pointer),
#791 (re-scope: chunking shipped; residual = prompt caching + streaming UX), #811
(Marasa-Trois RFC), #876/#901 (close after disposition comments + residual spin-outs),
#910 (methodology), #941 (Agency Seed deltas), #947 (economy meta-anchor, refresh checklist).

## Provenance
Triage workflow: 15 cluster agents + adversarial closure verification (run
`wf_f5edb339-03a`, 2026-06-10). Each verdict carries file:line / commit / PR evidence;
full record in the session transcript. Closures posted with citation comments on each issue.
