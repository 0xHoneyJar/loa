# Task: review a pull request

The directory `pr/` holds one pull request against a repository of shell and Python scripts, frozen for evaluation. The change: sprint 256 of the repository's agent framework — inert controls repaired or retired, a file-authoritative run position, a fail-closed heredoc classifier, capability profiles and a prose-diet fallback (68 files: hooks, scripts, skills, data and reference documents under `.claude/`).

The pull request is laid out as:

- `pr/PR.md` — the title and description
- `pr/head.diff` — the complete change (unified diff, base to head)
- `pr/base/` — every touched file before the change
- `pr/head/` — every touched file after the change

Review the change as the senior technical reviewer for the repository: find the defects it introduces and decide whether it can merge. Do not change any file under `pr/`.

## Output contract

Write your review to `review.md` at the repository root (a review workflow that also writes its own report files may do so; `review.md` follows this shape regardless):

- one finding per line, in the form `head/<path>:<line> — <description>`, where `<path>` is the file's path under `pr/head/` and `<line>` is a line number in that file;
- a final line that is exactly `Verdict: APPROVED` or `Verdict: CHANGES_REQUIRED`.
