# s1-b — Sprint 1 Task 1.3, release publish (C-3, FR-3, bd-kwloh)

Model: global.anthropic.claude-opus-5-5. Worktree `loa-wt-s1b` at 8ef474af3. Patch `~/.cache/loa/cycle-133/patches/s1-b.patch` (2 files, +1172 −63). Nothing committed or pushed. No GitHub setting changed.

## What was built (`.claude/scripts/post-merge-orchestrator.sh`)
- Header (:9–50) and `usage`: v2 contract, `--ledger-only`, `--allow-v1 REASON`, exit codes 0/1/2/3.
- `prepare_candidate` (:1962) writes schema 2, with `target_commit = merge_sha`. It seals `target_tree`, `target_on_main`, `main_ref`, `generated_head`, `release_title`, `release_notes_sha256` and `unpublished_paths`. For a cycle merge it adds `ledger_cycle`, the `.run/post-merge-ledger.patch` file and its sha, `ledger_commit` and `ref_updates[{ref, expected_old: merge, new}]`. The file is its own RFC 8785 form, so its SHA-256 is the approval digest.
- `build_ledger_commit` (:1701) applies the patch in a temporary index and checks the transition. It commits with the recorded identity, which makes the commit id deterministic.
- `validate_ledger_patch` (:1643) allows one text diff of `grimoires/loa/ledger.json` only. `ledger_transition_ok` (:1672) allows one cycle going active to archived, changing only `status`, `archived_at` and a nulled `active_cycle`.
- `validate_candidate_v2` (:1896) checks the schema, canonical bytes, notes sha and patch sha. It rebuilds the ledger commit, which must equal `new`.
- `verify_main_ancestry` and `publish_gate` (:1601) fetch the push URL's main into a private ref and run `merge-base --is-ancestor`. This runs at preflight (exit 2) and before the tag, release, ledger and notify steps (exit 1).
- `phase_tag` (:1062) accepts an existing tag only if it is annotated on the merge with subject "Release <tag>". Otherwise it exits 2.
- The release read-back also matches the sealed title.
- `phase_ledger` (:1831): if the approved commit is on main or the cycle is archived, it is done. If main equals the merge, it pushes with `--force-with-lease=refs/heads/main:<observed>`. Any other main defers.
- A rejected push defers as `lease_failed` (main moved) or `push_rejected` (main unchanged). The deferral writes `.run/post-merge-ledger-deferred.{json,patch}` and exits 3.
- `publish_ledger_only` (:1852) re-applies the patch onto the then-current main under the same lease.
- `publish_candidate` (:2076) refuses v1. `--allow-v1` runs the legacy path and records `.allow_v1.reason`. HEAD must be the merge, `generated_head` or `new`. Phase order is tag, release, ledger, notify. `.run/post-merge-progress.json` is the mutable record.
- `jcs_file` (:1549) uses `lib/jcs.sh` when rfc8785 is present, otherwise the exact stdlib form.

## Tests (`tests/unit/post-merge-publication.bats`)
- Setup keeps the `v1.0.0` tag pattern and is now hermetic for KF-034 / bd-fpt3, with an empty `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_NOSYSTEM=1`. The merge carries its `[1.0.1]` CHANGELOG heading and an active ledger cycle. Main is pushed to the bare remote.
- Added 26 `c133 v2:` cases (:413–739). Adapted the empty-Unreleased case (:175) and the rc fixture push. Added a reachability assertion to the approved-publish case (:206).
- **Red on the old code:** 26 of 47 failed. The added reachability assertion also failed: `merge-base --is-ancestor v1.0.1 refs/heads/main`. That is the rc.6/rc.7 defect.
- **Reproducing test:** `c133 v2: ancestor success publishes a tag reachable from main and fast-forwards the ledger`.
- **Green:** 48/48 under the host's own git config, with no KF-034 workaround. All orchestrator consumers pass under isolated config: `post-merge-*.bats`, the i697 integration suite and `mount-workflow-scaffold`, 169/169. The baseline was 128/128.
- The raw-sha256sum, swallowed-jq and knob-reader lints are clean. `shellcheck` is not installed.
- The real ledger (`cycle-133-follow-through`) passes the transition rule and a tampered copy is refused (scratch check).

## Acceptance criteria (sprint.md Task 1.3)
- Candidate v2 sealed and canonicalised, with progress beside it. **Met** (:413).
- v1 refusal with a regeneration message; `--allow-v1` with a logged reason. **Met** (:713, :722, :732).
- Digest and mutation refusal. **Met** (:619–661, :213).
- Ancestry on a fresh fetch, re-verified per step. **Met** (:434, :519, :530).
- Existing tag: identity match accepted, conflict refused. **Met** (:543, :556, :569).
- Release. **Met** (:595, existing cases).
- Ledger patch validated, then pushed with the lease. **Met** (:671, :685, :434).
- Lease failure gives deferred plus the file; `--ledger-only` completes it. **Met** (:477, :448, :490, :512).
- Recovery after a crash after the tag, after the release, and after the ledger push. **Met** (:581, :595, :607).
- Tag reachable from main, with KF-034 setup kept. **Met**.
- Branch protection read. **Met** (below).
- PRD FR-3 AC1, "moved main → refusal". **Met under the SDD rule:** a main without the merge refuses (:519); a descendant main publishes and defers the ledger (:448).
- PRD AC3, `branch --contains v2.0.0-rc.8`. **Not in Sprint 1.** It belongs to the C-14 ship.

