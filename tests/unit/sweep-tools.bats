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
  cat > "$T/bin/br" <<STUB
#!/usr/bin/env bash
# stub tracker: list serves the fixture; close honours BR_BLOCKS ("dep:blocker dep:blocker …"): a dep is refused with
# "blocked by: <blocker>" until the log shows "close <blocker>"; every mutating call is logged
LOG="$T/br.log"
case "\$1 \$2" in
  "list --json"*) if [[ -n "\${BR_FAIL_LIST:-}" ]]; then echo "Error: database is locked" >&2; exit 1; fi; cat "$T/beads.json" ;;
  close*) dep="\$2"; for pair in \${BR_BLOCKS:-bd-bbb22:bd-aaa11}; do d="\${pair%%:*}"; blk="\${pair#*:}"
            if [[ "\$d" == "\$dep" ]] && ! grep -q "^close \$blk " "\$LOG" 2>/dev/null; then
              if [[ -n "\${BR_SOFT_SKIP:-}" ]]; then echo "Warning: Skipped \$dep: blocked by: \$blk"; exit 0; fi
              echo "Warning: Skipped \$dep: blocked by: \$blk" >&2; exit 3; fi; done
          printf '%s\\n' "\$*" >> "\$LOG" ;;
  *) printf '%s\\n' "\$*" >> "\$LOG" ;;
esac
STUB
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
  ! grep -q '"description"' "$T/sw/inventory.jsonl"   # descriptions stay in the tracker (the inventory travels on the public record)
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

@test "SW-6 apply --validate: a PR-number evidence resolves through the repository's log; a bead closed meanwhile is noted, not refused" {
  freeze; write_manifests
  pr="$(git -C "$ROOT" log --all --format=%B -E --grep='(^|[^0-9])#[0-9]{3,5}([^0-9]|$)' -n 1 | grep -oE '#[0-9]{3,5}' | head -1)"
  [ -n "$pr" ] || skip "no PR number in this repository's log"
  printf '{"id":"bd-aaa11","category":"closed-implemented","evidence":"%s","confidence":"high"}\n{"id":"bd-bbb22","category":"closed-obsolete","evidence":"CHANGELOG.md","confidence":"medium"}\n' "$pr" > "$T/man/manifest-1.jsonl"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --validate
  [ "$status" -eq 0 ]
  jq '(.issues[] | select(.id == "bd-aaa11") | .status) = "closed"' "$T/beads.json" > "$T/b2.json" && mv "$T/b2.json" "$T/beads.json"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --validate
  [ "$status" -eq 0 ]; [[ "$output" == *"bd-aaa11 (closed-implemented) is already closed in the tracker"* ]]
}

@test "SW-7 apply --apply: closes with the evidence in the reason, labels and comments kept beads, logs every mutation, and a re-run skips them" {
  freeze; write_manifests
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31 --no-sample-check "bats"
  [ "$status" -eq 0 ]; [[ "$output" == *"applied 3 row(s), skipped 0"* ]]
  grep -q "^close bd-aaa11 --reason implemented: $HEAD_SHA\$" "$T/br.log"
  grep -q '^close bd-bbb22 --reason obsolete: CHANGELOG.md$' "$T/br.log"   # bd-aaa11 (its blocker) closed earlier in the same pass; never forced
  ! grep -q -- '--force' "$T/br.log"
  [[ "$output" == *" close pass(es)"* ]]
  grep -q '^label add bd-ccc33 backlog-2026-10$' "$T/br.log"
  grep -q '^comments add bd-ccc33 status: kept — still wanted; review-by 2027-01-31 (sweep sprint-275)$' "$T/br.log"
  [ "$(jq -c 'select(.action != "no-sample-check")' "$T/sw/applied.jsonl" | wc -l)" -eq 3 ]
  jq -e 'select(.action == "no-sample-check") | .reason == "bats"' "$T/sw/applied.jsonl" >/dev/null   # the override is logged
  jq -e 'select(.id == "bd-aaa11") | .action == "close" and (.reason | startswith("implemented: "))' "$T/sw/applied.jsonl" >/dev/null
  : > "$T/br.log"
  # the tracker now shows the closed beads closed: the re-run must still validate (they are in the applied log) and skip them
  jq '(.issues[] | select(.id == "bd-aaa11" or .id == "bd-bbb22") | .status) = "closed"' "$T/beads.json" > "$T/b2.json" && mv "$T/b2.json" "$T/beads.json"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31 --no-sample-check "bats"
  [ "$status" -eq 0 ]; [[ "$output" == *"applied 0 row(s), skipped 3"* ]]
  [ ! -s "$T/br.log" ]
}

