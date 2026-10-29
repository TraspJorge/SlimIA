// The island's provider table (src/core/providers.ts): which model the chat
// uses, which chips the picker shows, and what a server address exposes. Only
// model servers on this computer exist: there is no cloud provider.

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  PROVIDERS, activeModel, isLoopbackHost, pickModel, providerDef, urlExposure, visibleProviders, withModel,
} from "../src/core/providers.ts";
import { DEFAULT_SETTINGS } from "../src/core/state.ts";

const settings = (over = {}) => ({ ...DEFAULT_SETTINGS, ...over });

test("the ids match the Rust side, and every provider is a server of this computer", () => {
  assert.deepEqual(PROVIDERS.map((p) => p.id), ["ollama", "lmstudio", "custom"]);
  assert.deepEqual(PROVIDERS.map((p) => p.urlField), ["ollamaUrl", "lmstudioUrl", "customUrl"]);
  // An unknown id (an older settings.json that named a cloud provider) falls back to Ollama.
  assert.equal(providerDef("anthropic").id, "ollama");
  assert.equal(providerDef("nope").id, "ollama");
  assert.equal(DEFAULT_SETTINGS.chatProvider, "ollama");
});

test("the model is kept per provider", () => {
  assert.equal(activeModel(settings()), "");
  let s = withModel(settings({ chatProvider: "lmstudio" }), "lmstudio", "qwen2.5");
  assert.equal(activeModel(s), "qwen2.5");
  assert.equal(s.chatModels.lmstudio, "qwen2.5");
  assert.equal(activeModel(withModel(s, "ollama", "llama3.2")), "qwen2.5");
  // withModel never changes the object it was given.
  assert.deepEqual(DEFAULT_SETTINGS.chatModels, {});
});

test("model servers show in the picker once connected, or while in use", () => {
  const ids = (s) => visibleProviders(s).map((p) => p.id);
  assert.deepEqual(ids(settings()), ["ollama"]);
  assert.deepEqual(ids(settings({ chatProvider: "ollama", lmstudioUrl: "http://127.0.0.1:1234" })), ["ollama", "lmstudio"]);
  assert.deepEqual(ids(settings({ chatProvider: "custom" })), ["custom"]);
});

test("the saved model is kept when offered, else the first one", () => {
  const ollama = providerDef("ollama");
  assert.equal(pickModel(ollama, ["llama3.2", "qwen"], "qwen"), "qwen");
  assert.equal(pickModel(ollama, ["llama3.2", "qwen"], ""), "llama3.2");
  assert.equal(pickModel(ollama, ["llama3.2", "qwen"], "gone"), "llama3.2");
  assert.equal(pickModel(ollama, [], "x"), null);
});

test("loopback hosts match net.rs", () => {
  for (const host of ["localhost", "app.localhost", "127.0.0.1", "127.9.9.9", "[::1]", "::1", "0.0.0.0", "[::]"]) {
    assert.ok(isLoopbackHost(host), host);
  }
  for (const host of ["example.com", "192.168.1.2", "localhost.example.com", "128.0.0.1", "[2001:db8::1]"]) {
    assert.ok(!isLoopbackHost(host), host);
  }
});

test("an address is either this computer, another machine (refused), or not an address", () => {
  assert.equal(urlExposure(""), "local");
  assert.equal(urlExposure("http://localhost:11434"), "local");
  assert.equal(urlExposure("127.0.0.1:1234/v1"), "local");
  assert.equal(urlExposure("http://[::1]:8000"), "local");
  assert.equal(urlExposure("https://llm.example.com"), "remote");
  assert.equal(urlExposure("http://gpu-box.lan:8000"), "remote");
  assert.equal(urlExposure("192.168.1.20:8000"), "remote");
  assert.equal(urlExposure("ftp://example.com"), "invalid");
  assert.equal(urlExposure("http://user:pw@example.com"), "invalid");
  assert.equal(urlExposure("http://"), "invalid");
});
