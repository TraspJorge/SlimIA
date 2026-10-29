# SlimIA

Um bichinho animado (o **Mochi**) que fica na barra superior do seu computador e acompanha o que o Claude Code, o
Codex, o Gemini CLI, o Cursor e outros agentes de código estão fazendo. Ele mostra o que o agente está fazendo,
avisa quando termina, deixa você **permitir ou negar** pedidos de permissão sem abrir o terminal, controla o
**Spotify** e tem uma página de **Chat** com o que o Claude respondeu, como o painel da extensão do VS Code.

**Tudo local: nada entra e nada sai do computador.** Não há rede, voz, celular, nuvem nem atualização automática.

## Amostra

A cápsula na barra superior (aqui com um pedido de permissão esperando: a borda pulsa em laranja) e o popup que
abre ao clicar nela, com **Negar** e **Permitir**:

<p>
  <img src="docs/barra.png" alt="A cápsula do Mochi na barra superior, com a borda laranja" height="90">
</p>

<img src="docs/popup.png" alt="O popup com o pedido de permissão, os botões Negar e Permitir e os outros agentes e o Spotify na coluna da direita" width="640">

## O que ele faz

| | |
|---|---|
| **Mochi na barra** | Uma cápsula na barra superior com o Mochi e mini-Mochis para os outros agentes e o Spotify. Ele pensa, trabalha, pede permissão, faz pergunta, comemora, erra, cansa com o limite de uso e dorme, Os olhos seguem o mouse; passar o mouse um tempo parado rende corações. |
| **Permitir / Negar** | Quando o Claude Code pede permissão, o Mochi pula e a borda pulsa em laranja até você decidir. Clique na cápsula e use **Permitir** ou **Negar**. |
| **Avisos** | Som e animação quando um agente termina. |
| **Passos ao vivo** | O popup mostra as últimas etapas do agente (`Edit · main.rs`) e a **última resposta inteira**, em markdown e com rolagem, como no Chat. |
| **Spotify** | Música atual, anterior, play/pause e próxima, direto no popup. Botão do meio na cápsula dá play/pause; a roda troca entre agentes e Spotify. |
| **Chat** | Página da janela que lê as conversas do Claude Code em `~/.claude/projects` (somente leitura). **Limpar lista** só esconde as conversas antigas da tela, sem apagar nada. |

### Estados do Mochi

| Estado | Como aparece |
|---|---|
| Parado | Mochi neutro, piscando de tempos em tempos |
| Pensando | Roxo, olhando para cima, três pontinhos no badge |
| Trabalhando | Azul, olhos varrendo de um lado a outro |
| Pergunta | Ciano, cabeça inclinada, "?" e a borda pulsando |
| Permissão | Laranja, pulando, "!" e a borda pulsando **até você decidir** |
| Limite de uso | Laranja, olhos cansados e gota de suor |
| Erro | Vermelho, tremor curto, olhos em traço |
| Terminou | Verde, volta de 360°, uma luz percorre a borda, faíscas e som |
| Dormindo | Depois de 5 minutos parado e sem música: respira e solta "z" |
| Dançando | Com o Spotify tocando, no ritmo de 112 BPM |

### Na cápsula

- **Clique:** abre o popup (passos, última resposta, Permitir/Negar, Spotify).
- **Roda do mouse:** troca o foco entre os agentes e o Spotify.
- **Botão do meio:** play/pause do Spotify.
- No popup, clicar no **Mochi grande** leva um tapinha; clicar nas células da direita muda o foco.

### Limites

As perguntas de múltipla escolha do Claude Code (`AskUserQuestion`) **não** são respondidas pela barra: caem no
terminal.

## Garantias de ser local

- **Nada entra:** não há servidor, porta, link com celular nem WhatsApp. Só o canal local (pipe) que os hooks dos
  agentes usam escuta, neste computador.
- **Nada sai:** o programa não tem cliente HTTP. A política de conteúdo das janelas não permite nenhum endereço de
  fora, e a página do Mochi na barra roda num WebKit efêmero que só abre o próprio arquivo.
- **Sem voz:** sem ditado, sem microfone, sem modelo de fala.
- **Segunda trava, pelo sistema:** [windows/firewall/](windows/firewall/README.md).
- O indicador da barra só lê um arquivo local (`~/.local/share/coucou/status.json`) e só executa o app com
  `--shortcut openChat`, `--spotify <ação>` e `--decide allow|deny <pedido>`.

## Instalar (Linux, testado no elementary OS 8 / Pantheon)

Precisa de Rust, Node 20+ e, para o indicador da barra: `meson`, `valac`, `libwingpanel-dev`,
`libwebkit2gtk-4.1-dev`, `libgee-0.8-dev`, `libjson-glib-dev`.

```sh
cd windows
npm install
npx tauri build --no-bundle          # gera windows/target/release/coucou
GDK_BACKEND=x11 ./target/release/coucou
```

0. Abra o app pelo menu da bandeja (**Abrir SlimIA**) para chegar ao Chat e às **Configurações**.
1. Abra **Configurações → Agentes** e instale o hook do Claude Code (e dos outros agentes que usar).
2. Em **Configurações → Integrações**, ligue o **Spotify** se quiser os controles.
3. Para o Mochi na barra superior do Pantheon:

```sh
cd windows/wingpanel-indicator
./install.sh        # compila, instala em /usr/lib/.../wingpanel e /usr/share/coucou-indicator,
                    # pede sua senha pelo diálogo do sistema e reinicia a barra (precisa de Node)
./uninstall.sh      # tira o indicador e a página do Mochi
```

A **ilha** é o painel flutuante com o Mochi no topo da tela, que o app desenha onde não há o indicador da barra.
Com o indicador instalado, a janela da ilha **não é mostrada**: o app segue rodando por trás (recebe os eventos
e executa suas respostas) e o Mochi aparece só na barra. Em outros desktops, sem o indicador, a ilha aparece
no topo da tela.

No **Windows** o app usa a ilha no topo da tela. O build para Windows está no código, mas **não foi testado**
nesta versão.

## Onde ficam os dados

- `~/.config/coucou/settings.json`: suas configurações.
- `~/.local/share/coucou/status.json`: o estado que o indicador lê (só neste computador).
- `~/.claude/projects/`: as conversas do Claude Code, que o Chat só **lê**.
- O app só altera o `~/.claude/settings.json` quando você pede, com backup datado e o diff na tela.

## Estrutura

```
windows/
  src/                  front-end (TypeScript): ilha e janela (Chat, Geral, Agentes, Integrações)
  src-tauri/            backend (Rust): hooks, canal local, Spotify, status.json
  hook/                 coucou-hook: o relé que os agentes chamam
  wingpanel-indicator/  indicador da barra (Vala + página do Mochi em web/)
  firewall/             scripts para bloquear a rede pelo sistema
```

Os nomes internos continuam `coucou` (comando, pasta `~/.config/coucou`, `coucou-hook`) para não quebrar hooks
já instalados nem configurações.

## Testes

```sh
cd windows
npx tsc --noEmit && npm test
cargo test --workspace
```

## Licença

O código é MIT (veja [LICENSE](LICENSE)). O nome, o personagem e as ilustrações têm termos próprios: veja
[LICENSE-ASSETS.md](LICENSE-ASSETS.md) antes de redistribuir.
