# SlimIA in the top bar (elementary OS / Wingpanel)

A small Mochi in the panel that changes colour with what the agents are doing
(grey: SlimIA is closed · white: nothing running · blue: working · orange: waiting
for you · green: finished · red: something went wrong), and a panel with the
sessions and Claude's last answer.

It does not talk to SlimIA and opens no connection: it reads
`~/.local/share/slimia/status.json`, which the SlimIA app rewrites on every hook
event (`src-tauri/src/status.rs`). The only thing it runs is SlimIA's own
`--shortcut openChat` when you press **Open SlimIA**.

```
./install.sh      # builds it, installs it in the panel (password dialog), restarts the panel
./uninstall.sh    # takes it out again
```

Needs `valac meson ninja-build libwingpanel-dev libgranite-7-dev libjson-glib-dev`
to build. A bug in an indicator can take the panel down; the session starts it
again right away.
