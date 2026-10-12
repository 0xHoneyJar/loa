# Slice 7 Semantic Unit Review — Implementation Reconciliation

Date: 2026-09-12

Status: PRODUCER-AUTHORED IMPLEMENTATION RECONCILIATION — FRESH INDEPENDENT AUDIT REQUIRED

This record reconciles implementation with the exact adopted Slice 7 design and
its sole manual-reviewer-profile clarification. It is not an independent audit.
Passing results establish the named structural, checker, fixture, process,
compatibility, runtime or packaging proposition only. No SRC-001 semantic
validation, replay validation, agent sanction, acceptance, production readiness,
golden status or Aleph v1 is claimed.

## Authority, worktree and executable identity

| Identity | Exact value |
| --- | --- |
| Repository | `0xHoneyJar/loa-aleph` |
| Origin | `https://github.com/0xHoneyJar/loa-aleph.git` |
| Branch | `agent/slice-07-semantic-review-implementation-20260912` |
| Verified starting adoption commit | `094a7ce3220631c8d4ee4c179e79b9b4529b6681` |
| Verified starting adoption tree | `4443fa12f0633fa388d2f4ec6e677691bd4210ab` |
| Proposal commit | `d5cd2baf95dcfc1fb5e10ebf8af9f5ed819bbda0` |
| Proposal tree | `ed9ecd80f9cfabe48e964c13cac5b0dfa871974e` |
| Proposal Git blob | `f3307ac00fe98d5ec8b0cca56168e0bff2f269b9` |
| Proposal SHA-256 | `36ff7aa18cdd3e90e50d2e0c0eb5988d0182f51bff7a5cac7581e7c1e84da95e` |
| Authorization commit | `61bed05bcd19a2c03e8a45f181b0d34c16eb78bb` |
| Authorization tree | `5a73e0b0050ef6d8636e9d8a1379d7991c945124` |
| Clarification commit | `ddc2a3e7caaf9298780ef2795c534a4332357cf8` |
| Clarification tree | `37341822f9a0a409f48963f4e354ed439576fc4c` |
| Executable implementation commit | `6faac02c8cb32bbaf91c7cde77905cd1d5f7976d` |
| Executable implementation tree | `ec4aa4ada0961475e6a4821f24b4d799dd6aac19` |

All authority records below are under `calibration/src-001/core-design-basis/`:

- Proposal: `PROPOSED-slice-7-semantic-atomicity-context-qualifier-evidence-role-review-design-20260912.md`.
- Adoption: `ADOPTED-slice-7-semantic-atomicity-context-qualifier-evidence-role-review-design-20260912.md`.
- Implementation authorization: `AUTHORIZED-slice-7-implementation-20260912.md`.
- Clarification: `ADOPTED-slice-7-manual-reviewer-profile-clarification-20260912.md`.

The implementation authorization declaration remains exactly:

```text
I authorize Slice 7 implementation based on the adopted Slice 7 design.
```

The initial repository, branch, HEAD/tree, clean working tree, ancestry,
proposal/adoption bytes, manifest, capability state, findings and separate
adapter workstream were checked before implementation. Authorization was a
separate normal commit before executable changes. The proposal remains
historically PROPOSED; adoption establishes authority. Neither historical
proposal nor adoption was rewritten, no mutable main was merged, and all
implementation commits descend through the exact authority chain above.

The continuation began at the exact authorization HEAD/tree with the existing
uncommitted implementation preserved. The clarification commit contained only
its authority record and one manifest administration entry. Its staged names,
full diff and status were inspected, diff checking and CB1–CB10 passed, and
613 prior worktree file hashes were compared before/after, excluding the
explicitly authorized manifest addition. No existing implementation was
reset, stashed, cleaned, checked out over, or recreated.

This reconciliation is committed after the executable checkpoint. Its commit
adds this Core record and one Core manifest entry only. Like the Slice 6
precedent, it cannot embed its own Git object identity: publication HEAD/tree
and final-head package identities are reported after committing it. The
checkpoint identities below remain exact checkpoint identities, not aliases
for the later publication. Final-head packaging must be reproduced separately
because this Core record changes payload bytes.

## Manual reviewer-profile clarification

The conflict was between the proposal's generic exact pinned model-identity
object requirement and the existing manual-run identity doctrine. The human
clarification was preserved verbatim in the separate authority record:

```text
I clarify the adopted Slice 7 design: for manual runs only, reviewer_profile is exactly {profile_id:"n/a (core-manual)", profile_digest:null, role:"verifier-l2s", model_identity:"human"}. No model/profile/effort mapping is invented for manual execution; existing manual run identity rules remain controlling, and reviewer independence remains established by the distinct actor/pass evidence required by Slice 7 section 15.3. Agent and hybrid reviewer_profile requirements remain unchanged.
```

