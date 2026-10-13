**[2/3] Review by openai (gpt-5.5-pro)**

I’m reading this as a review-only pass and focusing on concrete behavioral defects in the diff, not style. The highest-signal risks are in the new shell gates and validators because they become enforcement points for the whole feature.
<!-- bridge-findings-start -->
```json
{
  "schema_version": 1,
  "findings": [
    {
      "id": "RTC-001",
      "title": "Configured red-test commands bypass the runner safety checks",
      "severity": "HIGH",
      "category": "security",
      "file": ".claude/scripts/red-test-check.sh:176",
      "description": "check_runner returns immediately when the test argv exactly matches red_test.command or red_test.setup, before applying the hard denials for shells, env, inline interpreter code, make variable assignment, cargo --config, npm --script-shell, and similar runner-escape flags. Because .loa.config.yaml is read from the checked-out branch and config drift only emits a WARN, a reviewed change can opt itself into an otherwise-refused command shape.",
      "suggestion": "Run the hard-deny checks before honoring red_test.command/red_test.setup, or make configured commands pass the same allowlist validation. Consider failing when .loa.config.yaml changed on the branch unless an explicit reviewer override is provided.",
      "confidence": 0.92
    },
    {
      "id": "SPK-001",
      "title": "Spike content can still be copied into non-spike branches",
      "severity": "MEDIUM",
      "category": "correctness",
      "file": ".claude/hooks/safety/block-destructive-bash.sh:879",
      "description": "The SP-1 rule states that spike content never enters another branch, but the implementation explicitly leaves gaps for commands such as git switch -c new spike/x, git worktree add -b new <dir> spike/x, git show spike/x:path > file, and git diff spike/x | git apply. Those paths copy spike branch content into a normal branch without using merge/cherry-pick, bypassing the intended spike isolation.",
      "suggestion": "Block branch/worktree creation from spike refs and common file-copy paths from spike refs, or narrow the documented guarantee from 'never enters another branch' to only 'merge/PR flows are blocked' and adjust the PRD/SDD acceptance criteria.",
      "confidence": 0.86
    },
    {
      "id": "CHART-001",
      "title": "Map epic creation is not idempotent after a partial write",
      "severity": "MEDIUM",
      "category": "reliability",
      "file": ".claude/scripts/chart-ticket.sh:187",
      "description": "op_epic creates the bead before writing the map doc, and on rerun it only reuses state when the doc already exists. If br create succeeds and the script dies before the doc is written, the next run creates another map epic for the same slug, leaving duplicates and no deterministic recovery path.",
      "suggestion": "Before creating an epic, look up an existing map epic by slug/label/description and reuse it. Alternatively write a pending marker or make br creation idempotent by external_ref/slug before writing the final map doc.",
      "confidence": 0.78
    },
    {
      "id": "CHART-002",
      "title": "Research scope check can miss same-timestamp writes",
      "severity": "LOW",
      "category": "correctness",
      "file": ".claude/scripts/chart-ticket.sh:585",
      "description": "research-end detects writes under .run and .beads with find -newer \"$m\". On filesystems with coarse timestamp resolution, files modified in the same timestamp tick as the dispatch marker may not compare newer and can evade the check. The tests work around this with sleep, but the production path does not.",
      "suggestion": "Capture a pre-run listing with mtimes and hashes, or create the marker and wait/force a timestamp boundary before dispatch. A hash-based before/after snapshot is more reliable than -newer for this guard.",
      "confidence": 0.72
    },
    {
      "id": "DEC-001",
      "title": "Decision ledger writer has strong append-only safeguards",
      "severity": "PRAISE",
      "category": "reliability",
      "file": ".claude/scripts/lib/dec-write-lib.sh:384",
      "description": "The writer uses a lock, writes a temp copy, validates row count/id preservation, rejects unrelated row edits, runs the artifact validator against the candidate with the current file as base, and only then renames. That is a solid implementation choice for a tracked ledger that many commands will depend on.",
      "suggestion": "Keep this verification boundary as the single write path for future decision-ledger operations.",
      "confidence": 0.94
    }
  ]
}
```
<!-- bridge-findings-end -->
