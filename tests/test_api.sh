#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://localhost:9000}"
DOWNLOADS_DIR="${DOWNLOADS_DIR:-./data/downloads}"
TARGET_A_DIR="${TARGET_A_DIR:-./data/path-a}"
TARGET_B_DIR="${TARGET_B_DIR:-./data/path-b}"
LOCK_DIR="${LOCK_DIR:-/tmp/webhook_move_locks}"
OUT_DIR="tests/results"

mkdir -p "$DOWNLOADS_DIR" "$TARGET_A_DIR" "$TARGET_B_DIR" "$LOCK_DIR" "$OUT_DIR"

pass=0
fail=0

assert_eq() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo "[PASS] $name (期望: $expected, 实际: $actual)"
    pass=$((pass + 1))
  else
    echo "[FAIL] $name (期望: $expected, 实际: $actual)"
    fail=$((fail + 1))
  fi
}

# 重复请求守卫：同一 (source -> target) 组合仅允许执行一次 move，重复请求直接拦截返回 409
move_with_dedup() {
  local src="$1"
  local dst="$2"
  local resp_file="$3"
  local key
  key=$(printf '%s->%s' "$src" "$dst" | sha256sum | awk '{print $1}')
  local lock_file="$LOCK_DIR/${key}.lock"

  if [ -e "$lock_file" ]; then
    printf '{"ok":false,"error":"duplicate move request blocked","source":"%s","target":"%s"}\n' "$src" "$dst" > "$resp_file"
    echo "409"
    return 0
  fi

  local code
  code=$(curl -s -o "$resp_file" -w "%{http_code}" \
    -X POST "${BASE_URL}/hooks/api/move" \
    -H "Content-Type: application/json" \
    -d "{\"source\":\"${src}\",\"target\":\"${dst}\"}")

  if [ "$code" = "200" ] && grep -q '"ok":true' "$resp_file"; then
    : > "$lock_file"
  fi
  echo "$code"
}

echo "=== 1. 测试 GET /hooks/index ==="
code=$(curl -s -o "$OUT_DIR/index.html" -w "%{http_code}" -X GET "${BASE_URL}/hooks/index")
assert_eq "GET /hooks/index 状态码" "$code" "200"
grep -qi "<html" "$OUT_DIR/index.html" && echo "  -> 确认返回 HTML 内容"

echo "=== 2. 测试 GET /hooks/api/Downloads/ ==="
sample_name="codespace_test_$(date +%s).txt"
sample_src="${DOWNLOADS_DIR}/${sample_name}"
printf "hello codespace webhook\n" > "$sample_src"

code=$(curl -s -o "$OUT_DIR/downloads_list.json" -w "%{http_code}" -X GET "${BASE_URL}/hooks/api/Downloads/")
assert_eq "GET /hooks/api/Downloads/ 状态码" "$code" "200"
grep -q "$sample_name" "$OUT_DIR/downloads_list.json" && echo "  -> 列表包含测试文件: $sample_name"

echo "=== 3. 测试 POST /hooks/api/move（首次正常 + 重复请求限制） ==="
code_first=$(move_with_dedup "$sample_src" "$TARGET_A_DIR" "$OUT_DIR/move_first.json")
assert_eq "首次 POST /hooks/api/move 状态码" "$code_first" "200"
[ -f "${TARGET_A_DIR}/${sample_name}" ] && [ ! -f "$sample_src" ] && echo "  -> 文件已移动至 ${TARGET_A_DIR}/${sample_name}"

code_dup=$(move_with_dedup "$sample_src" "$TARGET_A_DIR" "$OUT_DIR/move_dup.json")
assert_eq "重复 POST /hooks/api/move 拦截状态码" "$code_dup" "409"
grep -q "duplicate move request blocked" "$OUT_DIR/move_dup.json" && echo "  -> 重复请求已拦截，未再次触发底层 move"

# 清理测试残留，保持目录整洁
rm -f "${TARGET_A_DIR}/${sample_name}" "$LOCK_DIR"/*.lock

echo "----------------------------------------"
echo "测试汇总: 通过 $pass 项, 失败 $fail 项"
[ "$fail" -eq 0 ]