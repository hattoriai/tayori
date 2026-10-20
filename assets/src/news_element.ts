// <tayori-news api="/api/news">: the button, the panel and the
// announcement of the news, for a page that LiveView does not render, on
// the app's origin or another (the :embed feature). It reads Tayori.API:
// the count of unread entries at once and every few minutes, the entries
// when it opens (and marks them seen), an entry when a card is chosen. It
// renders the markup of Tayori.Components, so tayori.css styles both, in
// every theme.

import { icon } from "./icons";
import { localizeTimes } from "./times";

export type Messages = Record<string, string>;

export interface ApiCategory {
  key: string;
  name: string;
  color: string;
}

export interface ApiCover {
  url: string;
  alt: string;
  width: number | null;
  height: number | null;
}

export interface ApiReactions {
  counts: Record<string, number>;
  mine: string[];
}

export interface ApiEntry {
  id: string;
  slug: string;
  title: string;
  summary: string | null;
  cover: ApiCover | null;
  categories: ApiCategory[];
  pinned: boolean;
  publishedAt: string;
  locale: string;
  html: string | null;
  text: string | null;
  url: string | null;
  reactions?: ApiReactions;
}

export interface ApiAnnouncement extends ApiEntry {
  announce: "popup" | "toast" | "banner";
  until: string | null;
  cta: { url: string; label: string | null } | null;
}

/** What every answer of the news says of the reader and the app. */
interface About {
  signedIn: boolean;
  locale: string;
  features: string[];
  emoji: string[];
  messages: Messages;
}

interface UnreadResponse extends About {
  unread: number;
}

interface IndexResponse extends About {
  entries: ApiEntry[];
  more: boolean;
  unread: number;
  newAfter: string | null;
  page: string | null;
}

let elements = 0;

/** The count of unread entries in words. */
export function unreadText(messages: Messages, n: number): string {
  const key = n === 1 ? "unreadOne" : "unreadOther";
  return (messages[key] ?? "{n}").replace("{n}", String(n));
}

/** Whether an entry is new to the reader: published after `newAfter` (never for a visitor). */
export function isNew(entry: Pick<ApiEntry, "publishedAt">, newAfter: string | null): boolean {
  return newAfter !== null && new Date(entry.publishedAt).getTime() > new Date(newAfter).getTime();
}

/** The line of a card: the summary, else the start of the body, as the LiveView card. */
export function summaryText(entry: Pick<ApiEntry, "summary" | "text">): string | null {
  if (entry.summary) return entry.summary;
  const text = (entry.text ?? "").replace(/\s+/g, " ").trim();
  if (text === "") return null;
  return [...text].length > 180 ? `${[...text].slice(0, 177).join("")}…` : text;
}

/** The three most given reactions of an entry, for its card. */
export function topReactions(reactions: ApiReactions | undefined): [string, number][] {
  if (!reactions) return [];
  return Object.entries(reactions.counts)
    .filter(([, n]) => n > 0)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3);
}

type Attrs = Record<string, string | boolean | null | undefined>;
type Child = Node | string | null | undefined | false;

/** An element with attributes (false and nullish ones left out) and children. */
function h<K extends keyof HTMLElementTagNameMap>(tag: K, attrs: Attrs = {}, ...children: Child[]): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  for (const [name, value] of Object.entries(attrs)) {
    if (value === false || value === null || value === undefined) continue;
    el.setAttribute(name, value === true ? "" : value);
  }
  for (const child of children) if (child) el.append(child);
  return el;
}

export class TayoriNews extends HTMLElement {
  static observedAttributes = ["reader-token"];

  private readonly uid = ++elements;
  private readonly panelId = `tayori-panel-${this.uid}`;
  private button!: HTMLButtonElement;
  private badge!: HTMLSpanElement;
  private labelText: HTMLSpanElement | null = null;
  private panel: HTMLElement | null = null;
  private announcementEl: HTMLElement | null = null;
  private timer: number | undefined;

