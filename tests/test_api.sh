#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${WEBHOOK_URL:-http://localhost:9000}"
HOOK_PATH="${HOOK_PATH:-/hooks/deploy}"

echo "=== 1. 正常 POST 触发测试 ==="
curl -i -s -X POST "${BASE_URL}${HOOK_PATH}" \
  -H "Content-Type: application/json" \
  -d '{"event":"test","source":"codespace"}' | head -n 15

echo "=== 2. 不存在路由 404 测试 ==="
code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/hooks/non-existent-hook")
echo "Non-existent hook status: $code"

echo "=== 3. 非法方法测试 ==="
method_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "${BASE_URL}${HOOK_PATH}")
echo "DELETE method status: $method_code"