// The news in the app: the `Tayori` LiveView hook, for the panel of
// Tayori.Components, and <tayori-news>, for a page that LiveView does not
// render.

import { localizeTimes } from "./times";
import { defineNewsElement, TayoriNews } from "./news_element";

interface Hook {
  el: HTMLElement;
}

/**
 * The hook of the panel of Tayori.Components: it shows the dates in the
 * reader's time zone, in the language of the panel.
 */
export const Tayori = {
  mounted(this: Hook) {
    localizeTimes(this.el, this.el.lang || undefined);
  },
  updated(this: Hook) {
    localizeTimes(this.el, this.el.lang || undefined);
  },
};

/** The hooks of Tayori, to spread in the LiveSocket's `hooks`. */
export const hooks = { Tayori };

defineNewsElement();

export { defineNewsElement, TayoriNews, localizeTimes };
