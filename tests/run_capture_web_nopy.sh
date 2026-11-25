# 1. 启动本地静态服务托管 web/index.html
python3 -m http.server 8080 -d web > /tmp/web.log 2>&1 &
sleep 1


sudo apt-get install -y chromium
mkdir -p tests/screenshots
BIN=$(command -v chromium || command -v chromium-browser || command -v google-chrome)
"$BIN" --headless --disable-gpu --window-size=1440,900 \
  --screenshot=tests/screenshots/index_cli.png \
  "http://127.0.0.1:8080/index.html"
ls -lh tests/screenshots/index_cli.png