#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://localhost:9000}"
DOWNLOADS_DIR="${DOWNLOADS_DIR:-./data/downloads}"
TARGET_A_DIR="${TARGET_A_DIR:-./data/path-a}"
TARGET_B_DIR="${TARGET_B_DIR:-./data/path-b}"
LOCK_DIR="${MOVE_LOCK_DIR:-/tmp/webhook_move_locks}"
OUT_DIR="tests/results"

mkdir -p "$DOWNLOADS_DIR" "$TARGET_A_DIR" "$TARGET_B_DIR" "$LOCK_DIR" "$OUT_DIR"
rm -f "$LOCK_DIR"/*.lock

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

extract_body_code() {
  local file="$1"
  sed -n 's/.*"statusCode"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$file" | head -n 1
}

echo "=== 1. 测试 GET /hooks/index (HTTP 200) ==="
http_code=$(curl -s -o "$OUT_DIR/index.html" -w "%{http_code}" -X GET "${BASE_URL}/hooks/index")
assert_eq "GET /hooks/index HTTP 状态码" "$http_code" "200"
grep -qi "<html" "$OUT_DIR/index.html" && echo "  -> 确认返回 HTML"

echo "=== 2. 测试 GET /hooks/api/Downloads/ (HTTP 200 + body statusCode 200) ==="
sample_name="codespace_test_$(date +%s).txt"
sample_src="${DOWNLOADS_DIR}/${sample_name}"
printf "hello codespace\n" > "$sample_src"

http_code=$(curl -s -o "$OUT_DIR/downloads_list.json" -w "%{http_code}" -X GET "${BASE_URL}/hooks/api/Downloads/")
assert_eq "GET /hooks/api/Downloads/ HTTP 状态码" "$http_code" "200"
body_code=$(extract_body_code "$OUT_DIR/downloads_list.json")
assert_eq "GET /hooks/api/Downloads/ body statusCode" "$body_code" "200"

echo "=== 3. 测试 POST /hooks/api/move (首次 200 / 重复 409 / 缺失参数 400 / 不存在文件 404) ==="
# 3.1 首次正常移动 -> HTTP 200, body statusCode 200
http_code=$(curl -s -o "$OUT_DIR/move_first.json" -w "%{http_code}" \
  -X POST "${BASE_URL}/hooks/api/move" \
  -H "Content-Type: application/json" \
  -d "{\"source\":\"${sample_src}\",\"target\":\"${TARGET_A_DIR}\"}")
assert_eq "首次 move HTTP 状态码" "$http_code" "200"
assert_eq "首次 move body statusCode" "$(extract_body_code "$OUT_DIR/move_first.json")" "200"

# 3.2 重复请求 -> HTTP 200, body statusCode 409
http_code=$(curl -s -o "$OUT_DIR/move_dup.json" -w "%{http_code}" \
  -X POST "${BASE_URL}/hooks/api/move" \
  -H "Content-Type: application/json" \
  -d "{\"source\":\"${sample_src}\",\"target\":\"${TARGET_A_DIR}\"}")
assert_eq "重复 move HTTP 状态码" "$http_code" "200"
assert_eq "重复 move body statusCode" "$(extract_body_code "$OUT_DIR/move_dup.json")" "409"

# 3.3 非法 target -> HTTP 200, body statusCode 400
http_code=$(curl -s -o "$OUT_DIR/move_bad_target.json" -w "%{http_code}" \
  -X POST "${BASE_URL}/hooks/api/move" \
  -H "Content-Type: application/json" \
  -d "{\"source\":\"${sample_src}\",\"target\":\"./data/invalid-dir\"}")
assert_eq "非法 target HTTP 状态码" "$http_code" "200"
assert_eq "非法 target body statusCode" "$(extract_body_code "$OUT_DIR/move_bad_target.json")" "400"

# 3.4 源文件不存在 -> HTTP 200, body statusCode 404
http_code=$(curl -s -o "$OUT_DIR/move_not_found.json" -w "%{http_code}" \
  -X POST "${BASE_URL}/hooks/api/move" \
  -H "Content-Type: application/json" \
  -d "{\"source\":\"${DOWNLOADS_DIR}/not_exist_file.txt\",\"target\":\"${TARGET_B_DIR}\"}")
assert_eq "源文件不存在 HTTP 状态码" "$http_code" "200"
assert_eq "源文件不存在 body statusCode" "$(extract_body_code "$OUT_DIR/move_not_found.json")" "404"

# 清理测试文件与锁
rm -f "${TARGET_A_DIR}/${sample_name}" "$LOCK_DIR"/*.lock

echo "----------------------------------------"
echo "测试汇总: 通过 $pass 项, 失败 $fail 项"
[ "$fail" -eq 0 ]