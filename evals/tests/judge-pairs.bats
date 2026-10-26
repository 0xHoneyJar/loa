#!/usr/bin/env bats
# =============================================================================
# evals/tests/judge-pairs.bats — rater-confirmed credit (loa-smol REPORT.md §1–2, judge-v2; grader 1.5.0 --judge-verdicts)
#
# judge-pairs.sh over a synthetic suite (a PR fixture, a three-defect manifest, a review-catch task the real
# ablation-grade.sh grades with --allow-unfrozen) and a synthetic run directory, with a stub codex CLI (the packets on
# stdin, the verdict object to -o) and the stub claude CLI behind blind-session.sh in host mode (labels.json). No
# model call, no container. Covers the enumeration through the grader, packet blindness and the bullet rule, the
# verdict row schema the grader accepts, the supersedes chain and the majority rule, one rater, a missing verdict
# (degraded, exit 3), a failed lane (exit 1), the ledger rows, chunking, a matched cell's union, usage.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  JP="$REPO_ROOT/evals/harness/judge-pairs.sh"
  GRADER="$REPO_ROOT/evals/harness/ablation-grade.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/jp.XXXXXX")"
  S="$T/repo/grimoires/loa/evals/ablation-test"
  RUN="$T/results/b1/a1_full/review-x-t1"
  mkdir -p "$S/tasks/review-x" "$S/review-prs/pr-90/head/lib" "$S/manifests" "$T/log" "$T/tmp" "$T/codexhome/sessions" "$RUN/sandbox" "$RUN/meta"
  for i in $(seq 1 60); do printf 'echo f line %d\n' "$i"; done > "$S/review-prs/pr-90/head/f.sh"
  for i in $(seq 1 60); do printf 'echo g line %d\n' "$i"; done > "$S/review-prs/pr-90/head/lib/g.sh"
  printf '# PR\n\nA pull request.\n' > "$S/review-prs/pr-90/PR.md"
  printf -- '--- a/f.sh\n+++ b/f.sh\n' > "$S/review-prs/pr-90/head.diff"
  cat > "$S/manifests/pr-90.json" <<'J'
{"fixture": "pr-90", "defects": [
 {"id": "D01-off-by-one-in-the-loop", "file": "f.sh", "anchor_line": 10, "must_match": "echo f line 10", "severity": "high"},
 {"id": "D02-unquoted-expansion", "file": "f.sh", "anchor_line": 30, "description": "the expansion is unquoted", "severity": "medium"},
 {"id": "D03-missing-guard", "file": "lib/g.sh", "anchor_line": 5, "severity": "low"}]}
J
  cat > "$S/tasks/review-x/task.yaml" <<'YAML'
id: review-x
schema_version: 1
type: review-catch
fixture: null
criterion: "review the change"
test_command: null
regression_command: null
reference_patch: null
grader_protected: []
structural_check: null
review_catch: {fixture: review-prs/pr-90, manifest: manifests/pr-90.json}
suite_version: 1
YAML
  # the run: two findings on D01 (f.sh:9 and, last in a 12-bullet list, f.sh:11), one on D02, one on D03 by basename, a stray
  { printf '# Review\n\nEarly at head/f.sh:9 the bound is wrong.\n\n'
    for i in $(seq 1 11); do printf -- '- Bullet %d: %s head/f.sh:%d.\n' "$i" "$(printf 'filler %.0s' $(seq 1 20))" "$((50 + i % 3))"; done
    printf -- '- The loop at `head/f.sh:11` is off by one: THE CITING BULLET.\n\nUnquoted at head/f.sh:31.\n\nGuard g.sh:5 missing.\n\nStray at head/f.sh:45.\n'; } > "$RUN/sandbox/review.md"
  printf '{"run_id": "b1-a1_full-review-x-t1", "arm": "a1_full", "status": "completed"}\n' > "$RUN/meta/pipeline.json"
  # the codex stand-in: `exec … -C DIR --sandbox read-only --json -o FILE PROMPT`, the packets on stdin; verdicts from codex.ctl
  cat > "$T/codex" <<'STUB'
