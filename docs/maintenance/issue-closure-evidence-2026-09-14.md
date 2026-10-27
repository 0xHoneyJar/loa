# Issue closure evidence — 2026-09-14

Recommend closure of **18 original issue scopes** listed below. Keep **#1099
and #1027 open** for the explicit remaining conditions. This is a documentation
reconciliation of merged work, not a new implementation, live-provider test,
blanket audit approval, or issue-closing operation.

## Identity and evidence

Reviewed main: `80be4b0f57b39eb05c77b0a738a2797afac635a7`, tree
`74d91a6676ef8286e9a186c7bfcf28f2e18ed8b9`.
All repairs below entered through **PR #1251**, merge
`d834575a3586257e9d32bb270da9a3a57f9d0c62`.
PR #1252 subsequently fixed release-preparation script modes; it does not
supply the acceptance evidence claimed below.

**Fresh work:** read the current issue bodies and supplied author comments;
inspect current source/tests; verify Git ancestry and compare **72 distinct
source/test files** with both committed and retained audit inventories.
The committed [source-binding manifest](issue-closure-source-binding-2026-09-14.json)
records the compared paths, blob IDs and SHA-256 values. Every compared file matches audited head
`cea8bfe36bd243d497e46642b5602ba963e7ac23` byte-for-byte. The removed legacy
walker and two obsolete smoke/routing test files are absent from current Git.

**Retained execution:** the following completed independent audits tested that
earlier head. Their local results remain relevant to the unchanged files;
they were not rerun for this documentation change. A report's overall
`CHANGES_REQUIRED` verdict does not invalidate its explicitly supported,
separate original issue scopes.

| Receipt | Retained evidence used here |
|---|---|
| **H — hooks/lifecycle** | `validation-lifecycle.log`: 87 passing checks, including AC ownership and appendix cases; `spiral-authority.log`: five passing dispatch tests; `hook-issues.log`: 32 passing checks including Git-root command resolution; `l7-contract.log`: 17 passing L7 checks. |
| **I — installers** | `logs/bats-regressions.log`: 39 passing checks, including six real Aleph-installer cases, updater refusal, BSD-date contract and shipped-triage-template cases. BSD behavior is modeled on Linux, not native macOS execution. |
| **A — reviews/adapters** | 391 selected adapter/routing/cost/registry tests passed, one guarded live test skipped and five live cases deselected; Bridgebuilder template 32 and cache 21 passed; `results/bats-focused.log` includes passing redaction, degraded-handoff and zero-work bridge cases. Forty-two paired completion probes preserve behavior apart from intended CLI cost propagation. |
| **R — release/ledger** | `suite-results.tap`: 58 passing checks; the five semver-evidence cases cover initial `0.1.0`, explicit-source refusal and classified commit evidence. Other archive/publication findings remain separate. |
| **C — retained hosted unit log** | Shell Tests run `34826206173`, synthetic merge `e844224e521d93668d7895af373b4c3b736469e3`, PR head `cea8bfe…`, base `76458ff2…`. The five named #1065 checks passed at log lines 1480, 1483 and 1740–1742. No current hosted status is inferred. |

H/I/A/R reports are retained under
`/tmp/loa-fixes-audit-20260914/<area>/report.md`; areas are `hooks-lifecycle`,
`installers`, `reviews-adapters`, and `release-ledger`. C is
`/tmp/loa-issue-sweep-20260914/hosted-bats-final.log`, independently inventoried
by the completed `ci-coverage` audit. Local reconciliation records are
`/tmp/loa-issue-burndown-20260914/closure-evidence/source-binding.json` and
`receipt-hashes.json`. The conclusions and limits needed to interpret these
receipts are preserved here rather than requiring an external report to infer
the closure scope.

## Supported original scopes

Commit abbreviations identify implementation commits included in PR #1251.
Source/test links refer to this repository; behavior was freshly inspected,
while every execution claim is retained evidence as labeled above.