Core implements the exact manual-only variant in the same four-key order:

```json
{"profile_id":"n/a (core-manual)","profile_digest":null,"role":"verifier-l2s","model_identity":"human"}
```

Execution mode comes from retained run identity. Manual identity remains
`core-manual`, `human-operator`, `model_ids=human`, adapter profile
`n/a (core-manual)` and model execution mapping `n/a (manual)`. No model,
digest, effort or context mapping is fabricated. Agent/hybrid exact pinned
profile digest, model object, role mapping, context and effort remain required.
The exception changes no other Slice 7 design policy, role, profile or slice.

The exact seven-key §15.3 manual evidence record remains
`{producer_actor,reviewer_actor,producer_pass_id,reviewer_pass_id,subject_digest,shown_digest,withheld_declaration}`.
Distinct actors and passes are checked mechanically. Same-person separate
sittings can be retained as temporal evidence but do not meet independent
producer/reviewer requirements. The generic human profile cannot prove actor
identity or cognitive independence. Manual evidence stays
`manual-separate-pass`; it is never counted as native fresh dispatch.

The contract suite has 20 named manual/agent/hybrid profile and independence
cases before the portable-return case. They cover the valid manual object,
wrong/non-null/missing/extra values, agent and hybrid baselines, null digest,
human string and manual cross-variant refusal in each nonmanual mode, an
agent profile refused in manual mode, same actor/two passes refusal, distinct
actors/passes, native relabeling refusal, and variant digest/review invalidation.
These meet all 14 requested clarification propositions and establish only
structural/process separation.

## Implemented adopted contract

| Adopted obligation | Implementation and boundary |
| --- | --- |
| Cumulative format/capability | `1.7.0-provisional` / `semantic-unit-review` in the existing registry. Predecessors use explicit capability predicates, never equality to CURRENT. Marker injection fails; incidental frozen corpus strings remain data. |
| Exact source and semantic declarations | Closed anchors, facets, AtomicUnit, Context, Semantics, Coupling and Finding contracts; exact key order, enums, nulls, IDs and canonical JSON. Existing locators, half-open UTF-8 offsets, exact base64, selection/span/source hashes and packet coverage are checked without inventing a locator. |
| Semantic boundaries | Producer-declared atomicity/cardinality only. Unknown remains distinct from absent. Inspection context does not become evidence. Couplings annotate source composition without support inference, new relations or duplicate/overlap decisions. |
| Producer integration | Existing return fields and Slice 6 `material_use` retained; exact `semantic_units`, output kinds/indexes, selected packet fragments, origin/context projections and relation/material projections. One PKT per fragment, source-walk positions, joins and accounting remain controlling. |
| Immutable review subject | Complete sealed subject binds producer, run/prompt/profile/model/output/origins/packet/anchor/semantic/material/lineage/relation/ambiguity/context inputs. Changed load-bearing input needs a new subject/review; prior subjects are never retargeted. |
| L2S and portable results | Exact fresh role mapping, allowlists, withholding and Core result/field-review/issue/verdict coverage. Core enforces L2S `candidate_evidence=[]`. Native schema and fallback share the contract; standalone binding is `not-checked`, full-context binding is checked. This does not repair Slice 6 A-05. |
| S2/S3 and exhaustive accounting | Every applicable 1.7 candidate receives review; L1 gap review and L2F remain independent. Affirmative CCs require adopted admission predicates. No-claim remains distinct from indeterminacy. Assigned review history and cannot-determine escalation cannot be erased by a later upheld result. |
| Bounded S4 successor | Reviews an already proposed lineage successor with exact current predecessor/member references. The normalizer cannot choose merger groups, inspect unrelated inventory as an oracle, decide duplicate equivalence or repair L3 judgments. A failed preservation review blocks the successor. |
| Slice 4 / Slice 5 / Slice 6 reuse | Existing relation validators, bounded same-source referent procedure, material availability, use subjects, views and independent L2F obligations reused. Claim roles never map automatically to edge roles, dispositions, claim_type or relation semantics. |
| Durable review and writing | Exact semantic ledger, immutable SEM/assignment/result/resolution/process receipts and origin/follow-up accounting. Core plans exact preimages/prerequisites/reservation identities and bytes; Loa performs transport, journal persistence and recovery. No semantic policy is added to host regexes or provider abstractions. |
| Closure and unresolved summary | Stage-prefix seals, C1 semantic ledger closure and `semantic_review_closure_hash`; post-C1 mutation fails closed. Section 17 derives retained unresolved findings, including earlier failures behind usable narrower successors. Projection cannot mutate an accepted Précis. |
| K2.19 | Deterministic, read-only subject/review accounting with all 11 adopted stable reason tokens. No models, network, OCR, renderers, semantic heuristics, assertion counter, truth/entailment or duplicate-equivalence judgment. |
| Prompt/runtime contract | Exact common semantic block, role amendments, L2S heading/clarification, unresolved-record and bounded S4 headings, T3.7 and stage excerpt. Slice 6 common constraint block remains verbatim. All authored executables are TypeScript; runtime-js is canonical compiler output. |

