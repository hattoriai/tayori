// Times written in UTC by the server, shown in the reader's time zone and
// language: <time datetime="..." data-tayori-time>.

const formats = new Map<string, Intl.DateTimeFormat>();

function format(locale: string | undefined, withTime: boolean): Intl.DateTimeFormat {
  const key = `${locale ?? ""}|${withTime}`;
  let fmt = formats.get(key);

  if (!fmt) {
    fmt = new Intl.DateTimeFormat(locale, {
      day: "numeric",
      month: "short",
      year: "numeric",
      ...(withTime ? { hour: "2-digit", minute: "2-digit" } : {}),
    });
    formats.set(key, fmt);
  }

  return fmt;
}

/** The text of a time: the day, and the hour unless `date` is asked. */
export function timeText(iso: string, locale?: string, withTime = true): string | null {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return null;
  return format(locale, withTime).format(date);
}

/** Shows each time of a root that is not shown yet in the local zone. */
export function localizeTimes(root: ParentNode, locale?: string): void {
  root.querySelectorAll<HTMLTimeElement>("time[data-tayori-time]").forEach((el) => {
    const iso = el.getAttribute("datetime");
    if (!iso || el.dataset.tayoriShown === iso) return;

    // The browser's own language and conventions unless one is given.
    const text = timeText(iso, locale, el.dataset.tayoriTime !== "date");
    if (text) {
      el.textContent = text;
      el.dataset.tayoriShown = iso;
      el.title = new Date(iso).toString();
    }
  });
}