| Issue and original acceptance scope | Merged source and test evidence | Closure boundary |
|---|---|---|
| **#1244 — use the owning sprint for AC verification; document physical-line and heading requirements.** | `4714113a`: both gates in [implementing-tasks](../../.claude/skills/implementing-tasks/SKILL.md) use `"$SPRINT_FILE"` resolved from the bug handoff/ledger; [planning-sprints](../../.claude/skills/planning-sprints/SKILL.md) documents the authoring rules. H: [ownership tests](../../tests/unit/validation-skill-contracts.bats) accept the micro-sprint and reject unrelated root ACs. | **Recommend close.** This fixes the requested instruction contract; no deterministic ownership resolver or live `/bug` agent run is claimed. Ambiguous ownership must still be resolved. |
| **#1243 — search every appendix for whole goal IDs without accepting non-appendix occurrences.** | `4714113a`: [validate-artifact.sh](../../.claude/scripts/validate-artifact.sh) resumes its appendix walk and uses whole-word matching. H: [validator tests](../../tests/unit/validate-artifact.bats) cover later appendices, intervening headings, `G-1` versus `G-10`, and large-input handling. | **Recommend close.** Syntactic presence is proved; semantic correctness of mappings and rewriting old plans with genuinely missing sections are outside the fix. |
| **#1242 — refuse the standard updater on a declared submodule installation before destructive work, including discovery modes.** | `c9c37398`: [update.sh](../../.claude/scripts/update.sh) checks `installation_mode` before check/list/interactive/rollback/update work and points to `update-loa.sh`. I: [refusal tests](../../tests/unit/update-submodule-refusal.bats) cover normal/check/dry-run/list/force/rollback, malformed manifests and standard/help controls. | **Recommend close.** No live upgrade was run. Refusal precedes checksum processing, so the suggested checksum-stage bypass is unnecessary on this rejected route; general manifest freshness is not certified. |
| **#1241 — remove the unavoidable nested-source overlap failure without weakening the immutable Aleph installer.** | `c9c37398`: [mount-submodule.sh](../../.claude/scripts/mount-submodule.sh) stages captured committed bundle bytes outside the consumer before installation. I: [real-installer tests](../../tests/unit/aleph-submodule-real-installer.bats) cover successful/repeated installation, spaces/in-repo TMPDIR, dirty source, check-only mode, installed tamper and failed archive cleanup; retained base control reproduces the overlap error. | **Recommend close for the installer defect.** The author's partial-upgrade symptom shares that cause. Maintainer comments requesting a manual Aleph extraction-quality pass do not provide such evidence; research semantics and a full live update/commit remain unverified. |
| **#1235 — bootstrap a version when both tags and CHANGELOG versions are absent.** | `2af691ac`: [semver-bump.sh](../../.claude/scripts/semver-bump.sh) seeds `0.0.0` and emits initial `0.1.0` from classified history; [post-merge](../../.claude/scripts/post-merge-orchestrator.sh) consumes that result. R: [semver-evidence tests](../../tests/unit/semver-evidence.bats) include a tagless/no-changelog repository and explicit `--from-tag` refusal. | **Recommend close for bootstrap.** Classification remains required. First publication still requires candidate inspection/approval; this is not a live first-release receipt. RL-02/04/05 concern different preparation/publication inputs. |
| **#1230 — bounded, control-free schema diagnostics without rejected values or raw validation messages.** | `aa08aa41`: [_schema_rejection](../../.claude/adapters/loa_cheval/verdict/aggregate.py) emits a stable reason with bounded ASCII path/validator fields. A: [direct CLI cases](../../.claude/adapters/tests/test_verdict_quality_aggregate.py) and [Flatline log regression](../../tests/integration/flatline-issue-sweep.bats) cover long rationale, control bytes and other value-bearing validators. | **Recommend close.** Canonical schema validation remains active. This concerns rejection-log confidentiality, not the separate scoring/clearance correctness findings. |
| **#1216 — parse the shipped bug-triage template with POSIX whitespace syntax and retain invalid-ID/state failures.** | `c9c37398`: [validate-artifact.sh](../../.claude/scripts/validate-artifact.sh) uses `[[:space:]]` in grep and sed; fresh inspection finds no remaining `\s` expression in that validator. I/H: [BSD-dialect tests](../../tests/unit/validate-artifact-bsd.bats) use the shipped template, whitespace variants, malformed IDs and missing state. | **Recommend close for the regex defect.** The harness models BSD's missing GNU `\s` extension using local tools; no native macOS execution is claimed. |
| **#1215 — the cache test helper must pass an injected sanitizer and exercise its failure behavior.** | `aa08aa41`: [cache.test.ts](../../.claude/skills/bridgebuilder-review/resources/__tests__/cache.test.ts) now passes `opts?.sanitizer ?? mockSanitizer()`. A: its populated-cache strict-sanitizer case proves invocation and blocks posting; cache suite 21 passed. | **Recommend close.** This is the helper's original testing defect, not acceptance of all cache behavior or the separate Bridgebuilder clearance predicate. No stopped cache probes are used. |
| **#1214 — choose one missing-file L7 audit behavior and align header, runtime and tests.** | `4714113a`: [L7 hook](../../.claude/hooks/session-start/loa-l7-surface-soul.sh) documents no audit event for missing files/disabled L7, preserving existing runtime behavior. H: [L7 tests](../../tests/integration/soul-identity-7b.bats) assert that header, silent absence and no event, plus existing-file outcomes. | **Recommend close.** The shared schema's permissive `file-missing` outcome does not promise emission by this hook. No new audit/trust guarantee is implied. |
| **#1206 — apply explicit PR selection before batch truncation and reject an absent target.** | `aa08aa41`: [PRReviewTemplate.resolveItems](../../.claude/skills/bridgebuilder-review/resources/core/template.ts) filters the full returned list for `targetPr`; only unselected batches use `maxPrs`. A: [template tests](../../.claude/skills/bridgebuilder-review/resources/__tests__/template.test.ts) select PR 12 at limit 10 and reject PR 999. | **Recommend close.** This proves selection from the provider-returned list, not live GitHub pagination, successful review publication or safe merge clearance. |
| **#1181 — remove fabricated standing System-Zone grants and protect planning/harness scope.** | `4714113a`: [spiral-harness.sh](../../.claude/scripts/spiral-harness.sh) transports original task authority; generated plans cannot grant writes, planning/review have bounded outputs, and harness/safety-hook edits require explicit original-task scope. H: [five dispatch tests](../../tests/unit/test_spiral_task_authority.py) capture all eight real dispatch sites with a fake model executable. | **Recommend close for prompt authority.** The user's task, not a generated PRD string, supplies authorization. Tests prove prompt transport and preserved phase/model distinctions; model obedience and OS isolation are not claimed. |
| **#1174 — undriven default bridge execution must not report successful zero work; permit only explicit empty opt-out.** | `aa08aa41`: [bridge-orchestrator.sh](../../.claude/scripts/bridge-orchestrator.sh) checks current-run findings, executed-sprint records or commits since initial HEAD; `--allow-empty` is explicit. A: [bridge issue tests](../../tests/unit/bridge-issue-sweep.bats) halt the undriven default path and empty/stale findings, with work/commit/opt-out controls. | **Recommend close.** Activity evidence is not semantic proof of implementation quality or review clearance. |
| **#1172 — anchor registered hook executables and wrapped targets to quoted Git roots.** | `7a900437`: both [settings.json](../../.claude/settings.json) and [settings.hooks.json](../../.claude/hooks/settings.hooks.json) contain Git-root commands. H: [hook regressions](../../tests/unit/test_hook_issue_regressions.py) exercise spaces, nested linked worktrees, descendant cwd and a wrong project-dir variable; the real wrapped fence still blocks. | **Recommend close for executable location.** The upstream host's root detection and every hook's relative input semantics are separate. HL-001's role-write restriction is also a distinct defect. |
| **#1065 — harden the eight named extraction sites and enforce construct-index in the swallowed-output tripwire.** | `aa08aa41`: [construct-index-gen.sh](../../.claude/scripts/construct-index-gen.sh) uses `_strict_or_default` at all eight sites; successful commands/values pass through unchanged. [Scanner](../../tools/check-no-swallowed-jq.sh) includes this file and yq. C: [three extraction cases](../../tests/unit/construct-index-swallowed.bats) and [two tripwire cases](../../tests/unit/check-no-swallowed-jq-residual.bats) pass, including malformed YAML, partial failure output and success values. | **Recommend close for those sites.** Fresh diff inspection confirms the same successful extraction expressions; retained tests check values/union, not byte identity of every possible whole-index document. The separate numeric-comparison guard is unchanged. |
| **#1037 — use UTC for BSD Z timestamps, including the additional constructs fallback named in the author comment.** | `c9c37398`: [compat-lib.sh](../../.claude/scripts/compat-lib.sh) and both [constructs-lib.sh](../../.claude/scripts/constructs-lib.sh) fallbacks use `date -u -jf`. I: [date tests](../../tests/unit/compat-date-utc.bats) cover UTC/New York/Tokyo, local-time input, GNU/Perl controls and constructs staleness fallback. | **Recommend close.** The issue expressly allowed a TZ shim; that evidence exists. Native BSD execution and unrelated cleanup `du`/`df` portability are not claimed. |
| **#1036 — make triage DEGRADED visible at READY_FOR_HITL without changing convergence policy.** | `aa08aa41`: [post-pr-orchestrator.sh](../../.claude/scripts/post-pr-orchestrator.sh) records/surfaces `post-pr-degraded-summary.json` and clears stale state at the next phase. A: [handoff regression](../../tests/unit/bridge-issue-sweep.bats) checks marker, PR identity, visible warning and later clean removal. | **Recommend close for visibility.** Reaching the human checkpoint is not merge approval; whether DEGRADED should halt the loop was explicitly a separate design question. |
| **#1032 — remove dead Bash cost maps, share YAML routing/pricing, fix the named headers and delete obsolete tests while retaining deletion pins.** | `866e5008`: [generator](../../.claude/scripts/gen-adapter-maps.sh), [generated maps](../../.claude/scripts/generated-model-maps.sh), [shim header](../../.claude/scripts/model-adapter.sh) and [allowlist comment](../../tools/check-no-direct-llm-fetch.allowlist) reflect the requested cleanup. A: [registry parity](../../.claude/adapters/tests/test_model_registry_parity.py) compares generated aliases with Python YAML resolution and pricing. Fresh Git inspection confirms both obsolete tests are deleted. | **Recommend close for the enumerated scope.** The shim's separate `usage()` text still falsely describes a legacy routing switch at lines 315–342; track that remaining documentation bug separately. Headless clone-suite consolidation belongs to #1027. |
| **#1026 — delete the unused walker only after moving surviving assertions to live routing/dispatch.** | `866e5008`: `routing/chains.py` and its exports are absent; [live-chain tests](../../.claude/adapters/tests/test_live_chain_contracts.py) exercise actual resolution/dispatch, alias cycles, company/native boundaries, capability/circuit gates and budget block. A retains passing execution; [budget tests](../../.claude/adapters/tests/test_budget_fallback.py) name the separate deferred actuator. | **Recommend close for dead-walker removal.** Budget DOWNGRADE actuation remains deferred under #1001; deleting a dead walker did not implement it. |

