# 1. 启动本地静态服务托管 web/index.html
python3 -m http.server 8080 -d web > /tmp/web.log 2>&1 &
sleep 1

# 2. 安装 playwright 及 chromium（若环境尚未安装）
pip install -q playwright && playwright install chromium

# 3. 在终端执行单行/脚本将页面保存为图片
mkdir -p tests/screenshots
python3 ./capture_web.py

# 4. 验证图片文件已生成且非空
ls -lh tests/screenshots/index_desktop.png && file tests/screenshots/index_desktop.png