  private about: About = { signedIn: false, locale: "", features: [], emoji: [], messages: {} };
  private count = 0;
  private entries: ApiEntry[] = [];
  private more = false;
  private newAfter: string | null = null;
  private page: string | null = null;
  private categories: ApiCategory[] = [];
  private category: string | null = null;
  private entry: ApiEntry | null = null;
  private announcement: ApiAnnouncement | null = null;
  private readonly dismissed = new Set<string>();
  private token: string | null = null;

  private readonly onKey = (event: KeyboardEvent) => {
    if (event.key !== "Escape") return;
    if (this.panel) {
      if (this.entry) this.back();
      else this.close(true);
    } else if (this.announcement?.announce === "popup" && this.announcementEl) {
      void this.dismiss();
    }
  };

  private readonly onPointer = (event: PointerEvent) => {
    const target = event.target as Node;
    if (this.panel && !this.contains(target) && !this.announcementEl?.contains(target)) this.close(false);
  };

  private readonly onVisible = () => {
    if (document.visibilityState === "visible") void this.refresh();
  };

  /** The number of entries the reader has not seen. */
  get unread(): number {
    return this.count;
  }

  /** The path or URL of the JSON API (`api`, or `src`, its older name). */
  get api(): string {
    return (this.getAttribute("api") ?? this.getAttribute("src") ?? "/api/news").replace(/\/$/, "");
  }

  private get messages(): Messages {
    return this.about.messages;
  }

  private get pageLink(): string | null {
    return this.getAttribute("page") ?? this.page;
  }

  attributeChangedCallback(name: string, _old: string | null, value: string | null): void {
    if (name === "reader-token") {
      this.token = value && value.trim() !== "" ? value.trim() : null;
      if (this.isConnected && this.button) void this.refresh();
    }
  }

  connectedCallback(): void {
    this.button = h("button", {
      type: "button",
      class: this.hasAttribute("label") ? "tayori-button tayori-button-labelled" : "tayori-button",
      "aria-haspopup": "dialog",
      "aria-expanded": "false",
      "aria-controls": this.panelId,
    });
    this.button.append(icon("sparkles"));

    if (this.hasAttribute("label")) {
      this.labelText = h("span", { class: "tayori-button-label" });
      this.button.append(this.labelText);
    }

    this.badge = h("span", { class: "tayori-badge", "aria-hidden": "true" });
    this.badge.hidden = true;
    this.button.append(this.badge);
    this.button.addEventListener("click", () => (this.panel ? this.close(true) : void this.open()));
    this.replaceChildren(this.button);
    this.setUnread(0);

    document.addEventListener("visibilitychange", this.onVisible);
    document.addEventListener("keydown", this.onKey);
    void this.refresh();

    const poll = Number(this.getAttribute("poll") ?? "300");
    if (poll > 0) this.timer = window.setInterval(() => void this.refresh(), poll * 1000);
  }

  disconnectedCallback(): void {
    window.clearInterval(this.timer);
    document.removeEventListener("visibilitychange", this.onVisible);
    document.removeEventListener("keydown", this.onKey);
    this.close(false);
    this.announcementEl?.remove();
    this.announcementEl = null;
  }

  /** Asks the count of unread entries again, and the announcement. */
  async refresh(): Promise<void> {
    const data = await this.request<UnreadResponse>("/unread");
    if (!data) return;
    this.setAbout(data);
    this.setUnread(this.panel ? 0 : data.unread);
    if (this.has("announcements")) await this.loadAnnouncement();
  }

  /** Opens the panel, with the newest entries, and marks them seen. */
  async open(): Promise<void> {
    const [data, categories] = await Promise.all([
      this.request<IndexResponse>(this.listPath()),
      this.request<{ categories: ApiCategory[] }>("/categories"),
    ]);
    if (!data) return;

    this.setList(data);
    this.categories = categories?.categories ?? [];
    this.entry = null;
    this.createPanel();
    this.setUnread(0);
    void this.request("/seen", { method: "POST" });
    this.renderAnnouncement();
    this.dispatchEvent(new CustomEvent("tayori:open", { bubbles: true }));
  }

