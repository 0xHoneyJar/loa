#!/usr/bin/env bash
# plant.sh DIR — writes the secret-classes scan fixture into DIR and prints its path list.
# Every credential-shaped string is assembled at run time, so this file and the
# golden hit list carry no credential-shaped literal (the hit list names path:line:class only).
set -euo pipefail
export LC_ALL=C
d="$1"
mkdir -p "$d/a" "$d/b/c"
rep() { local s="" i; for ((i = 0; i < $2; i++)); do s="$s$1"; done; printf '%s' "$s"; }
body="$(rep 'Ab1Cd2Ef3Gh4' 3)"            # 36 characters, letters and digits, > 6 distinct
{
  printf 'line one has nothing\n'
  printf -- '-----%s %s-----\n' 'BEGIN RSA PRIVATE' 'KEY'
  printf 'anthropic %s%s\n' 'sk-' "ant-$body"
  printf 'openai %s%s\n' 'sk-' "$body"
  printf 'github %s%s and %s%s\n' 'gh' "p_$body" 'github_' "pat_${body}_x"
  printf 'aws %s%s\n' 'AK' "IA$(rep 'Q7R8S9T0' 2)"
  printf 'google %s%s\n' 'AI' "za$(rep 'Ab1Cd2E' 5)"
  printf 'slack %s%s\n' 'xo' "xb-$(rep 'a1b2c3d4' 2)"
  printf 'auth: %s %s\n' 'Bearer' "$body"
} > "$d/a/creds.txt"
{
  printf 'placeholder %s%s\n' 'gh' "p_$(rep 'x' 36)"
  printf 'placeholder %s%s\n' 'sk-' "$(rep '0' 24)"
  printf 'placeholder %s%s\n' 'sk-' "ant-$(rep 'REDACTED' 3)"
  printf 'prose %s %s\n' 'Bearer' 'authentication-is-required-for-this'
  printf 'aws placeholder %s%s\n' 'AK' "IA$(rep 'X' 16)"
} > "$d/b/c/placeholders.md"
{
  printf 'export %s%s\n' 'LOA_AUDIT_KEY_' 'PASSWORD=redacted'
  printf 'plain\n'
  printf 'both %s%s and %s%s\n' 'LOA_AUDIT_KEY_' 'PASSWORD=x' 'gh' "s_$body"
} > "$d/b/env.sh"
printf 'a/creds.txt\nb/c/placeholders.md\nb/env.sh\n'
