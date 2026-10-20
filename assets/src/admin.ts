// The admin's script: a page of its own, so it brings Phoenix, LiveView,
// Kotoba and Koyomi, and joins the app's LiveView socket at the path the
// layout names.

import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { Kotoba } from "kotoba";
import { Koyomi } from "koyomi";
import { localizeTimes } from "./times";

const meta = (name: string): string | null =>
  document.querySelector(`meta[name='${name}']`)?.getAttribute("content") ?? null;

const liveSocket = new LiveSocket(meta("tayori-socket") ?? "/live", Socket, {
  params: {
    _csrf_token: meta("csrf-token"),
    // The admin's own time zone: the times of the admin are in it.
    time_zone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    // And their language, for the order and names of the date picker.
    locale: navigator.language,
  },
  hooks: { Kotoba, Koyomi },
});

liveSocket.connect();

// The times of the page are written in UTC; each is shown in the admin's
// time zone and language, as it appears.
localizeTimes(document);
// LiveView patches a time's text in place, which is a characterData change.
new MutationObserver(() => localizeTimes(document)).observe(document.body, {
  childList: true,
  characterData: true,
  subtree: true,
});

declare global {
  interface Window {
    liveSocket: unknown;
  }
}

window.liveSocket = liveSocket;
