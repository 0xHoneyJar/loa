# CI failure audit — 2026-09-14

The recurring failures have several concrete causes: incomplete test selection,
environment-dependent prerequisites, platform assumptions, unchecked process
results, and generated artifacts that are validated inconsistently. Passing
focused tests also left important caller and failure paths untested.

This audit starts from main `80be4b0f57b39eb05c77b0a738a2797afac635a7`.
It incorporates the completed #1251 CI audit, local reproductions, independent
review of the repairs and the explicitly identified hosted runs below.
It does not certify every historical failed run as having one of these causes.

## Findings and repairs

| Cause | Observed consequence | Repair and validation |
| --- | --- | --- |
| Required checks have path-filtered PR triggers. | Documentation-only PR #1255 completed its selected checks but never scheduled the required `Shell Tests` context. | Run that required job on every PR targeting main. The regression checks the actual workflow trigger. This is separate from which tests a job selects. |
| Workflow selection omits active tests or their prerequisites. | Security Bats suites were unselected; Hypothesis properties could be absent; Bridgebuilder codegen cases all skipped without skill-local dependencies. | Discover the Python test directories, run security Bats explicitly, install Hypothesis and test schemas with the installed validator. The separate Bridgebuilder repair selects codegen and checks its prerequisites. |
| Local and hosted tool resolution differ. | A global AJV caused setup failures while the same security and scheduler cases passed using the existing Python validator. Default-routing tests inherited operator overrides. | Use the job's declared dependency environment and retain failed environment attempts separately from source results. Thirty-three unchanged security cases pass after selecting the intended tools. No schema assertion was weakened. |
| Quiet downloads fail before tests start. | #1254 run `34860258607`, job `104030348154`, stopped during pinned-yq download with exit 4; no transport diagnostic or test result was retained for that cell. | Add finite retries, timeouts and visible errors to the affected activation and Shell Tests setup, preserving checksum verification. The specific transport cause remains unknown; exhausted retries still fail. |
| Ambient credentials are treated as live-test authorization. | A broad local pytest run attempted Bedrock calls and included a credential in a failure traceback. Network resolution failed; no successful provider response was recorded. | Require explicit live-test opt-in before credential discovery, use a minimal offline environment and short tracebacks. Saved logs were redacted; already-rendered output could not be removed. Credential rotation remains necessary. |
| Process success is inferred from an incomplete exit-code table. | Eval exits such as missing output, 126, 127 and 137 could be reported as success. | The actual final-step regression requires both suites to return supported values. `0/0` passes; `1` fails; documented status `2` remains an explicit advisory; unknown or absent values fail. |
| Review history is treated as effective approval. | An earlier approval survived later changes requested, dismissal or a new PR head. Independent review also found rename and incomplete-file-enumeration gaps. | Recompute the effective current-head decision on review lifecycle events. Classify both rename paths and require a valid, complete file enumeration before claiming no protected changes. The operator-author exception remains the existing policy. |
| A source manifest is treated as proof of shipped runtime bytes. | Changing only shipped Bridgebuilder verdict JavaScript passed the old freshness check. The old CLI import smoke test could terminate before its assertions. | The separate Bridgebuilder repair rebuilds locked source in a disposable tree and compares the complete dist output, with source and dist negative controls. The manifest-only legacy check is labeled accordingly. |
| Platform checks are dormant or narrower than their label suggests. | Linux tests accepted Bash 4 syntax while the promised Bash 3.2 check was skipped. Enabling the native job exposed `;&` in the post-PR orchestrator. GNU-only cleanup options also survived a narrower realpath repair. | Execute the existing 3.2 contract in a dedicated job and repair incompatible source behavior. Keep syntax checks, platform-dialect fixtures and native runtime evidence distinct. Do not turn the failing check advisory. |
| Generated-map enforcement differs between jobs. | Regeneration drift was advisory in one workflow but failed the mandatory unit suite; source changes and concurrent repairs repeatedly left stale maps. | Reject drift consistently and regenerate the map/checksum from each final source tree. A later rebase that changes mapped source requires another regeneration. |
| Workflow setup itself changes the checkout. | Main run `34838888080` changed the mode of sourced `bootstrap.sh`, then failed its own clean-tree preparation guard. | Already fixed in #1252. Main run `34843608296` successfully prepared and uploaded the candidate. The regression executes the actual YAML preparation blocks. |

## Why passing tests missed defects

The repair reviews exercised boundaries absent from the original fixtures:
history-read failure versus an empty changelog domain; allocated versus installed
candidate bytes; direct-child exit versus surviving descendants; a lock across
the installer's actual directory transition; model-local versus global finding
IDs; and failure of the terminal verdict emitter itself.

These cases produced concrete counterexamples. They are tracked in the
[known-failures log](../../grimoires/loa/known-failures.md), with initial attempts
and practical limits retained. Re-running an unchanged provider call or raising
a token limit would not repair these deterministic caller defects.

## Evidence and limits

- The initial workflow reproduction had 36 failing assertions across 14 tests.
  The first repaired selection passed 14 workflow tests; an expanded selection
  then passed 18. Independent review added the rename, incomplete-list and
  native-syntax counterexamples. Their final repair passes 24 workflow tests
  with 71 subtests and 47 additional independent metadata controls.
- Actual GNU Bash 3.2.57 on Linux passes the unchanged six-case portability
  selection over all 368 shell files, seven dispatcher cases and the selected
  benign library checks. The latter required two additional syntax-compatible
  representations. This does not establish hosted macOS behavior.
- Fifteen independent offline yq-setup controls preserve failure propagation,
  checksum ordering and finite retry configuration across all three changed
  download blocks. They do not establish live transport success or duration.
- Before those final review corrections, the complete isolated Python selection
  passed **2,408 tests**, with **9 explicit skips** and **749 subtests**.
  This is an identified earlier execution, not a claim that every later source
  revision ran that full command.
- Fifteen schema/dependency cases and 33 security Bats cases passed locally
  with the declared validator environment. Existing security regression
  execution does not resume or certify the separately stopped trust audit.
- Local Python 3.12 and Node 22 results do not prove the hosted Python 3.13 and
  Node 20 environments. Likewise, Linux dialect fixtures do not prove macOS.
  Hosted results must be attached to the exact PR head and run attempt.
- The observed branch protection requires five contexts and one approval.
  The stronger settings in
  [BRANCH_PROTECTION.md](../../.github/BRANCH_PROTECTION.md) remain a proposal;
  this work changes no repository approval settings.

Each issue-closing PR still needs its relevant checks and maintainer review.
An accurate CI result is necessary evidence, not automatic merge permission.
