# PetAI-coucou: Windows and Linux

A tiny animated friend (Mochi) at the top of your screen that keeps an eye on your AI coding agent sessions
(Claude Code, Codex, Gemini CLI, Cursor and others). You approve permissions, watch what the agents do and chat
with a model, all on this computer.

This branch is a trimmed copy of [Louis-CFM/coucou](https://github.com/Louis-CFM/coucou) (MIT) that keeps only the
Windows and Linux app (Tauri 2: Rust in `windows/src-tauri`, TypeScript in `windows/src`).

## What is different from upstream

- **Everything stays on this computer.** The app accepts no command, approval or message from outside:
  - no Android or iPhone link (no TLS server, no local-network announcement, no relay);
  - no WhatsApp integration (no gateway, no webhook).
  The only thing that listens is the local pipe the agents' hooks use, on this machine.
- The macOS, iPhone and Android apps and their CI are not here.
- The app still makes outbound calls to the services you configure (model providers, GitHub, Stripe and so on),
  and to GitHub's releases API if you agree to update checks. Those point at the upstream project: change them
  in `windows/src-tauri/src/update.rs` before you publish your own builds.

## Build

```
cd windows
npm install
npm run tauri dev
```

Linux needs the Tauri system libraries (webkit2gtk 4.1 and friends); see [windows/README.md](windows/README.md).
`npm test` runs the TypeScript tests, `cargo test` in `windows/src-tauri` the Rust ones.

## License

Code: MIT (see [LICENSE](LICENSE)). The Coucou name, Mochi and the sounds belong to Louis Raillé
([LICENSE-ASSETS.md](LICENSE-ASSETS.md)): replace them before you redistribute under another name.
