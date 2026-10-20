// <tayori-news src="/api/news">: the button and panel of the news, for a
// page that LiveView does not render. It reads Tayori.API: the count of
// unread entries at once and every few minutes, the entries when it opens
// (and marks them seen). It renders the same markup as the LiveView
// components, so tayori.css styles both.

import { localizeTimes } from "./times";

export type Messages = Record<string, string>;

export interface ApiEntry {
  id: string;
  slug: string;
  title: string;
  summary: string | null;
  categories: string[];
  publishedAt: string;
  locale: string;
  html: string | null;
  url: string | null;
}

interface IndexResponse {
  entries: ApiEntry[];
  more: boolean;
  unread: number;
  newAfter: string | null;
  messages: Messages;
}

const ICON =
  '<svg class="tayori-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 6.5A2.5 2.5 0 0 1 6.5 4h11A2.5 2.5 0 0 1 20 6.5v11a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 17.5z"/><path d="m4 7 8 6 8-6"/></svg>';

let panels = 0;

/** The count of unread entries in words. */
export function unreadText(messages: Messages, n: number): string {
  const key = n === 1 ? "unreadOne" : "unreadOther";
  return (messages[key] ?? "{n}").replace("{n}", String(n));
}

/** Whether an entry is new to the reader: published after `newAfter` (never for a visitor). */
export function isNew(entry: ApiEntry, newAfter: string | null): boolean {
  return newAfter !== null && new Date(entry.publishedAt).getTime() > new Date(newAfter).getTime();
}

/** One entry, as Tayori.Components.entry/1 renders it. */
export function renderEntry(entry: ApiEntry, messages: Messages, isNewEntry: boolean): HTMLElement {
  const li = document.createElement("li");
  const article = document.createElement("article");
  article.className = "tayori-entry";
  article.lang = entry.locale;

  const meta = document.createElement("p");
  meta.className = "tayori-entry-meta";

  if (isNewEntry) {
    const mark = document.createElement("span");
    mark.className = "tayori-new";
    mark.textContent = messages.new ?? "New";
    meta.append(mark);
  }

  for (const category of entry.categories) {
    const chip = document.createElement("span");
    chip.className = "tayori-category";
    chip.textContent = category;
    meta.append(chip);
  }

  const time = document.createElement("time");
  time.dateTime = entry.publishedAt;
  time.dataset.tayoriTime = "date";
  time.textContent = entry.publishedAt.slice(0, 10);
  meta.append(time);

  const title = document.createElement("h3");
  title.className = "tayori-entry-title";

  if (entry.url) {
    const link = document.createElement("a");
    link.href = entry.url;
    link.textContent = entry.title;
    title.append(link);
  } else {
    title.textContent = entry.title;
  }

  article.append(meta, title);

  if (entry.html) {
    // The body as Kotoba renders it on the server: every text escaped, and
    // no HTML of the author's own.
    const body = document.createElement("div");
    body.className = "kotoba-content tayori-entry-body";
    body.innerHTML = entry.html;
    article.append(body);
  }

  li.append(article);
  return li;
}

export class TayoriNews extends HTMLElement {
  private button!: HTMLButtonElement;
  private badge!: HTMLSpanElement;
  private panel: HTMLElement | null = null;
  private messages: Messages = {};
  private count = 0;
  private entries: ApiEntry[] = [];
  private newAfter: string | null = null;
  private timer: number | undefined;
  private readonly panelId = `tayori-news-panel-${++panels}`;

  private readonly onKey = (event: KeyboardEvent) => {
    if (event.key === "Escape" && this.panel) this.close(true);
  };

  private readonly onPointer = (event: PointerEvent) => {
    if (this.panel && !this.contains(event.target as Node)) this.close(false);
  };

  private readonly onVisible = () => {
    if (document.visibilityState === "visible") void this.refresh();
  };

  /** The number of entries the reader has not seen. */
  get unread(): number {
    return this.count;
  }

  get src(): string {
    return (this.getAttribute("src") ?? "/api/news").replace(/\/$/, "");
  }

  connectedCallback(): void {
    this.button = document.createElement("button");
    this.button.type = "button";
    this.button.className = "tayori-button";
    this.button.setAttribute("aria-haspopup", "dialog");
    this.button.setAttribute("aria-expanded", "false");
    this.button.setAttribute("aria-controls", this.panelId);
    this.button.innerHTML = ICON;

    if (this.hasAttribute("label")) {
      const label = document.createElement("span");
      label.className = "tayori-button-label";
      this.button.append(label);
    }

    this.badge = document.createElement("span");
    this.badge.className = "tayori-badge";
    this.badge.setAttribute("aria-hidden", "true");
    this.badge.hidden = true;
    this.button.append(this.badge);
    this.button.addEventListener("click", () => (this.panel ? this.close(true) : void this.open()));
    this.replaceChildren(this.button);

    document.addEventListener("visibilitychange", this.onVisible);
    void this.refresh();

    const poll = Number(this.getAttribute("poll") ?? "300");
    if (poll > 0) this.timer = window.setInterval(() => void this.refresh(), poll * 1000);
  }

