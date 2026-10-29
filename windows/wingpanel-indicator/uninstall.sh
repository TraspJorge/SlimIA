#!/bin/sh
# Takes the indicator out of the panel and restarts the panel.
set -eu
dir=$(pkg-config --variable=indicatorsdir wingpanel)
pkexec rm -rf "$dir/libcoucou.so" /usr/share/coucou-indicator
pkill -f '^io.elementary.wingpanel' 2>/dev/null || true
sleep 2
pgrep -f '^io.elementary.wingpanel' >/dev/null || (setsid io.elementary.wingpanel >/dev/null 2>&1 &)
echo "removed"