  /** Closes the panel; `focus` gives the focus back to the button. */
  close(focus: boolean): void {
    if (!this.panel) return;
    this.panel.remove();
    this.panel = null;
    this.entry = null;
    this.button.setAttribute("aria-expanded", "false");
    document.removeEventListener("pointerdown", this.onPointer);
    if (focus) this.button.focus();
    this.renderAnnouncement();
    this.dispatchEvent(new CustomEvent("tayori:close", { bubbles: true }));
  }

  private has(feature: string): boolean {
    return this.about.features.includes(feature);
  }

  private setAbout(about: About): void {
    this.about = {
      signedIn: about.signedIn,
      locale: about.locale,
      features: about.features,
      emoji: about.emoji,
      messages: about.messages,
    };
  }

  private setList(data: IndexResponse): void {
    this.setAbout(data);
    this.entries = data.entries;
    this.more = data.more;
    this.newAfter = data.newAfter;
    this.page = data.page;
  }

  private listPath(before?: string): string {
    const params = new URLSearchParams();
    if (this.category) params.set("category", this.category);
    if (before) params.set("before", before);
    const query = params.toString();
    return query ? `?${query}` : "";
  }

  private setUnread(n: number): void {
    this.count = n;
    this.badge.hidden = n === 0;
    this.badge.textContent = n > 9 ? "9+" : String(n);
    const label = this.messages.button ?? "What's new";
    this.button.setAttribute("aria-label", n > 0 ? `${label}, ${unreadText(this.messages, n)}` : label);
    if (this.labelText) this.labelText.textContent = label;
  }

  // ── The panel ───────────────────────────────────────────────────

  private createPanel(): void {
    this.panel?.remove();
    const panel = h("div", {
      id: this.panelId,
      class: "tayori-panel",
      role: "dialog",
      "aria-modal": "false",
      "aria-labelledby": `${this.panelId}-title`,
      tabindex: "-1",
    });
    this.panel = panel;
    this.append(panel);
    this.button.setAttribute("aria-expanded", "true");
    document.addEventListener("pointerdown", this.onPointer);
    this.renderPanel();
    panel.focus();
  }

  private renderPanel(): void {
    const panel = this.panel;
    if (!panel) return;
    const m = this.messages;
    if (this.about.locale) panel.lang = this.about.locale;

    const page = this.pageLink;
    const header = h(
      "header",
      { class: "tayori-panel-header" },
      this.entry && this.iconButton("arrow-left", m.back ?? "Back", () => this.back(), "tayori-back-button"),
      h("h2", { id: `${this.panelId}-title` }, m.title ?? "What's new"),
      page && this.iconLink("arrow-up-right", m.allNews ?? "All the news", page),
      this.iconButton("x", m.close ?? "Close", () => this.close(true), "tayori-close"),
    );

    const body = this.entry ? this.entryBody(this.entry) : this.listBody();

    const footer = h(
      "footer",
      { class: "tayori-panel-footer" },
      h("span", { class: "tayori-hint" }, h("kbd", { class: "tayori-kbd" }, "Esc"), " ", this.entry ? (m.back ?? "Back") : (m.close ?? "Close")),
      page && h("a", { href: page }, m.allNews ?? "All the news", " ", icon("arrow-right")),
    );

    panel.replaceChildren(header, body, footer);
    localizeTimes(panel, this.about.locale || document.documentElement.lang || undefined);
  }

  private iconButton(name: Parameters<typeof icon>[0], label: string, onClick: () => void, extra = ""): HTMLButtonElement {
    const button = h("button", { type: "button", class: `tayori-icon-button ${extra}`.trim(), "aria-label": label }, icon(name));
    button.addEventListener("click", onClick);
    return button;
  }

