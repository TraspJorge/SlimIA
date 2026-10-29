// The SlamIA window (settings.html): Flow dictation, the Notetaker and, under
// Notch, every setting of the island — the place where anything that writes to
// disk is confirmed. The window's frame and the Flow pages live in ../hub; the
// island's settings are drawn here, one Notch page at a time.

import "./settings.css";
import { Bridge, onEvent, type HookPreview, type HookStatus, type ShortcutsReport } from "../core/bridge";
import { DEFAULT_SETTINGS, type Settings } from "../core/state";
import { SOUND_NAMES } from "../core/sound";
import {
  MAX_DECLARED, availablePills, sanitizeDeclared,
} from "../core/pills";
import { h, clear } from "../views/dom";
import { startHub, type PageId } from "../hub/shell";
import { PAGE_RENDERERS } from "../hub/pages";
import { agentsSection } from "./agents";
import { colorDot } from "./colors";
import { renderDiff, statusDot } from "./parts";
import {
  LANGUAGES, isRtl, onLanguageChange, resolveLanguage, setLanguage, systemLanguages, t,
} from "../i18n/i18n";


let settings: Settings = { ...DEFAULT_SETTINGS };
let version = "";

const windowRoot = document.getElementById("hub")!;
/** Where the Notch page being shown draws its sections. */
let root: HTMLElement = windowRoot;
let hub: { redraw(): void; current(): PageId } | null = null;

async function save() {
  await Bridge.saveSettings(settings);
}

/** A colour was picked for a pill's Mochi (see ./colors.ts): the island follows. */
function pickColor(next: Record<string, string>) {
  settings.pillColors = next;
  void save();
}

// ── Reusable bits ─────────────────────────────────────────────────────────────

function toggle(on: boolean, onChange: (v: boolean) => void): HTMLElement {
  const el = h("button", { class: on ? "switch on" : "switch", "aria-pressed": on });
  el.addEventListener("click", () => {
    const next = !el.classList.contains("on");
    el.classList.toggle("on", next);
    onChange(next);
  });
  return el;
}

// ── Changes to Claude Code's settings.json ────────────────────────────────────

/** One kind of change to ~/.claude/settings.json, with the words that go with it. */
interface Change {
  preview: (install: boolean) => Promise<HookPreview | null>;
  apply: (install: boolean, fingerprint: string) => Promise<string | null>;
  installText: string;
  removeText: string;
  installButton: string;
  removeButton: string;
  /** The note once written; `backup` is "" when there was no file to back up. */
  done: (backup: string) => string;
}

const HOOKS_CHANGE: Change = {
  preview: Bridge.hooksPreview,
  apply: Bridge.hooksApply,
  get installText() { return t("This is exactly what will change in your settings.json. Your own hooks are left untouched."); },
  get removeText() { return t("This removes SlamIA's entries only. Your own hooks are left untouched."); },
  get installButton() { return t("Back up and write"); },
  get removeButton() { return t("Back up and remove"); },
  done: (backup) => backup
    ? t("Done. Previous settings saved as {backup}. Open a new Claude Code session to pick the hooks up.", { backup })
    : t("Done. Open a new Claude Code session to pick the hooks up."),
};


/**
 * Shows the diff of a change in `body` and writes it only after an explicit
 * click, and only if settings.json still matches the diff that was shown.
 * `back` redraws the section; `applied` runs a moment after a successful write.
 */
