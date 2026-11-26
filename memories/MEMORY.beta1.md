# MEMORY.md — Long-Term Memory

*Your curated memories. The distilled essence, not raw logs.*
# Web 应用开发规范文档（单页 HTML + Webhook 后端）

## 1. 系统架构与核心约束
- **运行环境**：固定为 GitHub Codespaces 终端环境。
- **架构模式**：前后端分离的单体轻量化架构，**严禁引入 Nginx、Python 代理等任何额外第三方中间服务**。
- **前端形态**：单页面 HTML 文件（`web/index.html`），所有 CSS 样式与 JavaScript 逻辑必须内联在 `<style>` 和 `<script>` 标签中，**页面代码中严禁包含任何注释**。
- **后端形态**：由 `adnanh/webhook` 二进制文件加载 `hooks.json` 暴露 HTTP 接口，底层通过 `/bin/sh` 调用 `webhook-api.sh` 执行文件操作。
- **通信与状态码协议**：
  - 后端所有业务接口统一返回 **HTTP 200** 状态码。
  - 真实业务状态码封装在响应 JSON Body 的 `statusCode` 字段中（如 `200`、`400`、`404`、`409`、`500`）。

---

## 2. 目录结构约定
```text
.
├── hooks.json                  # Webhook 路由与命令映射配置
├── webhook-api.sh              # 后端核心业务 Shell 脚本
├── web/
│   └── index.html              # 前端单页面（内联 CSS/JS，无注释）
├── data/
│   ├── downloads/              # 默认源文件目录 (DOWNLOADS_DIR)
│   ├── path-a/                 # 目标目录 A (TARGET_A_DIR)
│   └── path-b/                 # 目标目录 B (TARGET_B_DIR)
└── tests/
    ├── test_hooks_api.sh       # 后端 API 自动化测试脚本
    ├── test_web_playwright.py  # 前端 Playwright 自动化操作与截图脚本
    ├── results/                # API 测试响应留档
    └── screenshots/            # 前端自动化测试截图输出目录
```

---

## 3. 后端接口契约（`hooks.json` & `webhook-api.sh`）

### 3.1 路由映射（默认端口 `9000`）
| 完整路径 | HTTP 方法 | 底层命令 | 响应类型 | 核心作用 |
| :--- | :--- | :--- | :--- | :--- |
| `/hooks/index` | `GET` | `/bin/cat web/index.html` | `text/html; charset=utf-8` | 返回前端单页面 HTML |
| `/hooks/api/Downloads/` | `GET` | `/bin/sh webhook-api.sh list` | `application/json; charset=utf-8` | 扫描并返回 `downloads` 目录文件列表 |
| `/hooks/api/move` | `POST` | `/bin/sh webhook-api.sh move <source> <target>` | `application/json; charset=utf-8` | 移动指定文件至目标目录并防重 |

### 3.2 响应体数据格式规范
- **统一响应信封**：
  - 成功：`{"statusCode":200,"ok":true,"data":...}`（`move` 接口返回 `{"statusCode":200,"ok":true,"source":"...","target":"..."}`）
  - 失败：`{"statusCode":<400|404|409|500>,"ok":false,"error":"<错误描述>"}`
- **`/hooks/api/Downloads/` 正常返回示例**：
  ```json
  {
    "statusCode": 200,
    "ok": true,
    "data": [
      {
        "filename": "测试文件A.m4a",
        "size": 18,
        "createdAt": "2026-11-25T08:42:54Z",
        "path": "./data/downloads/测试文件A.m4a"
      }
    ]
  }
  ```

### 3.3 后端核心逻辑要求（`webhook-api.sh`）
1. **统一退出码**：脚本无论业务成功或失败均执行 `exit 0` 配合 `respond_json` 输出，确保 `webhook` 始终返回 HTTP 200。
2. **路径安全校验（`move`）**：
   - `source` 必须位于 `./data/downloads/*` 目录下且文件存在（缺失返回 `400`，文件不存在返回 `404`）。
   - `target` 必须严格匹配 `./data/path-a` 或 `./data/path-b`（否则返回 `400`）。
3. **重复请求限制（防重锁）**：
   - 依托本地锁目录 `/tmp/webhook_move_locks`（环境变量 `MOVE_LOCK_DIR`），以 `source->target` 生成唯一哈希锁文件。
   - 若锁文件已存在，或目标路径已存在同名文件，直接拦截并返回 `statusCode: 409`（`duplicate move request blocked` / `target file already exists`）。

---

## 4. 前端交互与对接规范（`web/index.html`）
- **编码规范**：单文件 HTML，所有样式置于 `<style>`，所有脚本置于 `<script>`，**不得出现任何 HTML/CSS/JS 注释**。
- **初始化加载**：页面加载完成立即通过 `fetch('/hooks/api/Downloads/')` 获取文件列表并渲染至 `#list`。
- **响应解析**：前端须解析 JSON 响应体，校验 `statusCode === 200` 且 `ok !== false`，兼容读取 `data` 数组（或字符串化 JSON）进行列表渲染。
- **移动操作流程**：
  1. 点击列表项上的“移动”按钮（`.move`），打开模态框（`#modal`）。
  2. 选择目标路径 A（`./data/path-a`）或路径 B（`./data/path-b`）。
  3. 点击确认移动（`#confirm`），发送 `POST /hooks/api/move`（JSON Body: `{"source": file.path, "target": selectedTarget}`）。
  4. 校验返回体 `statusCode === 200`，成功后关闭弹窗并重新调用 `loadFiles()` 刷新列表；失败则弹窗提示 `error` 信息。

---

## 5. GitHub Codespaces 自动化测试规范

### 5.1 服务启动命令
```bash
chmod +x webhook-api.sh
webhook -hooks ./hooks.json -port 9000 -verbose > /tmp/webhook.log 2>&1 &
```

### 5.2 后端 API 测试要求（`tests/test_hooks_api.sh`）
- 校验 `GET /hooks/index` 返回 HTTP 200 及 HTML 内容。
- 校验 `GET /hooks/api/Downloads/` 返回 HTTP 200 且响应体 `statusCode` 为 `200`。
- 校验 `POST /hooks/api/move` 全场景（所有场景 HTTP 状态码均为 `200`，通过解析响应体 `statusCode` 断言）：
  - 首次合法移动 -> `statusCode: 200`
  - 相同参数重复请求 -> `statusCode: 409`
  - 非法目标目录 -> `statusCode: 400`
  - 源文件不存在 -> `statusCode: 404`

### 5.3 前端页面测试与截图要求（`tests/test_web_playwright.py`）
- 使用 Python `playwright.sync_api` 无头模式（视口 `1440x900`）在终端执行，**代码中不添加任何注释**。
- 必须按顺序执行并保存以下 3 张完整页面截图至 `tests/screenshots/`：
  1. `index_desktop.png`：访问 `http://127.0.0.1:9000/hooks/index` 等待 `networkidle` 后的初始页面截图。
  2. `点刷新按钮后图片.png`：点击 `#refresh` 按钮并等待 `/hooks/api/Downloads/` 响应完成后的截图。
  3. `点移动按钮后图片.png`：点击列表首项 `.move` 按钮并等待 `#modal` 弹窗可见后的截图。