The exact proposal was reopened section by section. Where no new code was
needed in a listed dependency-map surface, existing Core exports and import
closure were reused. No new build root, provider abstraction, general
orchestrator or unrelated `loa` repository change was introduced.

The additional narrow integration paths serve those same obligations:
`checks-k2-relations.ts` exposes its existing relation-row validation for the
semantic projection without changing relation policy; adapter manifests carry
the new supported format; `cli.ts` and `runtime-snapshot.ts` apply the new
semantic closure/capability checks to existing dispatch/resume paths.
`semantic-fixture-support.ts` constructs synthetic tests, and existing adapter
and representation tests use explicit predecessor copies. None introduces a
new provider, launcher protocol, semantic taxonomy or deferred repair.

## Verification at the executable checkpoint

| Validation | Result |
| --- | --- |
| git diff --check / staged check | PASS; exact executable commit clean |
| npm run typecheck | PASS |
| runtime:build / runtime:check | PASS; 40 canonical generated files; no drift |
| npm test at 6faac02c8cb32bbaf91c7cde77905cd1d5f7976d | PASS, exit 0; no source changes during execution |
| Runtime suite | 6/6 PASS |
| Core boundary | CB1–CB10 PASS; 654 classified paths at executable checkpoint |
| Worker-return contracts | 14/14 PASS; 20 pinned prompt contracts |
| Loa host / adapter / installer | 24/24, 34/34, 17/17 PASS |
| Discovered fixtures | 275/275 checks PASS across 12 fixtures |
| Isolated evidence / projection / complete-run checks | All PASS |
| Slice 5 contracts / deterministic cases / process | 12/12, 123/123 (106 mutations), 76/76 PASS |
| Slice 6 structural / process | 71/71 and 20/20 PASS |
| Slice 7 contracts / mutations | 64/64 and 62/62 PASS; FX01–FX22 and M01–M24 |
| Slice 7 source / generated-runtime process | 33/33 and 33/33 PASS; fixture-simulated |
| Conformance mutations / clean baselines | 117/117 and 11/11 PASS |
| Lineage / relations | 34/34 and 74/74 PASS |
| Core-boundary mutations / bundle cases | 12/12 and 31/31 PASS |
| Release-package suite | 23/23 PASS |
| Clean checkpoint assembly / release reproduction | Two assemblies and two releases independently verified and byte-identical |
| Installed Node 20.20.2 | 16/16 structural, launcher, checker, return and capability probes PASS |

Counts above were checked against individual emitted PASS/ok records and the
machine-readable discovered-check array, not only suite-reported totals.
Mutation helpers require a clean positive baseline and assert the actual
checker/process refusal and intended kernel/reason. The 62-case semantic
mutation suite covers every M01–M24 family, including closure, origin gaps,
interrupted/forked transactions, old-format marker injection and non-oracle
self-reported counts. The static ASSEMBLED section-17 mutation fixture checks
K2.19 specifically; it is not claimed to satisfy unrelated later K2–K6 gates.

FX01–FX22 use synthetic source material. FX17-a, FX17-b and
FX17-coherent-error all structurally PASS. The checker suite snapshots run
bytes before/after to establish read-only behavior, permits semantically
distinct coherent declarations, and does not encode an expected semantic
answer. The deliberately coherent semantic error remains challengeable by
L2S. Wrong meaning is not a deterministic negative. Alternate atomic/context,
result/interpretation, modality, attribution and narrower-successor cases
remain declaration checks rather than a semantic answer key.

Native JSON Schema validation was additionally exercised with a Draft
2020-12 validator on all three role schemas: extractor, normalizer and L2S,
with positives and extra-key negatives. This was local schema evaluation,
not native model dispatch. Duplicate-key semantic contract descriptors are
refused by the exact new strict parser; predecessor return parsing behavior
is preserved. Standalone PASS cannot establish run binding or meaning.

## Process/freshness evidence and runtime parity

The 33-case source process suite and 33-case generated-runtime suite exercise
actual sealed fixture requests, accepted-return quarantine and Core-planned
single-writer APIs. The path exercised is:

1. Fixture extractor invocation → accepted return → exact PKT/USE/source-walk
   capture → immutable semantic reservation.
2. Separate fixture L2S request → exact accepted result → semantic resolution
   and S2 stage seal.
3. S3 normalizer request over selected origins → reserved semantic/material
   subjects → separate accepted L2F and L2S → combined CC/USE/SEM transaction.
4. Two separate cannot-determine L2S returns → new producer subject and new
   L2S invocation upholding only a linked unresolved record. Both historical
   review findings remain; neither failed reservation is admitted as a CC.
5. S3 and C1 closure, then byte-preserving refusal of attempted mutation.

Six forbidden canaries are absent from the actual request and accessible
attachment files: calibration answers, producer rationale, authority
observations, unrelated sources, downstream narrative and expected
dispositions. Producer-context reuse and forged simulation markers are
refused at accepted-return transport. Static/native labels cannot upgrade
fixture evidence. New subjects bind new context without erasing old reviews.

Fresh subprocesses recover reservation, preparation, assignment, result,
stage-seal and C1 interruptions plus six positions in composed admission.
Changed preimages, missing review prerequisites and forks refuse before
further writes. Identical retries remain no-ops, including a completed older
retry after later valid rows. Retained host S4 facts prevent erased S3/C1 log
signals from downgrading the write window. These checks do not repair the
separately deferred generic resume findings.

The generated-runtime process suite uses Node 20.20.2 for recovery subprocesses.
Source/runtime positive and negative K2.19 reports, portable worker returns,
capability activation and transport behavior agree. Runtime generation is
through `runtime:build`; all 40 generated files pass canonical drift checks.
Installed Node 20.20.2 also passed 16 explicit probes: install, verify-install,
launcher status, positive/negative/coherent-error K2.19, three portable-return
cases for each of extractor/normalizer/L2S, and all eight format/capability
rows. Installed reports equal the TypeScript reports. These are runtime and
structural checks, not real human or native model review.

| Execution class | Evidence in this implementation |
| --- | --- |
| Native dispatch | NOT RUN. No genuine provider/model invocation or native freshness claim. |
| Fixture-simulated | Actual local transport/accepted-return/write/recovery mechanics with simulated responses and distinct declared fixture contexts. |
| Static-record | Exact schema/hash/accounting checks; never sufficient for agent freshness or invocation proof. |
| Manual-separate-pass | Synthetic retained manual actor/pass declarations tested structurally; not a claim that real human review sessions occurred. Same-actor temporal separation is insufficient for independence. |

Real model calls: **none**. No generated record is claimed as native evidence.
The tests cannot prove cognitive independence, semantic correctness or general
production reachability. In particular, F-03 remains OPEN.

## Compatibility and preserved bytes

All 425 pre-existing fixture/calibration files match the before-implementation
SHA-256 inventory. All 255 prior non-discovery check records are identical.
Discovery changes only by adding the new fixture: 275 passing checks over 12
fixtures. No accepted/frozen 1.0–1.6 run was migrated. New synthetic compatibility
copies used for adapter and Slice 6 tests pin 1.6 explicitly; historical fixture
bytes and old profile requirements are unchanged.

A genuine retained 1.6 run was created using the exact adoption checkout
`094a7ce3220631c8d4ee4c179e79b9b4529b6681`, then resumed and validated under current
TypeScript and generated runtime. Its 437 retained runtime files and identity
pins stayed unchanged, and its profile has no L2S mapping. Literal Slice 7
markers in its frozen source did not activate Slice 7. The bundle dependency
closure correctly records predecessor executable provenance
`c0ec43142710f39d50e7b7681760209112a0e17c` /
`c1a5d1b10700bff0edbe5b63475c00c8f35bdc21`, not the later administration-only
adoption commit. Its S0 authority was fixture-simulated.

The retained Node 22-created run correctly refused a Node 20 identity change;
that refusal is a preserved-pin result, not a migration, Node 20 success or
portability repair. The installed Node 20 tests instead use the exact current
bundle and declared static fixtures without retargeting a retained run.

The exact common semantic block, L2S clarification and prior Slice 6 common
constraint block were compared byte-for-byte to authority. No SRC-001 expected
answers, IDs, preferred wording or recall quotas entered generic Core, prompts
or tests. Existing withholding/status references do not provide answer material.

The separate adapter workstream remains at
`b9e2db742a087b8ae659ec39e476ed5e240cfa1f` /
`f9daba8ba3e9b33e2895265a1427d61829a90722`; preserved stash remains
`e5b49e873d8a03fcd0d1b3bc65fc7c80cb8b6ce8` /
`a71318a42d8dca812f7d57161d21e4d3bc1b388b`.

