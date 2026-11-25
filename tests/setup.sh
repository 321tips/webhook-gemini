if [ ! -f ./webhook ]; then
 ./get_webhook.sh
if

./webhook -hooks hooks.json -port 9000 -verbose > /tmp/webhook.log 2>&1 &