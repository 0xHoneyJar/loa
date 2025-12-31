#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_dir="${repo_root}/.codex/prompts"
dest_dir="${CODEX_HOME:-$HOME/.codex}/prompts"

if [[ ! -d "${src_dir}" ]]; then
  echo "Missing prompts source directory: ${src_dir}" >&2
  exit 1
fi

mkdir -p "${dest_dir}"

shopt -s nullglob
prompt_files=("${src_dir}"/*.md)
shopt -u nullglob

if [[ ${#prompt_files[@]} -eq 0 ]]; then
  echo "No prompts found in ${src_dir}" >&2
  exit 1
fi

cp -f "${src_dir}"/*.md "${dest_dir}/"

echo "Installed ${#prompt_files[@]} Loa prompts to ${dest_dir}."
echo "Restart Codex or open a new session to load updated prompts."