## Branch protection (read-only `gh api …/branches/main/protection`, 2026-10-24)
- `enforce_admins: false`. Strict required checks: Template Protection, Validate Framework Files, Lint Markdown, Lint YAML, Shell Tests. One approving review is required.
- `allow_force_pushes: false`. No restrictions or lock, and no rulesets. The token is admin.
- **A direct fast-forward by an admin is permitted,** because admins bypass checks and review and the ledger update is a fast-forward.
- A non-admin token's rejection becomes `push_rejected`, so deferral is the fallback.

## Judgment calls
- **Generated non-ledger changes** (a CHANGELOG fill, markers, ground truth) stay local. They are sealed as `unpublished_paths` and warned about at generate and publish. A refusal was rejected: it broke 13 cases in suites outside my ownership and contradicts "keep the existing --generate behaviour". Folding them into the patch was rejected because C-3 restricts it to `ledger.json`.
- **`--publish` pushes only the approved commit** (`expected_old = merge`). Any other main defers, descendants included, because a re-applied commit is not named in the candidate. `--ledger-only` is the explicit re-apply.
- **A temporary index instead of a detached worktree:** same tree and commit, no checkout I/O, no debris after a crash. The operator's checkout and index are untouched.
- **Ledger commit identity:** the operator's git `user.name`/`user.email`, dated at the merge's committer time `+0000`. The message is "chore(ledger): archive <cycle> after merge", with `--no-gpg-sign` and UTF-8 pinned. Generation-time dates (not reproducible) and a bot identity were rejected.
- **The candidate file is its own JCS form,** and the digest is the SHA-256 of its bytes. Publish requires byte equality with re-canonicalisation. `--approve-sha256` and the workflow's `sha256sum` keep working, and any byte change refuses.
- **Stdlib canonicaliser fallback** when `lib/jcs.sh` or rfc8785 is missing. Neither is available to the post-merge.yml runner, downstream mounts or the other suites' fixtures. It is exact for the candidate's value domain and refuses floats, big integers and lone surrogates. A conformance case compares it with rfc8785, and a disagreement can only refuse.
- **Tag identity:** annotated, object = merge, the tag name, and subject "Release <tag>". A signature is tolerated; a lightweight tag is refused. This also applies to local tags and to v1.
- **Release identity adds the title** in v2 only, so v1 subtitled releases still match.
- **Remote reads use the approved push URL** into `refs/loa/post-merge/observed-{main,tag}`, not FETCH_HEAD.
- **A push rejected while main is unchanged** defers (exit 3), the SDD's documented default.
- **Exit codes:** deferral 3 in both modes. Conflicting tag 2. Ancestry 2 at preflight, 1 mid-run. Release mismatch after the tag 1.
- **Checkout binding:** HEAD must be the merge, `generated_head` or `new`, and the merge tree must equal `target_tree`, so approved code publishes.
- **`--allow-v1` takes a REASON;** a blank one exits 2. The v1 path is legacy, without the ancestry gate.
- **`main_ref` is sealed as `refs/heads/main`;** other default branches refuse at preflight, which is out of scope.
- **Cycle already archived on main** counts as done (`already_archived`), with no push.
- **Fixture:** the merge carries its release content and the git config is hermetic.

## What the lead must do
1. **`post-merge.yml`:** upload `.run/post-merge-ledger.patch` in both "Retain inspectable release candidate" steps, or an artifact publish refuses. Optionally install `rfc8785==0.1.4`.
2. **`archive-cycle.sh`:** discovering the deferred file is not built (outside my ownership). It can call `--publish <candidate> --approve-sha256 <digest> --ledger-only`; the deferred file records both values.
3. **Stale v1 recipe text:** update `deploying-infrastructure/SKILL.md` (about :297–345) and `runbooks/post-merge-candidates.md`. Publish from a full clone at the merge or the generated head, keep the patch beside the candidate, and run `--ledger-only` on exit 3.
4. CHANGELOG, checksums, REPO-MAP.
5. **KF-034:** run `recur` (22 reds at baseline here) and add an attempt row: the hermetic setup fixes this suite, and the other post-merge suites still need `GIT_CONFIG_GLOBAL=/dev/null`.
6. **rc.8:** the PR carries the heading and markers. Use `--skip-gt` unless ground truth is current, and publish from a non-shallow clone.
7. Close bd-kwloh, naming the reproducing test.
8. `grimoires/loa/a2a/sprint-272/reviewer-b.md` is gitignored and not in the patch. It is a copy of this report in the worktree.
