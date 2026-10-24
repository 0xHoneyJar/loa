#!/usr/bin/env bats
# tests/unit/sweep-tools.bats — cycle-133 C-13 (FR-13): sweep-inventory.sh, sweep-apply.sh, sweep-sample.sh against a
# stub `br` (a JSON fixture served by `br list --json`; close / label add / comments add logged, never executed).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  INV="$ROOT/.claude/scripts/beads/sweep-inventory.sh"
  APPLY="$ROOT/.claude/scripts/beads/sweep-apply.sh"
  SAMPLE="$ROOT/.claude/scripts/beads/sweep-sample.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/sweep.XXXXXX")"
  mkdir -p "$T/bin" "$T/sw" "$T/man"
  # the stub tracker: four open beads and one closed; every mutating call is logged
  cat > "$T/beads.json" <<'JSON'
{"issues":[
 {"id":"bd-aaa11","title":"first","status":"open","issue_type":"task","priority":2,"labels":["x"],"created_at":"2026-02-01T00:00:00Z","description":"d1"},
 {"id":"bd-bbb22","title":"second","status":"open","issue_type":"bug","priority":1,"labels":[],"created_at":"2026-09-01T00:00:00Z","description":"d2"},
 {"id":"bd-ccc33","title":"third","status":"open","issue_type":"task","priority":3,"labels":[],"created_at":"2026-10-23T00:00:00Z","description":"d3"},
 {"id":"bd-ddd44","title":"tier one","status":"open","issue_type":"task","priority":1,"labels":[],"created_at":"2026-10-01T00:00:00Z","description":"d4"},
 {"id":"bd-zzz99","title":"gone","status":"closed","issue_type":"task","priority":2,"labels":[],"created_at":"2026-01-01T00:00:00Z","description":"d5"}
]}
JSON
  printf '#!/usr/bin/env bash\ncase "$1 $2" in\n  "list --json"*) cat "%s" ;;\n  "close bd-bbb22") case " $* " in *" --force "*) printf "%%s\\n" "$*" >> "%s" ;; *) echo "Warning: Skipped bd-bbb22: blocked by: ${BR_BLOCKER:-bd-aaa11}" >&2; exit 3 ;; esac ;;\n  *) printf "%%s\\n" "$*" >> "%s" ;;\nesac\n' "$T/beads.json" "$T/br.log" "$T/br.log" > "$T/bin/br"
  chmod +x "$T/bin/br"
  export PATH="$T/bin:$PATH"
  printf 'bd-ddd44\n# a comment\n\n' > "$T/tier1.txt"
  HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD)"
}
teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

freeze() { run "$INV" --out "$T/sw" --exclude "$T/tier1.txt" --batch-size 2; [ "$status" -eq 0 ]; }

@test "SW-1 inventory: freezes the open beads minus the excluded ids, in id order, with a sha256 and batches" {
  freeze
  [ "$(wc -l < "$T/sw/inventory.jsonl")" -eq 3 ]
  [ "$(jq -r '.id' "$T/sw/inventory.jsonl" | tr '\n' ' ')" = "bd-aaa11 bd-bbb22 bd-ccc33 " ]
  ! grep -q bd-ddd44 "$T/sw/inventory.jsonl"; ! grep -q bd-zzz99 "$T/sw/inventory.jsonl"
  [ "$(ls "$T/sw"/batches/batch-*.jsonl | wc -l)" -eq 2 ]
  grep -q '^[0-9a-f]\{64\}  inventory.jsonl$' "$T/sw/inventory.sha256"
  grep -q 'beads: 3' "$T/sw/INVENTORY.md"
  [ ! -s "$T/br.log" ]   # read-only
}

@test "SW-2 inventory: a second freeze is refused (the snapshot is frozen) unless --force" {
  freeze
  run "$INV" --out "$T/sw" --exclude "$T/tier1.txt"
  [ "$status" -eq 2 ]; [[ "$output" == *"frozen"* ]]
  run "$INV" --out "$T/sw" --exclude "$T/tier1.txt" --force
  [ "$status" -eq 0 ]
}