async function reviewChange(
  body: HTMLElement,
  change: Change,
  install: boolean,
  back: () => void,
  applied: () => void,
) {
  let preview;
  try {
    preview = await change.preview(install);
  } catch (err) {
    // An unreadable or invalid settings.json stops here rather than being
    // treated as empty and written over.
    clear(body);
    body.append(
      h("div", { class: "notice err", text: String(err).replace(/^Error:\s*/, "") }),
      h("div", { class: "row" }, h("button", { text: t("Back"), onclick: back })),
    );
    return;
  }
  if (!preview) return;
  clear(body);
  body.append(
    h("div", { class: "hint", text: install ? change.installText : change.removeText }),
    renderDiff(preview.diff),
    h("div", { class: "row" },
      h("span", {
        class: "path",
        text: preview.backup
          ? t("Backup → {path}", { path: preview.backup })
          : t("No settings.json yet — nothing to back up."),
      }),
    ),
  );
  const confirm = h("button", {
    class: install ? "primary" : "danger",
    text: install ? change.installButton : change.removeButton,
  });
  confirm.addEventListener("click", async () => {
    confirm.disabled = true;
    try {
      const backup = await change.apply(install, preview.fingerprint);
      clear(body);
      body.append(h("div", { class: "notice ok", text: change.done(backup ?? "") }));
      window.setTimeout(applied, 2600);
    } catch (err) {
      confirm.disabled = false;
      body.append(h("div", { class: "notice err", text: t("Could not write: {error}", { error: String(err) }) }));
    }
  });
  body.append(h("div", { class: "row" }, confirm, h("button", { text: t("Cancel"), onclick: back })));
}

// ── Claude Code section ───────────────────────────────────────────────────────

function claudeSection(status: HookStatus): HTMLElement {
  const body = h("div", { style: "display:flex;flex-direction:column;gap:12px" });
  const section = h(
    "section",
    {},
    h("h2", {}, statusDot(status.installed), h("span", { text: "Claude Code" })),
    body,
  );

  const redraw = () => {
    clear(body);
    draw();
  };
  const rebuild = async () => {
    const fresh = await Bridge.hooksStatus();
    if (fresh) Object.assign(status, fresh);
    redraw();
    const head = section.querySelector("h2")!;
    clear(head);
    head.append(statusDot(status.installed), h("span", { text: "Claude Code" }));
  };

  function draw() {
    body.append(
      h("div", {
        class: "hint",
        text: status.installed
          ? t("SlamIA is hooked into your Claude Code sessions. Tool calls, questions and permission requests show up in the island, and you can answer them there.")
          : t("Install the hooks to see your Claude Code sessions in the island and approve permissions without leaving what you are doing."),
      }),
      h("div", { class: "row" },
        h("label", { text: "settings.json" }),
        h("span", { class: "path", text: status.settingsPath }),
      ),
      h("div", { class: "row" },
        h("label", { text: t("Relay") }),
        h("span", { class: "path", text: status.hookPath }),
        statusDot(status.hookReady),
      ),
    );

    if (!status.hookReady) {
      body.append(h("div", {
        class: "notice warn",
        text: t("coucou-hook.exe is not in place yet. Restart SlamIA; if it still fails, build it with `cargo build -p coucou-hook`."),
      }));
    }

    const actions = h("div", { class: "row" });
    const install = h("button", {
      class: "primary",
      text: status.installed ? t("Reinstall hooks…") : t("Install hooks…"),
      onclick: () => void reviewChange(body, HOOKS_CHANGE, true, redraw, () => void rebuild()),
    });
    // Writing hook commands that point at a relay which isn't there would give
    // every Claude Code session a broken hook and nothing to show for it.
    if (!status.hookReady) {
      install.disabled = true;
      install.title = t("The relay isn't installed yet.");
    }
    actions.append(install);
    if (status.installed) {
      actions.append(h("button", {
        class: "danger",
        text: t("Uninstall hooks…"),
        onclick: () => void reviewChange(body, HOOKS_CHANGE, false, redraw, () => void rebuild()),
      }));
    }
    body.append(actions);
  }

  draw();
  return section;
}

// ── Plan usage section ────────────────────────────────────────────────────────

/**
 * The 5-hour and weekly limits in the island's header. They come from Claude
 * Code's status line, so the relay has to be the status line first: turning the
 * switch on without it starts the install, and the switch only stays on once
 * that has been confirmed. A status line the user had keeps working.
 */

// ── Active pills section ──────────────────────────────────────────────────────

