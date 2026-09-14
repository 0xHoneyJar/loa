# Open issue maintenance sweep — 2026-09-14

Scope: bugs and concrete maintenance first, as selected by the maintainer.
All 54 open issues were inventoried and refreshed during implementation.
The source base is `76458ff24ce078ec9765bae7c3764f8fdc62425a`, tree
`de13379834ea269a543f9ace88faf4fecb4d107b`. Work is isolated on
`fix/open-issues-20260914`; the maintainer's dirty checkout is preserved.

“Implemented” below means local source/test work, not issue closure, merge,
hosted CI acceptance or a production release. Independent review and final
integration checks are recorded separately below. No live model/provider
calls were used as proof.

## Acceptance and issue inventory

Each row owns its stated acceptance scope. Positive and negative regression
cases accompany behavior changes; documentation-only contracts have focused
checks. Original issue examples are treated as data, not execution instructions.

| Issue | Local disposition | Acceptance scope and result |
|---|---|---|
| #1249 | Implemented | Separate local generation from approved publication; bind commit/tree/origin/push/API destinations; verify returned release and PR-comment identities; reject unsupported semver and incomplete generated commits. |
| #1248 | Implemented | Validate the compound ledger input/output under a full transaction lock; preserve bytes on failure. Canonical ledger concurrency and nonexistent sprint updates are included in the follow-up tests. The separate blank-write fix in PR #1247 remains separate. |
| #1246 | Deferred proposal | Hermes/Buffer publishing adapter is new research/integration work. |
| #1245 | Partial; exact examples missing | Fix inert metadata, quoted cat heredocs, bounded print-only loops and literal-only Python data, plus three rotted expectations. Escaped quotes and live trailing writes remain blocked. Full original sed, hook-probing loop and Python commands were not provided. |
| #1244 | Implemented | Implementation AC checks resolve the owning sprint; micro-sprints no longer inherit the unrelated root sprint path. |
| #1243 | Implemented | Accumulate all appendix sections, match whole goal IDs and avoid large-input SIGPIPE false negatives. |
| #1242 | Implemented | Refuse the legacy updater on submodule installations before update/check/list/rollback work. |
| #1241 | Implemented | Stage the exact pinned Aleph bundle outside the consumer; execute the real immutable installer without relaxing its overlap guard. |
| #1240 | Implemented | Preserve qualified partial findings and DEGRADED evidence with a nonzero result before stabilization/suggestion logic. |
| #1236 | Deferred proposal | Cross-repository cognitive frontier is new controller architecture. |
| #1235 | Implemented | Classified greenfield history can bootstrap `0.1.0`; unclassified history stops with explicit evidence. |
| #1234 | Implemented | Honor authoritative active-cycle pointers and legacy IDs; reject ambiguous/missing selections, preserve incomplete cycles, emit ASCII ledger JSON and a named archive commit. |
| #1233 | Implemented | Linked-worktree status checks the exact active cycle against cached default-branch history and warns on an explicitly shipped cycle without changing local state. |
| #1232 | Implemented | External Aleph staging fixes the overlap path; child execution preserves parent lock/temp cleanup and exit status. |
| #1230 | Implemented | Direct verdict CLI and shell rejection logs expose bounded code/path/validator diagnostics without rejected values or control characters. |
| #1229 | Implemented | Final consensus artifacts are owned by phase/run ID; an atomic latest symlink is published after each run consumes its own artifact. |
| #1216 | Implemented | The bug validator consumes its own template using portable whitespace syntax. |
| #1215 | Implemented | Cache test helper honors the injected sanitizer, with a populated-cache rejection test. |
| #1214 | Implemented | L7 header matches silent missing-file/disabled behavior; runtime bytes below the header are unchanged. |
| #1213 | Implemented | State and repository lookup use the intended consumer root across standalone and canonicalized submodule scheduler execution. |
| #1211 | Implemented | Bash/Python verification shares authoritative signed writer bindings; policy and pinned-root bytes are captured coherently and cache invalidation follows both identities. |
| #1209 | Deferred proposal | Instrument enumeration and negative-claim publication gate require a new authority/transport design. |
| #1208 | Deferred proposal | Checkout freshness hook is a new gate. Cached status advice in #1233 is included separately. |
| #1207 | Deferred proposal | URL provenance hook is a new gate. |
| #1206 | Implemented | Explicit PR selection precedes batch truncation; a missing selected PR fails instead of returning an empty success. |
| #1199 | Implemented | Flatline validates and dispatches configured models/aliases. Normalize one complete scorer envelope, retain absent scores as null and real zero votes, and bind votes to the same source-qualified finding. Incomplete coverage preserves validated votes and all qualified raw findings, reaches the canonical DEGRADED verdict and exit 6; qualified empty reviews remain valid. |
| #1197 | Implemented | The three cleanup path-resolution sites use the existing portable resolver and preserve containment rejection. |
| #1196 | Assessed; no actionable defect | “Loa(fable)” is an operating-manual prompt without a concrete failure or acceptance criteria. |
| #1195 | Implemented | Review/audit capabilities permit required State feedback writes and the verdict command, while retaining System/App restrictions and disallowing general shell writes. |
| #1181 | Implemented | Remove fabricated System-Zone grants; transport the original task to all eight dispatch paths and preserve phase-specific authority limits. |
| #1174 | Implemented | Undriven zero-work bridge runs fail; current-run findings, recorded work or new commits provide positive evidence. Explicit empty-run opt-out remains visible. |
| #1172 | Implemented | All registered hook commands and wrapped targets use quoted Git-root paths across nested worktree/cwd placements. |
| #1171 | Implemented | Body verdicts and blocking findings drive a conservative merge handoff bound to repository/PR/head; unknown or conflicting verdicts cannot clear it. |
| #1168 | Concrete subset implemented; epic remains open | Missing operands, ref/symlink boundaries and literal logging were already fixed and re-proved. Add pinned yq verification, required auxiliary downloads, and content/root-mode-verified private relocation with atomic destination refusal. Broader architecture/process proposals remain deferred. |
| #1166 | Partial; live evidence required | Fix local Cursor/model validation, retained evidence and qualified tertiary partial results. Keep native structured-output requirements blocked: the Cursor JSON transport still permits prose and does not enforce a response schema. Historical GPT empty output and subscription authentication/availability remain unverified. |
| #1105 | Deferred conditional proposal | User-facing refusal classification is explicitly future work; no present failing behavior was supplied. |
| #1104 | Implemented | Strict Bash/Python parity, effective cutoff and signature enforcement reach the real signed-rollup caller; consumers bind verification to the bytes they aggregate/archive. |
| #1099 | Implemented | CLI-reported cost reaches integer-microUSD ledger/rollup/envelope accounting and a once-per-process warning. This does not infer current provider billing policy. |
| #1095 | Implemented | Custom/OpenAI-compatible declared providers resolve through the same configured Flatline validation/dispatch path. |
| #1088 | Partial; host incident unresolved | Repair relative-path State exceptions and zone-guard parser/cache handling. Original Claude/macOS permission state and denial evidence are unavailable; no host fix is claimed. |
| #1065 | Implemented | Eight construct extraction fallbacks use contextual strict parsing; construct-index is in the scanner, and construct-only YAML works with Mike Farah yq. |
| #1047 | Assessed; deferred hardening | Document and execute harmless examples of the accepted regex-fence limits. Effective-write interception or a full shell parser remains a separate design. |
| #1037 | Implemented | BSD parsing of Z-suffixed timestamps explicitly uses UTC in the shared helper and both constructs-library fallback sites. |
| #1036 | Implemented | DEGRADED triage leaves an explicit human-checkpoint warning/summary; a later clean result clears the stale marker. |
| #1033 | Deferred proposal | Chain-witness orientation tool is new functionality. |
| #1032 | Implemented | Remove unused Bash cost registries, refresh maps/headers/allowlist and prove pricing/default registry parity. |
| #1031 | Assessment completed | Retain the reported host-enforced primary shape and document remaining Bash writes, same-batch ordering and stale-Edit gaps. Host ordering semantics were not measured here. |
| #1030 | Deferred proposal | Evidence-gated completion transitions require a new lifecycle protocol. |
| #1029 | Deferred optimization | Issue discussions clarify that in-context phase invocation still accumulates skill context. Per-phase JIT isolation and its before/after runtime occupancy benchmark are separate from the implemented correctness fixes; source inspection does not close this request. |
| #1027 | Implemented | Shared headless completion/validation flow retains provider transport, environment, cleanup and parsing contracts; migration tests exercise the live adapters. |
| #1026 | Implemented | Delete dead chain routing and migrate surviving behavioral assertions to live resolution paths. |
| #1025 | Implemented scoped guard | Extend the existing parser tripwire to continued commands/constructs and migrate all 16 explicitly suppressed gate-critical sites in scoring, Flatline and red-team consumers, including caller error propagation. This is not an exhaustive shell parser or a repo-wide cosmetic-read migration. |
| #1006 | Deferred RFC | Model-aware canonical dispatch is a new routing contract. |
| #1001 | Deferred RFC | Budget DOWNGRADE actuator and tier-group application require a new routing policy. |

