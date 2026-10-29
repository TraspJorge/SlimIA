// Chat: what Claude Code answered, from the conversations it keeps on this
// computer (src-tauri/src/returns.rs). A list of recent conversations on the
// left, the chosen one on the right: what you asked, what Claude said, and the
// tools it used as small lines. It follows the conversation while it is open.
// Permissions and questions are answered from the island.

import { h, clear } from "../../views/dom";
import { renderMarkdown } from "../../views/markdown";
import { t } from "../../i18n/i18n";
import { Bridge, type ReturnEntry, type ReturnSession } from "../../core/bridge";
import type { HubContext } from "../shell";
import { emptyState } from "../hero";

/** How often the open conversation is read again. */
const POLL_MS = 2000;

const CLEARED_KEY = "slimai.chat.clearedAt";

/** Conversations whose last activity is before this are left out of the list (the files stay untouched). */
function clearedAt(): number {
  try {
    return Number(localStorage.getItem(CLEARED_KEY)) || 0;
  } catch {
    return 0;
  }
}

function setClearedAt(ms: number) {
  try {
    if (ms > 0) localStorage.setItem(CLEARED_KEY, String(ms));
    else localStorage.removeItem(CLEARED_KEY);
  } catch {
    // No storage: the list simply comes back next time.
  }
}

/** The conversation picked last, kept while the window is open. */
let picked: string | null = null;

const clock = (ms: number) =>
  new Date(ms).toLocaleTimeString(document.documentElement.lang || undefined, { hour: "2-digit", minute: "2-digit" });

function when(ms: number): string {
  const d = new Date(ms);
  const today = new Date();
  if (d.toDateString() === today.toDateString()) return clock(ms);
  return d.toLocaleDateString(document.documentElement.lang || undefined, { day: "numeric", month: "short" });
}

function project(cwd: string): string {
  const parts = cwd.split(/[\\/]/).filter(Boolean);
  return parts[parts.length - 1] ?? "";
}

function drawEntry(entry: ReturnEntry): HTMLElement {
  if (entry.kind === "step") {
    return h("div", { class: "ret-step", text: entry.text });
  }
  const bubble = h("div", { class: entry.kind === "user" ? "ret-msg user" : "ret-msg assistant" });
  if (entry.kind === "assistant") {
    const body = h("div", { class: "ret-md" });
    renderMarkdown(body, entry.text);
    bubble.append(body);
  } else {
    bubble.append(h("div", { class: "ret-text", text: entry.text }));
  }
  if (entry.at) bubble.append(h("div", { class: "ret-time", text: clock(entry.at) }));
  return bubble;
}

export async function returnsPage(page: HTMLElement, ctx: HubContext) {
  page.append(ctx.hero("chat", t("Chat"), t("What Claude answered in your conversations, read from this computer."), [], true));

  const items = h("div", { class: "ret-items" });
  const bar = h("div", { class: "ret-bar" });
  const list = h("div", { class: "ret-list" }, bar, items);
  const log = h("div", { class: "ret-log" });
  const note = h("div", { class: "hub-note ret-foot", text: t("Allow or deny from the top bar; answer questions in the terminal.") });
  page.append(h("div", { class: "ret-wrap" }, list, h("div", { class: "ret-main" }, log, note)));

  let sessions: ReturnSession[] = [];
  let shownKey = "";
  let timer: number | null = null;

  function atBottom(): boolean {
    return log.scrollHeight - log.scrollTop - log.clientHeight < 60;
  }

  function drawBar() {
    clear(bar);
    bar.append(h("button", {
      class: "link-btn",
      text: t("Clear list"),
      onclick: () => {
        // Everything older goes; the latest conversation stays, with its last message.
        void Bridge.returnsSessions().then((all) => {
          const newest = (all ?? []).reduce((m, x) => Math.max(m, x.updatedAt), 0);
          setClearedAt(newest > 0 ? newest - 1 : Date.now());
          void refresh();
        });
      },
    }));
    if (clearedAt() > 0) {
      bar.append(h("button", {
        class: "link-btn",
        text: t("Show all"),
        onclick: () => {
          setClearedAt(0);
          void refresh();
        },
      }));
    }
  }

  function drawList() {
    clear(items);
    drawBar();
    for (const s of sessions) {
      const item = h("button", { class: s.id === picked ? "ret-item on" : "ret-item", onclick: () => void pick(s.id) },
        h("div", { class: "ret-item-top" },
          h("b", { text: project(s.cwd) || "Claude Code" }),
          h("span", { text: when(s.updatedAt) }),
        ),
        h("div", { class: "ret-item-title", text: s.title }),
      );
      items.append(item);
    }
  }

  async function load(stick: boolean) {
    if (!picked) return;
    const entries = (await Bridge.returnsRead(picked, 120)) ?? [];
    // Nothing changed since the last read: leave the scroll alone.
    const key = `${picked}|${entries.length}|${entries.at(-1)?.text.length ?? 0}|${entries.at(-1)?.at ?? 0}`;
    if (key === shownKey) return;
    shownKey = key;
    const follow = stick || atBottom();
    clear(log);
    if (entries.length === 0) {
      log.append(emptyState(t("Nothing to show in this conversation yet.")));
      return;
    }
    for (const entry of entries) log.append(drawEntry(entry));
    if (follow) log.scrollTop = log.scrollHeight;
  }

  async function pick(id: string) {
    picked = id;
    shownKey = "";
    drawList();
    await load(true);
  }

  async function refresh() {
    const cut = clearedAt();
    sessions = ((await Bridge.returnsSessions()) ?? []).filter((s) => s.updatedAt > cut);
    if (!picked || !sessions.some((s) => s.id === picked)) picked = sessions[0]?.id ?? null;
    drawList();
    if (!picked) {
      clear(log);
      log.append(emptyState(clearedAt() > 0 ? t("List cleared — new conversations show up here, or press Show all.") : t("No Claude Code conversation found yet.")));
      return;
    }
    await load(false);
  }

  await refresh();
  if (picked) log.scrollTop = log.scrollHeight;

  // Follows the conversation while this page is on screen and the window is visible.
  timer = window.setInterval(() => {
    if (!page.isConnected) {
      if (timer != null) window.clearInterval(timer);
      return;
    }
    if (document.hidden) return;
    void refresh();
  }, POLL_MS);
  ctx.onLeave = () => {
    if (timer != null) window.clearInterval(timer);
  };
}
