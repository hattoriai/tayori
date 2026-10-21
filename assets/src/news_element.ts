// <tayori-news api="/api/news">: the button, the panel and the
// announcement of the news, for a page that LiveView does not render, on
// the app's origin or another (the :embed feature).
//
// The markup is not the element's: the server renders the components of
// Tayori.Components, as in a LiveView, and the element puts them in the
// page (Tayori.API's /ui routes). It answers what LiveView would: each
// phx-click with its phx-value-*, phx-click-away, and Escape where the
// markup asks (phx-window-keydown). One panel, wherever it is shown.

import { localizeTimes } from "./times";

/** An event of the markup: its name and its phx-value-* values. */
export interface PhxEvent {
  name: string;
  values: Record<string, string>;
}

/** The event a click on `target` sends, as LiveView reads it: the closest phx-click. */
export function phxEvent(target: Element, root: Element): PhxEvent | null {
  const el = target.closest<HTMLElement>("[phx-click]");
  if (!el || !root.contains(el)) return null;
  if (el instanceof HTMLButtonElement && el.disabled) return null;
  return { name: el.getAttribute("phx-click") ?? "", values: phxValues(el) };
}

/** The phx-value-* attributes of an element, by name. */
export function phxValues(el: Element): Record<string, string> {
  const values: Record<string, string> = {};
  for (const attr of Array.from(el.attributes)) {
    if (attr.name.startsWith("phx-value-")) values[attr.name.slice("phx-value-".length)] = attr.value;
  }
  return values;
}

/** The query of a view of the panel, as Tayori.API reads it. */
export function panelQuery(view: { category: string | null; pages: number; entry: string | null; since: string | null }): string {
  const params = new URLSearchParams();
  if (view.category) params.set("category", view.category);
  if (view.pages > 1) params.set("pages", String(view.pages));
  if (view.entry) params.set("entry", view.entry);
  if (view.since) params.set("since", view.since);
  const query = params.toString();
  return query ? `?${query}` : "";
}

interface Html {
  html: string | null;
}

/** The first element of a piece of HTML. */
function fragment(html: string): HTMLElement | null {
  const template = document.createElement("template");
  template.innerHTML = html;
  return template.content.firstElementChild as HTMLElement | null;
}

export class TayoriNews extends HTMLElement {
  static observedAttributes = ["reader-token"];

  private button: HTMLElement | null = null;
  private panel: HTMLElement | null = null;
  private announcementEl: HTMLElement | null = null;
  private announcementId: string | null = null;
  private timer: number | undefined;
  private token: string | null = null;
  private count: number | null = null;
  // With button="none", the page's own control that opened the panel,
  // which gets the focus back.
  private opener: HTMLElement | null = null;

  // The view of the open panel, which the server renders again.
  private category: string | null = null;
  private pages = 1;
  private entry: string | null = null;
  private since: string | null = null;

  private readonly onClick = (event: Event) => {
    const target = event.target as Element;
    const root = event.currentTarget as Element;
    const phx = phxEvent(target, root);
    if (!phx) return;
    event.preventDefault();
    void this.run(phx);
  };

  private readonly onKey = (event: KeyboardEvent) => {
    if (event.key !== "Escape") return;
    // As phx-window-keydown with phx-key="Escape": the panel's, else a popup's.
    const el = this.panel ?? this.announcementEl;
    const name = el?.getAttribute("phx-window-keydown");
    if (el && name && el.getAttribute("phx-key") === "Escape") void this.run({ name, values: phxValues(el) });
  };

  // phx-click-away: a press outside the panel closes it.
  private readonly onPointer = (event: PointerEvent) => {
    const target = event.target as Node;
    const inside =
      this.panel?.contains(target) ||
      this.button?.contains(target) ||
      this.opener?.contains(target) ||
      this.announcementEl?.contains(target);
    if (this.panel && !inside) this.close(false);
  };

  private readonly onVisible = () => {
    if (document.visibilityState === "visible") void this.refresh();
  };

  /** The number of entries the reader has not seen. */
  get unread(): number {
    return this.count ?? 0;
  }

  /** False with `button="none"`: the page has its own control, which calls open(). */
  get hasButton(): boolean {
    return this.getAttribute("button") !== "none";
  }

  /** The path or URL of Tayori.API (`api`, or `src`, its older name). */
  get api(): string {
    return (this.getAttribute("api") ?? this.getAttribute("src") ?? "/api/news").replace(/\/$/, "");
  }

  attributeChangedCallback(name: string, _old: string | null, value: string | null): void {
    if (name === "reader-token") {
      this.token = value && value.trim() !== "" ? value.trim() : null;
      if (this.isConnected) void this.refresh();
    }
  }

  connectedCallback(): void {
    this.addEventListener("click", this.onClick);
    document.addEventListener("visibilitychange", this.onVisible);
    document.addEventListener("keydown", this.onKey);
    void this.refresh();

    const poll = Number(this.getAttribute("poll") ?? "300");
    if (poll > 0) this.timer = window.setInterval(() => void this.refresh(), poll * 1000);
  }

