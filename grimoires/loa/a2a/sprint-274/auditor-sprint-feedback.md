# Sprint 274 (cycle-133 Sprint 3) — Security Audit

**Auditor:** lead (Fable 5.1) as the Paranoid Cypherpunk Auditor · **Dissent run 2 of 3:** `adversarial-audit.json` beside this file (`--type audit`; gpt-5.5-pro clean, claude-headless companion succeeded; 8 payloads: 6 accepted below, 1 fixed in this round, 1 rejected) · **Review:** `engineer-feedback.md` round 2 APPROVED after the unclosed-fence fix `87c7041e3` · **Scope read:** the executable diff `de366cc63..f63b4e92a`, the smoke evidence under `grimoires/loa/reports/ablation-2.0/c133-smoke/`, the HOME build and overlay code, the guard entrypoint, the shared secret classes, the floor amendment.

## Verdict

APPROVED - LET'S FUCKING GO

One medium is an accepted design risk recorded with its mitigations (the floor amendment); five lows are follow-up beads; one low was fixed in this round. No critical or high finding. The sprint's two live defects (KF-058, KF-061) were found by its own smoke and fixed; the home-scope isolation claim was withheld on evidence (KF-060) rather than claimed.

## Security checklist

- **Secrets.** The sandbox HOME carries the codex config and an auth.json whose refresh token is a placeholder (`make_home`, 0600/0700); API-key mode is not copied without an explicit opt-in; the Bedrock bearer token passes by environment through the ENV_SHIM and never lands in a file; `record-branch.sh` runs `set -euo pipefail`, so a crash of the shared scanner aborts the build (fail closed); the eight credential classes moved byte for byte into `lib/secret-classes.sh`. detect-secrets over every pushed commit: hashes, test canaries and placeholders only.
- **Trust boundary of PR-supplied `.claude/`.** Under home-scope the overlay removes the full prompt and executable surface from the root (skills, commands, agents, hooks, rules, output styles, plugins, settings, memory files at any depth, `.mcp.json`, `@`-imports five hops), never follows symlinks, and the session runs `--setting-sources user`; the spike proved 2.1.299 loads nothing from the project scope. Clause (g) stayed clean in both smoke runs.
- **Network.** The egress guard validates the sidecar name, installs IPv4 and IPv6 OUTPUT/INPUT rules (loopback, replies, sidecar:8888 only, reject with admin-prohibited) and drops to uid 65534 with cleared capabilities before the launcher proceeds; the sandbox joins the namespace without NET_ADMIN (EGR-13); CI's eval job confirmed the host gateway unreachable on the runner (KF-058); smoke run 2 logged 26 filtered denials and none from the allowlisted hosts.
- **Input validation.** The external seeder refuses unsafe paths (empty, `.`, `..`, absolute, backslash, NUL, control characters, `.git`) before any tree lookup, disables hooks on every git call, fetches blobs only after trees-API sizes agree with the clone, archives a synthesized tree and verifies every member by blob id; the guard refuses a proxy name outside `loa-proxy-<batch>` and a non-IPv4 resolution; verdict-derive's new scan fails closed on an unclosed fence (review round 1) and on a missing lib.
- **Floor.** `floor_amendments` is sha-pinned, DEC-named and additive-only; the amended bytes were read in full in both review rounds; `.claude/` is owned by the maintainer in CODEOWNERS, so a row cannot merge without that review.
- **Error handling and records.** Refusals exit 2 before any write (seeder § 5.4); took-effect FAILs pause the arm and leave the row `infrastructure_error`; the smoke evidence is copied under the tracked reports directory with the denials attributed by time window.

## Changes Required

None.

## Observations

