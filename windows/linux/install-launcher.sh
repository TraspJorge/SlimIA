#!/bin/sh
# Puts SlimIA in the applications menu (and its icon in the user's icon theme), for this user only.
#   ./linux/install-launcher.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
exe="$here/target/release/coucou"
[ -x "$exe" ] || { echo "build it first: npx tauri build --no-bundle" >&2; exit 1; }
icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$icons/128x128/apps" "$icons/256x256/apps" "$icons/32x32/apps" "$apps"
install -m 0644 "$here/src-tauri/icons/128x128.png" "$icons/128x128/apps/slimia.png"
install -m 0644 "$here/src-tauri/icons/128x128@2x.png" "$icons/256x256/apps/slimia.png"
install -m 0644 "$here/src-tauri/icons/32x32.png" "$icons/32x32/apps/slimia.png"
cat > "$apps/slimia.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=SlimIA
Comment=Mochi na barra superior: acompanha seus agentes de código, local
Exec=env GDK_BACKEND=x11 $exe
Icon=slimia
Terminal=false
Categories=Development;Utility;
StartupWMClass=coucou
EOF
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$icons" || true
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$apps" || true
echo "SlimIA is in the applications menu."
