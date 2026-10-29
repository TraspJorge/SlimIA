#!/bin/sh
# Runs Coucou on Linux with every network address denied except this computer
# (127.0.0.0/8 and ::1), enforced by the kernel through systemd's cgroup
# filter. A model server on 127.0.0.1 (Ollama, LM Studio) still works.
#
#   ./run-offline.sh /path/to/coucou
#
# Needs systemd with cgroup v2 and sudo: the filter is set by the system
# manager (a user manager cannot load it). The program itself still runs as
# you. Not tested on every distribution: check it with
#   sudo systemd-run --scope -p IPAddressDeny=any -p IPAddressAllow=localhost curl -sS https://example.com
# which must fail, while http://127.0.0.1:11434 (if Ollama runs) must answer.

set -eu

program="${1:?usage: run-offline.sh /path/to/coucou}"

# What a desktop program needs to find your session (display, bus, runtime dir).
env_args=""
for var in DISPLAY XAUTHORITY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_SESSION_TYPE HOME; do
    value=$(printenv "$var" || true)
    [ -n "$value" ] && env_args="$env_args $var=$value"
done

# shellcheck disable=SC2086
exec sudo systemd-run --scope --quiet \
    --uid "$(id -u)" --gid "$(id -g)" \
    -p IPAddressDeny=any \
    -p "IPAddressAllow=localhost" \
    env $env_args "$program"