  private iconLink(name: Parameters<typeof icon>[0], label: string, href: string): HTMLAnchorElement {
    return h("a", { href, class: "tayori-icon-button", "aria-label": label, title: label }, icon(name));
  }

  private listBody(): HTMLElement {
    const m = this.messages;
    const body = h("div", { class: "tayori-panel-body", "data-tayori-view": "list" });

    if (this.categories.length > 0) body.append(this.filter());

    if (this.entries.length > 0) {
      const list = h("ol", { class: "tayori-cards" });
      for (const entry of this.entries) list.append(h("li", { "data-entry-id": entry.id }, this.card(entry)));
      body.append(list);
    } else {
      body.append(h("div", { class: "tayori-empty" }, icon("inbox"), h("p", {}, m.empty ?? "No news yet.")));
    }

    if (this.more) {
      const more = h("button", { type: "button", class: "tayori-more" }, m.more ?? "Show more");
      more.addEventListener("click", () => void this.loadMore());
      body.append(more);
    }

    return body;
  }

  private filter(): HTMLElement {
    const m = this.messages;
    const nav = h("nav", { class: "tayori-filter", "aria-label": m.categories ?? "Categories" });
    const chip = (key: string | null, ...children: Child[]) => {
      const button = h("button", { type: "button", class: "tayori-chip", "aria-pressed": String(this.category === key) }, ...children);
      button.addEventListener("click", () => void this.filterBy(key));
      return button;
    };

    nav.append(chip(null, m.all ?? "All"));
    for (const category of this.categories) {
      const button = chip(category.key, h("span", { class: "tayori-dot", "aria-hidden": "true" }), category.name);
      button.dataset.color = category.color;
      nav.append(button);
    }
    return nav;
  }

  private meta(entry: ApiEntry): HTMLElement {
    const m = this.messages;
    const meta = h("p", { class: "tayori-meta" });
    if (entry.pinned) meta.append(h("span", { class: "tayori-pinned" }, icon("pin"), m.pinned ?? "Pinned"));
    if (isNew(entry, this.newAfter)) {
      meta.append(h("span", { class: "tayori-new", title: m.new ?? "New" }, h("span", { class: "tayori-visually-hidden" }, m.new ?? "New")));
    }
    for (const category of entry.categories) {
      meta.append(h("span", { class: "tayori-category", "data-color": category.color || "gray" }, category.name));
    }
    meta.append(h("time", { datetime: entry.publishedAt, "data-tayori-time": "date" }, entry.publishedAt.slice(0, 10)));
    return meta;
  }

  private cover(cover: ApiCover, className: string, loading = "lazy"): HTMLElement {
    const img = h("img", { src: cover.url, alt: cover.alt, loading, decoding: "async" });
    if (cover.width) img.width = cover.width;
    if (cover.height) img.height = cover.height;
    return h("figure", { class: `tayori-cover ${className}` }, img);
  }

  /** An entry as a card of the panel: the whole card opens it. */
  private card(entry: ApiEntry): HTMLElement {
    const title = h("button", { type: "button", "data-entry-id": entry.id }, entry.title);
    title.addEventListener("click", () => void this.show(entry));
    const summary = summaryText(entry);
    const counts = this.has("reactions") ? topReactions(entry.reactions) : [];

    return h(
      "article",
      { class: entry.pinned ? "tayori-card tayori-card-pinned" : "tayori-card", lang: entry.locale },
      entry.cover && this.cover(entry.cover, "tayori-card-cover"),
      this.meta(entry),
      h("h3", { class: "tayori-card-title" }, title),
      summary && h("p", { class: "tayori-card-summary" }, summary),
      counts.length > 0 && h("p", { class: "tayori-reaction-counts" }, ...counts.map(([emoji, n]) => h("span", {}, `${emoji} ${n}`))),
    );
  }

