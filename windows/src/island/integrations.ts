// Whether each pill is connected (hooks in place, local model server connected),
// for the idle cards. Nothing here talks to the network.

import { Bridge } from "../core/bridge";
import { availablePills } from "../core/pills";
import { State } from "../core/state";

export function registerIntegrationHandlers() {
  void refreshConfigured();
}

/**
 * Whether each pill is connected, so its idle card can say so: the hooks in
 * place for a pill fed by hook events, a connected local model server, nothing
 * at all for Claude Desktop.
 */
export async function refreshConfigured() {
  const hooks = (await Bridge.agentHooksStatus()) ?? null;
  for (const def of availablePills(State.os)) {
    let configured: boolean;
    switch (def.connect.kind) {
      case "hooks":
        // Without an answer from Rust (a plain browser), the Claude Code pill
        // falls back to what the settings say about its hooks.
        configured = hooks?.[def.id] ??
          (def.id === "integration_claude" ? State.settings.hooksInstalled : false);
        break;
      case "server":
        // A local model server counts once the chat is connected to it.
        configured = State.settings[def.connect.field] !== "";
        break;
      case "none":
        configured = true;
        break;
    }
    const info = State.integrations[def.id] ?? { data: {}, error: null, loaded: false, configured: false };
    State.integrations[def.id] = { ...info, configured };
  }
  State.notify();
}

/** Only the hook-driven pills, for when the island opens: a few small file reads. */
export async function refreshHookPills() {
  const hooks = await Bridge.agentHooksStatus();
  if (!hooks) return;
  for (const [id, present] of Object.entries(hooks)) {
    const info = State.integrations[id] ?? { data: {}, error: null, loaded: false, configured: false };
    State.integrations[id] = { ...info, configured: present };
  }
  State.notify();
}