## Reproduced executable-checkpoint packages

| Identity | Reproduced value |
| --- | --- |
| Core content | `sha256:7b9efd1b8de7020c3f9ef1021d9701d1757f8712db81ba82e613867421a3b331` |
| Checker content | `sha256:800e3255515ed01fa210c0a0caac70b586359e34b25f6e97c0158be8942f0658` |
| Loa adapter content | `sha256:fd97a8211fb7d51edcdc8d21e1ff95a761bd0aaf33d5f1b6fa4918cbaf29b43c` |
| Loa payload | `sha256:9e948297bd3183b6bb6b9b18eb7599eedf7f6229605f252a21ae9231c8c7f715` |
| Dependency-closure provenance commit | `6faac02c8cb32bbaf91c7cde77905cd1d5f7976d` |
| Dependency-closure provenance tree | `ec4aa4ada0961475e6a4821f24b4d799dd6aac19` |
| Provenance digest | `sha256:46e7ea567f1d720937f2336341a6a8bab65100e24c0732cf24a220d8a71a3493` |
| Loa lock | `sha256:dd8c1c6c59b4f42138e5a30a4dbd3320cd79aa55ad140a034443e5a0c1a7291c` |
| Loa bundle | `sha256:61cb77ce3b3fbd1201c3233989eed5c34d5862320c2bdb2b32a73b8d77e632d0` |
| Hermes bundle | `sha256:4c663eef83acb1743ee951be3307db60726117df62b793ad973d1b5a3e97c4a4` |
| Release archive | `sha256:fa95d8c26567dcbcbde6f301f48fd2e267d5b77ffa01b106fbaca2d8b21e76cb` |

Two clean canonical assemblies and two release packages were independently
verified and reproduced byte-for-byte. Both host bundles have identical Core
bytes; Loa remains structurally READY and Hermes planned/NOT-READY. Release
version is `0.1.0-provisional`. Content, checker, adapter, payload, provenance,
lock, bundle and archive identities are distinct. These are local structural
prerelease artifacts; they are not a published release, acceptance or sanction.

Adding this reconciliation changes Core payload bytes. The publication report
must identify a separately reproduced final-head package set, retaining the
checkpoint set above without relabeling it.

## Failed attempts retained

Earlier invocation failures remain in the local evidence directory. Restricted
subprocesses returned EPERM; unchanged permitted-context reruns were used.
Initial full-suite attempts exposed synthetic legacy adapter fixtures using
the new format with old returns, missing generated semantic modules in the
checker inventory, and stale Slice 6 tests assuming 1.7 was unknown/current
meant 1.6. The explicit compatibility fixture pins, generated checker inventory
and stale test assertions were corrected within the bounded change. The full
suite passed afterward, and was run again at the clean executable commit.

Intermediate structural/process runs exposed incomplete synthetic bindings,
transaction recovery/closure coverage and current-lineage reservation checks.
Those failures informed the final tests and implementation; their logs remain
retained. Later final changes were rebuilt through the canonical runtime
compiler and verified again. Earlier successful changing-worktree results are
not substituted for the clean executable-commit gate.

The first checkpoint packaging helper paired correct bundle paths with expected
IDs in the opposite order. Each bundle verified individually, but the set
assertion failed; corrected ordering reproduced both sets. A restricted retry
failed on Git subprocess permission before assembly. The installed Node 20
probe initially launched from the repository instead of the temporary installed
host, and correctly received a missing-installation-receipt error; the corrected
host-directory invocation was retained separately. A historical-check comparison initially assumed the new fixture was appended;
the actual discovery inserts it in order. Comparing complete records with
multiplicity confirms all 255 prior records remain identical. These were producer
probe errors, not native execution evidence.

The retained-run probe also preserves failed setup attempts (missing temporary
parent directory, missing launcher root argument, and the refused retained
Node identity change). No failed attempt is recast as PASS, an independent
audit finding, or a semantic result.

Retained local evidence (SHA-256 over exact bytes):