#!/usr/bin/env bash
T="$(cd "$(dirname "$0")" && pwd)"
out="" prompt=""
while [[ $# -gt 0 ]]; do case "$1" in -o|--output-last-message) out="$2"; shift 2 ;; -C|--sandbox) shift 2 ;; exec|--skip-git-repo-check|--json) shift ;; *) prompt="$1"; shift ;; esac; done
n=$(ls "$T/log" | grep -c '^codex-.*\.stdin$'); n=$((n + 1))
cat > "$T/log/codex-$n.stdin"
printf '%s' "$prompt" > "$T/log/codex-$n.prompt"
[[ -f "$T/codex.fail" ]] && { echo "stub: failure" >&2; exit 1; }
printf '{"type":"thread.started","thread_id":"thread-%s"}\n' "$n"
python3 -I - "$T/log/codex-$n.stdin" "$T/codex.ctl" "$out" <<'PY'
import json, os, re, sys
ids = re.findall(r"^===== (P\d+)\.md =====$", open(sys.argv[1]).read(), re.M)
ctl = {}
if os.path.isfile(sys.argv[2]):
    for line in open(sys.argv[2]):
        parts = line.split()
        if len(parts) == 2:
            ctl[parts[0]] = parts[1]
obj = {i: {"verdict": ctl.get(i, "does-not-describe"), "note": "stub"} for i in ids if ctl.get(i) != "SKIP"}
open(sys.argv[3], "w").write(json.dumps(obj, indent=1))
PY
printf '{"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":100,"output_tokens":50,"reasoning_output_tokens":5}}\n'
STUB
  # the claude stand-in behind blind-session.sh (host mode): labels.json from the sandbox's packets; verdicts from claude.ctl
  cat > "$T/claude" <<'STUB'
#!/usr/bin/env bash
T="$(cd "$(dirname "$0")" && pwd)"
n=$(ls "$T/log" | grep -c '^claude-call-'); n=$((n + 1)); printf '%s\n' "$@" > "$T/log/claude-call-$n"
ls -A > "$T/log/claude-sandbox-$n"
[[ -f "$T/claude.fail" ]] && exit 1
python3 -I - "$T/claude.ctl" <<'PY'
import glob, json, os, sys
ids = sorted(os.path.basename(p)[:-3] for p in glob.glob("P*.md"))
ctl = {}
if os.path.isfile(sys.argv[1]):
    for line in open(sys.argv[1]):
        parts = line.split()
        if len(parts) == 2:
            ctl[parts[0]] = parts[1]
obj = {i: {"verdict": ctl.get(i, "does-not-describe"), "note": "stub"} for i in ids if ctl.get(i) != "SKIP"}
open("labels.json", "w").write(json.dumps(obj))
PY
printf '%s\n' '{"type":"system","subtype":"init","session_id":"sess-stub"}' \
  '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":0,"output_tokens":0},"content":[{"type":"tool_use","id":"w","name":"Write","input":{"file_path":"labels.json","content":"{}"}}]}}' \
  '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.0123,"usage":{"input_tokens":200,"output_tokens":40,"cache_creation_input_tokens":5,"cache_read_input_tokens":7}}'
STUB
  chmod +x "$T/codex" "$T/claude"
  export CODEX_HOME="$T/codexhome" LOA_EVAL_ALLOW_HOST_SESSION=1 LOA_EVAL_ALLOW_HOST_GRADING=1 TMPDIR="$T/tmp" LOA_EVAL_WATCHDOG_POLL_S=0.1
  export LOA_EVAL_PRICING_JSON='{"m-test": {"input_per_mtok": 0, "output_per_mtok": 0}}'
  unset AWS_REGION AWS_DEFAULT_REGION AWS_PROFILE AWS_BEARER_TOKEN_BEDROCK ANTHROPIC_BEDROCK_REGION_PREFIX \
        ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL OPENAI_API_KEY GH_TOKEN
  ARGS=(--repo-root "$T/repo" --suite-root "$S" --allow-unfrozen --out "$T/out" --codex-bin "$T/codex" --executor host --claude-bin "$T/claude" --claude-model m-test)
}

teardown() { chmod -R u+rwx "$T" 2>/dev/null || true; rm -rf "$T"; }

codex_ctl() { printf '%s\n' "$@" > "$T/codex.ctl"; }
claude_ctl() { printf '%s\n' "$@" > "$T/claude.ctl"; }
K() { jq -r "$1" "$T/out/key.json"; }
G() { jq -r "$1" "$RUN/grade.json"; }
# pid_of <defect> <cited path> <line> → the packet id of that pair
pid_of() { jq -r --arg d "$1" --arg p "$2" --argjson a "$3" '.items | to_entries[] | select(.value.defect_key == $d and .value.region[0] == $p and .value.region[1] == $a) | .key' "$T/out/key.json"; }

@test "JP-1 --dry-run: the credited pairs come from the grader's own enumeration; one packet per pair in the grader's order; the key maps packets to pairs outside them; the bullet rule and the description fallbacks; no rater runs" {
  run "$JP" "$RUN" "${ARGS[@]}" --dry-run
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 credited pairs (4 findings, 3 defects) -> 4 packets in 1 chunk(s); prose located for 4; descriptions annotators=0 manifest=1 id_fallback=3"* ]]
  [[ "$output" == *"dry run"* ]]
  [ "$(ls "$T/out/packets" | tr '\n' ,)" = "P0001.md,P0002.md,P0003.md,P0004.md," ]
  [ "$(ls "$T/out/chunks/c01" | wc -l)" -eq 4 ]
  [ ! -e "$T/out/codex" ] && [ ! -e "$T/out/claude" ] && [ ! -e "$T/out/judge-verdicts.jsonl" ]
  # the pairs are the grader's: same (finding_id, defect_key) set and hashes as pairs-grade.json; order by defect then finding id
  diff <(jq -S '[.credited_pairs[] | {finding_id, finding_sha256, defect_key}] | sort_by(.defect_key, .finding_id)' "$T/out/pairs-grade.json") \
       <(jq -S '[.items | to_entries[] | .value | {finding_id, finding_sha256, defect_key}] | sort_by(.defect_key, .finding_id)' "$T/out/key.json")
  [ "$(K '[.items | to_entries[] | .value.defect_key] | join(",")')" = "d1,d1,d2,d3" ]
  [ "$(K '.grader_version')" = 1.5.0 ]
  [ "$(K '.fixture_sha256')" = "$(jq -r .fixture_sha256 "$T/out/pairs-grade.json")" ]
  [ "$(K '.recall_pm3')" = 1.0 ]
  # the citing bullet of the 12-line list, the head lines, the labelled defect with its head line
  j="$(pid_of d1 head/f.sh 11)"
  grep -qF '(the citing bullet(s) of a 12-line list; ' "$T/out/packets/$j.md"
  grep -qF 'THE CITING BULLET' "$T/out/packets/$j.md"
  run grep -c 'Bullet 1:' "$T/out/packets/$j.md"; [ "$output" = 0 ]
  grep -qF '## Cited lines: head/f.sh:11-11 (±5)' "$T/out/packets/$j.md"
  grep -qF '    11  echo f line 11' "$T/out/packets/$j.md"
  grep -qF 'File: `f.sh`; anchor lines: 10.' "$T/out/packets/$j.md"
  grep -qF 'Description: off by one in the loop' "$T/out/packets/$j.md"
  grep -qF 'echo f line 10' "$T/out/packets/$j.md"
  j="$(pid_of d2 head/f.sh 31)"
  grep -qF 'Description: the expansion is unquoted' "$T/out/packets/$j.md"
  j="$(pid_of d3 g.sh 5)"
  grep -qF '## Cited lines: head/lib/g.sh:5-5 (±5; cited as g.sh)' "$T/out/packets/$j.md"
  grep -qF 'Guard g.sh:5 missing.' "$T/out/packets/$j.md"
  [ "$(K '.items["'"$j"'"].cited_path_resolution')" = defect_suffix ]
  # the prompts: the template's pair-item wording with the rater's input and delivery paragraphs; three hashes recorded
  grep -qF 'blind judge for a software-review evaluation' "$T/out/prompt-codex.md"
  grep -qF '===== <file> =====' "$T/out/prompt-codex.md"
  grep -qF '{{LABELS_PATH}}' "$T/out/prompt-claude.md"
  run grep -c '{{INPUT}}\|{{DELIVERY}}' "$T/out/prompt-codex.md" "$T/out/prompt-claude.md"; [ "$output" = "0" ] || [[ "$output" == *":0"*":0"* ]]
  [ "$(wc -l < "$T/out/prompts.sha256")" -eq 3 ]
  [ "$(sha256sum "$T/out/prompt-codex.md" | cut -c1-64)" = "$(grep ' prompt-codex.md' "$T/out/prompts.sha256" | cut -c1-64)" ]
  # --descriptions: the annotators' text
  echo '{"schema_version": 1, "fixtures": {"pr-90": {"D01-off-by-one-in-the-loop": {"text": "Fixing change H01 — the loop bound runs one past the end"}}}}' > "$T/descs.json"
  run "$JP" "$RUN" "${ARGS[@]}" --dry-run --descriptions "$T/descs.json" --out "$T/out2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"descriptions annotators=2 manifest=1 id_fallback=1"* ]]
  grep -qlF 'Description: Fixing change H01 — the loop bound runs one past the end' "$T"/out2/packets/*.md
}

@test "JP-2 packets are blind: no arm, batch, run id, directory name, task id or grader word; a finding naming the arm refuses (exit 1, nothing written) unless the PR carries it; the run id refuses even then; --forbid" {
  run "$JP" "$RUN" "${ARGS[@]}" --dry-run
  [ "$status" -eq 0 ]
  run grep -rlE 'a1_full|a0_bare|b1-|b1/|review-x|credited|near-miss|stray|grader|^[[:space:]]*(arm|trial|batch|run_id)[[:space:]]*:' "$T/out/packets"
  [ "$status" -eq 1 ]
  [ ! -e "$T/out/packets/key.json" ]
  cp "$RUN/sandbox/review.md" "$T/review.bak"
  printf '# Review\n\nThe a1_full arm saw the bound wrong at head/f.sh:9.\n' > "$RUN/sandbox/review.md"
  run "$JP" "$RUN" "${ARGS[@]}" --dry-run --out "$T/o1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"provenance field (a1_full)"* ]]
  [ ! -e "$T/o1/packets" ] && [ ! -e "$T/o1/key.json" ]
  printf '# PR\n\nAdds the a1_full arm.\n' > "$S/review-prs/pr-90/PR.md"
  run "$JP" "$RUN" "${ARGS[@]}" --dry-run --out "$T/o2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"provenance exemptions 1"* ]]
  [ "$(jq -c '[.provenance_exempt[] | .token]' "$T/o2/key.json")" = '["a1_full"]' ]
  printf '# PR\n\nAdds the a1_full arm; run review-x-t1.\n' > "$S/review-prs/pr-90/PR.md"
  printf '# Review\n\nIn run review-x-t1 the bound is wrong at head/f.sh:9.\n' > "$RUN/sandbox/review.md"
  run "$JP" "$RUN" "${ARGS[@]}" --dry-run --out "$T/o3"
  [ "$status" -eq 1 ]
  [[ "$output" == *"provenance field (review-x-t1)"* ]]
  cp "$T/review.bak" "$RUN/sandbox/review.md"
  run "$JP" "$RUN" "${ARGS[@]}" --dry-run --out "$T/o4" --forbid "CITING BULLET"
  [ "$status" -eq 1 ]
  [[ "$output" == *"provenance field (CITING BULLET)"* ]]
}

@test "JP-3 two raters: one row per rater per pair chained through supersedes, then the majority row; the grader accepts the file; describes needs both raters; recall_judged beside recall_pm3; the previous grade kept; the verdicts copied under grading/" {
  codex_ctl "P0001 describes" "P0002 describes" "P0003 partially" "P0004 describes"
  claude_ctl "P0001 describes" "P0002 does-not-describe" "P0003 describes" "P0004 describes"
  # the codex rollout names the model the ledger and the rows record
  mkdir -p "$T/codexhome/sessions/2026/10/26"
  printf '{"timestamp":"x","type":"turn_context","payload":{"model":"gpt-test","cwd":"/"}}\n' > "$T/codexhome/sessions/2026/10/26/rollout-2026-10-26T00-00-00-thread-1.jsonl"
  echo '{"grader_version": "1.3.8", "recall": {"recall_pm3": 1.0}}' > "$RUN/grade.json"
  run "$JP" "$RUN" "${ARGS[@]}"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rows 12 for 4 of 4 pairs (0 unjudged); codex gpt-test: 4/4 rated, describes 3, partially 1; claude m-test: 4/4 rated, describes 3, partially 0"* ]]
  [[ "$output" == *"recall_pm3 1.0 -> recall_judged 0.6667 (defects 3; judged pairs 4, unjudged 0; majority describes 2 on 4 pairs); claude USD 0.0123, codex USD 0 (subscription)"* ]]
  # the file: 12 rows in the grader's schema; per pair codex → claude → majority, each later row naming the earlier one
  [ "$(wc -l < "$T/out/judge-verdicts.jsonl")" -eq 12 ]
  run python3 -I - "$T/out/judge-verdicts.jsonl" "$T/out/prompts.sha256" <<'PY'
import hashlib, json, re, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
sha = {l.split("  ", 1)[1].strip(): l.split("  ", 1)[0] for l in open(sys.argv[2])}
jcs = lambda o: json.dumps(o, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
KEYS = {"run_id", "finding_id", "finding_sha256", "defect_key", "fixture_sha256", "grader_version", "verdict", "judge_model", "judge_prompt_sha256", "blind", "ts"}
by_pair = {}
for r in rows:
    assert set(r) - {"supersedes"} == KEYS, r
    assert r["run_id"] == "review-x-t1" and r["blind"] is True and r["grader_version"] == "1.5.0", r
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", r["ts"]), r["ts"]
    by_pair.setdefault((r["finding_id"], r["defect_key"]), []).append(r)
assert len(by_pair) == 4
for k, rs in by_pair.items():
    assert [r["judge_model"] for r in rs] == ["gpt-test", "m-test", "majority:gpt-test+m-test"], rs
    assert "supersedes" not in rs[0] and rs[1]["supersedes"] == hashlib.sha256(jcs(rs[0]).encode()).hexdigest() \
        and rs[2]["supersedes"] == hashlib.sha256(jcs(rs[1]).encode()).hexdigest(), k
    assert rs[0]["judge_prompt_sha256"] == sha["prompt-codex.md"] and rs[1]["judge_prompt_sha256"] == sha["prompt-claude.md"]
    assert rs[2]["judge_prompt_sha256"] == sha["judge-pairs-prompt.md (template; the majority row)"]
    yes = [r["verdict"] == "describes" for r in rs[:2]]
    assert rs[2]["verdict"] == ("describes" if all(yes) else "does_not_describe"), rs
print("ok")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # the grade: recall_judged = d1 (one of its two pairs agreed) + d3 over 3 defects; the effective rows are the majority's
  [ "$(G '[.recall_judged, .judged_pairs, .unjudged_pairs, .judge.rows_this_run, .judge.rows_superseded] | join(" ")')" = "0.6667 4 0 12 8" ]
  [ "$(G '.judge.judge_models | join(",")')" = "majority:gpt-test+m-test" ]
  [ "$(G '.recall.recall_pm3')" = 1.0 ]
  [ "$(G '[.credited_pairs[] | .verdict] | join(",")')" = "describes,does_not_describe,does_not_describe,describes" ] || \
  [ "$(G '[.credited_pairs[] | .verdict] | join(",")')" = "does_not_describe,describes,does_not_describe,describes" ]
  [ "$(G '.judge.run_id')" = review-x-t1 ]
  # the copies: the previous grade, the verdicts beside the grader's gates-combined.md (sha256 = the grade's verdicts_sha256)
  [ "$(jq -r .grader_version "$T/out/grade.before-judge.json")" = 1.3.8 ]
  [ "$(sha256sum "$RUN/grading/judge-verdicts.jsonl" | cut -c1-64)" = "$(G '.judge.verdicts_sha256')" ]
  cmp "$RUN/grading/judge-verdicts.jsonl" "$T/out/judge-verdicts.jsonl"
  # the raters saw the packets: codex got every packet on stdin with the prompt as the argument; claude's sandbox held the chunk
  [ "$(grep -c '^===== P000[1-4].md =====$' "$T/log/codex-1.stdin")" = 4 ]
  grep -qF 'blind judge' "$T/log/codex-1.prompt"
  [ "$(cat "$T/log/claude-sandbox-1" | tr '\n' ,)" = "P0001.md,P0002.md,P0003.md,P0004.md," ]
  # the report
  [ "$(jq -c '[.recall_pm3, .recall_judged, .judged_pairs, (.unjudged_pairs | length), .rows, .majority_describes, .spend_usd.claude, .raters.codex.model]' "$T/out/report.json")" = '[1.0,0.6667,4,0,12,2,0.0123,"gpt-test"]' ]
  # two more runs over the same outputs are deterministic in everything but the timestamps
  diff <(jq -c 'del(.ts)' "$T/out/judge-verdicts.jsonl") <(jq -c 'del(.ts)' "$RUN/grading/judge-verdicts.jsonl")
}

@test "JP-4 one rater: its strict verdict is the row (partially is does_not_describe); no majority row; its model is the grade's judge model" {
  codex_ctl "P0001 describes" "P0002 describes" "P0003 partially" "P0004 describes"
  run "$JP" "$RUN" "${ARGS[@]}" --raters codex
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$T/out/judge-verdicts.jsonl")" -eq 4 ]
  run jq -r 'select(has("supersedes")) | .finding_id' "$T/out/judge-verdicts.jsonl"; [ -z "$output" ]
  [ "$(G '[.recall_judged, .judged_pairs, .judge.rows_superseded] | join(" ")')" = "0.6667 4 0" ]
  [ "$(G '.judge.judge_models | join(",")')" = codex-headless ]
  [ ! -e "$T/out/claude" ]
  [ "$(jq -r '.majority_describes' "$T/out/report.json")" = null ]
  claude_ctl "P0001 describes" "P0002 describes" "P0003 describes" "P0004 describes"
  run "$JP" "$RUN" "${ARGS[@]}" --raters claude --out "$T/o2"
  [ "$status" -eq 0 ]
  [ "$(G '[.recall_judged, .judge.judge_models[0]] | join(" ")')" = "1.0 m-test" ]
}

@test "JP-5 a pair any rater left unrated gets no row and stays unjudged (exit 3, named in the report); a lane that produced nothing fails the run (exit 1, no regrade)" {
  codex_ctl "P0001 describes" "P0004 describes"
  claude_ctl "P0001 describes" "P0004 SKIP"
  run "$JP" "$RUN" "${ARGS[@]}"
  echo "$output"
  [ "$status" -eq 3 ]
  [[ "$output" == *"rows 9 for 3 of 4 pairs (1 unjudged)"* ]]
  [ "$(jq -c '.unjudged_pairs | map([.item, .defect_key, (.missing | join("+"))])' "$T/out/report.json")" = '[["P0004","d3","claude"]]' ]
  [ "$(G '[.recall_judged, .judged_pairs, .unjudged_pairs] | join(" ")')" = "0.3333 3 1" ]
  run jq -r 'select(.defect_key == "d3") | .verdict' "$T/out/judge-verdicts.jsonl"; [ -z "$output" ]
  rm -f "$RUN/grade.json" "$RUN/grading/judge-verdicts.jsonl"
  touch "$T/codex.fail"
  run "$JP" "$RUN" "${ARGS[@]}" --out "$T/o2"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no pair received a verdict from every rater"* ]]
  [ ! -e "$RUN/grade.json" ] && [ ! -e "$RUN/grading/judge-verdicts.jsonl" ]
}

@test "JP-6 --ledger: one cost-ledger row per rater call in the .run/cost-ledger.jsonl schema; codex at cost 0 (subscription, pricing unknown), claude at the session's reported cost" {
  codex_ctl "P0001 describes"; claude_ctl "P0001 describes"
  run "$JP" "$RUN" "${ARGS[@]}" --ledger "$T/meter/ledger.jsonl" --trace-prefix test-
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$T/meter/ledger.jsonl")" -eq 2 ]
  jq -e . "$T/meter/ledger.jsonl" >/dev/null
  for k in ts trace_id request_id agent provider model tokens_in tokens_out latency_ms cost_micro_usd usage_source pricing_source pricing_mode phase_id sprint_id attempt interaction_id transport; do
    [ "$(jq -r --arg k "$k" 'has($k)' "$T/meter/ledger.jsonl" | sort -u)" = true ] || { echo "missing $k"; false; }
  done
  [ "$(jq -r 'select(.transport == "cli:codex") | [.trace_id, .agent, .provider, .model, .tokens_in, .tokens_out, .tokens_reasoning, .tokens_cache_read, .cost_micro_usd, .usage_source, .pricing_source, .interaction_id, .resolved_model] | join(" ")' "$T/meter/ledger.jsonl")" = "test-review-x-t1-codex-c01 codex-headless openai codex-headless 1000 50 5 100 0 actual unknown thread-1 codex-headless" ]
  [ "$(jq -r 'select(.transport == "cli:claude") | [.trace_id, .agent, .provider, .model, .tokens_in, .tokens_out, .tokens_cache_read, .tokens_cache_creation, .cost_micro_usd, .usage_source, .pricing_source, .interaction_id] | join(" ")' "$T/meter/ledger.jsonl")" = "test-review-x-t1-claude-c01 claude-headless anthropic m-test 200 40 7 5 12300 actual cli_reported sess-stub" ]
  [[ "$(jq -r '.ts' "$T/meter/ledger.jsonl" | head -1)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$ ]]
  [ "$(jq -r '.request_id' "$T/meter/ledger.jsonl" | sort -u | wc -l)" -eq 2 ]
}

@test "JP-7 --chunk: the packets go to the raters in chunks of at most N; every chunk's verdicts are collected; the Claude cap stops the lane and leaves the rest unjudged" {
  codex_ctl "P0001 describes" "P0002 describes" "P0003 describes" "P0004 describes"
  claude_ctl "P0001 describes" "P0002 describes" "P0003 describes" "P0004 describes"
  run "$JP" "$RUN" "${ARGS[@]}" --chunk 3
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 packets in 2 chunk(s)"* ]]
  [ "$(ls "$T/out/chunks/c01" | wc -l)" -eq 3 ] && [ "$(ls "$T/out/chunks/c02" | wc -l)" -eq 1 ]
  [ "$(ls "$T/log" | grep -c '^codex-.*\.stdin$')" -eq 2 ] && [ "$(ls "$T/log" | grep -c '^claude-call-')" -eq 2 ]
  [ "$(G '[.recall_judged, .judged_pairs] | join(" ")')" = "1.0 4" ]
  [ "$(wc -l < "$T/out/claude-spend.jsonl")" -eq 2 ]
  # a cap of USD 0.02: the first session (USD 0.0123) fits, the second does not → its pair stays unjudged
  rm -rf "$T/log"; mkdir "$T/log"
  run "$JP" "$RUN" "${ARGS[@]}" --chunk 3 --max-usd 0.02 --out "$T/o2"
  echo "$output"
  [ "$status" -eq 3 ]
  [ -f "$T/o2/claude/c02.skipped" ]
  grep -q 'claude c02 skipped: the cap' "$T/o2/lanes.log"
  [ "$(jq -r '.unjudged_pairs | length' "$T/o2/report.json")" = 1 ]
  [ "$(ls "$T/log" | grep -c '^claude-call-')" -eq 1 ]
}

@test "JP-8 --union: a matched cell's union pairs, prose from the sessions, the rows bound to the cell" {
  local C="$T/results/b1/a0_bare_matched/review-x-t1" i
  mkdir -p "$C/sessions/s1/sandbox" "$C/sessions/s2/sandbox" "$C/meta"
  printf '# Review\n\n- The loop at `head/f.sh:11` is off by one: SESSION ONE.\n' > "$C/sessions/s1/sandbox/review.md"
  printf '# Review\n\n- Unquoted at head/f.sh:31: SESSION TWO.\n- Guard lib/g.sh:5 missing.\n' > "$C/sessions/s2/sandbox/review.md"
  for i in 1 2; do run "$GRADER" "$C/sessions/s$i" review-x --suite-root "$S" --allow-unfrozen --docker-bin /nonexistent; [ "$status" -eq 0 ] || { echo "$output"; false; }; done
  jq -nc '{schema_version: 1, k: 2, sessions_valid: 2, sessions: [{id: "s1", valid: true, status: "completed", cost_usd: 1.0, attempts: 1, run_dir: "sessions/s1"},
          {id: "s2", valid: true, status: "completed", cost_usd: 1.5, attempts: 1, run_dir: "sessions/s2"}]}' > "$C/meta/cell.json"
  codex_ctl "P0001 describes" "P0002 does-not-describe" "P0003 describes"
  claude_ctl "P0001 describes" "P0002 describes" "P0003 describes"
  run "$JP" "$C" --union "${ARGS[@]}"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 credited pairs (3 findings, 3 defects)"* ]]
  grep -qF 'SESSION ONE' "$T/out/packets/P0001.md"
  grep -qF 'SESSION TWO' "$T/out/packets/P0002.md"
  [ "$(jq -r '[.union, .recall_judged, .judged_pairs, .judge.run_id] | join(" ")' "$C/grade.json")" = "true 0.6667 3 review-x-t1" ]
  [ -f "$C/grading/judge-verdicts.jsonl" ]
}

@test "JP-9 usage and refusals: exit 2 on a missing run, a bad rater list, an --out under grading/, a chunk over 64; exit 1 on a task the suite lacks or a grader refusal" {
  run "$JP"; [ "$status" -eq 2 ]
  run "$JP" "$RUN" "${ARGS[@]}" --raters gemini; [ "$status" -eq 2 ]
  run "$JP" "$RUN" "${ARGS[@]}" --raters codex,codex; [ "$status" -eq 2 ]
  run "$JP" "$RUN" --repo-root "$T/repo" --suite-root "$S" --allow-unfrozen --out "$RUN/grading/jp" --dry-run; [ "$status" -eq 2 ]
  run "$JP" "$RUN" "${ARGS[@]}" --chunk 65; [ "$status" -eq 2 ]
  run "$JP" "$RUN" "${ARGS[@]}" --task-id review-none --dry-run; [ "$status" -eq 1 ]
  run "$JP" "$RUN" --repo-root "$T/repo" --suite-root "$S" --out "$T/o" --dry-run   # no --allow-unfrozen: the suite has no MANIFEST.sha256
  [ "$status" -eq 1 ]
  [[ "$output" == *"refused the enumeration"* ]]
  [ ! -e "$T/o/packets" ]
}

@test "JP-10 one finding id covers a bare line and a range starting there: the pair's packet cites the citation that credits the defect, as the grader's hash does" {
  # f.sh:6 alone is four lines from D01's site (no credit); f.sh:6-8 reaches within ±3 → the pair's reference is the range
  printf '# Review\n\nFirst at head/f.sh:6 the bound is wrong.\n\nThen head/f.sh:6-8 spans the loop head: THE RANGE.\n' > "$RUN/sandbox/review.md"
  run "$JP" "$RUN" "${ARGS[@]}" --dry-run
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 credited pairs (1 findings, 1 defects)"* ]]
  grep -qF '## Cited lines: head/f.sh:6-8 (±5)' "$T/out/packets/P0001.md"
  grep -qF 'THE RANGE' "$T/out/packets/P0001.md"
  [ "$(K '.items.P0001.region | join(":")')" = "head/f.sh:6:8" ]
}