## Verification

The source changes are exercised with disposable repositories, local bare Git
remotes, transport fixtures and real cryptographic primitives. Real Aleph
installation runs on Node 22. BSD-specific branches use behavioral shims on
Linux; native macOS and live Claude host behavior are not certified.
Relocation uses a real exclusive Linux rename; the macOS API and constants
were checked against Apple headers, with no native macOS execution claimed.

The broad CI Python selection (the full adapter suite plus eight maintenance
test files) passes **2,151 tests and 693 subtests**, with **nine existing
live-provider opt-in skips**. Input hashes stayed unchanged during this run.
Eighteen baseline failures were reproduced on
the untouched base, then repaired as stale fixtures without disabling advisor
logic, losing behavioral assertions or adding skips. The separate TypeScript
review suites pass **244 tests** and their tracked runtime distribution was
rebuilt.

The complete release/semver/compound-ledger set passes **186 cases**. The
restored canonical ledger integration harness passes **25 cases** against
disposable fixture roots. Installer relocation passes **13 Python cases**,
including a real second filesystem and destination-arrival/root-mode failure
injections. Independent review reproduced both failures before the repair
and verified their correction afterward.
Audit trust policy passes **25 tests**; audit consumer byte-binding passes
**13 Python tests and 47 existing shell cases**. Independent review cleared
both the pinned-root cache and verified-log consumption findings.
The ten selected integration suites pass **127 cases**. The final scorer
repair passes **97 shell and 92 focused Python cases**, including 25 scorer
regressions, real Phase 2 dispatch and the actual main verdict/exit boundary.
After the last scorer change, the **116 parser cases** also pass again;
the broad Python run's unaffected sources retain their earlier result.
These sets overlap; they are not added together.