// ── Integrations section ──────────────────────────────────────────────────────

interface IntegrationDef {
  id: string;
  name: string;
  color: string;
}

const INTEGRATIONS: IntegrationDef[] = [
  // Nothing to enter: Spotify is read from the OS (src-tauri/src/spotify.rs).
  { id: "integration_spotify", name: "Spotify", color: "#1DB954" },
];

const MAX_ACTIVE = MAX_DECLARED;

/** Everything that shows the declared pills, redrawn when any of them changes. */
const declaredViews: (() => void)[] = [];

function declaredChanged() {
  for (const redraw of declaredViews) redraw();
  void save();
}

function integrationsSection(): HTMLElement {
  const note = h("div", { class: "hint" });
  const list = h("div", { style: "display:flex;flex-direction:column;gap:14px" });

  function updateNote() {
    const used = settings.activeIntegrations.length;
    note.textContent = t("Pick up to {max} pills to show next to Mochi — {used}/{max} in use.", { max: MAX_ACTIVE, used });
  }
  declaredViews.push(updateNote);

  const offered = new Set(availablePills().map((p) => p.id));
  for (const def of INTEGRATIONS.filter((d) => offered.has(d.id))) {
    const active = settings.activeIntegrations.includes(def.id);
    const sw = h("button", { class: active ? "switch on" : "switch" });
    sw.addEventListener("click", () => {
      const on = settings.activeIntegrations.includes(def.id);
      if (on) {
        settings.activeIntegrations = settings.activeIntegrations.filter((x) => x !== def.id);
      } else {
        if (settings.activeIntegrations.length >= MAX_ACTIVE) return;
        settings.activeIntegrations = [...settings.activeIntegrations, def.id];
      }
      sw.classList.toggle("on", !on);
      declaredChanged();
    });

    const rows = h("div", { style: "display:flex;flex-direction:column;gap:6px;flex:1 1 auto;min-width:0" });
    if (def.id === "integration_spotify") {
      // As on the Mac's row: said only when there is no Spotify to launch.
      const hint = h("div", { class: "hint", style: "padding-top:5px" });
      rows.append(hint);
      void Bridge.spotifyInstalled().then((ok) => {
        hint.textContent = ok === false ? t("Not installed") : "";
      });
    }

    list.append(
      h("div", { style: "display:flex;gap:12px;align-items:flex-start" },
        h("div", { style: "display:flex;align-items:center;gap:8px;min-width:132px;padding-top:4px" },
          sw,
          colorDot(def, "", () => settings.pillColors, pickColor),
          h("span", { style: "font-size:12.5px", text: def.name }),
        ),
        rows,
      ),
    );
  }

  updateNote();
  return h("section", {}, h("h2", {}, h("span", { text: t("Integrations") })), note, list);
}

// ── General section ───────────────────────────────────────────────────────────

function generalSection(): HTMLElement {
  const volume = h("input", {
    type: "range", min: "0", max: "0.2", step: "0.005",
    value: String(settings.soundVolume),
  }) as HTMLInputElement;
  volume.addEventListener("input", () => {
    settings.soundVolume = Number(volume.value);
    void save();
  });

  // Your own sounds: the folder, a reload, and how many are replaced.
  const customCount = h("span", { class: "hint" });
  const countCustom = () =>
    void Bridge.customSounds(SOUND_NAMES).then((own) => {
      const n = own?.length ?? 0;
      customCount.textContent = n > 0 ? t("{0} custom", { 0: n }) : "";
    });
  countCustom();
  const soundsFolder = h("button", { text: t("Open sounds folder"), onclick: () => void Bridge.revealSoundsFolder() });
  const reloadSounds = h("button", {
    text: t("Reload sounds"),
    onclick: () => void Bridge.reloadSounds().then(() => window.setTimeout(countCustom, 300)),
  });

  return h(
    "section",
    {},
    h("h2", {}, h("span", { text: t("General") })),
    h("div", { class: "row" },
      h("label", { text: t("Sound") }),
      toggle(settings.soundEnabled, (v) => { settings.soundEnabled = v; void save(); }),
      volume,
    ),
    h("div", { class: "row" }, soundsFolder, reloadSounds, customCount),
    h("div", { class: "hint", text: t("Drop a file named like one of Mochi's sounds (finish.wav, approval.mp3, greet.m4a…) in the sounds folder to replace it, then Reload.") }),
    h("div", { class: "row" },
      h("label", { text: t("Launch at startup") }),
      toggle(settings.autostart, (v) => { settings.autostart = v; void save(); }),
    ),
    languageRow(),
  );
}