  private entryBody(entry: ApiEntry): HTMLElement {
    const article = h(
      "article",
      { class: "tayori-entry", lang: entry.locale },
      this.meta(entry),
      h("h3", { class: "tayori-entry-title" }, entry.url ? h("a", { href: entry.url }, entry.title) : h("span", {}, entry.title)),
      entry.summary && h("p", { class: "tayori-entry-summary" }, entry.summary),
      entry.cover && this.cover(entry.cover, "tayori-entry-cover"),
    );

    if (entry.html) {
      // The body as Kotoba renders it on the server: every text escaped,
      // and no HTML of the author's own.
      const body = h("div", { class: "kotoba-content tayori-entry-body" });
      body.innerHTML = entry.html;
      article.append(body);
    }

    if (this.has("reactions")) article.append(h("footer", { class: "tayori-entry-footer" }, this.reactions(entry)));
    return h("div", { class: "tayori-panel-body", "data-tayori-view": "entry" }, article);
  }

  /** The reactions of an entry: each emoji with its count; the reader's own are pressed. */
  private reactions(entry: ApiEntry): HTMLElement {
    const m = this.messages;
    const counts = entry.reactions?.counts ?? {};
    const mine = entry.reactions?.mine ?? [];
    const group = h("div", { class: "tayori-reactions", role: "group", "aria-label": m.react ?? "React to this update" });

    for (const emoji of this.about.emoji) {
      const n = counts[emoji] ?? 0;
      const button = h(
        "button",
        {
          type: "button",
          class: "tayori-reaction",
          "aria-pressed": String(mine.includes(emoji)),
          disabled: !this.about.signedIn,
          title: !this.about.signedIn && (m.signInToReact ?? "Sign in to react"),
          "data-emoji": emoji,
        },
        h("span", { class: "tayori-reaction-emoji", "aria-hidden": "true" }, emoji),
        n > 0 && h("span", { class: "tayori-reaction-count" }, String(n)),
      );
      button.addEventListener("click", () => void this.react(entry, emoji));
      group.append(button);
    }
    return group;
  }

  private async filterBy(key: string | null): Promise<void> {
    this.category = key;
    const data = await this.request<IndexResponse>(this.listPath());
    if (!data || !this.panel) return;
    this.setList(data);
    this.entry = null;
    this.renderPanel();
    this.panel.querySelector<HTMLElement>(".tayori-chip[aria-pressed='true']")?.focus();
  }

  private async loadMore(): Promise<void> {
    const last = this.entries.filter((entry) => !entry.pinned).at(-1);
    if (!last) return;
    const data = await this.request<IndexResponse>(this.listPath(last.id));
    if (!data || !this.panel) return;
    this.entries = [...this.entries, ...data.entries];
    this.more = data.more;
    this.renderPanel();
    this.panel.querySelector<HTMLElement>(`button[data-entry-id="${data.entries[0]?.id ?? last.id}"]`)?.focus();
  }

  /** Opens an entry in the panel, whole, as the API gives it. */
  private async show(entry: ApiEntry): Promise<void> {
    const data = await this.request<{ entry: ApiEntry }>(`/${encodeURIComponent(entry.slug)}`);
    if (!data) return;
    if (!this.panel) {
      await this.open();
      if (!this.panel) return;
    }
    this.entry = data.entry;
    this.renderPanel();
    (this.panel as HTMLElement).querySelector<HTMLElement>(".tayori-back-button")?.focus();
  }

  /** Back to the list, with the focus on the card of the entry. */
  private back(): void {
    const id = this.entry?.id;
    this.entry = null;
    this.renderPanel();
    const card = id && this.panel?.querySelector<HTMLElement>(`button[data-entry-id="${id}"]`);
    if (card) card.focus();
    else this.panel?.focus();
  }

  private async react(entry: ApiEntry, emoji: string): Promise<void> {
    if (!this.about.signedIn) return;
    const data = await this.request<{ reactions: ApiReactions }>(`/${encodeURIComponent(entry.id)}/reactions`, {
      method: "POST",
      body: { emoji },
    });
    if (!data) return;

    const update = (e: ApiEntry) => (e.id === entry.id ? { ...e, reactions: data.reactions } : e);
    this.entries = this.entries.map(update);
    if (this.entry?.id === entry.id) {
      this.entry = update(this.entry);
      this.renderPanel();
      this.panel?.querySelector<HTMLElement>(`.tayori-reaction[data-emoji="${CSS.escape(emoji)}"]`)?.focus();
    }
  }

