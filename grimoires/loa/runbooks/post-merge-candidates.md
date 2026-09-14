# Inspecting and publishing post-merge candidates

The post-merge workflow prepares a release without pushing tags, creating
releases, or posting PR comments. The default script invocation and
`--generate` have the same behavior. Generation requires a clean tracked
checkout at the specified merge commit. It creates local commits for
generated files and records their exact target commit and tree.

The `release-candidate-<merge SHA>` Actions artifact contains:

- `post-merge-candidate.json`: version classification evidence, origin, target,
  release body, notification body, and preparation state.
- `post-merge-candidate.patch`: changes made after the merge commit.
- `post-merge-candidate.bundle`: Git objects needed to inspect the target.
- `post-merge-candidate.sha256`: digest of the exact candidate JSON.
- `post-merge-state.json`: phase results.

Inspect the patch, candidate bodies, semver source and target tree. A non-empty
commit history without classifying metadata stops generation; it does not
silently become a patch release. A repository with classified history and no
version source starts at `0.1.0`.

Use an isolated clean checkout to recover a CI candidate. Verify the bundle,
fetch its `HEAD` into a new local branch, and inspect that branch before checking
out the candidate's exact `target_commit`. Restore the candidate JSON beneath
`.run/`. The checkout's origin must match `remote_origin` in the candidate,
and its single effective push URL must match `remote_push_url`.
Neither fetching the bundle nor creating a local branch publishes a release.

After approving the inspected bytes, run from that exact checkout:

```bash
.claude/scripts/post-merge-orchestrator.sh \
  --publish .run/post-merge-candidate.json \
  --approve-sha256 <approved-candidate-sha256>
```

The publisher checks the digest, checkout commit/tree, origin and push
destination before publication. It binds every GitHub API request to the host
and repository parsed from the approved HTTPS or SSH origin. It reads back
the pushed annotated tag and the returned release and comment identifiers,
including the comment's parent PR. A failed command, missing identifier or mismatched
read-back returns nonzero and records `FAILED`. Publication can fail after an
earlier object was published; inspect the state receipt before retrying.
Each retry restores publication inputs from the approved candidate and retains
only the comment identifier needed to avoid a duplicate after failed readback.

The notification contains the preparation results that were inspected.
Publication results live in the state receipt; pending preparation rows do not
claim that publication succeeded. `DONE` records verified publication.
`PREPARED` records generation only.

The workflow no longer requires a model API key or write-capable GitHub token
to prepare candidates. Explicit publication needs normal repository permissions.
