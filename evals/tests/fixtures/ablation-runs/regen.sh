#!/usr/bin/env bash
# regen.sh — rebuild the fixture run directories under runs/ (cycle-130 Sprint 258)
#
# Each fixture is a real evals/harness/pipeline-run.sh run (host executor) against
# the stub CLI (../claude-stub-pipeline.sh) and the stub mount library
# (../mount-lib-stub.sh), using suite.yaml and the tasks under tasks/. The sandbox's
# own .git and the snapshot bundles are dropped (no nested repositories in the
# tracked tree); absolute paths are rewritten to /fixture and /home/operator.
# grade.json files and MANIFEST.json are written here as Sprint 259's grader and
# run-ablation.sh would shape them (SDD §3.4, §3.6).
#
# Usage: evals/tests/fixtures/ablation-runs/regen.sh
# Consumers: evals/tests/ablation-row.bats, evals/tests/took-effect.bats
set -euo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$HERE/../../../.." && pwd)"
GEN="$(mktemp -d "${TMPDIR:-/tmp}/abl-fixture.XXXXXX")"
trap 'chmod -R u+rwx "$GEN" 2>/dev/null; find "$GEN" -mindepth 1 -delete 2>/dev/null; rmdir "$GEN" 2>/dev/null || true' EXIT

# a temporary copy of the harness with the stub mount library at the literal path
# pipeline-run.sh sources (no environment override exists: eval.yml trust boundary)
H="$GEN/h/evals/harness"
mkdir -p "$H/lib"
cp "$REPO_ROOT/evals/harness/pipeline-run.sh" "$REPO_ROOT/evals/harness/fingerprint.sh" "$H/"
cp -a "$REPO_ROOT/evals/harness/lib/phase-prompts" "$H/lib/"
cp "$FIX/mount-lib-stub.sh" "$H/lib/sandbox-mount.sh"
PR="$H/pipeline-run.sh"

# the pinned source tree the mount is copied from (tiny stand-in)
mkdir -p "$GEN/src/.claude/loa"
for s in planning-sprints implementing-tasks reviewing-code auditing-security; do
  mkdir -p "$GEN/src/.claude/skills/$s"
  printf -- '---\nname: %s\neffort: xhigh\n---\nbody\n' "$s" > "$GEN/src/.claude/skills/$s/SKILL.md"
done
echo loa > "$GEN/src/.claude/loa/CLAUDE.loa.md"
printf 'flatline_protocol:\n  enabled: true\n  code_review:\n    enabled: true\n  security_audit:\n    enabled: true\n' > "$GEN/src/.loa.config.yaml"
( cd "$GEN/src" && git init -q && git add -A && git -c user.email=f@f -c user.name=f -c commit.gpgsign=false commit -qm fixture )

cat > "$GEN/claude" <<EOF
#!/usr/bin/env bash
set -a; . "$GEN/stub.env"; set +a
exec "$FIX/claude-stub-pipeline.sh" "\$@"
EOF
chmod +x "$GEN/claude"

export LOA_EVAL_WATCHDOG_POLL_S=0.1
export LOA_EVAL_PRICING_JSON='{"global.anthropic.claude-opus-5-5":{"input_per_mtok":4000000,"output_per_mtok":20000000},"global.anthropic.claude-fable-5-1":{"input_per_mtok":10000000,"output_per_mtok":50000000}}'
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"

OUT="$HERE/runs"
chmod -R u+rwx "$OUT" 2>/dev/null || true
find "$OUT" -mindepth 1 -delete 2>/dev/null || true
mkdir -p "$OUT"

run_one() {  # run_one <name> <arm> <task> <stub.env lines…>
  local name="$1" arm="$2" task="$3" rc=0; shift 3
  printf '%s\n' "$@" > "$GEN/stub.env"
  "$PR" --task-yaml "$HERE/tasks/$task/task.yaml" --arm "$arm" --run-dir "$GEN/runs/$name" \
    --run-id "abl-fixture-$arm-$task-t1" --trial 1 --source-tree "$GEN/src" --suite-file "$HERE/suite.yaml" \
    --executor host --claude-bin "$GEN/claude" > "$GEN/last.log" 2>&1 || { rc=$?; sed -n "1,20p" "$GEN/last.log" >&2; }
  echo "regen: $name ($arm on $task) exit $rc"
  if [[ -d "$GEN/runs/$name/sandbox/.git" ]]; then find "$GEN/runs/$name/sandbox/.git" -depth -delete; fi
  if [[ -d "$GEN/runs/$name/snapshots" ]]; then find "$GEN/runs/$name/snapshots" -name '*.bundle' -delete; fi
  cp -a "$GEN/runs/$name" "$OUT/$name"
}

