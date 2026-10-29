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
# The page with the island's own Mochi (needs Node, once, to bundle it).
if command -v node >/dev/null 2>&1 || [ -x "$HOME/.local/node/bin/node" ]; then
    PATH="$HOME/.local/node/bin:$PATH" node web/build.mjs
fi
pkexec sh -c 'install -d -m 0755 /usr/share/coucou-indicator && install -m 0644 "$1"/web/dist/* /usr/share/coucou-indicator/ && install -m 0644 "$1"/build/libcoucou.so "$2"/libcoucou.so' sh "$PWD" "$dir"
echo "installed in $dir"
# The panel loads indicators at start: restart it (the session brings it back).
pkill -x io.elementary.wingpanel 2>/dev/null || pkill -f '^io.elementary.wingpanel' || true
sleep 2
pgrep -f '^io.elementary.wingpanel' >/dev/null || (setsid io.elementary.wingpanel >/dev/null 2>&1 &)
