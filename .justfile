setup:
    ./tests/setup.sh
jtapi:
    ./tests/setup.sh
    ./tests/test_api.sh
pyimg:
    ./tests/setup.sh
    ./tests/run_capture_web_py.sh

nopyimg:
    ./tests/setup.sh
    ./tests/run_capture_web_nopy.sh
ps:
    ps -ef|grep webhook