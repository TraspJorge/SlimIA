// The pill catalog (src/core/pills.ts) and the declared pills in the app state.

import { beforeEach, test } from "node:test";
import assert from "node:assert/strict";
import {
  DEFAULT_MAIN_PILL, MAX_DECLARED, PILL_CATALOG, PILL_CATEGORIES, availablePills, chooseMainPill,
  isComingSoon, isHookPill, mainPillChoices, orderPills, pillDefinition, sanitizeDeclared, sessionSubtitle,
  toggleDeclared,
} from "../src/core/pills.ts";
import { DEFAULT_SETTINGS, State } from "../src/core/state.ts";
import { installFakeDom } from "./fakedom.mjs";
import { renderIntegrationCard } from "../src/views/integrations.ts";

installFakeDom();

// ── The catalog itself ────────────────────────────────────────────────────────

test("the catalog holds the pills of this build, with the Claude Code label for Windows and Linux", () => {
  // From NotchBuddy/Sources/CoucouKit/PillCatalog.swift, without the services and
  // cloud AI providers this build leaves out (it never goes to the network): an ID is a
  // contract value, and a colour or subtitle that drifts is a visible bug.
  // Windows and Linux name the Claude Code integration after the agent.
  const mac = [
    ["integration_claude", "Claude Code", "#F5F6F8", "workspace", "Integration"],
    ["agent_cursor", "Cursor", "#C0C4CC", "workspace", "Integration"],
    ["agent_antigravity", "Antigravity", "#E879F9", "workspace", "Integration"],
    ["agent_codex", "Codex", "#2DD4BF", "workspace", "Integration"],
    ["agent_gemini", "Gemini CLI", "#8AB4F8", "agent", "Agent"],
    ["agent_copilot", "Copilot CLI", "#818CF8", "agent", "Agent"],
    ["agent_muse", "Muse Code", "#38BDF8", "agent", "Agent"],
    ["agent_opencode", "OpenCode", "#4ADE80", "agent", "Agent"],
    ["agent_amp", "Amp", "#F59E0B", "agent", "Agent"],
    ["agent_hermes", "Hermes", "#C084FC", "agent", "Agent"],
    ["agent_claude-desktop", "Claude Desktop", "#D97757", "agent", "Agent"],
    ["integration_music", "Apple Music", "#FA2D48", "service", "Integration"],
    ["integration_spotify", "Spotify", "#1DB954", "service", "Integration"],
  ];
  assert.deepEqual(
    PILL_CATALOG.map((p) => [p.id, p.name, p.color, p.category, p.subtitle]),
    mac,
  );
  assert.deepEqual(PILL_CATEGORIES.map((c) => c.title), [
    "Where you code", "Agents", "Services",
  ]);
});

test("the shipped pills keep their IDs, colours and sources with current display names", () => {
  const shipped = [
    ["integration_claude", "Claude Code", "#F5F6F8", "claudeCode"],
  ];
  for (const [id, name, color, source] of shipped) {
    const def = pillDefinition(id);
    assert.deepEqual([def.id, def.name, def.color, def.source], [id, name, color, source]);
    assert.equal(def.support, "yes");
  }
});

test("IDs are unique", () => {
  const ids = PILL_CATALOG.map((p) => p.id);
  assert.equal(new Set(ids).size, ids.length);
});

test("this build leaves out what only macOS has, and Claude Desktop on Linux", () => {
  const windows = availablePills("windows").map((p) => p.id);
  const linux = availablePills("linux").map((p) => p.id);
  for (const id of ["integration_music"]) {
    assert.ok(!windows.includes(id), id);
    assert.ok(!linux.includes(id), id);
  }
  // Their plugins are written from Settings → Agents, and the chat talks to
  // every provider (port/chat-providers), on both systems.
  for (const id of ["agent_opencode", "agent_amp", "agent_hermes"]) {
    assert.ok(windows.includes(id), id);
    assert.ok(linux.includes(id), id);
  }
  assert.ok(windows.includes("agent_claude-desktop"));
  assert.ok(!linux.includes("agent_claude-desktop"));
  // Spotify: MPRIS on Linux, the system media controls on Windows.
  assert.ok(linux.includes("integration_spotify"));
  assert.ok(windows.includes("integration_spotify"));
  assert.deepEqual(linux, windows.filter((id) => id !== "agent_claude-desktop"));
});