## Partial scopes — no closing keyword

| Issue | Supported merged work | Remaining condition |
|---|---|---|
| **#1099 — CLI cost visibility** | `866e5008`, A: positive CLI USD becomes integer micro-USD; zero stays real zero; invalid/missing telemetry stays unknown; budget/rollup/MODELINV prefer `cli_reported` without config-price double counting. [Cost tests](../../.claude/adapters/tests/test_cli_reported_cost.py) cover a process-once warning and a local fake executable through dispatch. Adapter comments distinguish reported cost from billing policy. | **Hold.** Author comment `4764425109` corrected the original policy claim and explicitly required checking upstream #43333 on a current CLI; comment `4932144828` retained that prerequisite and `/plan` routing. No current-CLI reproduction, invoice or prerequisite-waiver evidence is present. The three telemetry implementation items are complete locally; do not claim that the author condition or current external billing behavior was verified. |
| **#1027 — headless template base and clone-test consolidation** | `866e5008`, A: [HeadlessCLIAdapter](../../.claude/adapters/loa_cheval/providers/headless_cli.py) centralizes completion, prompt, health, timeout and validation. Claude/Codex/Gemini/Cursor use shared completion; all six adapters participate in [shared contract tests](../../.claude/adapters/tests/test_headless_shared_contract.py), with 42 retained paired completion scenarios. | **Hold as partial.** The four original per-adapter suites still exist alongside the new parametrized suite; the expressly requested companion consolidation was not completed. Grok/AGY also retain specialized `complete()` methods. Author comment `4756530275` already retired the “before #966” timing gate and retained post-hoc consolidation. Native CLI behavior is unverified and must not substitute for the remaining code/test work. |

