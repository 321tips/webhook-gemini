#!/usr/bin/env bash
set -euo pipefail
if [ ! -f ./webhook ]; then
 ./get_webhook.sh
fi
downloads_dir="${DOWNLOADS_DIR:-./data/downloads}"
path_a="${TARGET_A_DIR:-./data/path-a}"
path_b="${TARGET_B_DIR:-./data/path-b}"
echo $downloads_dir
if [ ! -d $downloads_dir]; then
    mkdir -p $downloads_dir
    echo "测试文件A.m4a" > $downloads_dir/测试文件A.m4a
    echo "测试文件B.mp4" > $downloads_dir/测试文件B.mp4
    echo "测试文件C.txt" $downloads_dir/测试文件C.txt
fi
if [ ! -d $path_a]; then
    mkdir -p $path_a
fi
if [ ! -d $path_b]; then
    mkdir -p $path_b
fi

npm install -g rust-just
./webhook -hooks hooks.json -port 9000 -verbose > /tmp/webhook.log 2>&1 &

sleep 1
curl -s http://localhost:9000/hooks/ || ps aux | grep webhook
