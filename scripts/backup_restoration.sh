#!/usr/bin/env bash
# Local/private backup including ignored paid assets. Never uploads anything.
set -euo pipefail
project_root="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
backup_dir="${1:?Supply an absolute backup directory outside the project}"
case "$backup_dir" in
  /*) ;;
  *) echo "Backup directory must be absolute" >&2; exit 1 ;;
esac
mkdir -p "$backup_dir"
backup_dir="$(realpath "$backup_dir")"
case "$backup_dir/" in
  "$project_root/"*) echo "Backup must be outside the project" >&2; exit 1 ;;
esac
stamp="$(date +%Y%m%d-%H%M%S)"
archive="$backup_dir/lea177-$stamp.tar.gz"
bundle="$backup_dir/lea177-$stamp.bundle"
test ! -e "$archive"
test ! -e "$bundle"
git -C "$project_root" bundle create "$bundle" HEAD
tar --exclude='./.git' --exclude='.godot' --exclude='__pycache__' \
  --exclude='./artifacts-local/xdg' -czf "$archive" -C "$project_root" .
gzip -t "$archive"
git -C "$project_root" bundle verify "$bundle"
tar -tzf "$archive" > "$archive.files.txt"
for required in project.godot src/maps/main_battlefield/main_battlefield.tscn \
  src/samples/roads/base_demo.tscn src/samples/buildings/2story_wide_colors_demo.tscn \
  assets/AtomicRealmModularRoads/catalog.json src/world/roads/modules.json; do
  rg -Fx "./$required" "$archive.files.txt" > /dev/null
done
sha256sum "$archive" "$bundle" > "$archive.sha256"
printf 'LOCAL_BACKUP_PASS\nArchive: %s\nGit bundle: %s\nChecksums: %s\n' "$archive" "$bundle" "$archive.sha256"
