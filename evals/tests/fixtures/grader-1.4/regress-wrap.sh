#!/usr/bin/env bash
# regress-wrap.sh — the GRADER of evals/tests/ablation-grade.bats under fixtures/grader-1.4/regress.sh (cycle-133
# Sprint 273 Task 2.3): every grade call is graded first by the older grader ($AG_REGRESS_OLD, its grade.json to
# $AG_REGRESS_DIR/<test>-<n>.old.json, its exit status to .old.rc), then by the grader under test ($AG_REGRESS_NEW, whose
# output and exit status the test sees; its grade.json copied to .new.json, its status to .new.rc). --self-check,
# --union (the union refuses sessions another grader version graded) and --help calls go to the new grader only.
set -uo pipefail
export LC_ALL=C
new="$AG_REGRESS_NEW" old="$AG_REGRESS_OLD" dir="$AG_REGRESS_DIR"
case " $* " in *" --self-check "*|*" --union "*|*" --help "*|*" -h "*) exec "$new" "$@" ;; esac
n=$(( $(cat "$dir/seq.$AG_REGRESS_TEST" 2>/dev/null || echo 0) + 1 ))
printf '%s\n' "$n" > "$dir/seq.$AG_REGRESS_TEST"
id="$AG_REGRESS_TEST-$n" out="" prev=""
for a in "$@"; do [[ "$prev" == --out ]] && out="$a"; prev="$a"; done
[[ -n "$out" ]] || out="${1:-}/grade.json"
"$old" "$@" --out "$dir/$id.old.json" > "$dir/$id.old.log" 2>&1
printf '%s\n' "$?" > "$dir/$id.old.rc"
rm -f "$out.regress-stale"; [[ -f "$out" ]] && mv "$out" "$out.regress-stale"
"$new" "$@"
rc=$?
if [[ -f "$out" ]]; then cp "$out" "$dir/$id.new.json"; rm -f "$out.regress-stale"
elif [[ -f "$out.regress-stale" ]]; then mv "$out.regress-stale" "$out"; fi
printf '%s\n' "$rc" > "$dir/$id.new.rc"
exit "$rc"
