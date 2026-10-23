# run-mode Completion and PR Creation (`/run sprint-N`)

## Push Mode Resolution

Priority: `--local` > `--confirm-push` > config > default (`AUTO`). Delegate entirely to ICE as
the single source of truth:
- `--local` → `run-mode-ice.sh should-push local`
- `--confirm-push` → `run-mode-ice.sh should-push prompt`
- neither → `run-mode-ice.sh should-push` (reads `run_mode.git.auto_push` from config: `true` →
  `AUTO`, `false` → `LOCAL`, `prompt` → `PROMPT`; default `true`)

Record the resolved mode: `jq --arg mode "$push_mode" '.options.push_mode = $mode'` on
`.run/state.json`.

## LOCAL mode

1. Atomically set on `.run/state.json`:
   `.completion = {"pushed": false, "pr_created": false, "pr_url": null, "skipped_reason": "local_mode"} | .state = "JACKED_OUT"`.
2. Report:
   → verbatim block: `resources/render-templates.md` §local-mode-report

## PROMPT mode

1. Display the same summary (branch/commits/files) and use the `AskUserQuestion` tool with two
   options: "Push and create PR" (proceeds to AUTO-mode flow below) or "Keep local only" (declined
   flow). `AskUserQuestion` is invoked by Claude directly — no bash equivalent.
2. Declined flow: same atomic update as LOCAL mode but `skipped_reason: "user_declined"`, and
   report:
   → verbatim block: `resources/render-templates.md` §prompt-declined-report

## AUTO mode

1. Push: `.claude/scripts/run-mode-ice.sh push origin "$branch"`.
2. Build the PR body:
   → verbatim block: `resources/render-templates.md` §auto-mode-pr-body
3. Create the draft PR: `pr_url=$(.claude/scripts/run-mode-ice.sh pr-create "Run Mode: $target implementation" "$body")`.
4. Atomically set: `.completion = {"pushed": true, "pr_created": true, "pr_url": $url, "skipped_reason": null} | .state = "JACKED_OUT"`.
5. Report: "[COMPLETE] All checks passed! ✓ PR created: $pr_url" then "[JACKED_OUT] Run complete."

## Deleted Files Tree (PR body)

Render `.run/deleted-files.log` for a PR body: if the log is missing or empty, emit
   "No files deleted during this run." Otherwise:
   - Count lines: `wc -l < .run/deleted-files.log`.
   - Emit header `## 🗑️ DELETED FILES - REVIEW CAREFULLY`, then `**Total: {count} files deleted**`.
   - Inside a fenced code block, for each unique file (`cut -d'|' -f1 .../deleted-files.log | sort`),
     print `{dirname}/` then `└── {basename} ({sprint}, {cycle})` (metadata via
     `grep "^$file|" | cut -d'|' -f2,3`).
   - Close the fence, then append `> ⚠️ These deletions are intentional but please verify they are correct.`