| Path | Result / role | SHA-256 |
| --- | --- | --- |
| `/tmp/loa-aleph-slice7-clarification-20260912/npm-test-clean-6faac02.log` | PASS; full clean executable gate | `5094a00aaae2934511db5987e7517fc7737c2a025a9446c219b4381e4903e606` |
| `/tmp/loa-aleph-slice7-clarification-20260912/full-test-clean-6faac02-counts.json` | PASS; independently counted actual case records | `a49c954841cfd08a6ed9f166952424351ca9827e9d36f62e8b23b39c29447167` |
| `/tmp/loa-aleph-slice7-clarification-20260912/full-test-clean-6faac02-cases.json` | Exact individual case names from full gate | `27e85b22a692c25d0861871812a1f507c8107f467941a3174269a49c5528674d` |
| `/tmp/loa-aleph-slice7-clarification-20260912/core-clean-6faac02-permitted.json` | PASS; Core boundary at executable checkpoint | `3122d293d14e2612a4872f22365b0351916960dcd2dd63db3d2dec2717e10a0d` |
| `/tmp/loa-aleph-slice7-clarification-20260912/runtime-clean-6faac02-permitted.json` | PASS; canonical generated runtime drift check | `baa4580ea6aeabbaa8a2eb595e33b2bfb49a9696b317a0c2c1740fa4d7439c79` |
| `/tmp/loa-aleph-slice7-clarification-20260912/preserved-bytes-clean-6faac02.json` | PASS; all 425 historical fixture/calibration file hashes | `2ccf90f0fddbfecbd9fb8ec62f2a812a7d99a2c10958796b1fbd29456454165d` |
| `/tmp/loa-aleph-slice7-clarification-20260912/legacy-checks-clean-6faac02.json` | PASS; 255 unchanged prior check records | `7463af88238e1785bce0bdaf56880b518f2aa0f0bd1762d0aebb57dda7437e3e` |
| `/tmp/loa-aleph-slice7-clarification-20260912/discovery-clean-6faac02.json` | PASS; 275 actual check results | `8f9aad075d90166924d1d91c192e7412f3149f2770c5dffec12194456eed6f94` |
| `/tmp/loa-aleph-slice7-clarification-20260912/authority-legacy-prompt-verification.json` | PASS; proposal and common prompt byte verification | `660b9176b131a45b4d71df9a5cfa907a033dd132103f94702c1fb6d1ef10e0ee` |
| `/tmp/loa-aleph-slice7-clarification-20260912/native-schema-external-validation.json` | PASS; local Draft 2020-12 schema evaluation | `7964705bcaa81479474b115bdd2432ed98517ffc6292c0d75ede6e94103c89dd` |
| `/tmp/loa-aleph-slice7-clarification-20260912/genuine-retained-4/report.json` | PASS; retained 1.6 compatibility and Node identity refusal | `a0f905bcbac62b874ba3eced2b8e694a9e1ed0e31b4dfc8ae47f86d69f6f98fb` |
| `/tmp/loa-aleph-slice7-executable-6faac02-r2/identities.json` | PASS; two clean assemblies/releases and exact checkpoint identities | `bc274379704160989048eb4fd88e091abaa8e8ea46b249e539726a5cc088e104` |
| `/tmp/loa-aleph-slice7-installed-node20-6faac02-r2/report.json` | PASS; installed Node 20 checkpoint probes | `fd84ea7b3b7901ebdfa4f3df59f1d55193b0025e41588a95b6807c4bca0b609a` |
| `/tmp/loa-aleph-slice7-clarification-20260912/npm-test-attempt-1.log` | FAILED earlier legacy fixture integration attempt | `a90f7aa34666a6e5ec0717675f2e657049f270f3adc0c80d22d09305374def5a` |
| `/tmp/loa-aleph-slice7-clarification-20260912/adapter-compat-diagnostics.log` | FAILED earlier generated checker inventory attempt | `f3631e9a46bd9ec2e3edb893a1110a27f8def099a8f11f4ae285cf76803431d8` |
| `/tmp/loa-aleph-slice7-clarification-20260912/npm-test-attempt-2.log` | FAILED stale Slice 6 version assertion attempt | `0eabdfe2d22c50e08d226db3a81803aa48c8798c5e2758870afac619914f8729` |
| `/tmp/loa-aleph-slice7-clarification-20260912/manual-tests.log` | FAILED restricted subprocess invocation; retained | `dd356c76590edf79f52259bdeb6b3af73f527f5dc58ad9040e49feb38f937963` |
| `/tmp/loa-aleph-slice7-clarification-20260912/package-executable-6faac02.log` | FAILED reproduction helper expected-ID ordering | `d6a0590225f1045b2c90f6d80030e30ef53886f255e688024a1c7fd64fc22fe9` |
| `/tmp/loa-aleph-slice7-clarification-20260912/package-executable-6faac02-r2.log` | FAILED restricted Git subprocess invocation | `f0ea984748695856d7106c7df2bad7de9a784f4b91cfd7d5d31024225d7e020b` |
| `/tmp/loa-aleph-slice7-clarification-20260912/installed-node20-6faac02.log` | FAILED launcher probe run outside the installed host | `2e1714dcef38d6ec555b3ab368cb4c3c6007a3890726a097e0edc0e4caf98453` |

