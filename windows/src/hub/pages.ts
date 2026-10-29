// The pages of the Coucou window drawn by the window itself, by id (shell.ts
// draws the others from the island's settings).

import type { PageId, PageRenderer } from "./shell";
import { returnsPage } from "./pages/returns";

export const PAGE_RENDERERS: Partial<Record<PageId, PageRenderer>> = {
  chat: returnsPage,
};