@test "SW-8 apply --apply --dry-run prints the commands and writes neither the tracker nor the log; an invalid manifest never reaches apply" {
  freeze; write_manifests
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31 --no-sample-check "bats" --dry-run
  [ "$status" -eq 0 ]; [[ "$output" == *"DRY: "*"close bd-aaa11"* ]]
  [ ! -s "$T/sw/applied.jsonl" ]; [ ! -s "$T/br.log" ]
  printf '{"id":"bd-ccc33","category":"kept","evidence":"x","confidence":"high"}\n{"id":"bd-ccc33","category":"kept","evidence":"y","confidence":"high"}\n' > "$T/man/manifest-2.jsonl"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31 --no-sample-check "bats"
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
  export BR_BLOCKS="bd-bbb22:bd-ccc33"   # kept in the manifests, so bd-bbb22 stays blocked
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31 --no-sample-check "bats"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bd-bbb22 (closed-obsolete): skipped-blocked"* ]]
  [[ "$output" == *"applied 2 row(s), skipped 0 already in applied.jsonl or already closed, 1 not applied"* ]]
  ! grep -q 'close bd-bbb22' "$T/br.log"
  grep -q '^close bd-aaa11 ' "$T/br.log"; grep -q '^label add bd-ccc33 backlog-2026-10$' "$T/br.log"
  jq -e 'select(.id == "bd-bbb22") | .action == "skipped-blocked"' "$T/sw/applied.jsonl" >/dev/null
  : > "$T/br.log"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31 --no-sample-check "bats"
  [ "$status" -eq 0 ]; [[ "$output" == *"applied 0 row(s), skipped 3"* ]]; [ ! -s "$T/br.log" ]
}

@test "SW-11 apply: a chain closure→closure→kept is never forced — both closures end skipped-blocked after a pass without progress" {
  freeze; write_manifests
  export BR_BLOCKS="bd-aaa11:bd-bbb22 bd-bbb22:bd-ccc33"   # A blocked by B, B blocked by the kept C
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31 --no-sample-check "bats"
  [ "$status" -eq 1 ]
  ! grep -q '^close ' "$T/br.log"; ! grep -q -- '--force' "$T/br.log"
  [[ "$output" == *"bd-aaa11 (closed-implemented): skipped-blocked"* ]]; [[ "$output" == *"bd-bbb22 (closed-obsolete): skipped-blocked"* ]]
  grep -q '^label add bd-ccc33 backlog-2026-10$' "$T/br.log"
  [ "$(jq -r 'select(.action == "skipped-blocked") | .id' "$T/sw/applied.jsonl" | wc -l)" -eq 2 ]
}

@test "SW-12 sample --check fails closed on a corrupt or empty sample file" {
  printf 'not json\n' > "$T/bad.jsonl"; printf '{"id":"bd-aaa11","agree":true,"evidence":"x"}\n' > "$T/v.jsonl"
  run "$SAMPLE" --check "$T/bad.jsonl" "$T/v.jsonl"
  [ "$status" -eq 1 ]; [[ "$output" == *"does not parse"* ]]
  : > "$T/empty.jsonl"
  run "$SAMPLE" --check "$T/empty.jsonl" "$T/v.jsonl"
  [ "$status" -eq 1 ]; [[ "$output" == *"holds no sampled closure"* ]]
}

@test "SW-13 inventory: an exclude file with only comments and blank lines is an empty exclusion set, and the freeze is atomic" {
  printf '# tier 1 ids\n\n' > "$T/none.txt"
  run "$INV" --out "$T/sw2" --exclude "$T/none.txt" --batch-size 3
  [ "$status" -eq 0 ]; [ "$(wc -l < "$T/sw2/inventory.jsonl")" -eq 4 ]
  grep -q 'minus 0 excluded' "$T/sw2/INVENTORY.md"
  [ "$(ls "$T/sw2"/batches/batch-*.jsonl | wc -l)" -eq 2 ]
  [ -z "$(ls -A "$T/sw2" | grep '^\.freeze')" ]   # no temporary freeze directory left behind
}

@test "SW-14 apply: a closure bead already closed in the tracker is logged already-closed and skipped; the other rows apply" {
  freeze; write_manifests
  jq '(.issues[] | select(.id == "bd-aaa11") | .status) = "closed"' "$T/beads.json" > "$T/b2.json" && mv "$T/b2.json" "$T/beads.json"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --validate
  [ "$status" -eq 0 ]; [[ "$output" == *"already closed in the tracker"* ]]
  export BR_BLOCKS="none:none"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31 --no-sample-check "bats"
  [ "$status" -eq 0 ]
  ! grep -q '^close bd-aaa11' "$T/br.log"; grep -q '^close bd-bbb22 ' "$T/br.log"
  jq -e 'select(.id == "bd-aaa11") | .action == "already-closed"' "$T/sw/applied.jsonl" >/dev/null
}

@test "SW-15 apply: a failing tracker list is fatal — nothing validated as closed, nothing logged, nothing applied" {
  freeze; write_manifests
  BR_FAIL_LIST=1 run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31 --no-sample-check "bats"
  [ "$status" -eq 1 ]; [[ "$output" == *"br list failed"* ]]
  [ ! -s "$T/sw/applied.jsonl" ]; [ ! -s "$T/br.log" ]
}