## Carried findings and strongest status

| Finding / boundary | Carried status |
| --- | --- |
| F-03 | OPEN: accepted-worker-return → canonical LedgerWriter/orchestrator production reachability remains unproven. |
| F-04 | OPEN: path/case/platform portability remains unresolved. |
| F-05 | OPEN and bounded by F-03. |
| S5A4-02 | DEFERRED; no opportunistic broader activation repair. |
| S5A4-03 | DEFERRED; no opportunistic pre-existing S3 recognizer repair. |
| S5A2-03 / S5-A-03 | DEFERRED; generic resume/review-subject findings remain. |
| Slice 6 A-01, A-02, A-04, A-05 | Retained. New L2S portable enforcement does not close A-05. |
| Slice 6 A-03 | Remains a closed observation. |
| Slice 6 A-06 | Remains an accepted observation. |
| Prior slices / OQ-01 | Exact evidence, source walk/gaps, lineage, typed relations, ambiguity/referent procedure, procedural-only human authority and independent material/L2F boundaries preserved. |
| Mode | Manual mode remains the only currently sanctioned execution mode. |
| Calibration | SRC-001 CLOSED_FOR_CALIBRATION; SRC-002 NOT_AUTHORIZED. |
| Exclusions | Slice 8 not begun; replay not begun; no semantic validation, acceptance, agent sanction, production readiness, golden or v1. No merge. |

No carried finding is independently closed by this producer record. The next
audit must be a fresh independent Claude Opus/xhigh audit of the full range
from the exact starting adoption commit to the final publication HEAD/tree,
including authorization, clarification, executable implementation,
reconciliation and separately reproduced final-head package identities.

Strongest producer status:

SLICE 7 IMPLEMENTED ON IMPLEMENTATION BRANCH — STRUCTURAL / CHECKER / FIXTURE / PROCESS TESTS PASS — FRESH INDEPENDENT AUDIT REQUIRED

## Changed files at the executable checkpoint

### Core (5)

- `adapter-protocol/adapter.schema.json`
- `adapter-protocol/runner-capability-contract.md`
- `scripts/lib/run-model.ts`
- `scripts/lib/semantic-review.ts`
- `scripts/lib/worker-return-contract.ts`

### checker (4)

- `scripts/lib/checks-k2-relations.ts`
- `scripts/lib/checks-k2-semantics.ts`
- `scripts/lib/checks-k2.ts`
- `scripts/validate-worker-return.ts`

### prompts (5)

- `docs/architecture/prompts/README.md`
- `docs/architecture/prompts/orchestrator.md`
- `docs/architecture/prompts/verifier-lenses.md`
- `docs/architecture/prompts/workers-intake-extraction.md`
- `docs/architecture/prompts/workers-judgment.md`

### fixtures-and-tests (44)

