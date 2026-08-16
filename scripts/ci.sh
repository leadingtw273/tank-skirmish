#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

godot_bin="${GODOT_BIN:-godot}"
artifact_dir="$project_root/artifacts/ci"

export XDG_DATA_HOME="${XDG_DATA_HOME:-$project_root/.godot/xdg/data}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$project_root/.godot/xdg/cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$project_root/.godot/xdg/config}"

mkdir -p "$artifact_dir" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"

test -f project.godot
test -f src/main.tscn
test -f tests/smoke.gd
command -v "$godot_bin" >/dev/null 2>&1 || {
  echo "Godot executable not found: $godot_bin" >&2
  exit 1
}

run_godot() {
  local log_path="$1"
  shift

  "$godot_bin" "$@" 2>&1 | tee "$log_path"
  if grep -Eq '(^|[[:space:]])(ERROR:|SCRIPT ERROR:)' "$log_path"; then
    echo "Godot reported an error; see $log_path" >&2
    return 1
  fi
}

"$godot_bin" --version | tee "$artifact_dir/version.txt"
run_godot "$artifact_dir/import.log" --headless --path . --import
run_godot "$artifact_dir/smoke.log" --headless --audio-driver Dummy --path . --script res://tests/smoke.gd

if ! git diff --quiet -- project.godot; then
  echo "Godot import modified protected project.godot; host review is required." >&2
  git diff -- project.godot >&2
  exit 1
fi
