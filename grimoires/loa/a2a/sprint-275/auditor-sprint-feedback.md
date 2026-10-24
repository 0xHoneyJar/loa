# Sprint 275 (cycle-133 Sprint 4) — Security Audit

**Auditor:** lead (Fable 5.1) as the Paranoid Cypherpunk Auditor · **Dissent run 2 of 3 for this sprint:** `adversarial-audit.json` beside this file (`--type audit`; gpt-5.5-pro clean, claude-headless companion succeeded; 9 payloads: 3 medium and 6 low, all accepted — 8 fixed in this round, 1 fixed forward with the live artefact noted) · **Review:** `engineer-feedback.md` round 2 APPROVED after `9fb44fe10` · **Fixes reviewed:** `37547f3a4` · **Scope read:** the sweep tooling (`.claude/scripts/beads/sweep-{inventory,apply,sample}.sh`, `tests/unit/sweep-tools.bats` SW-1 … 20), the live sweep's artefacts (`a2a/sprint-275/sweep/`), the release metadata commit `f898c739e`.

## Verdict

APPROVED - LET'S FUCKING GO

No critical or high finding. The dissent's three mediums were real gaps in the tool's failure modes (a failing tracker list read as "everything already closed"; a tracker refusal printed with exit 0 read as a close; a sample drawn from older manifests gating nothing) and are fixed with tests; the six lows are fixed or, for the frozen inventory's descriptions, fixed forward with the live artefact documented. The sprint's mutations are confined to the beads tracker, every one is logged and reversible, and the live log shows no forced close and no false "already-closed" row.

## Security checklist

- **Secrets.** No credential touches the sweep path: `br` is a local tracker; the scripts read git and files only. detect-secrets over the sprint's commits: hashes, placeholders and the CHANGELOG's own description of credential patterns. The release notes and README carry no token. The version bump edited the managed header under the bounded zone marker with the integrity hash preserved.
- **Trust boundary.** Manifest rows are agent-produced data: ids must match `^[A-Za-z][A-Za-z0-9-]*-[a-z0-9]+$`; categories an enum; evidence a string without control characters (DISS-C-006, fixed) whose references resolve against the repository with fixed git argv — a commit by `cat-file -e`, a PR number by `log --grep`, a path only as a blob at HEAD (never `.` or a directory; DISS-C-008, fixed); the tracker is called with fixed argv and the evidence text reaches it only inside one reason or comment argument. Temporary files live in a private `mktemp -d` directory (DISS-C-007, fixed).
- **Mutations.** Every tracker mutation is appended to `applied.jsonl` before the next row; the log must parse before any apply (DISS-C-004, fixed); a re-run skips logged ids; a refused closure is logged skipped-blocked and never forced; a tracker that reports a skipped id with exit 0 is treated as the refusal it is (DISS-C-002, fixed); a failing or unparseable `br list` aborts before anything is read as closed (DISS-C-001, fixed). Live log: 174 closes, 154 labels, 1 skipped-blocked, 0 forced, 0 already-closed.
- **The sample gate.** `--apply` now requires the checked sample, whose rows carry the manifests' digest at the draw, and refuses when the manifests changed since; `--no-sample-check REASON` is the explicit, logged override (DISS-C-003, fixed). The live sweep predates the gate: its batch 03 was rewritten after the draw and the lead re-verified every closure of that batch (REPORT.md), which the gate would have required explicitly.
- **File system and portability.** The freeze builds in a temporary directory under the sweep dir and moves it into place; deletes are scoped to the sweep's own batches directory; no path from a manifest row is used as a filesystem path.
- **Integrity.** The scripts are tracked under `.claude/scripts/beads/` through the bounded marker; `checksums.json` and REPO-MAP regenerated; CI's integrity gate caught the one regeneration done while the files were untracked (fixed in `14bad657c`).

## Changes Required

None.

## Observations

- **LOW** (confidence: high) `.claude/scripts/beads/sweep-inventory.sh:1` — the frozen rows no longer carry bead descriptions (DISS-C-005, fixed forward), but this sprint's live inventory under `a2a/sprint-275/sweep/` was frozen with descriptions and travels on the public record branch. Failure: when a bead description names an internal host or a partner, then the record branch publishes it although the credential scan finds nothing. Mitigation recorded: the beads are this repository's own tracker entries, written for the public framework; the lead read the 329 titles and the closure notes; the record build's scan covers credential shapes. Follow-up: strip `description` from the live inventory copy on the record branch if the maintainer prefers (the manifests were validated against the frozen sha, which the record keeps as is).
- **LOW** (confidence: high) `.claude/scripts/beads/sweep-apply.sh:1` — the tooling has no test against a real `br` binary; the suite runs against a stub whose refusal text mirrors the one observed live (`Skipped <id>: blocked by: <ids>`, `epic has N/M open children`). Failure: when a future beads_rust release changes its refusal wording, then a blocked closure is logged failed instead of skipped-blocked (the apply still never forces and still exits 1). Follow-up: one bats case against the installed `br` on a scratch workspace when CI gains the binary.
- **LOW** (confidence: medium) `.claude/scripts/beads/sweep-apply.sh:124` — a path that exists as a blob at HEAD satisfies the evidence resolver, so the second pass and the lead's triage are the controls on a tangential path (review DISS-C-007; the audit's DISS-C-008 narrowed it to blobs). Failure: when an agent cites any real file as evidence for a closure, then the row passes validation and only the sample or the lead's read of the note can catch it. Accepted as designed and documented in the script header.

## Fixed in this round

- DISS-C-001 (medium): `br list` failure or unparseable output is fatal before anything is validated or logged (SW-15).
- DISS-C-002 (medium): a tracker reporting `Skipped … blocked by` or `open children` with exit 0 is a refusal (SW-16).
- DISS-C-003 (medium): the sample gate — `--sample FILE` with the manifests' digest, or a logged `--no-sample-check REASON` (SW-17); `sweep-sample.sh --check --manifests DIR` refuses a stale draw.
- DISS-C-004 (low): a corrupt applied log refuses before any mutation (SW-18).
- DISS-C-006 (low): control characters in evidence are an invalid field (SW-19).
- DISS-C-007 (low): temporary files in a private directory.
- DISS-C-008 (low): path evidence must be a blob, never the tree root or a directory (SW-19).
- DISS-C-009 (low): several verification rows for one id count any disagreement (SW-20).
- DISS-C-005 (low): the inventory carries no description going forward (SW-1); the live artefact is noted above.

## Rejected dissent payloads

None.

## Spend and records

- Sprint spend USD 0 (the sweep agents and the two dissent runs ran on subscription routes); cycle smoke share USD 20.88 of 40; Bridgebuilder share untouched before Task 4.5.
- Mandatory gates that may never be quarantined (sdd § 7.3): unchanged by this sprint and green on the last Shell Tests run.

*Generated by Paranoid Cypherpunk Auditor*
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":3},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-275","ts":"2026-10-24T15:12:34Z"} -->
