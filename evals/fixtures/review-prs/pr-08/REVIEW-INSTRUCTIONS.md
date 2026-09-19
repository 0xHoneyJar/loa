# Review instructions

This workspace holds one pull request against the Loa framework repository, frozen for evaluation.

- `PR.md` — the PR title and description
- `head.diff` — the complete change (unified diff, base → head)
- `base/` — every touched file before the change
- `head/` — every touched file after the change

Review the change as the senior technical reviewer for this repository. There is no sprint plan, beads database, implementation report or `grimoires/loa/a2a/` directory here — the PR files above are the entire input; skip any pre-flight step that needs them and do not ask questions.

Write your review to `review.md` in this directory using the Write tool. Cite every finding as `head/<path>:<line>` with line numbers taken from the `head/` files. Follow your reviewer skill's output format and end the file with its machine-readable verdict trailer.