  disconnectedCallback(): void {
    window.clearInterval(this.timer);
    document.removeEventListener("visibilitychange", this.onVisible);
    this.close(false);
  }

  /** Asks the count of unread entries again. */
  async refresh(): Promise<void> {
    const data = await this.request<{ unread: number; messages: Messages }>("/unread");
    if (!data) return;
    this.messages = data.messages;
    this.setUnread(data.unread);
  }

  /** Opens the panel, with the newest entries, and marks them seen. */
  async open(): Promise<void> {
    const data = await this.request<IndexResponse>("");
    if (!data) return;

    this.messages = data.messages;
    this.entries = data.entries;
    this.newAfter = data.newAfter;
    this.renderPanel(data.more);
    this.setUnread(0);
    void this.request("/seen", "POST");
    this.dispatchEvent(new CustomEvent("tayori:open", { bubbles: true }));
  }

  /** Closes the panel; `focus` gives the focus back to the button. */
  close(focus: boolean): void {
    if (!this.panel) return;
    this.panel.remove();
    this.panel = null;
    this.button.setAttribute("aria-expanded", "false");
    document.removeEventListener("keydown", this.onKey);
    document.removeEventListener("pointerdown", this.onPointer);
    if (focus) this.button.focus();
    this.dispatchEvent(new CustomEvent("tayori:close", { bubbles: true }));
  }

  private setUnread(n: number): void {
    this.count = n;
    this.badge.hidden = n === 0;
    this.badge.textContent = n > 9 ? "9+" : String(n);
    const label = this.messages.button ?? "What's new";
    this.button.setAttribute("aria-label", n > 0 ? `${label}, ${unreadText(this.messages, n)}` : label);
    const text = this.button.querySelector(".tayori-button-label");
    if (text) text.textContent = label;
  }

  private renderPanel(more: boolean): void {
    this.panel?.remove();

    const panel = document.createElement("div");
    panel.id = this.panelId;
    panel.className = "tayori-panel";
    panel.setAttribute("role", "dialog");
    panel.setAttribute("aria-modal", "false");
    panel.setAttribute("aria-labelledby", `${this.panelId}-title`);
    panel.tabIndex = -1;

    const header = document.createElement("header");
    header.className = "tayori-panel-header";
    const title = document.createElement("h2");
    title.id = `${this.panelId}-title`;
    title.textContent = this.messages.title ?? "What's new";
    const close = document.createElement("button");
    close.type = "button";
    close.className = "tayori-close";
    close.setAttribute("aria-label", this.messages.close ?? "Close");
    close.textContent = "×";
    close.addEventListener("click", () => this.close(true));
    header.append(title, close);

    const body = document.createElement("div");
    body.className = "tayori-panel-body";
    const list = document.createElement("ol");
    list.className = "tayori-news";
    for (const entry of this.entries) list.append(renderEntry(entry, this.messages, isNew(entry, this.newAfter)));
    body.append(list);

    if (this.entries.length === 0) {
      const empty = document.createElement("p");
      empty.className = "tayori-empty";
      empty.textContent = this.messages.empty ?? "No news yet.";
      body.append(empty);
    }

    if (more) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "tayori-more";
      button.textContent = this.messages.more ?? "Show more";
      button.addEventListener("click", () => void this.more(list, button));
      body.append(button);
    }

    panel.append(header, body);

    const page = this.getAttribute("page");
    if (page) {
      const footer = document.createElement("footer");
      footer.className = "tayori-panel-footer";
      const link = document.createElement("a");
      link.href = page;
      link.textContent = this.messages.allNews ?? "All the news";
      footer.append(link);
      panel.append(footer);
    }

    this.append(panel);
    this.panel = panel;
    localizeTimes(panel, document.documentElement.lang || undefined);
    this.button.setAttribute("aria-expanded", "true");
    document.addEventListener("keydown", this.onKey);
    document.addEventListener("pointerdown", this.onPointer);
    panel.focus();
  }

  private async more(list: HTMLElement, button: HTMLButtonElement): Promise<void> {
    const last = this.entries[this.entries.length - 1];
    if (!last) return;
    const data = await this.request<IndexResponse>(`?before=${encodeURIComponent(last.id)}`);
    if (!data) return;

    this.entries.push(...data.entries);
    for (const entry of data.entries) list.append(renderEntry(entry, this.messages, isNew(entry, this.newAfter)));
    if (this.panel) localizeTimes(this.panel, document.documentElement.lang || undefined);
    if (!data.more) button.remove();
  }

  private async request<T>(path: string, method = "GET"): Promise<T | null> {
    const headers: Record<string, string> = { accept: "application/json" };
    const csrf = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
    if (csrf && method !== "GET") headers["x-csrf-token"] = csrf;

    try {
      const response = await fetch(this.src + path, { method, headers, credentials: "same-origin" });
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