  // ── The announcement ────────────────────────────────────────────

  private async loadAnnouncement(): Promise<void> {
    const data = await this.request<{ announcement: ApiAnnouncement | null }>("/announcement");
    if (!data) return;
    const next = data.announcement && !this.dismissed.has(data.announcement.id) ? data.announcement : null;
    if (next?.id === this.announcement?.id && next?.title === this.announcement?.title) return;
    this.announcement = next;
    this.renderAnnouncement();
  }

  /** The announcement of the moment: a popup, a toast, or a banner where the page says. */
  private renderAnnouncement(): void {
    this.announcementEl?.remove();
    this.announcementEl = null;
    const a = this.announcement;
    // The open panel has the news: a popup or a toast would cover it.
    if (!a || (this.panel && a.announce !== "banner")) return;

    const m = this.messages;
    const titleId = `tayori-announcement-${this.uid}-title`;
    const popup = a.announce === "popup";

    const readMore = h("button", { type: "button", class: a.cta ? "tayori-cta tayori-cta-quiet" : "tayori-cta" }, m.readMore ?? "Read more");
    readMore.addEventListener("click", () => void this.readAnnouncement());
    const close = this.iconButton("x", m.dismiss ?? "Dismiss", () => void this.dismiss(), "tayori-announcement-close");

    const box = h(
      "div",
      { class: "tayori-announcement-box" },
      a.cover && a.announce !== "banner" && this.cover(a.cover, "tayori-announcement-cover", "eager"),
      h(
        "div",
        { class: "tayori-announcement-text" },
        h("p", { class: "tayori-announcement-eyebrow" }, icon("sparkles"), m.new ?? "New"),
        h("p", { id: titleId, class: "tayori-announcement-title" }, a.title),
        a.summary && a.announce !== "banner" && h("p", { class: "tayori-announcement-summary" }, a.summary),
      ),
      h("div", { class: "tayori-announcement-actions" }, a.cta && h("a", { href: a.cta.url, class: "tayori-cta" }, a.cta.label ?? m.tryIt ?? "Try it"), readMore),
      close,
    );

    const el = h(
      "div",
      {
        class: `tayori-announcement tayori-announcement-${a.announce}`,
        role: popup ? "dialog" : "status",
        "aria-modal": popup && "true",
        "aria-labelledby": titleId,
        lang: a.locale,
      },
      box,
    );

    if (popup) {
      const backdrop = h("div", { class: "tayori-announcement-backdrop" });
      backdrop.addEventListener("click", () => void this.dismiss());
      el.append(backdrop);
    }

    if (a.announce === "banner") {
      const selector = this.getAttribute("banner");
      const target = selector ? document.querySelector(selector) : null;
      if (target) target.append(el);
      else document.body.prepend(el);
    } else {
      this.append(el);
    }

    this.announcementEl = el;
    if (popup) readMore.focus();
  }

  /** Dismisses the announcement, for the reader on every device (for a visitor, on this page). */
  private async dismiss(): Promise<void> {
    const a = this.announcement;
    if (!a) return;
    const hadFocus = this.announcementEl?.contains(document.activeElement) ?? false;
    this.dismissed.add(a.id);
    this.announcement = null;
    this.renderAnnouncement();
    if (hadFocus) this.button.focus();
    await this.request(`/announcement/${encodeURIComponent(a.id)}/dismiss`, { method: "POST" });
  }

  /** Reading the announcement is enough of an answer to it. */
  private async readAnnouncement(): Promise<void> {
    const a = this.announcement;
    if (!a) return;
    await this.dismiss();
    await this.show(a);
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
