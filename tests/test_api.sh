#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://localhost:9000}"
OUT_DIR="tests/results"
mkdir -p "$OUT_DIR"

pass=0
fail=0

check_status() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo "[PASS] $name (HTTP $actual)"
    pass=$((pass + 1))
  else
    echo "[FAIL] $name (期望 HTTP $expected, 实际 HTTP $actual)"
    fail=$((fail + 1))
  fi
}

echo "=== 1. 测试 /hooks/index (GET HTML) ==="
code=$(curl -s -o "$OUT_DIR/index.html.out" -w "%{http_code}" -X GET "${BASE_URL}/hooks/index")
check_status "GET /hooks/index" "$code" "200"
grep -qi "<html" "$OUT_DIR/index.html.out" && echo "  -> 响应包含 HTML 结构"

echo "=== 2. 测试 /hooks/api/Downloads/ (GET list) ==="
code=$(curl -s -o "$OUT_DIR/downloads_list.json" -w "%{http_code}" -X GET "${BASE_URL}/hooks/api/Downloads/")
check_status "GET /hooks/api/Downloads/" "$code" "200"
cat "$OUT_DIR/downloads_list.json"; echo ""



echo "=== 3. 测试 /hooks/api/move (POST JSON payload) ==="
code=$(curl -s -o "$OUT_DIR/move_resp.json" -w "%{http_code}" \
  -X POST "${BASE_URL}/hooks/api/move" \
  -H "Content-Type: application/json" \
  -d '{"source":"test_src","target":"test_dst"}')
check_status "POST /hooks/api/move" "$code" "200"
cat "$OUT_DIR/move_resp.json"; echo ""

echo "=== 4. 负向测试：错误 HTTP 方法与不存在的路径 ==="
bad_method=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/hooks/api/Downloads/")
check_status "POST on GET-only /hooks/api/Downloads/" "$bad_method" "405"

not_found=$(curl -s -o /dev/null -w "%{http_code}" -X GET "${BASE_URL}/hooks/api/not_exists")
check_status "GET unknown hook" "$not_found" "404"

echo "----------------------------------------"
echo "测试汇总: 通过 $pass 项, 失败 $fail 项"
[ "$fail" -eq 0 ]