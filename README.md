# PetAI-coucou: Windows and Linux, local only

A tiny animated friend (Mochi) at the top of your screen that keeps an eye on your AI coding agent sessions
(Claude Code, Codex, Gemini CLI, Cursor and others). You see what the agents do and answer, you get told when
they finish, you approve permissions and answer their questions, and the **Chat** page of its window shows
what Claude answered, like the panel of the VS Code extension. No voice, no network.

This branch is a trimmed copy of [Louis-CFM/coucou](https://github.com/Louis-CFM/coucou) (MIT) that keeps only the
Windows and Linux app (Tauri 2: Rust in `windows/src-tauri`, TypeScript in `windows/src`), and **never goes to the network**.

## What is different from upstream

**Nothing comes in.** No phone link (no TLS server, no local-network announcement, no relay), no WhatsApp gateway,
no port. Only the local pipe the agents' hooks use listens, on this computer. Approving, denying and answering an
agent's question still work, from the island.

**Nothing goes out.**
- The program has no HTTP client at all. The windows' content security policy allows no outside address.
- Removed: automatic updates and "What's new", every chat (cloud and local models, the file drop that fed it), the
  service pills (GitHub, GitLab, Gitea, Stripe, Vercel, n8n, Resend, Notion, Cal.com), « OK Coucou », the Codex plan
  gauge (it started `codex app-server`) and Spotify's cover download.
- **No voice:** no dictation, no notes of calls, no microphone, no speech model.
- Kept: the Mochi and all its animations, the agents' pills with their live steps, the alert and sound when something
  finishes, approvals and the agents' questions answered from the island, the **Chat** page that reads Claude Code's
  conversations from `~/.claude/projects`, the Claude plan gauge read from Claude Code's status line, the weekly recap
  and Spotify's local controls.
- A second lock, from the system: [windows/firewall/](windows/firewall/README.md).

The macOS, iPhone and Android apps and their CI are not here.

## Build

```
cd windows
npm install
npm run tauri dev
```

Linux needs the Tauri system libraries (webkit2gtk 4.1 and friends); see [windows/README.md](windows/README.md).
`npm test` runs the TypeScript tests, `cargo test` in `windows/src-tauri` the Rust ones. There is no ready-made installer.

## License

Code: MIT (see [LICENSE](LICENSE)). The Coucou name, Mochi and the sounds belong to Louis Raillé
([LICENSE-ASSETS.md](LICENSE-ASSETS.md)): replace them before you redistribute under another name.