test("Spotify: a service on both systems with nothing to set up", () => {
  const def = pillDefinition("integration_spotify");
  assert.equal(def.support, "yes");
  assert.deepEqual(def.connect, { kind: "none" });
  assert.equal(def.category, "service");
  assert.ok(!isComingSoon("integration_spotify"));
  assert.ok(!isHookPill("integration_spotify"));
  assert.ok(!mainPillChoices("linux").some((p) => p.id === "integration_spotify"));
  assert.ok(!mainPillChoices("windows").some((p) => p.id === "integration_spotify"));
});

test("Spotify can be declared on both systems; Claude Desktop only on Windows", () => {
  const d = { mainPill: "integration_claude", activeIntegrations: ["integration_spotify", "agent_opencode"] };
  assert.deepEqual(sanitizeDeclared(d, "linux").activeIntegrations, ["integration_spotify", "agent_opencode"]);
  assert.deepEqual(sanitizeDeclared(d, "windows").activeIntegrations, ["integration_spotify", "agent_opencode"]);
  const empty = { mainPill: "integration_claude", activeIntegrations: [] };
  assert.deepEqual(toggleDeclared(empty, "integration_spotify", "linux"), ["integration_spotify"]);
  assert.deepEqual(toggleDeclared(empty, "integration_spotify", "windows"), ["integration_spotify"]);
  // Claude Desktop stays Windows only.
  assert.equal(toggleDeclared(empty, "agent_claude-desktop", "linux"), null);
  assert.deepEqual(toggleDeclared(empty, "agent_claude-desktop", "windows"), ["agent_claude-desktop"]);
});

test("no chat provider is offered: this build has no chat, so nothing here can leave the computer", () => {
  for (const id of ["ai_anthropic", "ai_google", "ai_openai", "ai_ollama", "ai_lmstudio"]) {
    assert.equal(pillDefinition(id), undefined, id);
  }
  assert.ok(!PILL_CATALOG.some((p) => p.category === "ai"));
});

test("the main pill is a workspace tool that works here", () => {
  assert.deepEqual(mainPillChoices("linux").map((p) => p.id), [
    "integration_claude", "agent_cursor", "agent_antigravity", "agent_codex",
  ]);
  assert.equal(DEFAULT_MAIN_PILL, "integration_claude");
});

test("hook-driven pills are the workspace tools and the agents with hooks", () => {
  for (const id of ["integration_claude", "agent_cursor", "agent_codex", "agent_gemini", "agent_copilot", "agent_muse", "agent_antigravity", "agent_opencode", "agent_amp", "agent_hermes"]) {
    assert.ok(isHookPill(id), id);
  }
  for (const id of ["agent_claude-desktop", "integration_spotify", "agent_unknown"]) {
    assert.ok(!isHookPill(id), id);
  }
});

test("a live session names its tool next to the project", () => {
  assert.equal(sessionSubtitle("integration_claude"), "Claude Code");
  assert.equal(sessionSubtitle("agent_cursor"), "Cursor");
  assert.equal(sessionSubtitle("agent_claude-desktop"), "Claude Desktop");
  assert.equal(sessionSubtitle("agent_gemini"), "Agent");
  assert.equal(sessionSubtitle("agent_whatever"), "Agent");
});

// ── Declaring pills ──────────────────────────────────────────────────────────

