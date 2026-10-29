// The last answer of the agent, in the popup: the same markdown the Chat page draws,
// in a scrolling box. The indicator (Vala) hands the text over: `coucou.answer("…")`,
// and reads the height it wants from the page's title.

import { renderMarkdown } from "../../src/views/markdown";

const root = document.getElementById("md") as HTMLElement;

function report() {
  document.title = String(Math.ceil(root.scrollHeight));
}

(window as unknown as { coucou: { answer(text: string): void } }).coucou = {
  answer(text: string) {
    root.textContent = "";
    renderMarkdown(root, text);
    root.scrollTop = 0;
    report();
  },
};
report();
