#!/bin/sh
set -eu

action="${1:-}"

downloads_dir="${DOWNLOADS_DIR:-/data/downloads}"
path_a="${TARGET_A_DIR:-/data/path-a}"
path_b="${TARGET_B_DIR:-/data/path-b}"

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\n'
}

fail() {
  printf '{"ok":false,"error":"%s"}\n' "$(json_escape "$1")"
  exit 1
}

list_files() {
  [ -d "$downloads_dir" ] || fail "downloads directory not found: $downloads_dir"
  printf '['
  sep=''
  find "$downloads_dir" -mindepth 1 -maxdepth 1 -type f -print | while IFS= read -r f; do
    name=$(basename "$f")
    size=$(wc -c < "$f" | tr -d '[:space:]')
    ctime=$(stat -c %W "$f" 2>/dev/null || echo 0)
    case "$ctime" in
      ''|0|'?') ctime=$(stat -c %Y "$f" 2>/dev/null || echo 0) ;;
    esac
    created=$(date -u -d "@$ctime" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)
    printf '%s{"filename":"%s","size":%s,"createdAt":"%s","path":"%s"}' \
      "$sep" "$(json_escape "$name")" "$size" "$created" "$(json_escape "$f")"
    sep=','
  done
  printf ']\n'
}

move_file() {
  src="${2:-}"
  target_dir="${3:-}"
  [ -n "$src" ] || fail "source is required"
  [ -n "$target_dir" ] || fail "target is required"
  case "$src" in
    "$downloads_dir"/*) ;;
    *) fail "source must be inside $downloads_dir" ;;
  esac
  case "$target_dir" in
    "$path_a"|"$path_b") ;;
    *) fail "target must be path A or path B" ;;
  esac
  [ -f "$src" ] || fail "source file not found: $src"
  mkdir -p "$target_dir" || fail "cannot create target directory"
  base=$(basename "$src")
  target="$target_dir/$base"
  [ ! -e "$target" ] || fail "target file already exists: $target"
  mv -- "$src" "$target" || fail "move failed"
  printf '{"ok":true,"source":"%s","target":"%s"}\n' "$(json_escape "$src")" "$(json_escape "$target")"
}

case "$action" in
  list) list_files ;;
  move) move_file "$@" ;;
  *) fail "unknown action" ;;
esac
