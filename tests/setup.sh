if [ ! -f ./webhook ]; then
 ./get_webhook.sh
fi
npm install -g rust-just
./webhook -hooks hooks.json -port 9000 -verbose > /tmp/webhook.log 2>&1 &

sleep 1
curl -s http://localhost:9000/hooks/ || ps aux | grep webhook
