# Task brief

## Criterion

review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict

## Task

# Task: review a pull request

The directory `pr/` holds one pull request against a repository of shell scripts, tests and documentation, frozen for evaluation. The change: sprint-257 — advisory open-weight voices, local_voices posture, Bridgebuilder trusted configuration and exit codes, E2E.

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
