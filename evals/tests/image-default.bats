#!/usr/bin/env bats
# evals/tests/image-default.bats — cycle-133 Sprint 274 (lead, from implementer D's Task 3.4 note): the three
# container launchers default to the pinned pipeline image named in evals/harness/README.md § Pipeline version,
# so an operator who omits --image runs the pinned image (CA bundle, fail-closed proxy defaults, the pinned
# Claude Code version), never a stale one.

setup() {
  R="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "ID-1 run-ablation.sh, blind-session.sh and ablation-grade.sh default --image to the README's pinned sandbox image" {
  pinned="$(grep -oE 'sandbox image \| `loa-ablation:[0-9]+`' "$R/evals/harness/README.md" | head -1 | grep -oE 'loa-ablation:[0-9]+')"
  [ -n "$pinned" ]
  grep -qE "^IMAGE=\"$pinned\"" "$R/evals/harness/run-ablation.sh"
  grep -qE "IMAGE=\"$pinned\"" "$R/evals/harness/blind-session.sh"
  grep -qE "default=\"$pinned\"" "$R/evals/harness/ablation-grade.sh"
  # the usage headers say the same
  grep -q "default $pinned" "$R/evals/harness/run-ablation.sh"
  grep -q "default $pinned" "$R/evals/harness/blind-session.sh"
  grep -q "default $pinned" "$R/evals/harness/ablation-grade.sh"
}

@test "ID-2 the Dockerfile builds the pinned tag" {
  pinned="$(grep -oE 'sandbox image \| `loa-ablation:[0-9]+`' "$R/evals/harness/README.md" | head -1 | grep -oE 'loa-ablation:[0-9]+')"
  grep -q "docker build -t $pinned" "$R/evals/harness/Dockerfile.ablation"
}
