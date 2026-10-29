// The Mochi of the top bar: the island's own engine (src/mochi/engine.ts), drawn
// on a small canvas inside the Wingpanel indicator. The indicator (Vala) only
// tells it what is going on — `coucou.set(...)` — and where the pointer is.
// Nothing here reads a file or opens a connection.

import { BotEngine, hexToRGB } from "../../src/mochi/engine";
import { Sound } from "../../src/core/sound";
import type { BotStateName } from "../../src/core/layout";

Sound.setEnabled(false);

interface PillIn {
  id: string;
  state: string;
  color: string;
  flat: boolean;
  dancing: boolean;
}

interface Scene {
  front: PillIn | null;
  others: PillIn[];
}

const STATES = new Set<string>([
  "idle", "working", "thinking", "searching", "approval", "question", "error",
  "finished", "ratelimit", "sleeping", "dizzy",
]);
const stateOf = (s: string): BotStateName => (STATES.has(s) ? (s as BotStateName) : "idle");

const big = location.hash === "#big";
const canvas = document.getElementById("c") as HTMLCanvasElement;
const ctx = canvas.getContext("2d")!;

const main = new BotEngine();
const minis = new Map<string, BotEngine>();
let scene: Scene = { front: null, others: [] };
let hovering = false;
let hoverSince = 0;
let lastLove = 0;
let lastFront = "";

function apply(engine: BotEngine, p: PillIn, forMini: boolean) {
  engine.setState(stateOf(p.state));
  engine.bodyColor = p.flat || forMini ? hexToRGB(p.color) : null;
  engine.setDancing(p.dancing);
}

const api = {
  set(next: Scene) {
    scene = next;
    if (next.front) {
      lastFront = next.front.state;
      apply(main, next.front, false);
    } else {
      lastFront = "";
    }
    const keep = new Set<string>();
    for (const p of next.others) {
      keep.add(p.id);
      let m = minis.get(p.id);
      if (!m) {
        m = new BotEngine();
        m.isMini = true;
        minis.set(p.id, m);
      }
      apply(m, p, true);
    }
    for (const id of [...minis.keys()]) if (!keep.has(id)) minis.delete(id);
  },
  /** The pointer, from -1 to 1 across the widget: his eyes follow it. */
  look(x: number, y: number) {
    main.lookX = Math.max(-1, Math.min(1, x));
    main.lookY = Math.max(-1, Math.min(1, y));
  },
  hover(on: boolean) {
    hovering = on;
    hoverSince = performance.now();
    if (!on) {
      main.lookX = 0;
      main.lookY = 0;
    }
  },
  click() {
    if (big) main.slap();
    else main.squash();
  },
};
(window as unknown as { coucou: typeof api }).coucou = api;

function fit(): { w: number; h: number; dpr: number } {
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const w = window.innerWidth;
  const h = window.innerHeight;
  if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    canvas.style.width = `${w}px`;
    canvas.style.height = `${h}px`;
  }
  return { w, h, dpr };
}

// The whole rim blinks at once, in the colour of the state: a finished or failed turn for two
// minutes, an alert until you answer.
const ALERT_RIM: Record<string, string> = {
  finished: "52,211,153",
  approval: "245,165,36",
  question: "34,211,238",
  error: "244,80,94",
  ratelimit: "251,146,60",
};

function pill(x: CanvasRenderingContext2D, X: number, Y: number, W: number, H: number, nowMs: number) {
  const r = H / 2;
  x.beginPath();
  x.roundRect(X, Y, W, H, r);
  x.fillStyle = "#000";
  x.fill();
  x.strokeStyle = "rgba(255,255,255,0.1)";
  x.lineWidth = 1;
  x.stroke();
  const rim = scene.front ? ALERT_RIM[scene.front.state] : undefined;
  if (rim) {
    // About 1.2 blinks a second: on, off, on, with soft edges.
    const k = Math.max(0, Math.min(1, 0.5 + 0.9 * Math.sin(nowMs / 1000 * 5.2)));
    x.strokeStyle = `rgba(${rim},${0.08 + 0.92 * k})`;
    x.lineWidth = 1.4 + 0.8 * k;
    x.stroke();
  }
}

function drawBot(engine: BotEngine, cx: number, cy: number, size: number) {
  // The engine draws its body at the middle of a size×size square.
  ctx.save();
  ctx.translate(cx - size / 2, cy - size / 2);
  engine.applyDance(ctx, size, size);
  engine.draw(ctx, size, size);
  ctx.restore();
}

let last = performance.now();
function frame(nowMs: number) {
  const dt = Math.min(0.05, (nowMs - last) / 1000);
  last = nowMs;
  const { w, h, dpr } = fit();
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);

  // Left alone with the pointer over him, he enjoys it (the island's "love").
  if (hovering && nowMs - hoverSince > 1200 && nowMs - lastLove > 3000) {
    lastLove = nowMs;
    main.triggerEmote("love");
  }

  main.update(dt);
  if (big) {
    drawBot(main, w / 2, h / 2, Math.min(w, h) * 1.25);
  } else {
    const ch = Math.min(h - 4, 24);
    const top = (h - ch) / 2;
    pill(ctx, 0.5, top, w - 1, ch, nowMs);
    drawBot(main, 7 + 10.5, h / 2, 31);
    const n = Math.min(scene.others.length, 4);
    const cols = n > 2 ? 2 : n;
    const rows = n > 2 ? 2 : 1;
    const gx = 7 + 21 + 5;
    const gy = h / 2 - (rows * 8 + (rows - 1) * 2) / 2;
    for (let i = 0; i < n; i++) {
      const m = minis.get(scene.others[i].id);
      if (!m) continue;
      m.update(dt);
      drawBot(m, gx + (i % cols) * 11 + 4, gy + Math.floor(i / cols) * 10 + 4, 14);
    }
  }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
