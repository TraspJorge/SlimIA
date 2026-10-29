# SlimIA — guia para agentes de código

App local para Linux e Windows (Tauri 2): Rust em `windows/src-tauri`, TypeScript em `windows/src`, o relé dos hooks
em `windows/hook`, o indicador da barra superior (Vala) em `windows/wingpanel-indicator`.

## Regras
- **Nada entra e nada sai do computador**: sem cliente HTTP, sem porta, sem voz. Não adicionar dependências de rede.
- Nunca bloquear o Claude Code: se o app não responde, o hook sai na hora.
- Nunca sobrescrever `~/.claude/settings.json`: backup datado, mostrar o diff e só escrever com confirmação.
- Nunca aprovar uma permissão sem um clique explícito (o `--decide` só vale para o pedido pendente da ilha).
- O Chat só lê `~/.claude/projects`; nunca escreve nem apaga lá.
- Os nomes internos seguem `coucou` (comando, `~/.config/coucou`, `coucou-hook`) para não quebrar hooks instalados.

## Testes
```
cd windows && npx tsc --noEmit && npm test && cargo test --workspace
```
Todo texto mostrado com `t()` precisa estar traduzido nos 11 idiomas em `windows/src/i18n/extra.json`.
