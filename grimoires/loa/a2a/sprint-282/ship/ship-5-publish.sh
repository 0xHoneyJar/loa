#!/usr/bin/env bash
# ship-3-publish.sh — recover the post-merge candidate in an isolated full clone and publish 2.0.0-rc.9 through C-3.
# Steps mirror grimoires/loa/runbooks/post-merge-candidates.md. Stops before --publish unless APPROVE=1 is set after inspection.
set -euo pipefail
source ~/.cache/loa/cycle-137/ship/MERGE
W=~/.cache/loa/cycle-137/publish-checkout-rc9; A=~/.cache/loa/cycle-137/candidate-rc9; mkdir -p "$A"
cd /home/merlin/Documents/thj/code/loa
run_id="$(gh run list --branch main --workflow post-merge.yml --limit 10 --json databaseId,headSha,status,conclusion --jq ".[] | select(.headSha==\"$MERGE_SHA\") | .databaseId" | head -1)"
[[ -n "$run_id" ]] || { echo "no post-merge run for $MERGE_SHA yet" >&2; exit 3; }
echo "post-merge run $run_id: $(gh run view "$run_id" --json status,conclusion --jq '"\(.status) \(.conclusion // "-")"')"
[[ "$(gh run view "$run_id" --json status --jq .status)" == completed ]] || { echo "post-merge run still in progress" >&2; exit 3; }
if [[ -f "$A/post-merge-candidate.sha256" && -f "$A/post-merge-candidate.json" ]]; then echo "artifact already downloaded in $A (kept; digest re-verified below)"; else gh run download "$run_id" --name "release-candidate-$MERGE_SHA" --dir "$A" 2>&1 | tail -1; fi
ls "$A"
digest="$(awk '{print $1}' "$A/post-merge-candidate.sha256")"
[[ "$(sha256sum "$A/post-merge-candidate.json" | awk '{print $1}')" == "$digest" ]] || { echo "digest mismatch between the sha256 file and the candidate json" >&2; exit 1; }
echo "candidate digest $digest"
jq -c '{schema_version, version: (.version // .target_version // .release_tag), prerelease, target_commit, merge_sha, main_ref}' "$A/post-merge-candidate.json" 2>/dev/null | cut -c1-300
if [[ ! -d "$W/.git" ]]; then git clone -q --no-single-branch https://github.com/0xHoneyJar/loa.git "$W"; fi
cd "$W"; git fetch -q origin main; git bundle verify "$A/post-merge-candidate.bundle" 2>&1 | tail -1; git fetch -q "$A/post-merge-candidate.bundle" HEAD:refs/heads/candidate-rc9 2>/dev/null || true
target="$(jq -r '.target_commit // .merge_sha' "$A/post-merge-candidate.json")"; echo "target_commit $target"
git checkout -q "$target"; mkdir -p .run; cp "$A/post-merge-candidate.json" .run/; [[ -f "$A/post-merge-ledger.patch" ]] && cp "$A/post-merge-ledger.patch" .run/
# the publisher compares the clone's origin and push URL byte-for-byte with the candidate (CI recorded the URL without .git)
ro="$(jq -r .remote_origin "$A/post-merge-candidate.json")"; rp="$(jq -r .remote_push_url "$A/post-merge-candidate.json")"
[[ "$ro" == https://github.com/0xHoneyJar/loa* && "$rp" == https://github.com/0xHoneyJar/loa* ]] || { echo "unexpected remote in the candidate: $ro / $rp" >&2; exit 1; }
git remote set-url origin "$ro"; git remote set-url --push origin "$rp"; echo "origin set to $(git remote get-url origin) (push $(git remote get-url --push origin))"
[[ "${APPROVE:-}" == 1 ]] || { echo "inspect $A then re-run with APPROVE=1"; exit 0; }
set +e
bash .claude/scripts/post-merge-orchestrator.sh --publish .run/post-merge-candidate.json --approve-sha256 "$digest"; rc=$?
set -e
echo "publish rc=$rc"
if [[ $rc -eq 3 ]]; then bash .claude/scripts/post-merge-orchestrator.sh --publish .run/post-merge-candidate.json --approve-sha256 "$digest" --ledger-only; echo "ledger-only rc=$?"; fi
git fetch -q origin main --tags; echo "tag on main: $(git branch -r --contains v2.0.0-rc.9 | tr '\n' ' ')"; gh release view v2.0.0-rc.9 --json tagName,isPrerelease,url --jq '"\(.tagName) prerelease=\(.isPrerelease) \(.url)"'