/**
 * Settings → General → Language, as on the Mac: "System" follows the
 * system's language when SlamIA has it (else English), or one of the ten.
 * Both windows and the tray switch in place, without a restart.
 */
function languageRow(): HTMLElement {
  const select = h("select", {}) as HTMLSelectElement;
  select.append(h("option", { value: "", text: t("System") }));
  for (const { code, name } of LANGUAGES) select.append(h("option", { value: code, text: name, lang: code }));
  select.value = LANGUAGES.some((l) => l.code === settings.language) ? settings.language : "";
  select.addEventListener("change", () => {
    settings.language = select.value;
    void save();
    applyLanguage();
  });
  return h("div", { class: "row" }, h("label", { text: t("Language") }), select);
}


// ── Language ──────────────────────────────────────────────────────────────────

/** The shortcuts section on screen, told about the events listened to once in main. */
let shortcutsListener: { report(fresh: ShortcutsReport): void; settingsChanged(): void } | null = null;

/**
 * Shows the language Settings asks for. A change redraws the window in place,
 * where it was scrolled to: nothing reloads, nothing is written.
 */
function applyLanguage() {
  setLanguage(resolveLanguage(settings.language, systemLanguages()));
}

function applyDirection() {
  document.documentElement.dir = isRtl() ? "rtl" : "ltr";
  document.title = "SlamIA";
}

// ── Boot ──────────────────────────────────────────────────────────────────────

async function main() {
  const boot = await Bridge.boot();
  if (boot) {
    settings = { ...settings, ...boot.settings };
    version = boot.version;
  }
  setLanguage(resolveLanguage(settings.language, systemLanguages()));
  applyDirection();
  hub = await startHub(windowRoot, {
    version,
    pages: PAGE_RENDERERS,
    renderNotch: async (page, container) => {
      notchPage = page;
      root = container;
      await render();
    },
  });
  onLanguageChange(() => {
    applyDirection();
    hub?.redraw();
  });

  void onEvent<ShortcutsReport>("shortcuts-status", (fresh) => shortcutsListener?.report(fresh));
  void onEvent<Settings>("settings-changed", (s) => {
    settings = { ...settings, ...s };
    shortcutsListener?.settingsChanged();
    for (const redraw of declaredViews) redraw();
    applyLanguage();
  });
}

/** The Notch page being shown. */
let notchPage: PageId = "general";

/** Reads what the sections of the Notch page show and draws them. */
async function render() {
  const status = (await Bridge.hooksStatus()) ?? {
    installed: false, planRelayInstalled: false, settingsPath: "", hookPath: "", hookReady: false,
  };
  const agents = await Bridge.agentHooksList();

  // A main pill this build can run, and no pill declared twice.
  settings = { ...settings, ...sanitizeDeclared(settings) };

  declaredViews.length = 0;
  shortcutsListener = null;
  clear(root);
  const sections: Partial<Record<PageId, () => HTMLElement[]>> = {
    general: () => [generalSection()],
    agents: () => [claudeSection(status), agentsSection(agents)],
    integrations: () => [integrationsSection()],
  };
  root.append(...(sections[notchPage]?.() ?? []));
  if (notchPage === "general") {
    root.append(h("div", {
      class: "hint",
      text: t("Nothing leaves this computer: SlamIA only talks to servers on this PC."),
    }));
  }
}

void main();
