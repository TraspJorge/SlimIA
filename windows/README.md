# SlimIA — código do app (Linux e Windows)

A descrição, a instalação e as garantias de ser local estão no [README da raiz](../README.md).

- `src/` front-end (TypeScript, vite) · `src-tauri/` backend (Rust, Tauri 2) · `hook/` relé dos agentes
- `wingpanel-indicator/` Mochi na barra superior do Pantheon (Vala + página em `web/`)
- `firewall/` trava de rede pelo sistema

```sh
npm install
npx tsc --noEmit && npm test       # TypeScript
cargo test --workspace             # Rust
npx tauri build --no-bundle        # ./target/release/coucou
```
