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
- `post-merge-ledger.patch`: (cycle merges, candidate schema 2) the ONE text
  diff of `grimoires/loa/ledger.json` that archives the merged cycle; the
  candidate seals its sha256 and the deterministic ledger commit id.
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

After approving the inspected bytes, run from that exact checkout — a FULL
(non-shallow) clone whose HEAD is the merge commit, the candidate's
`generated_head` or the sealed ledger commit `new`, with
`post-merge-ledger.patch` restored beside the candidate under `.run/`:

```bash
.claude/scripts/post-merge-orchestrator.sh \
  --publish .run/post-merge-candidate.json \
  --approve-sha256 <approved-candidate-sha256>
# exit 0 published; 1 failed mid-run (read the state receipt); 2 refused at
# preflight (digest, mutation, ancestry, conflicting tag, v1 candidate);
# 3 published tag + release, ledger fast-forward DEFERRED (main moved):
.claude/scripts/post-merge-orchestrator.sh \
  --publish .run/post-merge-candidate.json \
  --approve-sha256 <approved-candidate-sha256> --ledger-only
```

Candidate schema 2 (cycle-133 Sprint 272, sdd.md C-3) seals
`target_commit = merge_sha`, the target tree, `main_ref`, the release title and
notes digest, the ledger patch digest and `ref_updates[{ref, expected_old:
merge, new}]`; the candidate file is its own RFC 8785 form and the digest is
the SHA-256 of its bytes. The tag is created ON THE MERGE COMMIT and the
publisher verifies, on a fresh fetch of the push URL's `main`, that the merge
is an ancestor — at preflight (exit 2) and again before the tag, release,
ledger and notify steps (exit 1) — so a published tag is always reachable
from `main` (the rc.6/rc.7 defect: tags on a generated commit nobody merged).
An existing tag is accepted only if it is annotated on the merge with the
subject `Release <tag>`; any other tag of that name refuses (exit 2). The
ledger fast-forward pushes the sealed commit with
`--force-with-lease=refs/heads/main:<observed>` only when `main` still equals
the merge; otherwise the deferral writes `.run/post-merge-ledger-deferred.{json,patch}`
and exits 3, and `--ledger-only` re-applies the same patch onto the
then-current `main` under the same lease. A schema-1 candidate refuses with a
regeneration message; `--allow-v1 "<reason>"` runs the legacy path (no
ancestry gate) and records the reason. Generated non-ledger changes (a
CHANGELOG fill, markers, ground truth) stay local and are sealed as
`unpublished_paths`; they are warned about at generate and publish and ride
the next pull request.

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

## Pre-release candidates (`X.Y.Z-rc.N`)

The pipeline increments an existing pre-release on its own (a merge on the
`v2.0.0-rc.1` tag prepares `v2.0.0-rc.2`). Entering a pre-release from a release
tag and promoting out of one are operator decisions, and the operator states
them in `CHANGELOG.md` — no flag, no config key (sprint-bug-240,
`semver-bump.sh` `changelog_prerelease_transition`).

The signal is the topmost versioned heading of `CHANGELOG.md`, honoured only
while that heading is untagged:

| Current tag | Topmost heading | Commits warrant | Prepared version |
|-------------|-----------------|-----------------|------------------|
| `v1.202.1` | `## [2.0.0-rc.1] — …` | `2.0.0` (breaking) | `2.0.0-rc.1` (enter) |
| `v1.202.1` | `## [2.0.0-rc.1] — …` | `1.203.0` (no breaking) | `1.203.0`; a `WARN` names the ignored heading |
| `v2.0.0-rc.1` | `## [2.0.0-rc.1] — …` (tagged) | anything | `2.0.0-rc.2` (increment, unchanged) |
| `v2.0.0-rc.3` | `## [2.0.0] — …` | anything | `2.0.0` (promote) |

To cut a release candidate, the PR that will be merged moves the `[Unreleased]`
content under `## [2.0.0-rc.1] — <date> — <name>`, leaves `[Unreleased]`
empty, and sets `.loa-version.json` `framework_version` (and the README
version references via `sync-readme-version.sh --apply`) to the same string.
`semver-bump.sh --from-tag` on that branch already reports
`next: 2.0.0-rc.1` with `prerelease_transition.kind: enter`; the candidate
carries `tag: v2.0.0-rc.1` and `prerelease: true`, and publication creates
the GitHub release with `prerelease: true` and verifies the flag on read-back
(a release created by hand without the flag fails publication). The
`version_bump` phase stamps the same prerelease string into both framework
markers. Later fixes merged normally prepare `-rc.2`, `-rc.3`, …

To promote, a PR moves (or rewrites) the rollup under `## [2.0.0] — <date> —
<name>` above the `-rc.N` headings and sets the markers to `2.0.0`; the next
merge prepares `2.0.0` with `prerelease: false`, `prerelease_transition.kind:
promote`. The rc headings stay in the CHANGELOG as history.
