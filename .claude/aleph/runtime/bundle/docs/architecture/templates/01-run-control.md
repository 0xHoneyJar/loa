# Templates 01 — Run Control

## T1.1 Run manifest → `runs/<run-id>/run-manifest.md`

```markdown
# Run Manifest — ⟨RUN-slug⟩

## Identity
- run_id: ⟨RUN-slug⟩
- predecessor_run: ⟨none | RUN-prior-slug⟩
- mode: ⟨agent | manual | hybrid⟩
- created: ⟨YYYY-MM-DD⟩
- core_id: aleph-core
- core_version: ⟨exact version from bundle lock⟩
- core_digest: ⟨sha256:… complete Core tree digest⟩
- adapter_id: ⟨host adapter ID | core-manual⟩
- adapter_version: ⟨exact version⟩
- adapter_digest: ⟨sha256:… adapter tree or manual-binding digest⟩
- bundle_id: ⟨immutable bundle ID⟩
- bundle_digest: ⟨sha256:… complete bundle digest⟩
- bundle_lock_ref: ⟨run-local path or content-addressed immutable reference⟩
- checker_digest: ⟨sha256:… checker tree digest⟩
- adapter_protocol_version: ⟨exact version⟩
- run_format_version: ⟨exact version⟩
- host_identity: ⟨exact host/runtime name | human-operator⟩
- runtime_snapshot_ref: ⟨run-local immutable snapshot path⟩
- runtime_snapshot_digest: ⟨sha256:…⟩
- doctrine_sha: ⟨source-provenance commit containing these exact Core bytes⟩
- runbook: ⟨Core path + version/digest of the runbook followed⟩

## Corpus binding
- corpus_ref: corpus/manifest.md
- corpus_hash: ⟨sha256 over the sorted per-source hashes⟩
- declared_scope: >
    ⟨2–6 sentences: what claims are in scope; what is explicitly out.⟩

## Execution profile
| field | value |
|-------|-------|
| model_ids (per role, exact strings; or "human") | ⟨…⟩ |
| adapter profile ID + digest | ⟨… | n/a (core-manual)⟩ |
| model/context/effort mapping actually used | ⟨exact mapping | n/a (manual)⟩ |
| profile deviations | ⟨none | list⟩ |
| fan-out limits | ⟨…⟩ |
| budgets granted (per stage, tokens) | ⟨table or "n/a (manual)"⟩ |

## State log  <!-- append one row per transition; order must match doc 02 §3 -->
| # | state | entered | actor | note |
|---|-------|---------|-------|------|
| 1 | DRAFT | ⟨date⟩ | ⟨who⟩ | run created |

## Authority sign-offs  <!-- append-only -->
| gate | decision | by | date | reference |
|------|----------|----|------|-----------|
| S0 corpus scope + sensitivity | ⟨approved/…⟩ | ⟨authority⟩ | ⟨date⟩ | ⟨run-log anchor⟩ |

## Unvalidated-machinery notices  <!-- mandatory rows when triggered -->
| what ran | why noted | date |
|----------|-----------|------|

## Deviations from runbook
| # | what | why | approved-by |
|---|------|-----|-------------|
```

Rules: every pin is exact; aliases such as `latest`, moving branches, or moving
tags are forbidden. A Core, adapter, bundle, checker, model, or runtime change
does not amend the current run: resume with the original lock/snapshot or start
a successor run. Hybrid mode lists per-stage actors in the execution profile.
Historical fixtures keep their recorded predecessor format and are not
silently repinned to current bytes.

## T1.2 Run log → `runs/<run-id>/run-log.md`

```markdown
# Run Log — ⟨RUN-slug⟩
<!-- Append-only. One entry per event. Write for a reader who was not
     watching: complete sentences, spell out terms, no arrow-chains. -->

## ⟨YYYY-MM-DD HH:MM⟩ — ⟨STAGE⟩ — ⟨entry|exit|decision|anomaly|gate|spend⟩
⟨2–6 sentences. For exits: counts produced, DoD items closed, spend.
For decisions: what was decided, the one-line why, which ledger row records
it. For gates: the question, options, recommendation. For anomalies: what
was observed, what was done, where it is recorded.⟩
```

<!-- example -->
Example entry:

```markdown
## 2026-07-15 14:10 — S2 — exit
Extraction finished for all four sources. 87 packets written to
ledgers/packet-index.md (SRC-101: 21, SRC-102: 24, SRC-103: 19, SRC-104: 23).
Per-source completion declared for each. Coverage spot-check dispatched to
the harness (verification/harness/S2-coverage/). Spend this stage: 412k
tokens of the 600k budget.
```

## T1.3 Kernel report → `runs/<run-id>/verification/kernel-report.md`

```markdown
# Kernel Report — ⟨RUN-slug⟩
- checker_digest: ⟨required sha256 from the immutable bundle lock⟩
- checker_source_provenance: ⟨commit/release reference, informational⟩
- command: `⟨exact command line⟩`
- date: ⟨YYYY-MM-DD HH:MM⟩
- result: ⟨PASS | FAIL⟩

## Output (verbatim, complete)
```text
⟨paste the checker's full stdout/stderr⟩
```
```

Rules: the pasted output is never edited or truncated; a FAIL report is
committed too (it is evidence of the loop, not shame); one report file per
invocation, numbered `kernel-report.md`, `kernel-report-2.md`, … with the
latest linked from the run log. A local fixture developed in the same
uncommitted change as its checker uses `checker_source_provenance:
UNPINNED-WORKTREE`, records the last committed base separately, and records a
publication-repin instruction. It must still record the exact checker content
digest. The marker cannot support publication, acceptance, or replay claims.
Before publication, freeze a bundle, rerun the exact command from it, record
the lock's checker digest and provenance, and refresh the complete output.

Compute `checker_digest` by sorting every checker path declared by
`core.manifest.json`, hashing each
file's exact bytes with SHA-256, joining records as
`<repo-relative-path>\0<lowercase-file-digest>\n`, and hashing the joined bytes
with SHA-256. A source commit is provenance; it never replaces the content
digest.