@test "SW-16 apply: a tracker that prints 'Skipped … blocked by' with exit 0 is treated as a refusal, never logged as a close" {
  freeze; write_manifests
  export BR_BLOCKS="bd-bbb22:bd-ccc33" BR_SOFT_SKIP=1
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31 --no-sample-check "bats"
  [ "$status" -eq 1 ]; [[ "$output" == *"bd-bbb22 (closed-obsolete): skipped-blocked"* ]]
  ! jq -e 'select(.id == "bd-bbb22" and .action == "close")' "$T/sw/applied.jsonl" >/dev/null
  jq -e 'select(.id == "bd-bbb22" and .action == "skipped-blocked")' "$T/sw/applied.jsonl" >/dev/null
}

@test "SW-17 apply: the sample gate — a sample drawn from these manifests passes; a manifest rewritten afterwards refuses; --no-sample-check is logged" {
  freeze; write_manifests
  run "$SAMPLE" --manifests "$T/man" --out "$T/s.jsonl" --pct 100
  [ "$status" -eq 0 ]; jq -e '.manifests_sha256 | length == 64' "$T/s.jsonl" >/dev/null
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31 --sample "$T/s.jsonl" --dry-run
  [ "$status" -eq 0 ]
  printf '{"id":"bd-ccc33","category":"closed-obsolete","evidence":"CHANGELOG.md","confidence":"high"}\n' > "$T/man/manifest-2.jsonl"   # rewritten after the draw
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31 --sample "$T/s.jsonl"
  [ "$status" -eq 1 ]; [[ "$output" == *"manifests changed since the sample was drawn"* ]]; [ ! -s "$T/br.log" ]
  run "$SAMPLE" --check "$T/s.jsonl" "$T/s.jsonl" --manifests "$T/man"
  [ "$status" -eq 1 ]; [[ "$output" == *"manifests changed since this sample was drawn"* ]]
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31
  [ "$status" -eq 2 ]; [[ "$output" == *"needs --sample FILE"* ]]
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31 --no-sample-check "lead: batch 2 fully re-verified"
  [ "$status" -eq 0 ]
  jq -e 'select(.action == "no-sample-check") | .reason == "lead: batch 2 fully re-verified" and (.manifests_sha256 | length == 64)' "$T/sw/applied.jsonl" >/dev/null
}

@test "SW-18 apply: a corrupt applied log (a partial line) refuses before any mutation" {
  freeze; write_manifests
  printf '{"id":"bd-aaa11","category":"closed-implemented","action":"close","reason":"x","ts":"t"}\n{"id":"bd-bb' > "$T/sw/applied.jsonl"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --apply --sprint 275 --review-by 2027-01-31 --no-sample-check "bats"
  [ "$status" -eq 1 ]; [[ "$output" == *"does not parse as JSON Lines"* ]]; [ ! -s "$T/br.log" ]
}

@test "SW-19 validate: evidence with a control character is an invalid field; '.' and a directory are not resolvable paths" {
  freeze; write_manifests
  printf '{"id":"bd-aaa11","category":"closed-implemented","evidence":"\\u001b[2K ok","confidence":"high"}\n{"id":"bd-bbb22","category":"closed-obsolete","evidence":"CHANGELOG.md","confidence":"medium"}\n' > "$T/man/manifest-1.jsonl"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --validate
  [ "$status" -eq 1 ]; [[ "$output" == *"manifest-1.jsonl line 1: invalid field(s) evidence"* ]]
  write_manifests
  printf '{"id":"bd-aaa11","category":"closed-implemented","evidence":"%s","confidence":"high"}\n{"id":"bd-bbb22","category":"closed-obsolete","evidence":".","confidence":"medium"}\n' "$HEAD_SHA" > "$T/man/manifest-1.jsonl"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --validate
  [ "$status" -eq 1 ]; [[ "$output" == *"bd-bbb22 (closed-obsolete): evidence does not resolve"* ]]   # the tree root is not a file
  printf '{"id":"bd-aaa11","category":"closed-implemented","evidence":"tests","confidence":"high"}\n{"id":"bd-bbb22","category":"closed-obsolete","evidence":"CHANGELOG.md","confidence":"medium"}\n' > "$T/man/manifest-1.jsonl"
  run "$APPLY" --inventory "$T/sw" --manifests "$T/man" --validate
  [ "$status" -eq 1 ]; [[ "$output" == *"bd-aaa11 (closed-implemented): evidence does not resolve"* ]]   # a directory is not a blob
}

@test "SW-20 sample --check: several verification rows for one id — any disagreement counts" {
  freeze; write_manifests
  run "$SAMPLE" --manifests "$T/man" --out "$T/s.jsonl" --pct 100
  [ "$status" -eq 0 ]
  { jq -c '{id, agree: true, evidence: "first look"}' "$T/s.jsonl"; jq -c 'select(.id == "bd-aaa11") | {id, agree: false, evidence: "re-check: fix never landed"}' "$T/s.jsonl"; } > "$T/v.jsonl"
  run "$SAMPLE" --check "$T/s.jsonl" "$T/v.jsonl"
  [ "$status" -eq 1 ]; [[ "$output" == *"bd-aaa11"*"DISAGREES"*"re-check"* ]]
}