write_manifests() {  # a complete, valid partition: one closure with a commit, one with a path, one kept
  printf '{"id":"bd-aaa11","category":"closed-implemented","evidence":"%s","confidence":"high"}\n' "$HEAD_SHA" > "$T/man/manifest-1.jsonl"
  printf '{"id":"bd-bbb22","category":"closed-obsolete","evidence":"CHANGELOG.md","confidence":"medium"}\n' >> "$T/man/manifest-1.jsonl"
  printf '{"id":"bd-ccc33","category":"kept","evidence":"still wanted","confidence":"high"}\n' > "$T/man/manifest-2.jsonl"
}

@test "SW-3 apply --validate: a complete partition with resolvable evidence is VALID and mutates nothing" {
  freeze; write_manifests
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --validate
  [ "$status" -eq 0 ]; [[ "$output" == *"VALID"* ]]
  [ ! -s "$T/br.log" ]
}

@test "SW-4 apply --validate: duplicate, unknown and missing ids are each named and rejected" {
  freeze; write_manifests
  printf '{"id":"bd-aaa11","category":"kept","evidence":"again","confidence":"low"}\n{"id":"bd-nope1","category":"kept","evidence":"x","confidence":"low"}\n' > "$T/man/manifest-3.jsonl"
  sed -i '/bd-ccc33/d' "$T/man/manifest-2.jsonl"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --validate
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate or conflicting): bd-aaa11"* ]]
  [[ "$output" == *"not in the frozen inventory: bd-nope1"* ]]
  [[ "$output" == *"partition is incomplete): bd-ccc33"* ]]
  [ ! -s "$T/br.log" ]
}

@test "SW-5 apply --validate: unresolvable closure evidence, a bad category and a moved snapshot are rejected" {
  freeze; write_manifests
  printf '{"id":"bd-aaa11","category":"closed-implemented","evidence":"deadbeefcafe1234","confidence":"high"}\n{"id":"bd-bbb22","category":"closed-obsolete","evidence":"no/such/path.txt","confidence":"medium"}\n' > "$T/man/manifest-1.jsonl"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --validate
  [ "$status" -eq 1 ]
  [[ "$output" == *"bd-aaa11 (closed-implemented): evidence does not resolve"* ]]
  [[ "$output" == *"bd-bbb22 (closed-obsolete): evidence does not resolve"* ]]
  write_manifests
  printf '{"id":"bd-ccc33","category":"maybe","evidence":"x","confidence":"high"}\n' > "$T/man/manifest-2.jsonl"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --validate
  [ "$status" -eq 1 ]; [[ "$output" == *"invalid field(s) category"* ]]
  write_manifests
  echo '{"id":"bd-eee55","title":"late"}' >> "$T/sw/inventory.jsonl"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --validate
  [ "$status" -eq 1 ]; [[ "$output" == *"snapshot moved"* ]]
}

@test "SW-6 apply --validate: a PR-number evidence resolves through the repository's log; a bead closed meanwhile is reported" {
  freeze; write_manifests
  pr="$(git -C "$ROOT" log --all --format=%B -E --grep='(^|[^0-9])#[0-9]{3,5}([^0-9]|$)' -n 1 | grep -oE '#[0-9]{3,5}' | head -1)"
  [ -n "$pr" ] || skip "no PR number in this repository's log"
  printf '{"id":"bd-aaa11","category":"closed-implemented","evidence":"%s","confidence":"high"}\n{"id":"bd-bbb22","category":"closed-obsolete","evidence":"CHANGELOG.md","confidence":"medium"}\n' "$pr" > "$T/man/manifest-1.jsonl"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --validate
  [ "$status" -eq 0 ]
  jq '(.issues[] | select(.id == "bd-aaa11") | .status) = "closed"' "$T/beads.json" > "$T/b2.json" && mv "$T/b2.json" "$T/beads.json"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --validate
  [ "$status" -eq 1 ]; [[ "$output" == *"bd-aaa11 (closed-implemented): not open in the tracker now"* ]]
}

@test "SW-7 apply --apply: closes with the evidence in the reason, labels and comments kept beads, logs every mutation, and a re-run skips them" {
  freeze; write_manifests
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31
  [ "$status" -eq 0 ]; [[ "$output" == *"applied 3 row(s), skipped 0"* ]]
  grep -q "^close bd-aaa11 --reason implemented: $HEAD_SHA\$" "$T/br.log"
  grep -q '^close bd-bbb22 --reason obsolete: CHANGELOG.md (blockers bd-aaa11 close in the same sweep) --force$' "$T/br.log"   # blocked by a closure of this sweep → forced
  grep -q '^label add bd-ccc33 backlog-2026-10$' "$T/br.log"
  grep -q '^comments add bd-ccc33 status: kept — still wanted; review-by 2027-01-31 (sweep sprint-275)$' "$T/br.log"
  [ "$(wc -l < "$T/sw/applied.jsonl")" -eq 3 ]
  jq -e 'select(.id == "bd-aaa11") | .action == "close" and (.reason | startswith("implemented: "))' "$T/sw/applied.jsonl" >/dev/null
  : > "$T/br.log"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31
  [ "$status" -eq 0 ]; [[ "$output" == *"applied 0 row(s), skipped 3"* ]]
  [ ! -s "$T/br.log" ]
}