test("a declaration from an older or edited settings file is made usable", () => {
  assert.deepEqual(
    sanitizeDeclared({ mainPill: "integration_stripe", activeIntegrations: ["integration_claude", "x"] }, "linux"),
    { mainPill: "integration_claude", activeIntegrations: [] },
  );
  assert.deepEqual(
    sanitizeDeclared({ mainPill: "agent_cursor", activeIntegrations: ["agent_cursor", "agent_opencode", "agent_opencode", "integration_music"] }, "linux"),
    { mainPill: "agent_cursor", activeIntegrations: ["agent_opencode"] },
  );
  // No mainPill at all: a settings.json from before this version.
  assert.deepEqual(
    sanitizeDeclared({ activeIntegrations: ["agent_amp"] }, "windows"),
    { mainPill: "integration_claude", activeIntegrations: ["agent_amp"] },
  );
  assert.equal(sanitizeDeclared({ mainPill: "agent_claude-desktop", activeIntegrations: [] }, "windows").mainPill,
    "integration_claude");
});

test("up to four pills next to the main one, never the main one itself", () => {
  const d = {
    mainPill: "integration_claude",
    activeIntegrations: ["agent_opencode", "agent_amp", "agent_hermes"],
  };
  const four = toggleDeclared(d, "agent_gemini", "linux");
  assert.equal(four.length, MAX_DECLARED);
  assert.equal(toggleDeclared({ ...d, activeIntegrations: four }, "agent_cursor", "linux"), null);
  assert.equal(toggleDeclared(d, "integration_claude", "linux"), null);
  assert.equal(toggleDeclared(d, "integration_music", "linux"), null);
  assert.equal(toggleDeclared(d, "agent_claude-desktop", "linux"), null);
  assert.ok(toggleDeclared(d, "agent_claude-desktop", "windows").includes("agent_claude-desktop"));
  assert.deepEqual(toggleDeclared(d, "agent_amp", "linux"), ["agent_opencode", "agent_hermes"]);
  // A pill that does not exist cannot be declared.
  assert.equal(toggleDeclared(d, "ai_google", "linux"), null);
});

test("picking a main pill takes it out of the declared ones, and only workspace tools qualify", () => {
  const d = { mainPill: "integration_claude", activeIntegrations: ["agent_cursor", "agent_opencode"] };
  assert.deepEqual(chooseMainPill(d, "agent_cursor", "linux"), {
    mainPill: "agent_cursor", activeIntegrations: ["agent_opencode"],
  });
  assert.equal(chooseMainPill(d, "agent_opencode", "linux"), null);
  assert.equal(chooseMainPill(d, "agent_gemini", "linux"), null);
});

test("pills are ordered main first, then other agents, then the catalog's order", () => {
  const ids = (list) => list.map((t) => t.id);
  const tasks = ["integration_spotify", "agent_mine", "agent_copilot", "agent_cursor", "integration_claude", "agent_gemini"]
    .map((id) => ({ id }));
  assert.deepEqual(ids(orderPills(tasks, "integration_claude")), [
    "integration_claude", "agent_mine", "agent_cursor", "agent_gemini", "agent_copilot", "integration_spotify",
  ]);
  assert.deepEqual(ids(orderPills(tasks, "agent_cursor")).slice(0, 3), [
    "agent_cursor", "agent_mine", "integration_claude",
  ]);
});

// ── In the app state ─────────────────────────────────────────────────────────

beforeEach(() => {
  State.tasks = [];
  State.focusId = null;
  State.os = "windows";
  State.settings = { ...DEFAULT_SETTINGS };
});

const ids = () => State.tasks.map((t) => t.id);

test("the main pill always loads, the declared ones join it, and focus starts on it", () => {
  State.settings.mainPill = "agent_cursor";
  State.settings.activeIntegrations = ["integration_spotify", "agent_gemini"];
  State.loadIntegrationTasks();
  assert.deepEqual(ids(), ["agent_cursor", "agent_gemini", "integration_spotify"]);
  assert.equal(State.focusId, "agent_cursor");
  assert.equal(State.tasks[1].name, "Gemini CLI");
  assert.equal(State.tasks[1].color, "#8AB4F8");
});

