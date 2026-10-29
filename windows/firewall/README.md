# Block Slimai's network from the system

Slimai's code already refuses every address that is not this computer (`src-tauri/src/net.rs`),
is built without TLS and has a content security policy with no outside address. These scripts add
a second lock that does not depend on the code: the operating system itself blocks the network
for Slimai.

| System | Script | How |
|---|---|---|
| Windows | [block-network.ps1](block-network.ps1) | Windows Defender Firewall rules, inbound and outbound, for `coucou.exe` and `coucou-hook.exe`. Loopback is not filtered, so a local model (Ollama, LM Studio) still works. |
| Linux | [run-offline.sh](run-offline.sh) | Starts Slimai in a systemd scope with `IPAddressDeny=any` and `IPAddressAllow=localhost`. |

**Limit on Windows.** The rules cover `coucou.exe` and `coucou-hook.exe`. The page itself is drawn by
Microsoft's WebView2 runtime, which runs as its own `msedgewebview2.exe`. Slimai's page asks for nothing
outside (its content security policy allows no address), but that runtime has its own background
traffic (component updates) that these rules do not block, and blocking `msedgewebview2.exe` would
also cut every other program that uses it. On Linux the scope covers the web view too, since it runs
inside it.

Neither script is run by anything: you run them yourself, once (Windows) or each time you start
Slimai (Linux). The Windows rules can be removed with `-Remove`. They were written for this branch
and have not been run on a real Windows or Linux desktop yet: test them (the Linux script has a
one-line check in its header) before relying on them.