@test "SW-8 apply --apply --dry-run prints the commands and writes neither the tracker nor the log; an invalid manifest never reaches apply" {
  freeze; write_manifests
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31 --dry-run
  [ "$status" -eq 0 ]; [[ "$output" == *"DRY: "*"close bd-aaa11"* ]]
  [ ! -s "$T/sw/applied.jsonl" ]; [ ! -s "$T/br.log" ]
  printf '{"id":"bd-ccc33","category":"kept","evidence":"x","confidence":"high"}\n{"id":"bd-ccc33","category":"kept","evidence":"y","confidence":"high"}\n' > "$T/man/manifest-2.jsonl"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31
  [ "$status" -eq 1 ]; [ ! -s "$T/br.log" ]; [ ! -s "$T/sw/applied.jsonl" ]
}

@test "SW-9 sample: ceil(10 %) of the closures, deterministic for the seed, and --check confirms or names the disagreeing batch" {
  freeze; write_manifests
  for i in $(seq 1 18); do printf '{"id":"bd-x%02d00","category":"closed-obsolete","evidence":"CHANGELOG.md","confidence":"high"}\n' "$i"; done > "$T/man/manifest-3.jsonl"
  run "$SAMPLE" --manifests "$T/man" --out "$T/s1.jsonl"
  [ "$status" -eq 0 ]; [[ "$output" == *"2 of 20 proposed closures sampled"* ]]
  run "$SAMPLE" --manifests "$T/man" --out "$T/s2.jsonl"
  cmp -s "$T/s1.jsonl" "$T/s2.jsonl"
  run "$SAMPLE" --manifests "$T/man" --out "$T/s3.jsonl" --seed 7
  [ "$status" -eq 0 ]
  jq -e '.batch | startswith("manifest-")' "$T/s1.jsonl" >/dev/null
  jq -c '{id, agree: true, evidence: "confirmed"}' "$T/s1.jsonl" > "$T/v-ok.jsonl"
  run "$SAMPLE" --check "$T/s1.jsonl" "$T/v-ok.jsonl"
  [ "$status" -eq 0 ]; [[ "$output" == *"all 2 sampled closures confirmed"* ]]
  jq -c '{id, agree: false, evidence: "the fix never landed"}' "$T/s1.jsonl" | head -1 > "$T/v-bad.jsonl"
  run "$SAMPLE" --check "$T/s1.jsonl" "$T/v-bad.jsonl"
  [ "$status" -eq 1 ]; [[ "$output" == *"DISAGREES"* ]]; [[ "$output" == *"no verification row"* ]]
}


@test "SW-10 apply: a bead br refuses as blocked by a bead this sweep KEEPS is logged skipped-blocked, the rest apply, exit 1 names it; a re-run skips the log" {
  freeze; write_manifests
  export BR_BLOCKER=bd-ccc33   # kept in the manifests, so bd-bbb22 must not be forced
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31
  [ "$status" -eq 1 ]
  [[ "$output" == *"bd-bbb22 (closed-obsolete): skipped-blocked"* ]]
  [[ "$output" == *"applied 2 row(s), skipped 0 already in applied.jsonl, 1 not applied"* ]]
  ! grep -q 'close bd-bbb22' "$T/br.log"
  grep -q '^close bd-aaa11 ' "$T/br.log"; grep -q '^label add bd-ccc33 backlog-2026-10$' "$T/br.log"
  jq -e 'select(.id == "bd-bbb22") | .action == "skipped-blocked"' "$T/sw/applied.jsonl" >/dev/null
  : > "$T/br.log"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31
  [ "$status" -eq 0 ]; [[ "$output" == *"applied 0 row(s), skipped 3"* ]]; [ ! -s "$T/br.log" ]
}
