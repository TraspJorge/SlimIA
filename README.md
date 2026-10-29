# PetAI-coucou: Windows and Linux, local only

A tiny animated friend (Mochi) at the top of your screen that keeps an eye on your AI coding agent sessions
(Claude Code, Codex, Gemini CLI, Cursor and others). You approve permissions, watch what the agents do and chat
with a model that runs on your own PC.

This branch is a trimmed copy of [Louis-CFM/coucou](https://github.com/Louis-CFM/coucou) (MIT) that keeps only the
Windows and Linux app (Tauri 2: Rust in `windows/src-tauri`, TypeScript in `windows/src`), and **never goes to the network**.

## What is different from upstream

**Nothing comes in.** No phone link (no TLS server, no local-network announcement, no relay), no WhatsApp gateway,
no port. Only the local pipe the agents' hooks use listens, on this computer. Approving, denying and answering an
agent's question still work, from the island.

**Nothing goes out.**
- The only HTTP client (`windows/src-tauri/src/net.rs`) refuses any address that is not this computer, and the build has
  no TLS, so an `https://` address cannot even be tried. The windows' content security policy allows no outside address.
- Removed: automatic updates and "What's new", the cloud chat (Anthropic, OpenAI, Google, OpenRouter), the service
  pills (GitHub, GitLab, Gitea, Stripe, Vercel, n8n, Resend, Notion, Cal.com), « OK Coucou » (it needed Claude and
  ElevenLabs), the text clean-up and call summaries by Claude, the Codex plan gauge (it started `codex app-server`),
  the voice model download (copy the files by hand) and Spotify's cover download.
- Kept: the chat with a model on `127.0.0.1` (Ollama, LM Studio, any OpenAI-compatible server), the agents' pills,
  approvals, dictation and the Notetaker with the local Parakeet model, the Claude plan gauge read from Claude Code's
  status line, the weekly recap, Spotify's local controls.
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
