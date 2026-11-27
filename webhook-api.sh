#!/usr/bin/env sh
set -eu

DOWNLOADS_DIR="${DOWNLOADS_DIR:-./data/downloads}"
LOCK_DIR="${MOVE_LOCK_DIR:-/tmp/webhook_move_locks}"
TARGETS_FILE="${TARGETS_FILE:-./list_targets.csv}"

respond_json() {
  printf '%s\n' "$1"
  exit 0
}

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g' -e 's/\r/\\r/g' -e 's/\t/\\t/g'
}

trim() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

strip_quotes() {
  val=$(trim "$1")
  case "$val" in
    \"*\")
      val="${val#\"}"
      val="${val%\"}"
      val=$(printf '%s' "$val" | sed -e 's/""/"/g')
      ;;
  esac
  printf '%s' "$val"
}

parse_targets() {
  [ -f "$TARGETS_FILE" ] || return 0
  tr -d '\r' < "$TARGETS_FILE" | while IFS= read -r line || [ -n "$line" ]; do
    clean_line=$(trim "$line")
    [ -z "$clean_line" ] && continue
    case "$clean_line" in
      \#*) continue ;;
    esac
    case "$clean_line" in
      *,*) ;;
      *) continue ;;
    esac
    raw_name="${clean_line%%,*}"
    raw_target="${clean_line#*,}"
    t_name=$(strip_quotes "$raw_name")
    t_path=$(strip_quotes "$raw_target")
    if [ "$t_name" = "name" ] && [ "$t_path" = "target" ]; then
      continue
    fi
    [ -n "$t_name" ] && [ -n "$t_path" ] && printf '%s\t%s\n' "$t_name" "$t_path"
  done
}

is_valid_target() {
  candidate="$1"
  parse_targets | while IFS='	' read -r _name t_path; do
    if [ "$t_path" = "$candidate" ]; then
      printf '1\n'
      return 0
    fi
  done
}

targets_json() {
  out=""
  first=1
  while IFS='	' read -r t_name t_path; do
    [ -z "$t_name" ] && continue
    esc_name=$(json_escape "$t_name")
    esc_path=$(json_escape "$t_path")
    item="{\"name\":\"${esc_name}\",\"target\":\"${esc_path}\"}"
    if [ "$first" -eq 1 ]; then
      out="$item"
      first=0
    else
      out="${out},${item}"
    fi
  done <<EOF
$(parse_targets)
EOF
  printf '[%s]' "$out"
}

lock_key_for() {
  printf '%s' "$1" | cksum | awk '{print $1 "_" $2}'
}

list_downloads() {
  mkdir -p "$DOWNLOADS_DIR"
  out=""
  first=1
  for entry in "$DOWNLOADS_DIR"/*; do
    [ -e "$entry" ] || continue
    [ -f "$entry" ] || continue
    fname=$(basename "$entry")
    size=$(wc -c < "$entry" | tr -d '[:space:]')
    ts=$(date -u -r "$entry" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
    esc_name=$(json_escape "$fname")
    esc_path=$(json_escape "$entry")
    esc_ts=$(json_escape "$ts")
    item="{\"filename\":\"${esc_name}\",\"size\":${size},\"createdAt\":\"${esc_ts}\",\"path\":\"${esc_path}\"}"
    if [ "$first" -eq 1 ]; then
      out="$item"
      first=0
    else
      out="${out},${item}"
    fi
  done
  respond_json "{\"statusCode\":200,\"ok\":true,\"data\":[${out}]}"
}

move_file() {
  src="${1:-}"
  dst_dir="${2:-}"

  if [ -z "$src" ] || [ -z "$dst_dir" ]; then
    respond_json '{"statusCode":400,"ok":false,"error":"missing source or target"}'
  fi

  case "$src" in
    ./data/downloads/* | data/downloads/*) ;;
    *) respond_json '{"statusCode":400,"ok":false,"error":"invalid source path"}' ;;
  esac

  case "$src" in
    *..*) respond_json '{"statusCode":400,"ok":false,"error":"path traversal blocked"}' ;;
  esac

  if [ -z "$(is_valid_target "$dst_dir")" ]; then
    respond_json '{"statusCode":400,"ok":false,"error":"invalid target directory"}'
  fi

  if [ ! -f "$src" ]; then
    respond_json '{"statusCode":404,"ok":false,"error":"source file not found"}'
  fi

  mkdir -p "$dst_dir" "$LOCK_DIR"
  base_name=$(basename "$src")
  dst_file="${dst_dir}/${base_name}"
  lock_file="${LOCK_DIR}/$(lock_key_for "${src}->${dst_dir}").lock"

  if [ -e "$lock_file" ]; then
    respond_json '{"statusCode":409,"ok":false,"error":"duplicate move request blocked"}'
  fi

  if [ -e "$dst_file" ]; then
    respond_json '{"statusCode":409,"ok":false,"error":"target file already exists"}'
  fi

  : > "$lock_file"
  if mv "$src" "$dst_file"; then
    esc_src=$(json_escape "$src")
    esc_dst=$(json_escape "$dst_dir")
    respond_json "{\"statusCode\":200,\"ok\":true,\"source\":\"${esc_src}\",\"target\":\"${esc_dst}\"}"
  else
    rm -f "$lock_file"
    respond_json '{"statusCode":500,"ok":false,"error":"failed to move file"}'
  fi
}

cmd="${1:-}"
case "$cmd" in
  list)
    list_downloads
    ;;
  targets)
    respond_json "{\"statusCode\":200,\"ok\":true,\"data\":$(targets_json)}"
    ;;
  move)
    move_file "${2:-}" "${3:-}"
    ;;
  *)
    respond_json '{"statusCode":400,"ok":false,"error":"unknown command"}'
    ;;
esac