## Limits and retained provenance

The completed audits also report independent clearance/scoring defects
(ADP-001–006), role/caller-integration defects (HL-001–003), installer
cancellation/lock/cleanup limits, and release archive/publication defects
(RL-01–05). These are not silently accepted or repaired here. They do not
reopen unrelated, specifically satisfied original scopes above. Later worker
repairs are outside this exact-main assessment.

No repository executable code changed, and no behavioral suites or probes
were rerun. This reconciliation performed no provider call, live installation,
GitHub write, publication, commit or settings change. No native
macOS/BSD/Bash-3.2 evidence was added. The stopped audit-trust/signing/cache
work and issues #1211/#1104 are excluded.

A separate parent-reported full-pytest run inherited a Bedrock credential,
automatically enabled `test_bedrock_live.py`, and exposed the credential in
failure output. That run supplies no evidence here. The parent reports log
redaction and an explicit-opt-in repair in progress; neither was independently
verified by this reconciliation. Any follow-up tests must use a minimal
allowlisted environment, preserve `HOME`, and omit inherited provider, routing
and credential variables. The closure recommendations do not certify general
pytest live-test isolation or authorize provider calls.

Input snapshots beside the worktrees:

- `issues.json` SHA-256: `d1052e50af4a06c24de063549dbe101c2f640fb9f2407731efeb2db46536a011`.
- `issue-comments.json` SHA-256: `75f4c22e19a4e5ee47e440bc95164fd704262fc75f191708c14697bb6f775842`.
- Hosted unit log SHA-256: `b2e2d2b0d4d1ce1ebb7b5165c72627da3dbc6738d5bd2a2b19739062d1d3d419`.

These are retained snapshots, not a live issue-status or CI-status refresh.
The parent retains review, publication and issue-closing authority.