- `adapters/loa/tests/test-loa-adapter.ts`
- `adapters/loa/tests/test-representation-process.ts`
- `adapters/loa/tests/test-semantic-review-process.ts`
- `docs/fixtures/semantic-unit-review/README.md`
- `docs/fixtures/semantic-unit-review/cases.json`
- `docs/fixtures/semantic-unit-review/positive/README.md`
- `docs/fixtures/semantic-unit-review/positive/control/runtime/bundle/bundle.lock.json`
- `docs/fixtures/semantic-unit-review/positive/control/runtime/bundle/docs/architecture/04-pipeline-stages-and-dod.md`
- `docs/fixtures/semantic-unit-review/positive/control/runtime/bundle/docs/architecture/prompts/README.md`
- `docs/fixtures/semantic-unit-review/positive/control/runtime/bundle/docs/architecture/prompts/verifier-lenses.md`
- `docs/fixtures/semantic-unit-review/positive/control/runtime/bundle/docs/architecture/templates/03-extraction-claims.md`
- `docs/fixtures/semantic-unit-review/positive/corpus/manifest.md`
- `docs/fixtures/semantic-unit-review/positive/corpus/representations.md`
- `docs/fixtures/semantic-unit-review/positive/corpus/sources/semantic.txt`
- `docs/fixtures/semantic-unit-review/positive/ledgers/claim-inventory.md`
- `docs/fixtures/semantic-unit-review/positive/ledgers/disposition-ledger.md`
- `docs/fixtures/semantic-unit-review/positive/ledgers/extraction-criteria.md`
- `docs/fixtures/semantic-unit-review/positive/ledgers/lineage.md`
- `docs/fixtures/semantic-unit-review/positive/ledgers/packet-index.md`
- `docs/fixtures/semantic-unit-review/positive/ledgers/representation-uses.md`
- `docs/fixtures/semantic-unit-review/positive/ledgers/semantic-review.md`
- `docs/fixtures/semantic-unit-review/positive/ledgers/source-walk.md`
- `docs/fixtures/semantic-unit-review/positive/run-log.md`
- `docs/fixtures/semantic-unit-review/positive/run-manifest.md`
- `docs/fixtures/semantic-unit-review/positive/verification/harness/S2/VER-0701.md`
- `docs/fixtures/semantic-unit-review/positive/verification/harness/S3/VER-0702.md`
- `docs/fixtures/semantic-unit-review/positive/verification/harness/semantic-assignments/VER-0701.json`
- `docs/fixtures/semantic-unit-review/positive/verification/harness/semantic-assignments/VER-0702.json`
- `docs/fixtures/semantic-unit-review/positive/verification/harness/semantic-process/manual-producer-0701.raw.json`
- `docs/fixtures/semantic-unit-review/positive/verification/harness/semantic-process/manual-producer-0702.raw.json`
- `docs/fixtures/semantic-unit-review/positive/verification/harness/semantic-process/producer-0701.json`
- `docs/fixtures/semantic-unit-review/positive/verification/harness/semantic-process/producer-0702.json`
- `docs/fixtures/semantic-unit-review/positive/verification/harness/semantic-process/reviewer-0701.json`
- `docs/fixtures/semantic-unit-review/positive/verification/harness/semantic-process/reviewer-0702.json`
- `docs/fixtures/semantic-unit-review/positive/verification/harness/semantic-results/VER-0701.json`
- `docs/fixtures/semantic-unit-review/positive/verification/harness/semantic-results/VER-0702.json`
- `docs/fixtures/semantic-unit-review/positive/verification/harness/semantic-stage-seals/S2.json`
- `docs/fixtures/semantic-unit-review/positive/verification/harness/semantic-subjects/SEM-0701.json`
- `docs/fixtures/semantic-unit-review/positive/verification/harness/semantic-subjects/SEM-0702.json`
- `scripts/semantic-fixture-support.ts`
- `scripts/test-representation-mutations.ts`
- `scripts/test-semantic-review-contracts.ts`
- `scripts/test-semantic-review-mutations.ts`
- `scripts/test-worker-return-contract.ts`

### adapter (11)

- `adapters/hermes/adapter.manifest.json`
- `adapters/loa/adapter.manifest.json`
- `adapters/loa/profiles/loa-default.json`
- `adapters/loa/src/cli.ts`
- `adapters/loa/src/ledger-writer.ts`
- `adapters/loa/src/run-control.ts`
- `adapters/loa/src/runtime-snapshot.ts`
- `adapters/loa/src/types.ts`
- `adapters/loa/src/worker-bundle.ts`
- `adapters/loa/src/worker-dispatch.ts`
- `adapters/loa/src/worker-return.ts`

### runtime (15)

- `runtime-js/adapters/loa/src/cli.js`
- `runtime-js/adapters/loa/src/ledger-writer.js`
- `runtime-js/adapters/loa/src/run-control.js`
- `runtime-js/adapters/loa/src/runtime-snapshot.js`
- `runtime-js/adapters/loa/src/types.js`
- `runtime-js/adapters/loa/src/worker-bundle.js`
- `runtime-js/adapters/loa/src/worker-dispatch.js`
- `runtime-js/adapters/loa/src/worker-return.js`
- `runtime-js/scripts/lib/checks-k2-relations.js`
- `runtime-js/scripts/lib/checks-k2-semantics.js`
- `runtime-js/scripts/lib/checks-k2.js`
- `runtime-js/scripts/lib/run-model.js`
- `runtime-js/scripts/lib/semantic-review.js`
- `runtime-js/scripts/lib/worker-return-contract.js`
- `runtime-js/scripts/validate-worker-return.js`

### docs-and-administration (11)

- `core.manifest.json`
- `docs/PRECIS-CONFORMANCE-CHECKER.md`
- `docs/architecture/03-artifact-contracts.md`
- `docs/architecture/04-pipeline-stages-and-dod.md`
- `docs/architecture/08-runbook-agent-mode.md`
- `docs/architecture/09-runbook-manual-mode.md`
- `docs/architecture/checker-spec/K1-K2-fixtures-and-runs.md`
- `docs/architecture/templates/03-extraction-claims.md`
- `docs/architecture/templates/07-verification.md`
- `package.json`
- `scripts/compatibility-fixture-source.ts`

Authorization and clarification were separate authority/admin commits. This
reconciliation adds `docs/architecture/19-slice-7-implementation-reconciliation.md`
and its Core manifest entry after the 95-file executable checkpoint above.
