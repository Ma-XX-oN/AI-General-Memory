#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$SCRIPT_DIR"

repo_root="$(git rev-parse --show-toplevel)"
repo_root="$(cd -- "$repo_root" && pwd -P)"
if [[ "$repo_root" != "$SCRIPT_DIR" ]]; then
  printf 'ERROR: %s is not the AI-General-Memory repository root.\n' "$SCRIPT_DIR" >&2
  exit 1
fi

branch="$(git branch --show-current)"
if [[ "$branch" != "master" ]]; then
  printf 'ERROR: expected AI-General-Memory branch master, found %s.\n' "$branch" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain --untracked-files=no --ignore-submodules=none)" ]]; then
  printf 'ERROR: tracked files or submodules have local changes; refusing to pull.\n' >&2
  exit 1
fi

git pull --ff-only origin master
git submodule sync --recursive
git submodule update --init --recursive

core_path='dependencies/AIConversationCore'
expected_core="$(git rev-parse "HEAD:${core_path}")"
actual_core="$(git -C "$core_path" rev-parse HEAD)"

if [[ "$actual_core" != "$expected_core" ]]; then
  printf 'ERROR: AIConversationCore is out of sync. Expected %s, found %s.\n' \
    "$expected_core" "$actual_core" >&2
  exit 1
fi

printf 'AI-General-Memory: %s\n' "$(git rev-parse HEAD)"
printf 'AIConversationCore: %s\n' "$actual_core"
