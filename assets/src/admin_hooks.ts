// The admin's own hooks: the appearance menu, and copying a link.

type Hook = {
  el: HTMLElement;
  mounted(): void;
  destroyed?(): void;
  [key: string]: unknown;
};

type Appearance = "light" | "dark" | "system";

const KEY = "tayori-appearance";

function stored(): Appearance {
  try {
    const value = localStorage.getItem(KEY);
    return value === "light" || value === "dark" ? value : "system";
  } catch {
    return "system";
  }
}

const dark = matchMedia("(prefers-color-scheme: dark)");

// Light, dark, or the system's: data-theme on <html>, which the tokens of
// Tayori, Kotoba and Koyomi follow.
export function applyAppearance(appearance: Appearance = stored()): void {
  const theme = appearance === "system" ? (dark.matches ? "dark" : "light") : appearance;
  document.documentElement.dataset.theme = theme;
}

dark.addEventListener("change", () => applyAppearance());

export const TayoriAppearance = {
  mounted(this: Hook) {
    const button = this.el.querySelector<HTMLButtonElement>("button[aria-haspopup]")!;
    const menu = this.el.querySelector<HTMLElement>("[role=menu]")!;
    const items = Array.from(menu.querySelectorAll<HTMLButtonElement>("[data-appearance]"));

    const mark = () => {
      const current = stored();
      for (const item of items) {
        item.setAttribute("aria-checked", String(item.dataset.appearance === current));
      }
    };

    const close = () => {
      menu.hidden = true;
      button.setAttribute("aria-expanded", "false");
    };

    button.addEventListener("click", () => {
      mark();
      menu.hidden = !menu.hidden;
      button.setAttribute("aria-expanded", String(!menu.hidden));
      if (!menu.hidden) items.find((i) => i.getAttribute("aria-checked") === "true")?.focus();
    });

    for (const item of items) {
      item.addEventListener("click", () => {
        const appearance = item.dataset.appearance as Appearance;
        try {
          if (appearance === "system") localStorage.removeItem(KEY);
          else localStorage.setItem(KEY, appearance);
        } catch {
          // A browser with no storage keeps it for this page only.
        }
        applyAppearance(appearance);
        close();
        button.focus();
      });
    }

    const outside = (event: Event) => {
      if (!this.el.contains(event.target as Node)) close();
    };

    const escape = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !menu.hidden) {
        close();
        button.focus();
      }
    };

    document.addEventListener("click", outside);
    document.addEventListener("keydown", escape);
    this.destroyed = () => {
      document.removeEventListener("click", outside);
      document.removeEventListener("keydown", escape);
    };
  },
};

// Copies the element's data-copy (a link, made absolute) or data-copy-text
// (as it is) to the clipboard on a click.
export const TayoriCopy = {
  mounted(this: Hook) {
    this.el.addEventListener("click", () => {
      const raw = this.el.dataset.copyText;
      if (raw) {
        navigator.clipboard?.writeText(raw).catch(() => undefined);
        return;
      }
      const text = this.el.dataset.copy;
      if (!text) return;
      const url = new URL(text, location.href).toString();
      navigator.clipboard?.writeText(url).catch(() => undefined);
    });
  },
};
