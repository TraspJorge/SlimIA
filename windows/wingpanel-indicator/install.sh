#!/bin/sh
# Builds the indicator and installs it into the panel (asks for your password
# through the system's own dialog), then restarts the panel so it shows up.
#   ./install.sh            install
#   ./uninstall.sh          remove it again
set -eu
cd "$(dirname "$0")"
dir=$(pkg-config --variable=indicatorsdir wingpanel)
[ -d build ] || meson setup build
ninja -C build
pkexec install -m 0644 "$PWD/build/libcoucou.so" "$dir/libcoucou.so"
echo "installed in $dir"
# The panel loads indicators at start: restart it (the session brings it back).
pkill -x io.elementary.wingpanel 2>/dev/null || pkill -f '^io.elementary.wingpanel' || true
sleep 2
pgrep -f '^io.elementary.wingpanel' >/dev/null || (setsid io.elementary.wingpanel >/dev/null 2>&1 &)