  disconnectedCallback(): void {
    window.clearInterval(this.timer);
    this.removeEventListener("click", this.onClick);
    document.removeEventListener("visibilitychange", this.onVisible);
    document.removeEventListener("keydown", this.onKey);
    this.close(false);
    this.removeAnnouncement();
  }

  /** Asks the button again (its count of unread entries), and the announcement. */
  async refresh(): Promise<void> {
    if (this.hasButton) {
      const label = this.hasAttribute("label") ? "?label=1" : "";
      const data = await this.request<Html & { unread: number }>(`/ui/button${label}`);
      if (data?.html) {
        const button = fragment(data.html);
        if (button) {
          if (this.button) this.button.replaceWith(button);
          else this.prepend(button);
          this.button = button;
          this.setCount(this.panel ? 0 : data.unread);
          if (this.panel) this.markOpen(true);
        }
      }
    } else {
      const data = await this.request<{ unread: number }>("/unread");
      if (data) this.setCount(this.panel ? 0 : data.unread);
    }
    await this.loadAnnouncement();
  }

  /**
   * Opens the panel on the newest entries, and marks them seen. `control`
   * is the page's own button, with `button="none"`: a press on it does not
   * count as outside, and it gets the focus back when the panel closes.
   */
  async open(control?: HTMLElement): Promise<void> {
    if (control) this.opener = control;
    const data = await this.request<Html & { since: string | null }>("/ui/panel", { method: "POST" });
    if (!data?.html) return;
    this.category = null;
    this.pages = 1;
    this.entry = null;
    this.since = data.since;
    this.setCount(0);
    this.putPanel(data.html);
    this.button?.querySelector(".tayori-badge")?.remove();
    this.button?.setAttribute("aria-label", this.button.getAttribute("aria-label")?.split(",")[0] ?? "");
    // The open panel has the news: a popup or a toast steps aside until it closes.
    if (this.announcementEl && !this.announcementEl.classList.contains("tayori-announcement-banner")) {
      this.removeAnnouncement();
    }
    this.panel?.focus();
    this.dispatchEvent(new CustomEvent("tayori:open", { bubbles: true }));
  }

  /** Opens the panel, or closes it when it is open: for the page's own control (see open()). */
  async toggle(control?: HTMLElement): Promise<void> {
    if (this.panel) this.close(true);
    else await this.open(control);
  }

  /** Closes the panel; `focus` gives the focus back to the button, or to the page's control that opened it. */
  close(focus: boolean): void {
    if (!this.panel) return;
    this.panel.remove();
    this.panel = null;
    this.entry = null;
    this.markOpen(false);
    document.removeEventListener("pointerdown", this.onPointer);
    if (focus) (this.button ?? this.opener)?.focus();
    this.opener = null;
    void this.loadAnnouncement();
    this.dispatchEvent(new CustomEvent("tayori:close", { bubbles: true }));
  }

  // ── The events of the markup, as Tayori.Live answers them ────────

  private async run({ name, values }: PhxEvent): Promise<void> {
    switch (name) {
      case "tayori:open":
        return this.panel ? this.close(true) : this.open();
      case "tayori:close":
        return this.close(true);
      case "tayori:filter":
        this.category = values.category || null;
        this.pages = 1;
        this.entry = null;
        return this.view(() => this.panel?.querySelector<HTMLElement>(".tayori-chip[aria-pressed='true']"));
      case "tayori:more": {
        const shown = this.panel?.querySelectorAll(".tayori-cards > li").length ?? 0;
        this.pages += 1;
        return this.view(() => this.panel?.querySelectorAll<HTMLElement>(".tayori-card-title button")[shown] ?? null);
      }
      case "tayori:show":
        return this.show(values.id);
      case "tayori:back": {
        const id = this.entry;
        this.entry = null;
        return this.view(() => (id ? this.cardButton(id) : this.panel));
      }
      case "tayori:react":
        return this.react(values.id, values.emoji);
      case "tayori:dismiss":
        return this.dismiss(values.id);
    }
  }

  /** Opens an entry of the list, or the announcement, whole in the panel. */
  private async show(id: string | undefined): Promise<void> {
    if (!id) return;
    if (id === this.announcementId) this.removeAnnouncement(true);
    this.entry = id;
    if (!this.panel) {
      this.category = null;
      this.pages = 1;
    }
    await this.view(() => this.panel?.querySelector<HTMLElement>("[phx-click='tayori:back']") ?? null);
  }

  private async react(id: string | undefined, emoji: string | undefined): Promise<void> {
    if (!id || !emoji) return;
    const done = await this.request(`/${encodeURIComponent(id)}/reactions`, { method: "POST", body: { emoji } });
    if (!done) return;
    await this.view(() =>
      this.panel?.querySelector<HTMLElement>(`.tayori-reaction[phx-value-emoji="${CSS.escape(emoji)}"]`) ?? null,
    );
  }