run_one a1-build  a1_full           bf-01 STUB_VERDICT_REVIEW=CHANGES_REQUIRED STUB_LEDGER_USD_REVIEW=0.4 STUB_LEDGER_USD_AUDIT=0.3
run_one a0-build  a0_bare           bf-01
run_one a2-build  a2_no_sprint_plan bf-01
run_one a3-review a3_one_voice      rc-01 STUB_LEDGER_USD_REVIEW=0.2
run_one a4-build  a4_no_gates       bf-01
run_one a5-build  a5_no_flatline    bf-01
run_one a6-build  a6_one_window     bf-01 STUB_VERDICT_REVIEW=CHANGES_REQUIRED
run_one a7-build  a7_effort_medium  bf-01
run_one a1-review a1_full           rc-01
run_one refused-a4-review a4_no_gates rc-01

# path hygiene: no generator temp path or operator home in the tracked fixtures
while IFS= read -r f; do
  sed -i -e "s|$GEN|/fixture|g" -e "s|$HOME|/home/operator|g" "$f"
done < <(grep -rlI -e "$GEN" -e "$HOME" "$OUT" || true)

# the tracked set only: drop what .gitignore excludes (*.log, .loa.config.yaml copies), so
# the fixtures on disk equal the fixtures a checkout carries
( cd "$OUT" && find . -type f | sed 's|^\./||' | git -C "$OUT" check-ignore --stdin 2>/dev/null || true ) \
  | while IFS= read -r f; do rm -f "$OUT/$f"; done

# grade.json as Sprint 259's grader writes it (SDD §3.6)
cat > "$OUT/a1-build/grade.json" <<'JSON'
{"hidden_tests": {"passed": 7, "total": 8, "failed_names": ["t8"]}, "regressions": {"newly_failing": []},
 "recall": null, "false_positives": null, "verdict": {"source_file": "auditor-sprint-feedback.md", "value": "APPROVED"},
 "verdict_accuracy": false, "verdict_accuracy_review": true, "verdict_accuracy_audit": false,
 "diff_lines": 12, "files_changed": 1, "contaminated": null, "grader_version": "1"}
JSON
cat > "$OUT/a3-review/grade.json" <<'JSON'
{"hidden_tests": null, "regressions": null,
 "recall": {"defects_seeded": 3, "defects_caught": 2, "recall": 0.6667, "flags": 4}, "false_positives": 1,
 "verdict": {"source_file": "auditor-sprint-feedback.md", "value": "APPROVED"},
 "verdict_accuracy": false, "verdict_accuracy_review": false, "verdict_accuracy_audit": false,
 "diff_lines": null, "files_changed": null, "contaminated": null, "grader_version": "1"}
JSON
jq -n '{batch: "fixture-batch", suite_manifest_sha256: "0000000000000000000000000000000000000000000000000000000000000000",
        suite_version: 1, fingerprint: "fp:fixture", image_digest: "sha256:fixture-image", executor_mode: "host",
        agy_opt_in: false,
        arm_map: {"abl-fixture-a1_full-bf-01-t1": "a1_full", "abl-fixture-a0_bare-bf-01-t1": "a0_bare",
                  "abl-fixture-a2_no_sprint_plan-bf-01-t1": "a2_no_sprint_plan", "abl-fixture-a3_one_voice-rc-01-t1": "a3_one_voice",
                  "abl-fixture-a4_no_gates-bf-01-t1": "a4_no_gates", "abl-fixture-a5_no_flatline-bf-01-t1": "a5_no_flatline",
                  "abl-fixture-a6_one_window-bf-01-t1": "a6_one_window", "abl-fixture-a7_effort_medium-bf-01-t1": "a7_effort_medium",
                  "abl-fixture-a1_full-rc-01-t1": "a1_full", "abl-fixture-a4_no_gates-rc-01-t1": "a4_no_gates"}}' > "$HERE/MANIFEST.json"
echo "regen: wrote $(find "$OUT" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ') run directories"
