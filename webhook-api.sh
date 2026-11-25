#!/bin/sh
set -eu

action="${1:-}"

downloads_dir="${DOWNLOADS_DIR:-./data/downloads}"
path_a="${TARGET_A_DIR:-./data/path-a}"
path_b="${TARGET_B_DIR:-./data/path-b}"
lock_dir="${MOVE_LOCK_DIR:-/tmp/webhook_move_locks}"

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\n'
}

# 统一以 exit 0 输出（配合 webhook 返回 HTTP 200），将业务状态码写入 JSON body
respond_json() {
  code="$1"
  payload="$2"
  printf '{"statusCode":%s,%s}\n' "$code" "$payload"
  exit 0
}

fail_with_code() {
  code="$1"
  msg="$2"
  respond_json "$code" "\"ok\":false,\"error\":\"$(json_escape "$msg")\""
}

list_files() {
  [ -d "$downloads_dir" ] || fail_with_code 404 "downloads directory not found: $downloads_dir"
  items=''
  sep=''
  while IFS= read -r f; do
    name=$(basename "$f")
    size=$(wc -c < "$f" | tr -d '[:space:]')
    ctime=$(stat -c %W "$f" 2>/dev/null || echo 0)
    case "$ctime" in
      ''|0|'?') ctime=$(stat -c %Y "$f" 2>/dev/null || echo 0) ;;
    esac
    created=$(date -u -d "@$ctime" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)
    entry=$(printf '%s{"filename":"%s","size":%s,"createdAt":"%s","path":"%s"}' \
      "$sep" "$(json_escape "$name")" "$size" "$created" "$(json_escape "$f")")
    items="${items}${entry}"
    sep=','
  done <<EOF
$(find "$downloads_dir" -mindepth 1 -maxdepth 1 -type f | sort)
EOF
  respond_json 200 "\"ok\":true,\"data\":[${items}]"
}

move_file() {
  src="${2:-}"
  target_dir="${3:-}"
  [ -n "$src" ] || fail_with_code 400 "source is required"
  [ -n "$target_dir" ] || fail_with_code 400 "target is required"

  case "$src" in
    "$downloads_dir"/*) ;;
    *) fail_with_code 400 "source must be inside $downloads_dir" ;;
  esac

  case "$target_dir" in
    "$path_a"|"$path_b") ;;
    *) fail_with_code 400 "target must be path A or path B" ;;
  esac

  [ -f "$src" ] || fail_with_code 404 "source file not found: $src"

  mkdir -p "$lock_dir" || fail_with_code 500 "cannot create lock directory"
  key=$(printf '%s->%s' "$src" "$target_dir" | cksum | awk '{print $1"_"$2}')
  lock_file="$lock_dir/${key}.lock"
  if [ -e "$lock_file" ]; then
    fail_with_code 409 "duplicate move request blocked"
  fi

  mkdir -p "$target_dir" || fail_with_code 500 "cannot create target directory"
  base=$(basename "$src")
  target="$target_dir/$base"
  [ ! -e "$target" ] || fail_with_code 409 "target file already exists: $target"

  mv -- "$src" "$target" || fail_with_code 500 "move failed"
  : > "$lock_file"

  respond_json 200 "\"ok\":true,\"source\":\"$(json_escape "$src")\",\"target\":\"$(json_escape "$target")\""
}

case "$action" in
  list) list_files ;;
  move) move_file "$@" ;;
  *) fail_with_code 400 "unknown action" ;;
esac