  /** Dismisses the announcement, for the reader on every device (for a visitor, on this page). */
  private async dismiss(id: string | undefined): Promise<void> {
    if (!id) return;
    const hadFocus = this.announcementEl?.contains(document.activeElement) ?? false;
    this.removeAnnouncement(true);
    if (hadFocus) (this.button ?? this.opener)?.focus();
    await this.request(`/announcement/${encodeURIComponent(id)}/dismiss`, { method: "POST" });
  }

  /** Renders the panel's view again, then puts the focus where `focus` says. */
  private async view(focus: () => HTMLElement | null | undefined): Promise<void> {
    const query = panelQuery({ category: this.category, pages: this.pages, entry: this.entry, since: this.since });
    const data = await this.request<Html>(`/ui/panel${query}`);
    if (!data?.html) return;
    this.putPanel(data.html);
    (focus() ?? this.panel)?.focus();
  }

  private putPanel(html: string): void {
    const panel = fragment(html);
    if (!panel) return;
    panel.tabIndex = -1;
    localizeTimes(panel, panel.lang || undefined);
    if (this.panel) this.panel.replaceWith(panel);
    else this.append(panel);
    this.panel = panel;
    this.markOpen(true);
    document.addEventListener("pointerdown", this.onPointer);
  }

  // The count, and tayori:unread when it changes, for a page that shows it
  // itself (a dot on its own control, with button="none").
  private setCount(count: number): void {
    if (count === this.count) return;
    this.count = count;
    this.dispatchEvent(new CustomEvent("tayori:unread", { bubbles: true, detail: { count } }));
  }

  private markOpen(open: boolean): void {
    this.button?.setAttribute("aria-expanded", String(open));
  }

  private cardButton(id: string): HTMLElement | null {
    return this.panel?.querySelector<HTMLElement>(`[phx-click="tayori:show"][phx-value-id="${CSS.escape(id)}"]`) ?? null;
  }

  // ── The announcement ────────────────────────────────────────────

  private readonly dismissed = new Set<string>();

  private async loadAnnouncement(): Promise<void> {
    const data = await this.request<Html & { id: string | null; kind: string | null }>("/ui/announcement");
    // No :announcements feature, or none: nothing to show.
    if (!data?.html || !data.id || this.dismissed.has(data.id)) return this.removeAnnouncement();
    // The open panel has the news: a popup or a toast would cover it.
    if (this.panel && data.kind !== "banner") return this.removeAnnouncement();
    if (data.id === this.announcementId) return;

    const el = fragment(data.html);
    if (!el) return;
    this.removeAnnouncement();
    el.addEventListener("click", this.onClick);

    if (data.kind === "banner") {
      const selector = this.getAttribute("banner");
      const target = selector ? document.querySelector(selector) : null;
      if (target) target.append(el);
      else document.body.prepend(el);
    } else {
      this.append(el);
    }

    this.announcementEl = el;
    this.announcementId = data.id;
    if (data.kind === "popup") el.querySelector<HTMLElement>("[phx-click='tayori:show']")?.focus();
  }

  /** Takes the announcement off the page; `forGood` keeps it off on this page. */
  private removeAnnouncement(forGood = false): void {
    if (forGood && this.announcementId) this.dismissed.add(this.announcementId);
    this.announcementEl?.removeEventListener("click", this.onClick);
    this.announcementEl?.remove();
    this.announcementEl = null;
    this.announcementId = null;
  }

  // ── The API ─────────────────────────────────────────────────────

  private async request<T>(path: string, options: { method?: string; body?: unknown } = {}, retry = true): Promise<T | null> {
    const method = options.method ?? "GET";
    const url = new URL(this.api + path, document.baseURI);
    const sameOrigin = url.origin === window.location.origin;
    const headers: Record<string, string> = { accept: "application/json" };

    // A reader on another origin is the token's; on the app's own, the
    // session's, with its CSRF token.
    if (this.token) headers.authorization = `Bearer ${this.token}`;
    if (sameOrigin && method !== "GET") {
      const csrf = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
      if (csrf) headers["x-csrf-token"] = csrf;
    }
    if (options.body !== undefined) headers["content-type"] = "application/json";

    try {
      const response = await fetch(url, {
        method,
        headers,
        credentials: "same-origin",
        body: options.body === undefined ? undefined : JSON.stringify(options.body),
      });

      if (response.status === 401 && this.token && retry) {
        const error = (await response.json().catch(() => null)) as { error?: string } | null;
        if (error?.error === "token_expired") {
          // The page may give a new token; until then, the reader is a visitor.
          this.token = null;
          this.dispatchEvent(new CustomEvent("tayori:token-expired", { bubbles: true }));
          return this.request<T>(path, options, false);
        }
      }

      if (!response.ok) return null;
      return (await response.json()) as T;
    } catch {
      return null;
    }
  }
}

/** Defines <tayori-news>, once. */
export function defineNewsElement(name = "tayori-news"): void {
  if (typeof customElements !== "undefined" && !customElements.get(name)) {
    customElements.define(name, TayoriNews);
  }
}