- **MEDIUM** (confidence: high) `.claude/data/floor.yaml:58` — the floor amendment lets a floor file differ from origin/main at a pinned sha, so an actor with branch write access could add a row for `adversarial-review-gate.sh`, bump `FLOOR_SHA256` and insert an early exit without deleting a line (dissent DISS-C-004; the lead's own caveat in DEC-0946). Failure: when such a row and a zero-deletion weakening land on a branch and nobody reads the amended bytes, then floor-snapshot FS-1 passes and the review gate is bypassed for the rest of the cycle while the floor reports intact. Accepted risk with mitigations: CODEOWNERS routes every `.claude/` change to the maintainer; FS-1b/1c keep the row load-bearing; this row's bytes were read line by line in two review rounds and this audit; the row is removed after the merge to main; bead bd-znx6q strengthens FS-1 (the amended file's own suites, a recorded human read).
- **LOW** (confidence: medium) `evals/harness/ablation-grade.sh:1945` — the verdicts' run id defaults to the run directory's basename and the binding covers the citation reference, not the finding text (dissent DISS-C-001, downgraded: the sha binds file, anchor and id, and `--run-id` exists). Failure: when two batches hold run directories with the same basename and the operator relies on the default, then verdicts of one run bind to the other's pairs. Follow-up bd-afz2p (document the default and refuse a run id that another batch already used in the same verdicts file).
- **LOW** (confidence: medium) `evals/harness/lib/corpus-seed.sh:495` — `write_layout` does not itself assert that every output path resolves under the fixture directory; it relies on the caller's refusal (dissent DISS-C-003; today every caller refuses first). Failure: when a future caller passes an unchecked path, then the layout writer creates files outside `--out`. Follow-up bd-868s1 (defense in depth).
- **LOW** (confidence: high) `evals/harness/lib/corpus-seed.sh:136` — the record seeder's redaction replaces a multi-line private-key block with one token, shifting every later line of that file and of head.diff (dissent DISS-C-005). Failure: when a seeded record repository holds a multi-line test key in a reviewed file, then fix regions and the crediting window below the block are misaligned by the block's height. Follow-up bd-868s1 (redact line by line).
- **LOW** (confidence: medium) `evals/harness/pipeline-run.sh:330` — the phase containers are not started with `--cap-drop ALL` or `no-new-privileges` (dissent DISS-C-007; D4 noted the same). Failure: when a profile or a future launcher change grants NET_ADMIN to the sandbox, then a process inside it can flush the guard's rules while egress.json still records enforced true. Follow-up bd-vlgk1.
- **LOW** (confidence: medium) `evals/harness/ablation-grade.sh:2012` — a rewritten verdicts file leaves no record of what was previously judged beyond the file hash in each grade (dissent DISS-C-008). Failure: when rows are deleted or a blind flag flipped and the grade re-run, then grade.json shows a clean effective set and only an older grade.json would reveal the change. Follow-up bd-afz2p (verdicts files travel with the grades on the record branch; the header says so).

## Fixed in this round

- Dissent DISS-C-006 (low): `LOA_SUPERVISOR_CGROUP_FILE` let a production environment skip the supervisor's linger check; the knob is now honoured only under the bats marker (`evals/harness/lib/batch-supervisor.sh`, commit `f63b4e92a`; `batch-supervisor.bats` 13/13).

## Rejected dissent payloads

- DISS-C-002 (medium, "repository-derived text reaches task.yaml unquoted"): rejected. The only task writer is `lib/corpus-seed.sh` `write_tasks`, whose `what` argument is a fixed template of the record seeder (`record fixture pr-NN (sprint-N round 1; N label(s); hidden manifest)` with a validated fixture id and two integers); the external seeder writes no task file, and its PR title and body go to `PR.md` only after control characters are stripped.

## Spend and records

- Sprint spend USD 20.88 of the USD 40 share (two smoke launches); no model call by any implementer.
- Mandatory gates that may never be quarantined (sdd § 7.3): egress isolation (22/22 with real containers, CI eval job green), mount provenance (clauses e–g green in both runs; f failed as designed), writer tool disabling (unchanged), the finding-clause blocking rule (verdict-derive, now fail-closed on fences).

*Generated by Paranoid Cypherpunk Auditor*
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":5},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-274","ts":"2026-10-24T13:08:21Z"} -->