test("an old settings file gets Claude Code as its main pill and keeps its integrations", () => {
  State.settings = { ...DEFAULT_SETTINGS, mainPill: undefined, activeIntegrations: ["agent_codex", "agent_gemini"] };
  State.loadIntegrationTasks();
  assert.deepEqual(ids(), ["integration_claude", "agent_codex", "agent_gemini"]);
  assert.equal(State.settings.mainPill, "integration_claude");
  assert.equal(State.tasks[0].name, "Claude Code");
});

test("switching the main pill frees its slot and the old main pill goes when idle", () => {
  State.loadIntegrationTasks();
  State.settings.mainPill = "agent_codex";
  State.loadIntegrationTasks();
  assert.equal(ids()[0], "agent_codex");
  assert.ok(!ids().includes("integration_claude"));
  assert.equal(State.focusId, "agent_codex");
});

test("a pill in the middle of a session stays until the session ends", () => {
  State.loadIntegrationTasks();
  State.tasks[0].state = "working";
  State.settings.mainPill = "agent_cursor";
  State.loadIntegrationTasks();
  assert.ok(ids().includes("integration_claude"));
  State.removeTask("integration_claude");
  assert.ok(!ids().includes("integration_claude"));
});

test("the end of a session puts a kept pill back as it was, and removes any other", () => {
  State.settings.activeIntegrations = ["agent_gemini"];
  State.loadIntegrationTasks();
  const gemini = State.tasks.find((t) => t.id === "agent_gemini");
  Object.assign(gemini, { name: "proj", state: "finished", steps: ["a"], pillBadge: "finished" });
  State.removeTask("agent_gemini");
  assert.deepEqual(
    [gemini.name, gemini.state, gemini.steps, gemini.pillBadge],
    ["Gemini CLI", "idle", [], null],
  );
  State.upsertExternalAgent("agent_mine", "mine", "#22C55E");
  State.setFocus("agent_mine");
  State.removeTask("agent_mine");
  assert.ok(!ids().includes("agent_mine"));
  assert.equal(State.focusId, "integration_claude");
});

test("a Claude Code session gets its pill even when it is not loaded", () => {
  State.settings.mainPill = "agent_codex";
  State.loadIntegrationTasks();
  const t = State.upsertWorkspacePill("integration_claude", "proj", "/p");
  assert.equal(ids()[1], "integration_claude");
  assert.equal(t.name, "proj");
  assert.equal(t.sessionCwd, "/p");
  assert.equal(State.upsertWorkspacePill("not_a_pill", "x", ""), null);
});

test("toggling declares up to four pills and never the main one", () => {
  State.settings.activeIntegrations = [];
  State.loadIntegrationTasks();
  for (const id of ["agent_opencode", "agent_gemini", "agent_copilot", "agent_amp", "agent_hermes"]) {
    State.toggleIntegration(id);
  }
  assert.deepEqual(State.settings.activeIntegrations, [
    "agent_opencode", "agent_gemini", "agent_copilot", "agent_amp",
  ]);
  State.toggleIntegration("integration_claude");
  assert.ok(ids().includes("integration_claude"));
  State.setFocus("agent_gemini");
  State.toggleIntegration("agent_gemini");
  assert.ok(!ids().includes("agent_gemini"));
  assert.equal(State.focusId, "integration_claude");
});

test("Claude Code is named after the agent in main-tool choices on both platforms", () => {
  for (const os of ["windows", "linux"]) {
    const choice = mainPillChoices(os).find((p) => p.id === "integration_claude");
    assert.equal(choice.name, "Claude Code");
    assert.equal(choice.source, "claudeCode");
  }
});

test("the Claude Code idle card keeps the agent title when the task has a project name", () => {
  State.loadIntegrationTasks();
  const task = State.tasks.find((t) => t.id === "integration_claude");
  task.name = "my-project";
  const card = renderIntegrationCard(task, { openSettings() {} });
  assert.ok(card.textContent.includes("Claude Code"));
  assert.ok(!card.textContent.includes("my-project"));
  assert.ok(card.textContent.includes("Open Visual Studio Code"));
});
