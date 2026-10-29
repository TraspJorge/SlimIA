// The SlamIA window: a sidebar with the Chat page (what Claude answered) and the
// island's settings, and the page on the right, under its coloured band.
// Port of FlowHub.swift, without the dictation pages: this build has no voice.

import "./hub.css";
import { h, clear } from "../views/dom";
import { t } from "../i18n/i18n";
import { onEvent } from "../core/bridge";
import { hero, liveMochi, setWindowShown } from "./hero";
import { icon } from "./ui";

export type PageId = "chat" | "general" | "agents" | "integrations";

interface PageDef {
  id: PageId;
  icon: string;
  title: () => string;
  /** The band's line; none for pages that draw their own band. */
  subtitle?: () => string;
}

export const PAGES: PageDef[] = [
  { id: "chat", icon: "chat", title: () => t("Chat") },
  { id: "general", icon: "gear", title: () => t("General"), subtitle: () => t("Mochi and his sounds.") },
  { id: "agents", icon: "terminal", title: () => t("Agents"), subtitle: () => t("Claude Code, Codex and the other agents Mochi follows.") },
  { id: "integrations", icon: "puzzle", title: () => t("Integrations"), subtitle: () => t("Spotify, for the controls on the bar.") },
];

/** What a page gets to draw itself and reach the rest of the window. */
export interface HubContext {
  navigate(page: PageId): void;
  /** The band of a page, its Mochis walking. */
  hero(page: PageId, title: string, subtitle: string | null, actions?: HTMLElement[], compact?: boolean): HTMLElement;
  /** Set by a page: called when the page is left. */
  onLeave?: () => void;
}

export type PageRenderer = (container: HTMLElement, ctx: HubContext) => void | Promise<void>;

export interface HubOptions {
  version: string;
  pages: Partial<Record<PageId, PageRenderer>>;
  /** Draws the island's settings for one of the settings pages into `container`. */
  renderNotch(page: PageId, container: HTMLElement): Promise<void>;
}

export async function startHub(root: HTMLElement, opts: HubOptions) {
  document.body.classList.add("hub-window");
  // The window is created hidden and only shown and hidden afterwards: its
  // canvases animate only while it is on screen (#792).
  await onEvent<boolean>("hub-visible", setWindowShown);
  let current: PageId = "chat";
  const items = new Map<PageId, HTMLElement>();
  const scroll = h("div", { class: "hub-scroll" });
  let rendering = 0;

  const ctx: HubContext = {
    navigate: (page) => void show(page),
    hero: (page, title, subtitle, actions = [], compact = false) => hero(page, title, subtitle, actions, compact),
  };

  async function show(page: PageId) {
    const def = PAGES.find((p) => p.id === page) ?? PAGES[0];
    ctx.onLeave?.();
    ctx.onLeave = undefined;
    current = def.id;
    for (const [id, el] of items) el.classList.toggle("on", id === current);
    const token = ++rendering;
    const page_ = h("div", { class: "hub-page" });
    const renderer = opts.pages[def.id];
    if (renderer) {
      await renderer(page_, ctx);
    } else {
      page_.append(hero(def.id, def.title(), def.subtitle?.() ?? null));
      const container = h("div", { id: "settings-root" });
      page_.append(container);
      await opts.renderNotch(def.id, container);
    }
    if (token !== rendering) return;
    clear(scroll);
    scroll.append(page_);
    scroll.scrollTop = 0;
  }

  // ── The sidebar ──
  const side = h("nav", { class: "hub-side" });
  const logo = h("canvas", {});
  side.append(h("div", { class: "hub-brand" }, logo, h("span", { text: "SlamIA" })));
  liveMochi(logo as HTMLCanvasElement);
  for (const p of PAGES) {
    const b = h("button", { class: "hub-item", onclick: () => void show(p.id) });
    b.append(icon(p.icon), h("span", { text: p.title() }));
    items.set(p.id, b);
    side.append(b);
  }
  side.append(h("div", { class: "spacer" }), h("div", { class: "hub-version", text: `SlamIA ${opts.version}` }));

  clear(root);
  root.append(side, h("main", { class: "hub-panel" }, scroll));
  await show(current);

  void onEvent<string>("hub-page", (page) => {
    const id = (page === "settings" ? "general" : page) as PageId;
    if (PAGES.some((p) => p.id === id)) void show(id);
  });
  return {
    redraw: () => void show(current),
    current: () => current,
  };
}
