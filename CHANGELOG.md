# Histórico de mudanças

## Em andamento

- **SlimIA**: nome novo do projeto. Versão para Linux e Windows, só local: sem rede, voz, celular, nuvem nem
  atualização automática.
- **Mochi na barra superior** (elementary OS / Pantheon): indicador do Wingpanel que roda o motor do Mochi,
  mostra os agentes e o Spotify, tem popup com os passos, a última resposta e **Permitir / Negar**.
- **Chat**: lê as conversas do Claude Code em `~/.claude/projects` (somente leitura), com **Limpar lista**.
- `status.json` v2 (agente, cor, pedido pendente e música); `--spotify <ação>` e `--decide allow|deny <pedido>`.
- Com o indicador instalado, a janela da ilha não é mostrada: o app segue por trás.
- Popup: a última resposta aparece inteira, em markdown e com rolagem (antes era cortada em 700 caracteres).
- Barra: ao terminar, uma luz verde dá a volta na borda junto com o giro do Mochi; a borda pulsa enquanto
  uma permissão ou pergunta espera.
- Chat: **Limpar lista** (só filtra a tela, não apaga nada).
- Menu enxuto: bandeja com Abrir, Configurações e Sair; janela com Chat, Geral, Agentes e Integrações.
- Removidos: resumo semanal, guarda-roupa, atalhos e pílulas da ilha, ditado e notas por voz, chats com IA,
  serviços (GitHub, Stripe…), link com celular e WhatsApp, atualização automática.
- [Scripts de firewall](windows/firewall/README.md) para bloquear a rede também pelo sistema.