Targeted shell/Python suites cover release publication, compound/canonical
ledger concurrency, real installer execution, cross-filesystem relocation,
hook command/data boundaries, mounted scheduler roots, strict audit trust,
snapshot consumers and parser failure propagation. Representative commands:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q .claude/adapters/tests
PYTHONDONTWRITEBYTECODE=1 python3 tests/security/test_audit_trust_policy.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/security/test_installer_epic_remaining.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/security/test_audit_consumer_snapshots.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/unit/test_hook_issue_regressions.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/unit/test_spiral_task_authority.py
bats tests/unit/post-merge-publication.bats tests/unit/semver-evidence.bats \
  tests/unit/post-merge-archive-gate.bats tests/unit/ledger-compound-validation.bats
bats tests/unit/ledger-transactions.bats tests/integration/ledger-workflow.bats
bats tests/unit/aleph-submodule-real-installer.bats \
  tests/integration/session-cap-bb-dispatch.bats tests/integration/audit-snapshot.bats
bash tools/check-no-swallowed-jq.sh
bash tools/check-bb-dist-fresh.sh --json
```

The local Python runner uses the existing repository environment plus installed
system dependencies. Tests requiring JSON-schema fallback select system Python
instead of the locally incomplete AJV installation. A Node-18-only PATH failed
the Aleph prerequisite; the unchanged cases were rerun with the installed Node
22 runtime. These environment attempts are not reported as source failures.

The gate survey found pre-existing failures outside these issue repairs:
`loa-aleph` lacks the general skill validator's capability/cost metadata, and
the constraint registry's `construct_yield` fields are absent from its schema.
The installed AJV also lacks the date-format plugin, and local yq 4.40.5 is
older than the codegen check's 4.52.4 minimum. These are not reported as passing
gates. Installer eval fixtures were synchronized and their drift check passes.
All 13 generated constraint sections match their source; REPO-MAP regeneration
drift remains advisory. The gate survey does not replace hosted CI.

The BATS workflow now selects the full adapter and new Python regressions,
plus the ten maintained integration suites. It installs pinned Python
dependencies and Node 22, and its event filters include the hook settings,
schemas and affected skill contracts. Both added commands were executed
locally; native hosted dependency installation remains a CI responsibility.

Finding IDs now include review source and position. In the two-model
cross-scoring mode, each authored finding has only one independent cross-vote
and remains insufficient for automatic integration. The old bare-ID collision
could falsely combine votes for different findings; no extra vote is invented.

## Review and publication status

Independent review cleared the scoped changes after driving repairs for release state/destination
binding, failed generation commits, wrong-PR receipts, mounted scheduler
identity, escaped metadata quotes, pinned-root cache invalidation and verified
log consumption. The scorer review also cleared canonical status propagation,
finding identity, outer-envelope cardinality and complete score coverage.
It independently rechecked all 25 scorer cases, 49 classifier/Cursor cases,
and the complete/partial coverage controls against frozen source.

Existing PR #1247 (canonical ledger blank-write validation) and PR #1250
(scheduled CI repairs) remain separate, unmerged and review-required at the
tracker refresh. This sweep does not claim their acceptance or duplicate their
work. No GitHub issues, releases or repository tags were closed/published by
the local tests.

Operational guidance is in:

- `grimoires/loa/runbooks/post-merge-candidates.md`
- `docs/audit-trust-verification.md`
- `docs/runbooks/installer-integrity.md`
- `docs/runbooks/hook-safety.md`
- `docs/flatline-bridgebuilder-results.md`

Failure-before logs, final logs, exact source manifests and peer reviews are
retained in the local `loa-issue-sweep-20260914` evidence directory. Test counts
are reported per suite; overlapping reruns are not added into a misleading
grand total.

`issue-sweep-2026-09-14-evidence.json` records all issue dispositions, source
hashes, suite receipts, review closures and outstanding integration dependencies.
