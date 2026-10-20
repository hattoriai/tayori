// Builds the static HTML screens of "Atelier", a fictional studio project tool,
// into dev/seed/screens/. Each file is self-contained: inline CSS and SVG,
// no scripts, no external requests. shoot.mjs renders them to images.
//
//   node dev/seed/build-screens.mjs

import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, "screens");

// ---------------------------------------------------------------------------
// Dates

const DAY = 864e5;
const D = (s) => new Date(s + "T00:00:00Z");
const diff = (a, b) => Math.round((D(b) - D(a)) / DAY);
const addDays = (s, n) => new Date(D(s).getTime() + n * DAY).toISOString().slice(0, 10);
const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const MONTH = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const WD = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const TODAY = "2026-10-20";
const fmt = (s) => `${WD[D(s).getUTCDay()]} ${D(s).getUTCDate()} ${MON[D(s).getUTCMonth()]}`;
function isoWeek(s) {
  const d = D(s);
  const day = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - day + 3);
  const firstThu = new Date(Date.UTC(d.getUTCFullYear(), 0, 4));
  return 1 + Math.round(((d - firstThu) / DAY - 3 + ((firstThu.getUTCDay() + 6) % 7)) / 7);
}

// ---------------------------------------------------------------------------
// Icons (Lucide-style strokes)

const P = {
  search: '<circle cx="11" cy="11" r="7.5"/><path d="m20.5 20.5-4.2-4.2"/>',
  inbox: '<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
  check2: '<circle cx="12" cy="12" r="9.5"/><path d="m8.5 12 2.5 2.5 4.5-5"/>',
  calendar: '<rect width="18" height="17" x="3" y="4.5" rx="2.5"/><path d="M16 2.5v4M8 2.5v4M3 10h18"/>',
  board: '<rect width="18" height="18" x="3" y="3" rx="2.5"/><path d="M9 3v18M15 3v12"/>',
  timeline: '<path d="M4 6.5h9M8 12h11M6 17.5h8"/>',
  file: '<path d="M14.5 2.5H6.5a2 2 0 0 0-2 2v15a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2V7.5z"/><path d="M14 2.5v5.5h5.5"/>',
  note: '<path d="M14.5 2.5H6.5a2 2 0 0 0-2 2v15a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2V7.5z"/><path d="M14 2.5v5.5h5.5M8.5 13h7M8.5 17h5"/>',
  overview: '<rect width="7" height="9" x="3" y="3" rx="1.5"/><rect width="7" height="5" x="14" y="3" rx="1.5"/><rect width="7" height="9" x="14" y="12" rx="1.5"/><rect width="7" height="5" x="3" y="16" rx="1.5"/>',
  sliders: '<path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1.5 14h5M9.5 8h5M17.5 16h5"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  chevD: '<path d="m6 9 6 6 6-6"/>',
  chevR: '<path d="m9 18 6-6-6-6"/>',
  chevL: '<path d="m15 18-6-6 6-6"/>',
  more: '<circle cx="5" cy="12" r="1.2" fill="currentColor"/><circle cx="12" cy="12" r="1.2" fill="currentColor"/><circle cx="19" cy="12" r="1.2" fill="currentColor"/>',
  link: '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
  copy: '<rect width="13" height="13" x="9" y="9" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
  download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5M12 15V3"/>',
  x: '<path d="M18 6 6 18M6 6l12 12"/>',
  key: '<circle cx="7.5" cy="15.5" r="5"/><path d="m21 2-9.6 9.6M15.5 7.5l3 3L22 7l-3-3"/>',
  lock: '<rect width="16" height="11" x="4" y="11" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
  eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
  bell: '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>',
  filter: '<path d="M3 5h18M6.5 12h11M10 19h4"/>',
  users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
  clock: '<circle cx="12" cy="12" r="9.5"/><path d="M12 7v5l3 2"/>',
  alert: '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4M12 17h.01"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  msg: '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
  clip: '<path d="m21.44 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l8.57-8.57A4 4 0 1 1 18 8.84l-8.59 8.57a2 2 0 0 1-2.83-2.83l8.49-8.48"/>',
  rss: '<path d="M4 11a9 9 0 0 1 9 9M4 4a16 16 0 0 1 16 16"/><circle cx="5" cy="19" r="1.2" fill="currentColor"/>',
  archive: '<rect width="20" height="5" x="2" y="3" rx="1.5"/><path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8M10 12h4"/>',
  pencil: '<path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/>',
  trash: '<path d="M3 6h18M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2"/>',
  star: '<path d="m12 2.5 2.9 6 6.6.9-4.8 4.6 1.2 6.5L12 17.4l-5.9 3.1 1.2-6.5L2.5 9.4l6.6-.9z"/>',
  dup: '<rect width="13" height="13" x="9" y="9" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
  share: '<path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/><path d="m16 6-4-4-4 4M12 2v13"/>',
  export: '<path d="M14.5 2.5H6.5a2 2 0 0 0-2 2v15a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2V7.5z"/><path d="M14 2.5v5.5h5.5M12 18v-6M9 15l3 3 3-3"/>',
  globe: '<circle cx="12" cy="12" r="9.5"/><path d="M2.5 12h19M12 2.5a14.5 14.5 0 0 1 0 19 14.5 14.5 0 0 1 0-19"/>',
  hook: '<path d="M18 16.98h-5.99c-1.1 0-1.95.94-2.48 1.9A4 4 0 0 1 2 17c.01-.7.2-1.4.57-2"/><path d="m6 17 3.13-5.78c.53-.97.1-2.18-.5-3.1a4 4 0 1 1 6.89-4.06"/><path d="m12 6 3.13 5.73C15.66 12.7 16.9 13 18 13a4 4 0 0 1 0 8"/>',
  user: '<circle cx="12" cy="8" r="4.5"/><path d="M4 21a8 8 0 0 1 16 0"/>',
  card: '<rect width="20" height="14" x="2" y="5" rx="2"/><path d="M2 10h20"/>',
  puzzle: '<path d="M19.4 13.5a2.5 2.5 0 0 0 0-3H18V7a1 1 0 0 0-1-1h-3.5V4.6a2.5 2.5 0 0 0-3 0V6H7a1 1 0 0 0-1 1v3.5H4.6a2.5 2.5 0 0 0 0 3H6V17a1 1 0 0 0 1 1h3.5v1.4a2.5 2.5 0 0 0 3 0V18H17a1 1 0 0 0 1-1v-3.5z"/>',
  arrowL: '<path d="M19 12H5M12 19l-7-7 7-7"/>',
  arrowR: '<path d="M5 12h14M12 5l7 7-7 7"/>',
  cornerDL: '<path d="M9 10 4 15l5 5"/><path d="M20 4v7a4 4 0 0 1-4 4H4"/>',
  sparkle: '<path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1"/>',
  hash: '<path d="M4 9h16M4 15h16M10 3 8 21M16 3l-2 18"/>',
  folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  flag: '<path d="M4 22V4M4 4h12l-2 4 2 4H4"/>',
  tag: '<path d="M20.6 13.4 13.4 20.6a2 2 0 0 1-2.8 0L3 13V3h10l7.6 7.6a2 2 0 0 1 0 2.8z"/><circle cx="7.5" cy="7.5" r="1.2" fill="currentColor"/>',
  info: '<circle cx="12" cy="12" r="9.5"/><path d="M12 16v-4.5M12 8h.01"/>',
  undo: '<path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>',
  zap: '<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>',
  grip: '<circle cx="9" cy="6" r="1" fill="currentColor"/><circle cx="15" cy="6" r="1" fill="currentColor"/><circle cx="9" cy="12" r="1" fill="currentColor"/><circle cx="15" cy="12" r="1" fill="currentColor"/><circle cx="9" cy="18" r="1" fill="currentColor"/><circle cx="15" cy="18" r="1" fill="currentColor"/>',
};
const icon = (n, s = 16, cls = "") =>
  `<svg class="i ${cls}" width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${P[n]}</svg>`;

const atelierMark = (s = 22) =>
  `<svg width="${s}" height="${s}" viewBox="0 0 24 24" aria-hidden="true"><rect width="24" height="24" rx="6.5" fill="#2e6b5c"/><path d="M7 18.5v-6.2a5 5 0 0 1 10 0v6.2" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round"/><path d="M12 7.4v11.1" stroke="#fff" stroke-width="1.6" stroke-linecap="round" opacity=".55"/></svg>`;

// ---------------------------------------------------------------------------
// People and projects

const people = {
  AH: { name: "Aiko Hattori", role: "Creative director", c: "#b8674a" },
  TO: { name: "Tom Okafor", role: "Designer", c: "#4f7a6b" },
  IM: { name: "Inês Moreira", role: "Designer", c: "#8a5d8f" },
  RS: { name: "Ravi Shah", role: "Developer", c: "#4c6a9e" },
  LB: { name: "Lena Brandt", role: "Copywriter", c: "#a07a3c" },
  MS: { name: "Mariko Sato", role: "Producer", c: "#4d8592" },
  NK: { name: "Noah Kim", role: "Photographer", c: "#6b7a3f" },
  SL: { name: "Sofia Lindqvist", role: "Kiln & Co.", c: "#7b6f63" },
};
const av = (k, s = 24) => `<span class="av" style="--s:${s}px;background:${people[k].c}">${k}</span>`;
const stack = (ks, s = 22) => `<span class="stack">${ks.map((k) => av(k, s)).join("")}</span>`;

const projects = [
  { name: "Harbour Museum rebrand", c: "#2e6b5c" },
  { name: "Kiln &amp; Co. catalogue", c: "#c07a3b" },
  { name: "Northfield Library signage", c: "#4c6a9e" },
  { name: "Tamsin Ceramics shop", c: "#b05a6f" },
  { name: "Orchard Street Bakery", c: "#7a6a9b" },
];

// ---------------------------------------------------------------------------
// Base CSS shared by every screen (inlined into each file)

const BASE_CSS = `
*{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#fbfaf8;--panel:#f5f2ee;--surface:#fff;--line:#ece7e0;--line-2:#ddd6cc;--line-3:#f3f0eb;
  --text:#1f1c18;--text-2:#524d46;--muted:#8b847a;--faint:#b5aea4;
  --accent:#2e6b5c;--accent-2:#245548;--accent-soft:#e5f0eb;--accent-line:#b9d6cb;
  --amber:#e2981a;--amber-soft:#fdf1da;--purple:#7353c2;--purple-soft:#efe9fb;
  --red:#c2493d;--red-soft:#fbe9e6;--green:#3c7d4f;--green-soft:#e6f2e8;--orange:#c06a1f;--orange-soft:#fcefe0;
  --hover:#f0ece6;
  --shadow:0 1px 2px rgba(31,28,24,.05),0 2px 8px rgba(31,28,24,.04);
  --pop:0 0 0 1px rgba(31,28,24,.07),0 16px 40px -8px rgba(31,28,24,.22),0 4px 10px -2px rgba(31,28,24,.08);
}
html,body{height:100%}
body{font-family:Inter,-apple-system,"Segoe UI",system-ui,sans-serif;font-size:13px;line-height:1.45;color:var(--text);background:var(--bg);-webkit-font-smoothing:antialiased;font-feature-settings:"cv11","ss03","tnum" 0;letter-spacing:-.006em}
.i{flex:none;display:block}
.app{display:grid;grid-template-columns:236px 1fr;height:100vh;overflow:hidden}
.side{background:var(--panel);border-right:1px solid var(--line);padding:10px 8px;display:flex;flex-direction:column;gap:1px;min-width:0}
.ws{display:flex;align-items:center;gap:8px;padding:5px 8px 5px 6px;border-radius:7px;font-weight:600;font-size:13.5px;margin-bottom:6px}
.ws .chev{color:var(--muted)}
.ws-logo{width:24px;height:24px;border-radius:7px;background:#1f1c18;color:#f5efe6;display:grid;place-items:center;font-size:11px;font-weight:700;letter-spacing:.02em}
.side .tools{margin-left:auto;display:flex;gap:2px;color:var(--muted)}
.side .tools span{width:26px;height:26px;border-radius:6px;display:grid;place-items:center}
.nav a{display:flex;align-items:center;gap:9px;padding:0 8px;border-radius:6px;color:var(--text-2);text-decoration:none;font-weight:500;height:29px;white-space:nowrap;overflow:hidden}
.nav a.on{background:var(--surface);color:var(--text);box-shadow:0 0 0 1px var(--line),0 1px 2px rgba(31,28,24,.05)}
.nav .i{color:var(--muted)}
.nav a.on .i{color:var(--text-2)}
.nav .count{margin-left:auto;font-size:11px;color:var(--muted);font-weight:500}
.nav .count.hot{background:var(--accent);color:#fff;border-radius:9px;padding:0 6px;line-height:17px}
.sec{font-size:11.5px;font-weight:600;color:var(--muted);padding:16px 8px 5px;display:flex;align-items:center;justify-content:space-between}
.pdot{width:9px;height:9px;border-radius:3px;flex:none;margin:0 3px}
.side-foot{margin-top:auto;display:flex;flex-direction:column;gap:6px}
.plan-card{border:1px solid var(--line);background:var(--surface);border-radius:9px;padding:10px 11px;font-size:12px;color:var(--text-2)}
.plan-card b{color:var(--text);font-weight:600}
.meter{height:4px;border-radius:2px;background:var(--line);margin-top:8px;overflow:hidden}
.meter i{display:block;height:100%;background:var(--accent);border-radius:2px}
.main{display:flex;flex-direction:column;min-width:0;background:var(--surface);position:relative}
.top{height:48px;flex:none;border-bottom:1px solid var(--line);display:flex;align-items:center;padding:0 14px 0 18px;gap:10px}
.crumbs{display:flex;align-items:center;gap:7px;color:var(--muted);font-weight:500;white-space:nowrap}
.crumbs b{color:var(--text);font-weight:600}
.crumbs .i{color:var(--faint)}
.spacer{flex:1}
.tabs{display:flex;gap:4px;height:40px;flex:none;align-items:stretch;padding:0 12px;border-bottom:1px solid var(--line)}
.tab{display:flex;align-items:center;gap:7px;padding:0 8px;color:var(--muted);font-weight:500;border-bottom:2px solid transparent;margin-bottom:-1px}
.tab .i{color:var(--faint)}
.tab.on{color:var(--text);border-color:var(--text)}
.tab.on .i{color:var(--text-2)}
.btn{display:inline-flex;align-items:center;gap:6px;height:28px;padding:0 10px;border-radius:7px;border:1px solid var(--line-2);background:var(--surface);font-weight:500;color:var(--text);font-size:12.5px;box-shadow:0 1px 1px rgba(31,28,24,.04);white-space:nowrap;font-family:inherit}
.btn .i{color:var(--text-2)}
.btn.primary{background:var(--accent);border-color:var(--accent-2);color:#fff;box-shadow:0 1px 2px rgba(36,85,72,.35),inset 0 1px 0 rgba(255,255,255,.12)}
.btn.primary .i{color:#fff}
.btn.ghost{border-color:transparent;box-shadow:none;background:transparent;color:var(--text-2)}
.btn.icon{width:28px;padding:0;justify-content:center}
.btn.lg{height:34px;padding:0 14px;font-size:13px}
.av{width:var(--s);height:var(--s);border-radius:50%;display:inline-grid;place-items:center;color:#fff;font-size:calc(var(--s) * .38);font-weight:600;flex:none;letter-spacing:.01em}
.stack{display:inline-flex;padding-left:5px}
.stack .av{box-shadow:0 0 0 2px var(--surface);margin-left:-3px}
.kbd{display:inline-flex;align-items:center;justify-content:center;min-width:18px;height:18px;font:500 10.5px/1 Inter,sans-serif;padding:0 4px;border:1px solid var(--line-2);border-bottom-width:1.5px;border-radius:4px;color:var(--text-2);background:var(--surface)}
.chip{display:inline-flex;align-items:center;gap:5px;height:20px;padding:0 7px;border-radius:5px;font-size:11px;font-weight:500;background:var(--line-3);color:var(--text-2);white-space:nowrap}
.chip.green{background:var(--green-soft);color:var(--green)}
.chip.orange{background:var(--orange-soft);color:var(--orange)}
.chip.red{background:var(--red-soft);color:var(--red)}
.chip.purple{background:var(--purple-soft);color:var(--purple)}
.chip.accent{background:var(--accent-soft);color:var(--accent-2)}
.chip.line{background:transparent;box-shadow:inset 0 0 0 1px var(--line-2)}
.sdot{width:7px;height:7px;border-radius:50%;background:currentColor;flex:none}
.seg{display:inline-flex;background:var(--line-3);border:1px solid var(--line);border-radius:8px;padding:2px;gap:2px}
.seg span{height:22px;padding:0 9px;border-radius:6px;display:flex;align-items:center;font-size:12px;font-weight:500;color:var(--muted)}
.seg span.on{background:var(--surface);color:var(--text);box-shadow:0 0 0 1px var(--line-2),0 1px 2px rgba(31,28,24,.06)}
.toolbar{height:48px;flex:none;display:flex;align-items:center;gap:8px;padding:0 14px 0 18px;border-bottom:1px solid var(--line)}
.toolbar h2{font-size:14px;font-weight:600;letter-spacing:-.01em;margin:0 4px}
.scrim{position:absolute;inset:0;background:rgba(28,25,21,.38);z-index:50}
.dialog{position:absolute;z-index:60;background:var(--surface);border-radius:14px;box-shadow:var(--pop)}
.dialog h3{font-size:15px;font-weight:600;letter-spacing:-.012em}
.field{display:flex;flex-direction:column;gap:6px}
.label{font-size:12px;font-weight:500;color:var(--text-2)}
.input{height:34px;border:1px solid var(--line-2);border-radius:8px;padding:0 11px;display:flex;align-items:center;gap:8px;background:var(--surface);font-size:13px;box-shadow:inset 0 1px 1px rgba(31,28,24,.03)}
.input.focus{border-color:var(--accent);box-shadow:0 0 0 3px rgba(46,107,92,.16)}
.cb{width:16px;height:16px;border-radius:4.5px;border:1.5px solid var(--line-2);display:grid;place-items:center;flex:none;background:var(--surface)}
.cb.on{background:var(--accent);border-color:var(--accent);color:#fff}
.toggle{width:30px;height:18px;border-radius:9px;background:var(--line-2);position:relative;flex:none}
.toggle::after{content:"";position:absolute;top:2px;left:2px;width:14px;height:14px;border-radius:50%;background:#fff;box-shadow:0 1px 2px rgba(0,0,0,.2)}
.toggle.on{background:var(--accent)}
.toggle.on::after{left:14px}
.toast{position:absolute;z-index:70;background:#23201c;color:#f3efe9;border-radius:11px;box-shadow:0 12px 32px -6px rgba(0,0,0,.35);display:flex;align-items:center;gap:10px;padding:11px 12px 11px 14px;font-size:12.5px;font-weight:500}
.toast .muted{color:#a8a197;font-weight:400}
.toast .act{color:#fff;font-weight:600;padding:4px 9px;border-radius:6px;background:rgba(255,255,255,.1)}
mark{background:#fbe7a6;color:inherit;border-radius:3px;padding:0 1px;box-shadow:0 0 0 1px #fbe7a6}
`;

function page(title, body, css = "", bodyClass = "") {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} · Atelier</title>
<style>${BASE_CSS}${css}</style>
</head>
<body${bodyClass ? ` class="${bodyClass}"` : ""}>
${body}
</body>
</html>
`;
}

// ---------------------------------------------------------------------------
// App shell

function sidebar({ nav = "", project = "" } = {}) {
  const n = (key, ic, label, count = "") =>
    `<a class="${nav === key ? "on" : ""}">${icon(ic, 16)}<span>${label}</span>${count}</a>`;
  return `<aside class="side">
  <div class="ws"><span class="ws-logo">H</span><span>Hattori Studio</span>${icon("chevD", 13, "chev")}
    <span class="tools"><span>${icon("search", 15)}</span><span>${icon("pencil", 14)}</span></span></div>
  <nav class="nav">
    ${n("inbox", "inbox", "Inbox", '<span class="count hot">4</span>')}
    ${n("mywork", "check2", "My work", '<span class="count">12</span>')}
    ${n("calendar", "calendar", "Calendar")}
    ${n("clients", "users", "Clients")}
  </nav>
  <div class="sec"><span>Projects</span>${icon("plus", 14)}</div>
  <nav class="nav">
    ${projects
      .map((p) => `<a class="${project === p.name ? "on" : ""}"><span class="pdot" style="background:${p.c}"></span><span>${p.name}</span></a>`)
      .join("")}
  </nav>
  <div class="sec"><span>Favourites</span></div>
  <nav class="nav">
    <a>${icon("note", 16)}<span>Studio rituals</span></a>
    <a>${icon("file", 16)}<span>Type licences</span></a>
  </nav>
  <div class="side-foot">
    <div class="plan-card"><div style="display:flex;justify-content:space-between"><b>Pro plan</b><span>6 seats</span></div>
      <div style="margin-top:3px">48.2 GB of 200 GB</div><div class="meter"><i style="width:24%"></i></div></div>
    <nav class="nav">${n("settings", "sliders", "Settings")}</nav>
  </div>
</aside>`;
}

function projectTop(name, color, extra = "") {
  return `<header class="top">
  <div class="crumbs">${icon("folder", 15)}<span>Projects</span>${icon("chevR", 13)}<span class="pdot" style="background:${color}"></span><b>${name}</b>
    <span style="color:var(--faint);margin-left:2px">${icon("star", 14)}</span></div>
  <div class="spacer"></div>
  ${stack(["AH", "TO", "IM", "RS", "LB"], 24)}
  <span class="btn">${icon("share", 14)}Share</span>
  ${extra || `<span class="btn icon">${icon("more", 16)}</span>`}
</header>`;
}

function projectTabs(active) {
  const t = [
    ["overview", "Overview"],
    ["board", "Board"],
    ["timeline", "Timeline"],
    ["calendar", "Calendar"],
    ["file", "Files"],
    ["note", "Notes"],
  ];
  const ic = { overview: "overview", board: "board", timeline: "timeline", calendar: "calendar", file: "file", note: "note" };
  return `<div class="tabs">${t
    .map(([k, l]) => `<span class="tab ${active === k ? "on" : ""}">${icon(ic[k], 15)}${l}${k === "file" ? '<span style="color:var(--faint);font-size:11px">86</span>' : ""}</span>`)
    .join("")}</div>`;
}

// ---------------------------------------------------------------------------
// Timeline

const BAR_COLORS = {
  teal: ["#e0eee8", "#bcd8cc", "#2e6b5c", "#1e4b40"],
  sky: ["#e2eaf5", "#c3d3ea", "#4c6a9e", "#2b4570"],
  rose: ["#f6e4e6", "#e7c4c9", "#b05a6f", "#6f2f3e"],
  sand: ["#f5ead7", "#e6d1ad", "#b8862f", "#694816"],
  lilac: ["#ebe5f4", "#d4c9e8", "#7a62ad", "#47376e"],
  sage: ["#e6ecdd", "#cbd8b9", "#6f8a4c", "#3f5228"],
};

const TASKS = {
  AH: [
    ["Discovery interviews", "2026-09-21", "2026-10-02", "sage", 0],
    ["Brand strategy workshop", "2026-10-05", "2026-10-09", "lilac", 0],
    ["Logo concepts review", "2026-10-19", "2026-10-22", "teal", 0],
    ["Final identity sign-off", "2026-11-02", "2026-11-05", "teal", 0],
    ["Reopening campaign", "2027-01-11", "2027-02-19", "lilac", 0],
  ],
  TO: [
    ["Wordmark refinement", "2026-10-12", "2026-10-23", "teal", 0],
    ["Wayfinding icon set", "2026-10-26", "2026-11-13", "sand", 0],
    ["Brand guidelines", "2026-11-16", "2026-12-11", "teal", 0],
    ["Logo animation", "2026-10-19", "2026-10-28", "lilac", 1],
    ["Exhibition graphics", "2027-01-04", "2027-02-05", "rose", 0],
  ],
  IM: [
    ["Colour & type system", "2026-10-06", "2026-10-20", "teal", 0],
    ["Exhibition poster series", "2026-10-21", "2026-10-27", "rose", 0],
    ["Merchandise mock-ups", "2026-11-02", "2026-11-11", "rose", 0],
    ["Social templates", "2026-10-14", "2026-10-23", "sky", 1],
    ["Gallery maps", "2026-11-16", "2026-12-04", "sand", 0],
    ["Annual report layout", "2027-01-11", "2027-02-26", "rose", 0],
  ],
  RS: [
    ["Website wireframes", "2026-10-12", "2026-10-23", "sky", 0],
    ["CMS templates", "2026-10-26", "2026-11-20", "sky", 0],
    ["Accessibility audit", "2026-10-28", "2026-11-03", "sage", 1],
    ["Ticketing integration", "2026-11-23", "2026-12-18", "sky", 0],
    ["Website launch", "2027-01-18", "2027-02-12", "sky", 0],
  ],
  LB: [
    ["Tone of voice guide", "2026-10-05", "2026-10-16", "lilac", 0],
    ["Gallery label copy", "2026-10-21", "2026-11-04", "sage", 0],
    ["Website copy", "2026-11-09", "2026-12-04", "sage", 0],
    ["Press kit", "2027-02-01", "2027-03-05", "lilac", 0],
  ],
  MS: [
    ["Budget review", "2026-10-12", "2026-10-14", "sage", 0],
    ["Print vendor quotes", "2026-10-19", "2026-10-23", "sand", 0],
    ["Signage install plan", "2026-11-02", "2026-11-12", "sand", 0],
    ["Signage fabrication", "2026-11-16", "2026-12-18", "sand", 0],
    ["Reopening logistics", "2027-02-15", "2027-03-19", "sage", 0],
  ],
  NK: [
    ["Staff portraits", "2026-10-13", "2026-10-16", "lilac", 0],
    ["Gallery photography", "2026-10-26", "2026-11-06", "sand", 0],
    ["Collection shoot", "2026-11-16", "2026-12-11", "sand", 0],
    ["Campaign photography", "2027-01-25", "2027-02-26", "lilac", 0],
  ],
};
const MILESTONES = [
  ["Concepts approved", "2026-10-16", true],
  ["Board presentation", "2026-10-29", false],
  ["Identity launch", "2026-12-10", false],
  ["Museum reopens", "2027-03-20", false],
];

const textW = (t, size = 11.5) => t.length * size * 0.5 + 20;

function timeline({ start, end, scale, width, laneW = 200, drag = null, animate = false, lanes = Object.keys(TASKS) }) {
  const days = diff(start, end) + 1;
  const pd = width / days;
  const x = (s) => diff(start, s) * pd;
  let top = "";
  let bot = "";
  let layer = "";

  if (scale === "day" || scale === "week") {
    for (let i = 0; i < days; i++) {
      const d = addDays(start, i);
      const dt = D(d);
      const wd = dt.getUTCDay();
      const we = wd === 0 || wd === 6;
      const isToday = d === TODAY;
      const inDrag = drag && drag.range && diff(drag.range[0], d) >= 0 && diff(d, drag.range[1]) >= 0;
      const label =
        scale === "day"
          ? `<span>${WD[wd]}</span><b>${dt.getUTCDate()}</b>`
          : pd >= 30 ? `<span>${"SMTWTFS"[wd]}</span><b>${dt.getUTCDate()}</b>` : `<b>${dt.getUTCDate()}</b>`;
      bot += `<div class="hc${we ? " we" : ""}${isToday ? " today" : ""}${inDrag ? " drag" : ""}" style="left:${i * pd}px;width:${pd}px">${label}</div>`;
      if (we) layer += `<div class="we-shade" style="left:${i * pd}px;width:${pd}px"></div>`;
      if (scale === "day" || wd === 1) layer += `<div class="col-line${wd === 1 ? " strong" : ""}" style="left:${i * pd}px"></div>`;
      if (wd === 1 || i === 0) {
        const wEnd = addDays(d, (7 - ((wd + 6) % 7)) - 1);
        const span = Math.min(diff(d, wEnd) + 1, days - i);
        const lbl =
          scale === "day"
            ? `${MONTH[dt.getUTCMonth()]} ${dt.getUTCFullYear()} <em>Week ${isoWeek(d)}</em>`
            : `${dt.getUTCDate()} – ${D(wEnd).getUTCDate()} ${MON[D(wEnd).getUTCMonth()]} <em>W${isoWeek(d)}</em>`;
        if (span * pd > 60) top += `<div class="ht" style="left:${i * pd}px;width:${span * pd}px">${lbl}</div>`;
      }
    }
  } else if (scale === "weeks") {
    for (let i = 0; i < days; i += 7) {
      const d = addDays(start, i);
      const dt = D(d);
      const cur = diff(d, TODAY) >= 0 && diff(TODAY, addDays(d, 6)) >= 0;
      bot += `<div class="hc${cur ? " cur" : ""}" style="left:${i * pd}px;width:${7 * pd}px"><b>${dt.getUTCDate()}</b><span>W${isoWeek(d)}</span></div>`;
      layer += `<div class="col-line" style="left:${i * pd}px"></div>`;
    }
    let m = start;
    while (diff(m, end) >= 0) {
      const dt = D(m);
      const next = new Date(Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth() + 1, 1)).toISOString().slice(0, 10);
      const segEnd = diff(next, end) >= 0 ? next : addDays(end, 1);
      top += `<div class="ht" style="left:${x(m)}px;width:${diff(m, segEnd) * pd}px">${MONTH[dt.getUTCMonth()]} <em>${dt.getUTCFullYear()}</em></div>`;
      m = next;
    }
  } else if (scale === "quarter") {
    let m = start;
    while (diff(m, end) >= 0) {
      const dt = D(m);
      const next = new Date(Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth() + 1, 1)).toISOString().slice(0, 10);
      const cur = dt.getUTCMonth() === 9 && dt.getUTCFullYear() === 2026;
      bot += `<div class="hc${cur ? " cur" : ""}" style="left:${x(m)}px;width:${diff(m, next) * pd}px"><b>${MON[dt.getUTCMonth()]}</b></div>`;
      layer += `<div class="col-line${dt.getUTCMonth() % 3 === 0 ? " strong" : ""}" style="left:${x(m)}px"></div>`;
      if (dt.getUTCMonth() % 3 === 0 || m === start) {
        const q = Math.floor(dt.getUTCMonth() / 3) + 1;
        const qEnd = new Date(Date.UTC(dt.getUTCFullYear(), (q) * 3, 1)).toISOString().slice(0, 10);
        const segEnd = diff(qEnd, end) >= 0 ? qEnd : addDays(end, 1);
        top += `<div class="ht" style="left:${x(m)}px;width:${diff(m, segEnd) * pd}px">Q${q} <em>${dt.getUTCFullYear()}</em></div>`;
      }
      // faint week ticks
      for (let k = 0; k < diff(m, next); k++) {
        const d = addDays(m, k);
        if (D(d).getUTCDay() === 1) layer += `<div class="col-line faint" style="left:${x(d)}px"></div>`;
      }
      m = next;
    }
  }

  // today
  const tx = x(TODAY) + (scale === "day" || scale === "week" ? pd / 2 : pd / 2);
  layer += `<div class="today-line" style="left:${tx - 1}px"></div>`;
  const todayFlag = `<div class="today-flag" style="left:${tx}px"></div>`;

  // drag guides
  if (drag && drag.range && !animate) {
    layer += `<div class="guide" style="left:${x(drag.range[0])}px"></div><div class="guide" style="left:${x(drag.range[1]) + pd}px"></div>`;
  }

  // milestones lane
  let ms = "";
  const visMs = MILESTONES.filter(([, d]) => diff(start, d) >= 0 && diff(d, end) >= 0);
  visMs.forEach(([t, d, done], i) => {
    const mx = x(d) + pd / 2;
    const nextX = i + 1 < visMs.length ? x(visMs[i + 1][1]) + pd / 2 : width + 40;
    const roomMs = nextX - mx - 30;
    const lbl = roomMs >= textW(t) - 20 ? `<span>${t}</span>` : "";
    ms += `<div class="ms${done ? " done" : ""}" style="left:${mx}px"><i></i>${lbl}</div>`;
  });

  // lanes
  let rows = "";
  for (const k of lanes) {
    const visible = TASKS[k].filter(([, s, e]) => diff(start, e) >= 0 && diff(s, end) >= 0);
    const nRows = Math.max(1, ...visible.map((t) => t[4] + 1));
    const h = nRows * 34 + 24;
    let bars = "";
    for (const [t, s, e, c, row] of visible) {
      const isDrag = drag && drag.task === t;
      const [bg, bd, k1, tx1] = BAR_COLORS[c];
      let s2 = s;
      let e2 = e;
      if (isDrag && !animate) {
        s2 = addDays(s, drag.by);
        e2 = addDays(e, drag.by);
      }
      const clipL = diff(start, s2) < 0;
      const clipR = diff(e2, end) < 0;
      const l = Math.max(0, x(s2));
      const r = Math.min(width, x(e2) + pd);
      const w = Math.max(r - l - 3, 6);
      const y = 12 + row * 34;
      // room after the bar in the same row
      const nexts = visible.filter((o) => o[4] === row && diff(e2, o[1]) > 0).map((o) => x(o[1]));
      const room = (nexts.length ? Math.min(...nexts) : width) - (l + w) - 10;
      const tw = textW(t);
      const mode = tw <= w ? "in" : room >= tw - 12 ? "out" : w >= 64 ? "in" : "none";
      const style = `left:${l + 1}px;width:${w}px;top:${y}px;--b:${bg};--bd:${bd};--k:${k1};--t:${tx1}`;
      const cls = `bar${clipL ? " cl" : ""}${clipR ? " cr" : ""}`;
      if (isDrag && !animate) {
        const gl = x(s) + 1;
        bars += `<div class="ghostbar" style="left:${gl}px;width:${w}px;top:${y}px"></div>`;
        bars += `<div class="${cls} lifted" style="${style}"><span>${t}</span>
          <div class="tip" ><b>${fmt(s2)} → ${fmt(e2)}</b><em>+${drag.by} days</em></div>
          <svg class="grab" width="22" height="22" viewBox="0 0 24 24"><path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V12M11 11.5V4a1.5 1.5 0 0 1 3 0v7.5M14 11.5V5.5a1.5 1.5 0 0 1 3 0v6.5M17 12V8.5a1.5 1.5 0 0 1 3 0V15a6 6 0 0 1-6 6h-2a6 6 0 0 1-5-2.7L4.3 14.4a1.6 1.6 0 0 1 2.6-1.8L8 14" fill="#fff" stroke="#1f1c18" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/></svg>
          <i class="handle l"></i><i class="handle r"></i></div>`;
        continue;
      }
      if (isDrag && animate) {
        bars += `<div class="ghostbar anim-ghost" style="left:${x(s) + 1}px;width:${w}px;top:${y}px"></div>`;
        bars += `<div class="${cls} anim-bar" style="${style};--d:${pd}px"><span>${t}</span>
          <div class="tip anim-tip"><b><i class="t0">${fmt(s)} → ${fmt(e)}</i><i class="t1">${fmt(addDays(s, 1))} → ${fmt(addDays(e, 1))}</i><i class="t2">${fmt(addDays(s, 2))} → ${fmt(addDays(e, 2))}</i></b><em><i class="t0">0 days</i><i class="t1">+1 day</i><i class="t2">+2 days</i></em></div></div>`;
        bars += `<div class="cursor" style="left:${l + w / 2}px;top:${y + 12}px;--d:${pd}px">
          <svg class="c-arrow" width="20" height="20" viewBox="0 0 24 24"><path d="M5 3l14 7.5-6.2 1.6L9.6 18.5z" fill="#1f1c18" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>
          <svg class="c-grab" width="22" height="22" viewBox="0 0 24 24"><path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V12M11 11.5V4a1.5 1.5 0 0 1 3 0v7.5M14 11.5V5.5a1.5 1.5 0 0 1 3 0v6.5M17 12V8.5a1.5 1.5 0 0 1 3 0V15a6 6 0 0 1-6 6h-2a6 6 0 0 1-5-2.7L4.3 14.4a1.6 1.6 0 0 1 2.6-1.8L8 14" fill="#fff" stroke="#1f1c18" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/></svg></div>`;
        continue;
      }
      if (mode === "in") {
        bars += `<div class="${cls}" style="${style}"><span>${t}</span></div>`;
      } else if (mode === "none") {
        bars += `<div class="${cls}" style="${style}" title="${t}"></div>`;
      } else {
        bars += `<div class="${cls}" style="${style}"></div><div class="bar-out" style="left:${l + w + 7}px;top:${y}px;max-width:${Math.max(room, 30)}px">${t}</div>`;
      }
    }
    const p = people[k];
    rows += `<div class="lane" style="height:${h}px">
      <div class="lane-label">${av(k, 26)}<div><div class="nm">${p.name}</div><div class="rl">${p.role} · ${visible.length} ${visible.length === 1 ? "task" : "tasks"}</div></div></div>
      <div class="lane-track">${bars}</div></div>`;
  }

  return `<div class="tl" style="--lane:${laneW}px;--w:${width}px">
  <div class="tl-head">
    <div class="tl-corner"><span>Person</span>${icon("chevD", 12)}<span class="spacer"></span><span>${lanes.length} people</span></div>
    <div class="tl-scale"><div class="tl-top">${top}</div><div class="tl-bot">${bot}</div>${todayFlag}</div>
  </div>
  <div class="tl-body">
    <div class="tl-layer">${layer}</div>
    <div class="lane ms-lane"><div class="lane-label ms-label">${icon("flag", 14)}<span>Milestones</span></div><div class="lane-track">${ms}</div></div>
    ${rows}
  </div>
</div>`;
}

const TL_CSS = `
.tl{position:relative;flex:1;overflow:hidden;font-size:12px;background:var(--surface)}
.tl-head{display:flex;height:54px;border-bottom:1px solid var(--line);background:var(--surface);position:relative;z-index:5}
.tl-corner{width:var(--lane);flex:none;border-right:1px solid var(--line);display:flex;align-items:flex-end;gap:5px;padding:0 14px 9px 16px;color:var(--muted);font-weight:500;font-size:11.5px}
.tl-corner .spacer{flex:1}
.tl-scale{position:relative;width:var(--w)}
.tl-top,.tl-bot{position:relative;height:27px}
.tl-top{border-bottom:1px solid var(--line-3)}
.ht{position:absolute;top:0;height:27px;display:flex;align-items:center;gap:6px;padding-left:9px;font-weight:600;color:var(--text);border-left:1px solid var(--line);white-space:nowrap;font-size:11.5px;overflow:hidden}
.ht em{font-style:normal;color:var(--muted);font-weight:500}
.hc{position:absolute;top:0;height:27px;display:flex;align-items:center;justify-content:center;gap:4px;color:var(--muted);font-size:10.5px;font-weight:500;white-space:nowrap}
.hc b{font-weight:600;color:var(--text-2);font-size:11px;min-width:18px;height:18px;display:inline-grid;place-items:center;border-radius:9px;padding:0 3px}
.hc.we span,.hc.we b{color:var(--faint)}
.hc.today b{background:var(--amber);color:#fff}
.hc.today span{color:#a8690a}
.hc.cur b{color:#a8690a}
.hc.drag{background:var(--accent-soft)}
.hc.drag b{color:var(--accent-2)}
.today-flag{position:absolute;bottom:-1px;width:0;height:0}
.today-flag:not(:empty){bottom:auto;top:30px;transform:translateX(-50%);width:auto;height:18px;background:var(--amber);color:#fff;font-size:10.5px;font-weight:600;padding:0 6px;border-radius:9px;display:grid;place-items:center}
.tl-body{position:relative}
.tl-layer{position:absolute;top:0;bottom:0;left:var(--lane);width:var(--w);pointer-events:none;z-index:0}
.col-line{position:absolute;top:0;bottom:0;width:1px;background:var(--line-3)}
.col-line.strong{background:var(--line)}
.col-line.faint{background:#f7f5f1}
.we-shade{position:absolute;top:0;bottom:0;background:repeating-linear-gradient(135deg,#faf8f4 0 6px,#f6f3ee 6px 7px)}
.today-line{position:absolute;top:0;bottom:0;width:2px;background:var(--amber);z-index:3;box-shadow:0 0 0 3px rgba(226,152,26,.12)}
.guide{position:absolute;top:0;bottom:0;width:0;border-left:1.5px dashed rgba(46,107,92,.55);z-index:3}
.lane{display:flex;border-bottom:1px solid var(--line);position:relative}
.lane-label{width:var(--lane);flex:none;border-right:1px solid var(--line);display:flex;align-items:flex-start;gap:10px;padding:13px 14px 0 16px;background:var(--surface);position:relative;z-index:4}
.lane-label .nm{font-weight:600;font-size:12.5px;color:var(--text);line-height:1.25;white-space:nowrap}
.lane-label .rl{font-size:11px;color:var(--muted);margin-top:1px;white-space:nowrap}
.lane-track{position:relative;flex:1;z-index:2}
.ms-lane{height:42px;background:linear-gradient(#fdfcfa,#fdfcfa)}
.ms-label{align-items:center;padding-top:0;color:var(--muted);font-weight:500;gap:8px}
.ms{position:absolute;top:14px;display:flex;align-items:center;gap:7px;transform:translateX(-6px);white-space:nowrap;font-size:11.5px;font-weight:500;color:var(--text-2)}
.ms i{width:11px;height:11px;transform:rotate(45deg);border-radius:2px;background:var(--surface);border:2px solid var(--text-2)}
.ms.done i{background:var(--accent);border-color:var(--accent)}
.ms.done span{color:var(--muted)}
.bar{position:absolute;height:25px;border-radius:7px;display:flex;align-items:center;padding:0 8px 0 11px;font-weight:550;font-size:11.5px;white-space:nowrap;background:var(--b);color:var(--t);box-shadow:inset 0 0 0 1px var(--bd);overflow:visible}
.bar>span{overflow:hidden;text-overflow:ellipsis;min-width:0}
.bar::before{content:"";position:absolute;left:3px;top:4px;bottom:4px;width:3px;border-radius:2px;background:var(--k)}
.bar.cl{border-top-left-radius:0;border-bottom-left-radius:0}
.bar.cl::before{display:none}
.bar.cr{border-top-right-radius:0;border-bottom-right-radius:0}
.bar-out{position:absolute;height:25px;display:flex;align-items:center;font-size:11.5px;font-weight:500;color:var(--text-2);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ghostbar{position:absolute;height:25px;border-radius:7px;border:1.5px dashed #c9a4ad;background:rgba(246,228,230,.35)}
.bar.lifted{box-shadow:inset 0 0 0 1.5px var(--k),0 10px 22px -6px rgba(111,47,62,.38),0 2px 5px rgba(31,28,24,.12);transform:translateY(-2px);z-index:6}
.bar .handle{position:absolute;top:6px;bottom:6px;width:3px;border-radius:2px;background:var(--k);opacity:.55}
.bar .handle.l{display:none}
.bar .handle.r{right:4px}
.tip{position:absolute;bottom:34px;left:50%;transform:translateX(-50%);background:#23201c;color:#f5f1ea;border-radius:8px;padding:6px 9px;display:flex;align-items:center;gap:8px;font-size:11.5px;white-space:nowrap;box-shadow:0 8px 18px -6px rgba(0,0,0,.35)}
.tip b{font-weight:500}
.tip em{font-style:normal;font-weight:600;color:#1f1c18;background:var(--amber);border-radius:5px;padding:1px 6px;font-size:11px}
.tip::after{content:"";position:absolute;left:50%;bottom:-4px;width:8px;height:8px;background:#23201c;transform:translateX(-50%) rotate(45deg)}
.grab{position:absolute;left:46%;top:11px;filter:drop-shadow(0 2px 2px rgba(0,0,0,.25))}
`;

// ---------------------------------------------------------------------------
// Timeline screens

function timelineToolbar(zoom, label) {
  const z = ["Day", "Week", "Month", "Quarter"];
  return `<div class="toolbar">
    <span class="btn">Today</span>
    <span class="btn icon ghost">${icon("chevL", 15)}</span><span class="btn icon ghost">${icon("chevR", 15)}</span>
    <h2>${label}</h2>
    <div class="spacer" style="flex:1"></div>
    <span class="seg">${z.map((s) => `<span class="${s === zoom ? "on" : ""}">${s}</span>`).join("")}</span>
    <span class="btn">${icon("filter", 14)}Filter</span>
    <span class="btn">${icon("users", 14)}Group: Person</span>
    <span class="btn primary">${icon("plus", 14)}New task</span>
  </div>`;
}

function timelineScreen({ zoom, label, tl, title = "Timeline" }) {
  const proj = projects[0];
  const body = `<div class="app">${sidebar({ project: proj.name })}
  <main class="main">${projectTop(proj.name, proj.c)}${projectTabs("timeline")}${timelineToolbar(zoom, label)}${tl}</main></div>`;
  return page(title, body, TL_CSS);
}

const GRID_W = 1280 - 236 - 200; // 844

const screens = {};

screens["timeline"] = timelineScreen({
  zoom: "Week",
  label: "October 2026",
  tl: timeline({ start: "2026-10-12", end: "2026-11-06", scale: "week", width: GRID_W, drag: { task: "Exhibition poster series", by: 2, range: ["2026-10-23", "2026-10-29"] } }),
});
screens["timeline-day"] = timelineScreen({
  zoom: "Day",
  label: "19 – 30 October",
  tl: timeline({ start: "2026-10-19", end: "2026-10-30", scale: "day", width: GRID_W }),
});
screens["timeline-week"] = timelineScreen({
  zoom: "Week",
  label: "October 2026",
  tl: timeline({ start: "2026-10-12", end: "2026-11-06", scale: "week", width: GRID_W }),
});
screens["timeline-quarter"] = timelineScreen({
  zoom: "Quarter",
  label: "Sep 2026 – Mar 2027",
  tl: timeline({ start: "2026-09-01", end: "2027-03-31", scale: "quarter", width: GRID_W }),
});

// Animated variant for the screen recording (body.play starts it).
{
  const proj = projects[0];
  const panelW = 304;
  const w = 1280 - 236 - panelW - 184;
  const tl = timeline({ start: "2026-10-14", end: "2026-11-03", scale: "week", width: w, laneW: 184, drag: { task: "Exhibition poster series", by: 2 }, animate: true, lanes: ["AH", "TO", "IM", "RS", "LB", "MS", "NK"] });
  const panel = `<aside class="panel">
    <div class="ph"><span class="chip orange"><span class="sdot"></span>In progress</span><span class="spacer" style="flex:1"></span><span class="btn icon ghost">${icon("more", 16)}</span><span class="btn icon ghost">${icon("x", 15)}</span></div>
    <h3>Exhibition poster series</h3>
    <p class="desc">Six A1 posters for the reopening, one per gallery. Uses the new harbour blue and the condensed cut of the wordmark.</p>
    <dl>
      <dt>Assignee</dt><dd>${av("IM", 20)} Inês Moreira</dd>
      <dt>Start</dt><dd><span class="swap"><i class="old">${fmt("2026-10-21")}</i><i class="new">${fmt("2026-10-23")}</i></span></dd>
      <dt>Due</dt><dd><span class="swap"><i class="old">${fmt("2026-10-27")}</i><i class="new">${fmt("2026-10-29")}</i></span></dd>
      <dt>Project</dt><dd><span class="pdot" style="background:${proj.c};margin:0"></span> Harbour Museum</dd>
      <dt>Tags</dt><dd><span class="chip">Print</span><span class="chip">Exhibition</span></dd>
    </dl>
    <div class="subhead">Subtasks <span>2 of 4</span></div>
    <ul class="subs">
      <li><span class="cb on">${icon("check", 11)}</span>Grid and type scale</li>
      <li><span class="cb on">${icon("check", 11)}</span>Photography selects</li>
      <li><span class="cb"></span>Proofs to Mariko</li>
      <li><span class="cb"></span>Print-ready PDFs</li>
    </ul>
    <div class="subhead">Activity</div>
    <div class="act">${av("AH", 20)}<div><b>Aiko</b> commented <span>2h</span><p>Love poster 3. Can we try the date in the harbour blue?</p></div></div>
  </aside>`;
  const css = `
  .wrap{display:flex;flex:1;min-height:0}
  .panel{width:${panelW}px;flex:none;border-left:1px solid var(--line);padding:14px 18px;display:flex;flex-direction:column;gap:12px;background:var(--surface);overflow:hidden}
  .ph{display:flex;align-items:center;gap:4px}
  .panel h3{font-size:17px;font-weight:600;letter-spacing:-.018em}
  .desc{color:var(--text-2);font-size:12.5px;line-height:1.55}
  dl{display:grid;grid-template-columns:76px 1fr;row-gap:9px;font-size:12.5px;align-items:center}
  dt{color:var(--muted)}
  dd{display:flex;align-items:center;gap:7px;font-weight:500}
  .swap{position:relative;display:inline-block;height:22px;min-width:110px}
  .swap i{position:absolute;left:0;top:0;font-style:normal;white-space:nowrap;line-height:22px;padding:0 6px;margin-left:-6px;border-radius:5px}
  .swap .new{opacity:0}
  .subhead{display:flex;justify-content:space-between;font-size:12px;font-weight:600;color:var(--text-2);padding-top:6px;border-top:1px solid var(--line)}
  .subhead span{color:var(--muted);font-weight:500}
  .subs{list-style:none;display:flex;flex-direction:column;gap:7px;font-size:12.5px}
  .subs li{display:flex;align-items:center;gap:9px}
  .act{display:flex;gap:9px;font-size:12px;color:var(--text-2)}
  .act span{color:var(--muted)}
  .act p{margin-top:3px;color:var(--text);line-height:1.5}
  .cursor{position:absolute;z-index:20;width:0;height:0;transform:translate(170px,150px)}
  .cursor svg{position:absolute;left:-3px;top:-3px;filter:drop-shadow(0 2px 3px rgba(0,0,0,.25))}
  .cursor .c-grab{opacity:0;left:-9px;top:-6px}
  .anim-ghost{opacity:0}
  .anim-tip{opacity:0}
  .anim-tip i{font-style:normal}
  .anim-tip b,.anim-tip em{display:grid}
  .anim-tip b i,.anim-tip em i{grid-area:1/1}
  .anim-tip .t1,.anim-tip .t2{opacity:0}
  .toast{right:${panelW + 20}px;bottom:20px;opacity:0;transform:translateY(8px)}
  body.play .cursor{animation:cur 4.2s linear forwards}
  body.play .cursor .c-arrow{animation:arrow 4.2s steps(1) forwards}
  body.play .cursor .c-grab{animation:grabc 4.2s steps(1) forwards}
  body.play .anim-bar{animation:bar 4.2s forwards}
  body.play .anim-ghost{animation:ghost 4.2s forwards}
  body.play .anim-tip{animation:tip 4.2s forwards}
  body.play .anim-tip .t0{animation:t0 4.2s steps(1) forwards}
  body.play .anim-tip .t1{animation:t1 4.2s steps(1) forwards}
  body.play .anim-tip .t2{animation:t2 4.2s steps(1) forwards}
  body.play .swap .old{animation:old 4.2s forwards}
  body.play .swap .new{animation:new 4.2s forwards}
  body.play .toast{animation:toast 4.2s forwards}
  @keyframes cur{
    0%{transform:translate(170px,150px);animation-timing-function:cubic-bezier(.3,.1,.2,1)}
    16%{transform:translate(0,0)}
    20%{transform:translate(0,0);animation-timing-function:cubic-bezier(.45,0,.4,1)}
    52%{transform:translate(calc(var(--d) * 2),0)}
    62%{transform:translate(calc(var(--d) * 2),0);animation-timing-function:ease-in-out}
    80%{transform:translate(calc(var(--d) * 2 + 60px),70px)}
    100%{transform:translate(calc(var(--d) * 2 + 60px),70px)}}
  @keyframes arrow{0%{opacity:1}19%{opacity:0}58%{opacity:1}}
  @keyframes grabc{0%{opacity:0}19%{opacity:1}58%{opacity:0}}
  @keyframes bar{
    0%,18%{transform:none;box-shadow:inset 0 0 0 1px var(--bd)}
    20%{transform:translateY(-2px);box-shadow:inset 0 0 0 1.5px var(--k),0 10px 22px -6px rgba(111,47,62,.38)}
    33%{transform:translate(0,-2px)}
    35%{transform:translate(var(--d),-2px)}
    43%{transform:translate(var(--d),-2px)}
    45%{transform:translate(calc(var(--d) * 2),-2px)}
    57%{transform:translate(calc(var(--d) * 2),-2px);box-shadow:inset 0 0 0 1.5px var(--k),0 10px 22px -6px rgba(111,47,62,.38)}
    61%,100%{transform:translate(calc(var(--d) * 2),0);box-shadow:inset 0 0 0 1px var(--bd)}}
  @keyframes ghost{0%,19%{opacity:0}21%,57%{opacity:1}61%,100%{opacity:0}}
  @keyframes tip{0%,21%{opacity:0}24%,57%{opacity:1}61%,100%{opacity:0}}
  @keyframes t0{0%{opacity:1}34%{opacity:0}}
  @keyframes t1{0%{opacity:0}34%{opacity:1}44%{opacity:0}}
  @keyframes t2{0%{opacity:0}44%{opacity:1}}
  @keyframes old{0%,60%{opacity:1}63%,100%{opacity:0}}
  @keyframes new{0%,60%{opacity:0;background:transparent}63%{opacity:1;background:var(--amber-soft);box-shadow:0 0 0 1px #f2d79c}88%{background:var(--amber-soft);box-shadow:0 0 0 1px #f2d79c}100%{opacity:1;background:transparent;box-shadow:none}}
  @keyframes toast{0%,62%{opacity:0;transform:translateY(8px)}67%,100%{opacity:1;transform:none}}
  `;
  const toast = `<div class="toast">${icon("check2", 16)}<span>Moved to 23 – 29 Oct <span class="muted">· Exhibition poster series</span></span><span class="act">Undo <span class="kbd" style="background:transparent;color:#d8d2c8;border-color:#5a554e;margin-left:4px">⌘Z</span></span></div>`;
  const body = `<div class="app">${sidebar({ project: proj.name })}
  <main class="main">${projectTop(proj.name, proj.c)}${projectTabs("timeline")}${timelineToolbar("Week", "October 2026")}
  <div class="wrap">${tl}${panel}</div>${toast}</main></div>`;
  screens["timeline-drag"] = page("Timeline", body, TL_CSS + css);
}

// ---------------------------------------------------------------------------
// Kanban boards

function potArt(bg, glaze, shape = "jar", accent = "#fff") {
  const shapes = {
    jar: `<ellipse cx="100" cy="128" rx="52" ry="7" fill="rgba(0,0,0,.12)"/><path d="M78 34h44c0 6 6 9 14 18 12 14 14 32 10 48-4 15-16 26-46 26s-42-11-46-26c-4-16-2-34 10-48 8-9 14-12 14-18z" fill="${glaze}"/><path d="M78 34h44" stroke="rgba(0,0,0,.18)" stroke-width="3"/><path d="M70 58c-6 12-7 28-3 40" stroke="${accent}" stroke-opacity=".35" stroke-width="5" stroke-linecap="round" fill="none"/>`,
    vase: `<ellipse cx="100" cy="128" rx="34" ry="6" fill="rgba(0,0,0,.12)"/><path d="M90 22h20v14c0 8 16 14 18 40 2 28-8 50-28 50s-30-22-28-50c2-26 18-32 18-40z" fill="${glaze}"/><path d="M84 66c-4 14-3 30 2 42" stroke="${accent}" stroke-opacity=".35" stroke-width="4" stroke-linecap="round" fill="none"/>`,
    bowls: `<ellipse cx="100" cy="122" rx="70" ry="8" fill="rgba(0,0,0,.12)"/><path d="M36 84h64c0 20-14 36-32 36S36 104 36 84z" fill="${glaze}"/><path d="M96 92h72c0 18-16 30-36 30s-36-12-36-30z" fill="${accent}" opacity=".9"/><ellipse cx="68" cy="84" rx="32" ry="6" fill="rgba(255,255,255,.25)"/><ellipse cx="132" cy="92" rx="36" ry="6" fill="rgba(0,0,0,.08)"/>`,
    swatches: [0, 1, 2, 3, 4]
      .map((i) => `<rect x="${26 + i * 31}" y="${40 + (i % 2) * 8}" width="26" height="70" rx="5" fill="${["#c7b39a", "#7d8f86", "#3e5a6b", "#b9764e", "#e9e1d3"][i]}" stroke="rgba(0,0,0,.08)"/>`)
      .join(""),
  };
  return `<svg viewBox="-60 6 320 140" preserveAspectRatio="xMidYMid slice" width="100%" height="100%"><rect x="-60" width="320" height="150" fill="${bg}"/><rect x="-60" y="104" width="320" height="46" fill="rgba(0,0,0,.05)"/>${shapes[shape]}</svg>`;
}

function card({ title, art, labels = [], due, dueTone = "", comments, files, who = [], status }) {
  return `<div class="kc">
    ${art ? `<div class="kc-art">${art}</div>` : ""}
    <div class="kc-b">
      ${labels.length || status ? `<div class="kc-l">${status || ""}${labels.map((l) => `<span class="chip">${l}</span>`).join("")}</div>` : ""}
      <div class="kc-t">${title}</div>
      <div class="kc-m">
        ${due ? `<span class="due ${dueTone}">${icon("calendar", 12)}${due}</span>` : ""}
        ${comments ? `<span>${icon("msg", 12)}${comments}</span>` : ""}
        ${files ? `<span>${icon("clip", 12)}${files}</span>` : ""}
        <span class="spacer" style="flex:1"></span>${who.length ? stack(who, 20) : ""}
      </div>
    </div>
  </div>`;
}

const KANBAN_CSS = `
.kb{flex:1;display:flex;gap:14px;padding:16px 18px;overflow:hidden;background:var(--bg);align-items:flex-start}
.kcol{width:252px;flex:none;display:flex;flex-direction:column;gap:8px}
.kh{display:flex;align-items:center;gap:7px;padding:2px 4px 4px;font-weight:600;font-size:12.5px}
.kh .n{color:var(--muted);font-weight:500}
.kh .spacer{flex:1}
.kh .i{color:var(--faint)}
.kc{background:var(--surface);border-radius:10px;box-shadow:0 0 0 1px var(--line),0 1px 2px rgba(31,28,24,.04);overflow:hidden}
.kc-art{height:118px;border-bottom:1px solid var(--line-3)}
.kc-art svg{display:block}
.kc-b{padding:10px 11px 10px;display:flex;flex-direction:column;gap:7px}
.kc-l{display:flex;gap:5px;flex-wrap:wrap}
.kc-t{font-weight:550;font-size:13px;line-height:1.35;letter-spacing:-.008em}
.kc-m{display:flex;align-items:center;gap:10px;color:var(--muted);font-size:11.5px}
.kc-m>span{display:inline-flex;align-items:center;gap:4px}
.due.soon{color:#a8690a}
.due.late{color:var(--red)}
.kadd{display:flex;align-items:center;gap:6px;color:var(--muted);padding:6px 6px;font-weight:500}
`;

const harbourCols = [
  {
    t: "Backlog", n: 9, dot: "#b5aea4",
    cards: [
      { title: "Shop bag and ticket stock", labels: ["Print"], due: "12 Nov", who: ["MS"], files: 2 },
      { title: "Newsletter template in the new type", labels: ["Digital"], due: "18 Nov", who: ["RS", "LB"] },
      { title: "Café menu boards", labels: ["Signage"], who: ["TO"] },
    ],
  },
  {
    t: "In progress", n: 6, dot: "#c06a1f",
    cards: [
      { title: "Exhibition poster series", art: potArt("#e9dfd2", "#335c74", "vase", "#f4ede3"), labels: ["Print", "Exhibition"], due: "27 Oct", dueTone: "soon", comments: 4, files: 6, who: ["IM", "AH"] },
      { title: "Wayfinding icon set", labels: ["Signage"], due: "13 Nov", comments: 2, who: ["TO"] },
      { title: "Website wireframes", labels: ["Digital"], due: "23 Oct", dueTone: "soon", files: 3, who: ["RS"] },
    ],
  },
  {
    t: "Review", n: 3, dot: "#7353c2",
    cards: [
      { title: "Wordmark — final weights", labels: ["Identity"], due: "Today", dueTone: "late", comments: 7, files: 4, who: ["TO", "AH"] },
      { title: "Tone of voice guide v2", labels: ["Copy"], due: "22 Oct", comments: 3, who: ["LB"] },
    ],
  },
  {
    t: "Done", n: 14, dot: "#3c7d4f",
    cards: [
      { title: "Colour & type system", labels: ["Identity"], due: "20 Oct", files: 9, who: ["IM"] },
      { title: "Brand strategy workshop", labels: ["Strategy"], comments: 12, who: ["AH", "LB", "MS"] },
    ],
  },
];

function kanban(cols) {
  return `<div class="kb">${cols
    .map(
      (c) => `<div class="kcol"><div class="kh"><span class="sdot" style="color:${c.dot}"></span>${c.t}<span class="n">${c.n}</span><span class="spacer"></span>${icon("plus", 14)}${icon("more", 14)}</div>
      ${c.cards.map(card).join("")}<div class="kadd">${icon("plus", 14)}Add card</div></div>`
    )
    .join("")}</div>`;
}

function boardToolbar() {
  return `<div class="toolbar">
    <span class="btn">${icon("filter", 14)}Filter</span>
    <span class="btn">${icon("users", 14)}Everyone</span>
    <span class="btn ghost">${icon("tag", 14)}Labels</span>
    <div style="flex:1"></div>
    <span class="seg"><span class="on">Status</span><span>Person</span><span>Phase</span></span>
    <span class="btn primary">${icon("plus", 14)}New card</span>
  </div>`;
}

function harbourBoard({ topExtra = "", overlay = "" } = {}) {
  const proj = projects[0];
  return `<div class="app">${sidebar({ project: proj.name })}
  <main class="main">${projectTop(proj.name, proj.c, topExtra)}${projectTabs("board")}${boardToolbar()}${kanban(harbourCols)}${overlay}</main></div>`;
}

// ---------------------------------------------------------------------------
// Kiln & Co. board (shared with a client)

const kilnCols = [
  {
    t: "To do", n: 3, dot: "#b5aea4",
    cards: [
      { title: "Index and price list", labels: ["Layout"], due: "6 Nov", files: 2, who: ["LB"] },
      { title: "Back cover photograph", art: potArt("#e7e1d6", "#3e5a6b", "bowls", "#c9b79c"), labels: ["Photography"], due: "9 Nov", comments: 1, who: ["TO", "NK"] },
      { title: "Order form and colophon", labels: ["Copy"], due: "11 Nov", who: ["LB"] },
    ],
  },
  {
    t: "In progress", n: 3, dot: "#c06a1f",
    cards: [
      { title: "Glaze swatch spread", art: potArt("#efe7dc", "#7d8f86", "swatches"), labels: ["Layout"], due: "28 Oct", comments: 3, files: 5, who: ["IM"] },
      { title: "Studio portraits, retouch", labels: ["Photography"], due: "30 Oct", files: 14, who: ["NK"] },
      { title: "Price list layout", labels: ["Layout"], due: "2 Nov", comments: 1, who: ["IM"] },
    ],
  },
  {
    t: "Client review", n: 3, dot: "#7353c2",
    cards: [
      { title: "Cover, option B", art: potArt("#e4d6c3", "#b9764e", "jar", "#fff6ea"), status: '<span class="chip orange"><span class="sdot"></span>In review</span>', due: "22 Oct", dueTone: "soon", comments: 5, files: 3, who: ["AH"] },
      { title: "Spring range introduction", status: '<span class="chip orange"><span class="sdot"></span>In review</span>', labels: ["Copy"], due: "23 Oct", comments: 2, who: ["LB"] },
      { title: "Glaze names, final list", status: '<span class="chip red"><span class="sdot"></span>Waiting for Kiln &amp; Co.</span>', due: "21 Oct", dueTone: "late", comments: 4, who: ["LB"] },
    ],
  },
  {
    t: "Approved", n: 3, dot: "#3c7d4f",
    cards: [
      { title: "Moon jar product shots", art: potArt("#dfe3df", "#f1ece2", "jar", "#c8bfb1"), status: '<span class="chip green"><span class="sdot"></span>Approved</span>', comments: 6, files: 18, who: ["TO"] },
      { title: "Catalogue grid and type", status: '<span class="chip green"><span class="sdot"></span>Approved</span>', labels: ["Layout"], files: 4, who: ["IM", "AH"] },
      { title: "Paper: Munken Pure 150 g", status: '<span class="chip green"><span class="sdot"></span>Approved</span>', labels: ["Print"], files: 1, who: ["MS"] },
    ],
  },
];

function kilnBoard({ overlay = "" } = {}) {
  const proj = projects[1];
  return `<div class="app">${sidebar({ project: proj.name })}
  <main class="main">${projectTop(proj.name, proj.c)}${projectTabs("board")}${boardToolbar()}${kanban(kilnCols)}${overlay}</main></div>`;
}

// ---------------------------------------------------------------------------
// Share dialog

screens["share-dialog"] = page(
  "Share board",
  kilnBoard({
    overlay: `<div class="scrim"></div>
  <div class="dialog share" style="left:50%;top:84px;transform:translateX(-50%);width:500px">
    <div class="dh"><div><h3>Share board</h3><p class="sub">Kiln &amp; Co. catalogue · Board</p></div><span class="btn icon ghost">${icon("x", 16)}</span></div>
    <div class="db">
      <div class="row-t">
        <div class="ico">${icon("globe", 17)}</div>
        <div style="flex:1"><div class="rt">Link on</div><div class="rs">Anyone with the link can open this board. They don't need an account.</div></div>
        <span class="toggle on"></span>
      </div>
      <div class="linkrow"><div class="input" style="flex:1">${icon("link", 14)}<span class="url">atelier.test/s/kiln-co/<b>8fQ2-mR4x</b></span></div><span class="btn lg primary">${icon("copy", 14)}Copy link</span></div>
      <div class="opts">
        <div class="opt"><div class="ico sm">${icon("eye", 15)}</div><div style="flex:1"><div class="rt">Read only</div><div class="rs">Clients can read cards, open files and leave comments marked “client”.</div></div><span class="toggle on"></span></div>
        <div class="opt"><div class="ico sm">${icon("clock", 15)}</div><div style="flex:1"><div class="rt">Link expires</div><div class="rs">The link stops working at midnight.</div></div><span class="btn">${icon("calendar", 13)}30 Nov 2026${icon("chevD", 13)}</span></div>
        <div class="opt"><div class="ico sm">${icon("lock", 15)}</div><div style="flex:1"><div class="rt">Hide internal notes and budgets</div><div class="rs">Always hidden on shared boards.</div></div><span class="cb on">${icon("check", 11)}</span></div>
      </div>
      <div class="people">
        <div class="label" style="margin-bottom:8px">Sent to</div>
        <div class="person">${av("SL", 28)}<div style="flex:1"><div class="rt">Sofia Lindqvist</div><div class="rs">sofia@kilnandco.test · Kiln &amp; Co.</div></div><span class="chip">Client</span><span class="muted-s">Opened 2 h ago</span></div>
      </div>
    </div>
    <div class="df"><span class="chip accent">${icon("star", 11)}Pro</span><span class="muted-s">Part of Atelier Pro.</span><div style="flex:1"></div><span class="btn">Preview as client</span><span class="btn primary">Done</span></div>
  </div>`,
  }),
  KANBAN_CSS +
    `
  .share .dh{display:flex;align-items:flex-start;justify-content:space-between;padding:18px 18px 4px 22px}
  .sub{color:var(--muted);font-size:12.5px;margin-top:2px}
  .db{padding:12px 22px 18px;display:flex;flex-direction:column;gap:14px}
  .row-t{display:flex;align-items:center;gap:12px;padding:12px;border-radius:10px;background:var(--accent-soft);box-shadow:inset 0 0 0 1px var(--accent-line)}
  .ico{width:34px;height:34px;border-radius:9px;background:var(--surface);display:grid;place-items:center;color:var(--accent);box-shadow:0 0 0 1px var(--accent-line)}
  .ico.sm{width:30px;height:30px;color:var(--text-2);box-shadow:0 0 0 1px var(--line);background:var(--bg)}
  .rt{font-weight:600;font-size:13px}
  .rs{color:var(--muted);font-size:12px;margin-top:1px;line-height:1.4}
  .linkrow{display:flex;gap:8px}
  .linkrow .input{height:34px;color:var(--text-2)}
  .url{color:var(--muted);white-space:nowrap}
  .url b{color:var(--text);font-weight:500}
  .opts{display:flex;flex-direction:column;border:1px solid var(--line);border-radius:10px}
  .opt{display:flex;align-items:center;gap:12px;padding:11px 12px}
  .opt+.opt{border-top:1px solid var(--line)}
  .person{display:flex;align-items:center;gap:10px}
  .muted-s{color:var(--muted);font-size:12px}
  .df{display:flex;align-items:center;gap:8px;padding:12px 18px 12px 22px;border-top:1px solid var(--line);background:var(--bg);border-radius:0 0 14px 14px}
  `
);

// ---------------------------------------------------------------------------
// Client's read-only view

screens["client-board"] = page(
  "Kiln & Co. catalogue",
  `<div class="client">
  <div class="sharebar"><span class="ws-logo" style="width:20px;height:20px;font-size:10px;background:#f5efe6;color:#1f1c18">H</span><span>Shared by <b>Hattori Studio</b></span><span class="ro">${icon("eye", 12)}Read only</span><div style="flex:1"></div><span class="exp">Link expires 30 Nov</span><span class="made">${atelierMark(16)}Made with Atelier</span></div>
  <header class="chead">
    <div class="studio"><div class="slogo">HATTORI<br>STUDIO</div></div>
    <div style="flex:1">
      <div class="eyebrow">Kiln &amp; Co. · Board</div>
      <h1>Spring 2027 catalogue</h1>
      <div class="meta">${stack(["AH", "IM", "TO", "LB"], 22)}<span>Updated today at 14:32</span><span>·</span><span>11 cards</span><span>·</span><span>Print date 20 Nov</span></div>
    </div>
    <div class="cfil"><span class="seg"><span class="on">All cards</span><span>Waiting for you <b class="badge">2</b></span></span><span class="btn">${icon("msg", 14)}Comment</span></div>
  </header>
  ${kanban(kilnCols).replace(/<div class="kadd">.*?<\/div>/g, "").replace(/<span class="spacer"><\/span><svg[\s\S]*?<\/svg><svg[\s\S]*?<\/svg><\/div>/g, '<span class="spacer"></span></div>')}
</div>`,
  KANBAN_CSS +
    `
  body{background:#f6f3ee}
  .client{height:100vh;display:flex;flex-direction:column;overflow:hidden}
  .sharebar{height:38px;flex:none;background:#23201c;color:#d9d3c9;display:flex;align-items:center;gap:9px;padding:0 20px;font-size:12.5px}
  .sharebar b{color:#fff;font-weight:600}
  .ro{display:inline-flex;align-items:center;gap:5px;height:20px;padding:0 8px;border-radius:10px;background:rgba(255,255,255,.1);color:#f0ebe3;font-size:11.5px;font-weight:500}
  .exp{color:#9e978c}
  .made{display:inline-flex;align-items:center;gap:7px;color:#cfc8bd;font-weight:500;padding-left:12px;margin-left:4px;border-left:1px solid #48433c}
  .chead{display:flex;align-items:center;gap:18px;padding:22px 28px 18px;background:#fdfcfa;border-bottom:1px solid var(--line)}
  .slogo{width:64px;height:64px;border-radius:12px;background:#1f1c18;color:#f5efe6;display:grid;place-items:center;text-align:center;font-size:9.5px;font-weight:700;letter-spacing:.16em;line-height:1.5}
  .eyebrow{color:var(--muted);font-size:12px;font-weight:500}
  h1{font-size:23px;font-weight:650;letter-spacing:-.025em;margin:1px 0 6px}
  .meta{display:flex;align-items:center;gap:8px;color:var(--muted);font-size:12px}
  .cfil{display:flex;gap:8px;align-items:center}
  .badge{background:var(--purple);color:#fff;border-radius:8px;font-size:10px;padding:0 5px;margin-left:5px;line-height:15px}
  .kb{padding:18px 28px;background:#f6f3ee;gap:16px}
  .kcol{flex:1;width:auto;min-width:0}
  `
);

// ---------------------------------------------------------------------------
// Export menu with toast

screens["export-menu"] = page(
  "Harbour Museum rebrand",
  harbourBoard({
    topExtra: `<span class="btn icon pressed">${icon("more", 16)}</span>`,
    overlay: `<div class="menu" style="right:14px;top:44px">
      <div class="mi">${icon("pencil", 15)}Rename<span class="k">R</span></div>
      <div class="mi">${icon("dup", 15)}Duplicate project</div>
      <div class="mi">${icon("star", 15)}Add to favourites</div>
      <div class="sep"></div>
      <div class="mi">${icon("share", 15)}Share…</div>
      <div class="mi on">${icon("export", 15)}<span>Export…</span><span class="hint">Zip with files, notes, history</span></div>
      <div class="mi">${icon("sliders", 15)}Project settings<span class="k">⌘ ,</span></div>
      <div class="sep"></div>
      <div class="mi">${icon("archive", 15)}Archive</div>
      <div class="mi red">${icon("trash", 15)}Delete project…</div>
    </div>
    <div class="toast" style="right:20px;bottom:20px;width:440px"><span class="tic">${icon("check", 13)}</span><div style="flex:1"><div>Your export is ready — we emailed you a link</div><div class="muted" style="font-size:12px;margin-top:2px">harbour-museum-rebrand.zip · 412 MB · link valid 7 days</div></div><span class="act">${icon("download", 13)}</span></div>`,
  }),
  KANBAN_CSS +
    `
  .pressed{background:var(--hover);border-color:var(--line-2)}
  .menu{position:absolute;z-index:40;width:268px;background:var(--surface);border-radius:11px;box-shadow:var(--pop);padding:5px}
  .mi{display:flex;align-items:center;gap:10px;height:32px;padding:0 10px;border-radius:7px;font-weight:500;color:var(--text)}
  .mi .i{color:var(--muted)}
  .mi .k{margin-left:auto;color:var(--faint);font-size:11.5px}
  .mi.on{background:var(--accent);color:#fff;height:44px;flex-wrap:wrap;align-content:center;row-gap:0;position:relative;padding-left:35px}
  .mi.on .i{color:#fff;position:absolute;left:10px;top:9px}
  .mi.on span{width:100%;line-height:1.25}
  .mi.on .hint{font-size:11px;font-weight:400;color:rgba(255,255,255,.75)}
  .mi.red,.mi.red .i{color:var(--red)}
  .sep{height:1px;background:var(--line);margin:5px 4px}
  .toast .tic{width:22px;height:22px;border-radius:50%;background:#3c7d4f;display:grid;place-items:center;color:#fff;flex:none}
  .toast .act{padding:7px}
  `
);

// ---------------------------------------------------------------------------
// Search (before / after)

function searchScreen(after) {
  const results = `
    <div class="note">${icon("sparkle", 14)}<span>Showing results for <b>harbour</b></span><span class="m">· searched for “harbur”</span></div>
    <div class="grp">Projects</div>
    <div class="res on"><span class="ri" style="background:#e0eee8;color:#2e6b5c">${icon("folder", 15)}</span><div class="rb"><div class="rt"><mark>Harbour</mark> Museum rebrand</div><div class="rm">Project · 42 cards · Aiko Hattori</div></div><span class="kbd">↵</span></div>
    <div class="grp">Cards</div>
    <div class="res"><span class="ri">${icon("board", 15)}</span><div class="rb"><div class="rt">Wayfinding icon set</div><div class="rm"><mark>Harbour</mark> Museum rebrand · In progress · due 13 Nov</div></div></div>
    <div class="res"><span class="ri">${icon("board", 15)}</span><div class="rb"><div class="rt">Exhibition poster series</div><div class="rm">“…date set in the <mark>harbour</mark> blue…” · comment by Aiko</div></div></div>
    <div class="grp">Files</div>
    <div class="res pdf"><span class="ri pdfi">PDF</span><div class="rb"><div class="rt"><mark>Harbour</mark>-Museum-brand-guidelines.pdf <span class="pg">Page 14</span></div><div class="snip">“…the <mark>harbour</mark> blue (Pantone 2189 C) is kept for wayfinding and the museum’s <mark>harbour</mark> walk; never set body text in it…”</div><div class="rm">Files / Identity · 18.4 MB · updated 20 Oct</div></div></div>
    <div class="res"><span class="ri">${icon("note", 15)}</span><div class="rb"><div class="rt">Kick-off notes, <mark>Harbour</mark> Museum</div><div class="rm">Note · Lena Brandt · 2 Sep</div></div></div>`;
  const empty = `
    <div class="empty">
      <div class="eic">${icon("search", 22)}</div>
      <div class="et">No results for “harbur”</div>
      <div class="es">Check the spelling, or try fewer words.<br>Words inside files are not searched.</div>
    </div>`;
  const css = `
  .pal{position:absolute;z-index:60;left:50%;top:76px;transform:translateX(-50%);width:640px;background:var(--surface);border-radius:14px;box-shadow:var(--pop);overflow:hidden}
  .q{height:56px;display:flex;align-items:center;gap:12px;padding:0 16px 0 18px;border-bottom:1px solid var(--line);font-size:16px}
  .q .i{color:var(--muted)}
  .q .typed{font-weight:450;letter-spacing:-.01em}
  .caret{display:inline-block;width:1.5px;height:20px;background:var(--accent);vertical-align:middle;margin-left:1px}
  .scope{display:flex;gap:6px;padding:10px 16px;border-bottom:1px solid var(--line)}
  .scope .chip{height:24px;padding:0 9px;font-size:12px}
  .scope .chip.on{background:var(--text);color:#fff}
  .spin{width:16px;height:16px;border-radius:50%;border:2px solid var(--line);border-top-color:var(--muted)}
  .timing{display:inline-flex;align-items:center;gap:4px;color:var(--green);font-size:12px;font-weight:600;background:var(--green-soft);border-radius:6px;padding:2px 7px}
  .body{padding:6px 8px 8px}
  .note{display:flex;align-items:center;gap:7px;padding:8px 10px 6px;font-size:12.5px;color:var(--text-2)}
  .note .i{color:var(--purple)}
  .note .m{color:var(--muted)}
  .grp{font-size:11.5px;font-weight:600;color:var(--muted);padding:9px 10px 5px}
  .res{display:flex;align-items:flex-start;gap:11px;padding:8px 10px;border-radius:9px}
  .res.on{background:var(--line-3);box-shadow:inset 0 0 0 1px var(--line)}
  .ri{width:30px;height:30px;border-radius:8px;display:grid;place-items:center;background:var(--line-3);color:var(--text-2);flex:none}
  .pdfi{background:#fbe9e6;color:#b3392f;font-size:9.5px;font-weight:700;letter-spacing:.04em}
  .rb{flex:1;min-width:0}
  .rt{font-weight:550;font-size:13px}
  .rm{color:var(--muted);font-size:12px;margin-top:1px}
  .pg{margin-left:6px;font-size:11px;font-weight:600;color:#b3392f;background:#fbe9e6;border-radius:5px;padding:1px 6px}
  .snip{font-size:12.5px;color:var(--text-2);margin:5px 0 4px;padding:7px 10px;background:var(--bg);border-radius:7px;border-left:2px solid #e3b4ad;line-height:1.5}
  .res .kbd{margin-top:6px}
  .foot{display:flex;align-items:center;gap:14px;padding:9px 16px;border-top:1px solid var(--line);color:var(--muted);font-size:11.5px;background:var(--bg)}
  .foot span{display:inline-flex;align-items:center;gap:5px}
  .empty{padding:56px 20px 62px;text-align:center;display:flex;flex-direction:column;align-items:center;gap:8px}
  .eic{width:48px;height:48px;border-radius:14px;background:var(--line-3);display:grid;place-items:center;color:var(--faint);margin-bottom:6px}
  .et{font-weight:600;font-size:14px}
  .es{color:var(--muted);font-size:12.5px;line-height:1.55}
  `;
  const pal = `<div class="scrim" style="background:rgba(28,25,21,.28)"></div>
  <div class="pal">
    <div class="q">${icon("search", 19)}<span class="typed">harbur<span class="caret"></span></span><div style="flex:1"></div>${after ? `<span class="timing">${icon("zap", 12)}35 ms</span>` : '<span class="spin"></span><span style="font-size:12px;color:var(--muted)">Searching…</span>'}<span class="kbd">esc</span></div>
    <div class="scope"><span class="chip on">Everything</span><span class="chip line">Projects</span><span class="chip line">Cards</span><span class="chip line">Files</span><span class="chip line">Notes</span><span class="chip line">People</span></div>
    <div class="body">${after ? results : empty}</div>
    <div class="foot"><span><span class="kbd">↑</span><span class="kbd">↓</span> to move</span><span><span class="kbd">↵</span> to open</span><span><span class="kbd">⌘</span><span class="kbd">↵</span> open in new tab</span><div style="flex:1"></div><span>${after ? "6 results · words inside PDFs included" : "0 results · 1.9 s"}</span></div>
  </div>`;
  return page("Search", harbourBoard({ overlay: pal }), KANBAN_CSS + css);
}
screens["search-before"] = searchScreen(false);
screens["search-after"] = searchScreen(true);

// ---------------------------------------------------------------------------
// API tokens

screens["api-tokens"] = page(
  "API tokens",
  `<div class="app">
  <aside class="side">
    <div class="ws" style="color:var(--text-2);font-weight:500">${icon("arrowL", 15)}<span>Back to Atelier</span></div>
    <div class="sec">Account</div>
    <nav class="nav"><a>${icon("user", 16)}Profile</a><a>${icon("bell", 16)}Notifications</a><a>${icon("sliders", 16)}Preferences</a></nav>
    <div class="sec">Hattori Studio</div>
    <nav class="nav"><a>${icon("overview", 16)}General</a><a>${icon("users", 16)}Members<span class="count">6</span></a><a>${icon("users", 16)}Clients<span class="count">9</span></a><a>${icon("card", 16)}Plan and billing</a></nav>
    <div class="sec">Developers</div>
    <nav class="nav"><a class="on">${icon("key", 16)}API tokens</a><a>${icon("hook", 16)}Webhooks</a><a>${icon("puzzle", 16)}Integrations</a></nav>
  </aside>
  <main class="main settings">
    <div class="sw">
      <div class="sh"><div><h1>API tokens</h1><p>Tokens let scripts and other apps use the Atelier API as you. Each one carries only the scopes you give it.</p></div><span class="btn primary">${icon("plus", 14)}New token</span></div>
      <div class="vb">${icon("info", 15)}<span>API version 2 is here: webhooks, cursor pages and scoped tokens. Version 1 answers until 31 March 2027.</span><span class="lnk">Read the changes</span></div>
      <div class="tbl">
        <div class="tr th"><span>Name</span><span>Scopes</span><span>Created</span><span>Last used</span><span></span></div>
        <div class="tr"><span class="nm">${icon("key", 14)}Figma plugin</span><span><span class="chip">projects:read</span><span class="chip">files:read</span></span><span>2 Sep 2026</span><span>12 minutes ago</span><span>${icon("more", 15)}</span></div>
        <div class="tr"><span class="nm">${icon("key", 14)}Invoice export (Zapier)</span><span><span class="chip">projects:read</span><span class="chip">clients:read</span></span><span>14 Jul 2026</span><span>Yesterday</span><span>${icon("more", 15)}</span></div>
        <div class="tr"><span class="nm">${icon("key", 14)}Old site sync <span class="chip orange" style="margin-left:4px">v1</span></span><span><span class="chip">full access</span></span><span>3 Feb 2025</span><span>9 Oct 2026</span><span>${icon("more", 15)}</span></div>
      </div>
    </div>
    <div class="scrim"></div>
    <div class="dialog tok" style="left:50%;top:50px;transform:translateX(-50%);width:520px">
      <div class="dh"><div class="dic">${icon("key", 17)}</div><div style="flex:1"><h3>New API token</h3><p class="sub">For API version 2. You can revoke it at any time.</p></div><span class="btn icon ghost">${icon("x", 16)}</span></div>
      <div class="db">
        <div class="two">
          <div class="field" style="flex:1.4"><span class="label">Name</span><div class="input focus">Website sync<span class="caret"></span></div></div>
          <div class="field" style="flex:1"><span class="label">Expires</span><div class="input" style="justify-content:space-between">In 90 days${icon("chevD", 14)}</div></div>
        </div>
        <div class="field"><span class="label">Scopes <span style="color:var(--muted);font-weight:400">· 2 selected</span></span>
          <div class="scopes">
            ${[
              ["projects:read", "Read projects, boards and cards", true],
              ["projects:write", "Create and change cards and due dates", false],
              ["files:read", "Download files and previews", false],
              ["files:write", "Upload files to a project", true],
              ["webhooks:manage", "Add and remove webhooks", false],
              ["clients:read", "Read client names and contacts", false],
            ]
              .map(
                ([s, d, on]) =>
                  `<div class="sc${on ? " on" : ""}"><span class="cb${on ? " on" : ""}">${on ? icon("check", 11) : ""}</span><div><code>${s}</code><div class="sd">${d}</div></div></div>`
              )
              .join("")}
          </div>
        </div>
        <div class="warn">${icon("alert", 16)}<div><b>Copy once.</b> The token is shown once, right after you create it. Keep it in your password manager; we only store its hash.</div></div>
        <div class="preview"><span class="label" style="margin:0">Token</span><code>atl_v2_••••••••••••••••••••••••••</code><span class="btn" style="opacity:.5">${icon("copy", 13)}Copy</span></div>
      </div>
      <div class="df"><span class="muted-s">Requests count toward 1,000 per minute.</span><div style="flex:1"></div><span class="btn">Cancel</span><span class="btn primary">Create token</span></div>
    </div>
  </main>
</div>`,
  `
  .settings{background:var(--surface)}
  .sw{max-width:780px;padding:40px 48px;width:100%}
  .sh{display:flex;align-items:flex-start;gap:20px;justify-content:space-between}
  .sh h1{font-size:21px;font-weight:650;letter-spacing:-.022em}
  .sh p{color:var(--muted);margin-top:4px;max-width:520px;line-height:1.55}
  .vb{display:flex;align-items:center;gap:9px;margin:22px 0 18px;padding:10px 12px;border-radius:9px;background:var(--accent-soft);color:var(--accent-2);font-size:12.5px;box-shadow:inset 0 0 0 1px var(--accent-line)}
  .vb .lnk{margin-left:auto;font-weight:600;white-space:nowrap}
  .tbl{border:1px solid var(--line);border-radius:10px;overflow:hidden}
  .tr{display:grid;grid-template-columns:1.5fr 1.6fr 1fr 1fr 28px;align-items:center;gap:12px;padding:0 14px;height:46px;border-top:1px solid var(--line);color:var(--text-2)}
  .tr.th{border-top:none;height:34px;background:var(--bg);font-size:11.5px;font-weight:600;color:var(--muted)}
  .tr .nm{display:flex;align-items:center;gap:8px;font-weight:550;color:var(--text)}
  .tr .nm .i{color:var(--muted)}
  .tr>span:nth-child(2){display:flex;gap:5px}
  .tr .chip{font-family:"JetBrains Mono",monospace;font-size:10.5px}
  .tok .dh{display:flex;align-items:flex-start;gap:12px;padding:18px 16px 6px 20px}
  .dic{width:36px;height:36px;border-radius:10px;background:var(--accent-soft);color:var(--accent);display:grid;place-items:center;box-shadow:inset 0 0 0 1px var(--accent-line)}
  .sub{color:var(--muted);font-size:12.5px;margin-top:2px}
  .db{padding:12px 20px 18px;display:flex;flex-direction:column;gap:16px}
  .two{display:flex;gap:12px}
  .caret{display:inline-block;width:1.5px;height:16px;background:var(--accent);margin-left:-6px}
  .scopes{display:grid;grid-template-columns:1fr 1fr;border:1px solid var(--line);border-radius:10px;overflow:hidden}
  .sc{display:flex;gap:10px;padding:10px 12px;align-items:flex-start;border-top:1px solid var(--line)}
  .sc:nth-child(-n+2){border-top:none}
  .sc:nth-child(odd){border-right:1px solid var(--line)}
  .sc .cb{margin-top:1px}
  .sc.on{background:#f7fbf9}
  code{font-family:"JetBrains Mono",monospace;font-size:11.5px;font-weight:500;color:var(--text)}
  .sd{color:var(--muted);font-size:11.5px;margin-top:2px;line-height:1.35}
  .warn{display:flex;gap:10px;padding:11px 12px;border-radius:10px;background:var(--amber-soft);color:#7a4f08;font-size:12.5px;line-height:1.5;box-shadow:inset 0 0 0 1px #f2d79c}
  .warn .i{color:#c07f0e;margin-top:1px}
  .warn b{color:#5f3c04}
  .preview{display:flex;align-items:center;gap:10px;padding:8px 8px 8px 12px;border:1px dashed var(--line-2);border-radius:9px;background:var(--bg)}
  .preview code{flex:1;color:var(--faint);letter-spacing:.02em}
  .df{display:flex;align-items:center;gap:8px;padding:12px 16px 12px 20px;border-top:1px solid var(--line);background:var(--bg);border-radius:0 0 14px 14px}
  .muted-s{color:var(--muted);font-size:12px}
  `
);

// ---------------------------------------------------------------------------
// Calendar

{
  const ev = {
    "2026-09-29": [["Discovery report", 2]],
    "2026-10-01": [["Kick-off: Orchard St", 4]],
    "2026-10-02": [["Discovery interviews", 0]],
    "2026-10-05": [["Glaze test firing", 1], ["Sign survey", 2]],
    "2026-10-06": [["Shop wireframes", 3]],
    "2026-10-07": [["Moodboard review", 0], ["Product list", 3], ["Sourdough shoot", 4]],
    "2026-10-09": [["Strategy workshop", 0]],
    "2026-10-12": [["Budget review", 0], ["Shot list", 1]],
    "2026-10-13": [["Paper samples", 1], ["Font licences", 3]],
    "2026-10-14": [["Budget sign-off", 0], ["Shelf labels", 2], ["Menu draft", 4]],
    "2026-10-15": [["Studio portraits", 1]],
    "2026-10-16": [["Concepts approved", 0, "done"], ["Tone of voice", 0, "done"]],
    "2026-10-19": [["Print quotes", 0], ["Floor plan", 2]],
    "2026-10-20": [["Colour & type", 0, "done"], ["Wordmark weights", 0], ["Checkout copy", 3], ["Box labels", 4]],
    "2026-10-21": [["Logo review", 0], ["Moon jar shots", 1, "done"]],
    "2026-10-22": [["Cover, option B", 1], ["Tone of voice v2", 0]],
    "2026-10-23": [["Wireframes", 0], ["Spring range copy", 1], ["Print quotes", 0]],
    "2026-10-26": [["Shop launch", 3]],
    "2026-10-27": [["Poster series", 0], ["Sign mock-ups", 2]],
    "2026-10-28": [["Glaze swatches", 1], ["Logo animation", 0], ["Window vinyl", 4]],
    "2026-10-29": [["Board presentation", 0, "ms"], ["Allergen labels", 4]],
    "2026-10-30": [["Portrait retouch", 1], ["Wayfinding pilot", 2]],
    "2026-11-02": [["Identity sign-off", 0]],
  };
  const pc = ["#2e6b5c", "#c07a3b", "#4c6a9e", "#b05a6f", "#7a6a9b"];
  const soft = ["#e0eee8", "#f6e8d8", "#e2eaf5", "#f6e4e6", "#ebe5f4"];
  const dark = ["#1e4b40", "#6e4113", "#2b4570", "#6f2f3e", "#47376e"];
  let cells = "";
  for (let i = 0; i < 35; i++) {
    const d = addDays("2026-09-28", i);
    const dt = D(d);
    const out = dt.getUTCMonth() !== 9;
    const wd = dt.getUTCDay();
    const items = ev[d] || [];
    const show = items.slice(0, 3);
    const more = items.length - show.length;
    cells += `<div class="cell${out ? " out" : ""}${wd === 0 || wd === 6 ? " we" : ""}${d === TODAY ? " today" : ""}">
      <div class="dn">${dt.getUTCDate() === 1 ? `${MON[dt.getUTCMonth()]} 1` : `<b>${dt.getUTCDate()}</b>`}</div>
      ${show
        .map(([t, p, f]) =>
          f === "ms"
            ? `<div class="ev ms"><i style="border-color:${pc[p]}"></i>${t}</div>`
            : `<div class="ev${f === "done" ? " done" : ""}" style="--c:${pc[p]};--s:${soft[p]};--t:${dark[p]}">${f === "done" ? icon("check", 11) : ""}<span>${t}</span></div>`
        )
        .join("")}
      ${more > 0 ? `<div class="more">${more} more</div>` : ""}
    </div>`;
  }
  const legend = projects
    .map((p, i) => `<span class="lg"><span class="pdot" style="background:${p.c};margin:0"></span>${p.name}</span>`)
    .join("");
  screens["calendar"] = page(
    "Calendar",
    `<div class="app">${sidebar({ nav: "calendar" })}
    <main class="main">
      <header class="top"><div class="crumbs">${icon("calendar", 15)}<b>Calendar</b><span class="beta">Beta</span></div><div class="spacer"></div>
        <span class="btn">${icon("rss", 14)}Subscribe (iCal)</span><span class="btn">${icon("share", 14)}Share</span><span class="btn icon">${icon("more", 16)}</span></header>
      <div class="toolbar">
        <span class="btn">Today</span><span class="btn icon ghost">${icon("chevL", 15)}</span><span class="btn icon ghost">${icon("chevR", 15)}</span>
        <h2 style="font-size:16px">October <span style="color:var(--muted);font-weight:500">2026</span></h2>
        <div style="flex:1"></div>
        <span class="btn">${icon("filter", 14)}All projects${icon("chevD", 13)}</span>
        <span class="btn">${icon("user", 14)}Everyone${icon("chevD", 13)}</span>
        <span class="seg"><span>Week</span><span class="on">Month</span></span>
      </div>
      <div class="legend">${legend}<span style="flex:1"></span><span class="lg muted">41 due this month</span></div>
      <div class="cal">
        <div class="wh">${["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((w) => `<span>${w}</span>`).join("")}</div>
        <div class="grid">${cells}</div>
      </div>
    </main></div>`,
    `
    .beta{display:inline-flex;align-items:center;height:19px;padding:0 7px;border-radius:10px;background:var(--purple-soft);color:var(--purple);font-size:11px;font-weight:600;box-shadow:inset 0 0 0 1px #dccff5;margin-left:2px}
    .legend{display:flex;align-items:center;gap:16px;padding:9px 18px;border-bottom:1px solid var(--line);font-size:12px;color:var(--text-2);white-space:nowrap;overflow:hidden}
    .lg{display:inline-flex;align-items:center;gap:7px}
    .lg.muted{color:var(--muted)}
    .cal{flex:1;display:flex;flex-direction:column;min-height:0}
    .wh{display:grid;grid-template-columns:repeat(7,1fr);border-bottom:1px solid var(--line)}
    .wh span{padding:7px 10px;font-size:11.5px;font-weight:600;color:var(--muted)}
    .grid{flex:1;display:grid;grid-template-columns:repeat(7,1fr);grid-template-rows:repeat(5,1fr)}
    .cell{border-right:1px solid var(--line);border-bottom:1px solid var(--line);padding:6px 6px 4px;display:flex;flex-direction:column;gap:3px;min-width:0;overflow:hidden}
    .cell:nth-child(7n){border-right:none}
    .cell.we{background:#fcfbf9}
    .cell.out{background:repeating-linear-gradient(135deg,#fbfaf7 0 6px,#f7f4ef 6px 7px)}
    .cell.out .dn{color:var(--faint)}
    .dn{font-size:12px;font-weight:600;color:var(--text-2);height:22px;display:flex;align-items:center;padding-left:3px}
    .dn b{font-weight:600}
    .cell.today{background:#fffbf3;box-shadow:inset 0 0 0 1.5px var(--amber)}
    .cell.today .dn b{background:var(--amber);color:#fff;border-radius:11px;min-width:22px;height:22px;display:inline-grid;place-items:center;margin-left:-3px}
    .ev{display:flex;align-items:center;gap:5px;height:21px;border-radius:5px;padding:0 6px 0 7px;font-size:11.5px;font-weight:550;background:var(--s);color:var(--t);white-space:nowrap;position:relative;box-shadow:inset 2.5px 0 0 var(--c)}
    .ev span{overflow:hidden;text-overflow:ellipsis}
    .ev.done{opacity:.6}
    .ev.done span{text-decoration:line-through;text-decoration-color:rgba(0,0,0,.25)}
    .ev.ms{background:transparent;box-shadow:none;color:var(--text);padding-left:3px}
    .ev.ms i{width:9px;height:9px;transform:rotate(45deg);border:2px solid;border-radius:1.5px;flex:none;margin-right:2px}
    .more{font-size:11px;color:var(--muted);font-weight:500;padding-left:5px}
    `
  );
}

// ---------------------------------------------------------------------------
// Studio desk banner (flat-lay illustration, 1600x640)

{
  const W = 1600;
  const H = 640;
  // laptop screen mini-board
  const mini = (() => {
    const cols = [
      ["#b5aea4", [72, 44, 56, 44]],
      ["#c06a1f", [80, 50, 44]],
      ["#7353c2", [66, 52, 44, 40]],
      ["#3c7d4f", [74, 46, 52]],
    ];
    let s = "";
    cols.forEach(([c, cards], i) => {
      const x = 96 + i * 110;
      s += `<circle cx="${x + 4}" cy="70" r="3" fill="${c}"/><rect x="${x + 12}" y="67" width="${30 + (i % 2) * 10}" height="6" rx="3" fill="#cfc8bd"/>`;
      let y = 84;
      cards.forEach((h, j) => {
        s += `<rect x="${x}" y="${y}" width="100" height="${h}" rx="5" fill="#fff" stroke="#e6e0d7"/>`;
        if (j === 0) s += `<rect x="${x}" y="${y}" width="100" height="${h * 0.5}" rx="5" fill="${["#d9c7b0", "#c9d3cd", "#e3cfc0", "#d4dae3"][i]}"/><circle cx="${x + 50}" cy="${y + h * 0.3}" r="${h * 0.14}" fill="${["#b9764e", "#3e5a6b", "#7d8f86", "#f1ece2"][i]}"/>`;
        if (j === 1) s += `<circle cx="${x + 88}" cy="${y + h - 12}" r="5" fill="${["#b8674a", "#4f7a6b", "#8a5d8f", "#4c6a9e"][i]}"/>`;
        s += `<rect x="${x + 7}" y="${y + h - 20}" width="${46 + ((i + j) % 3) * 8}" height="5" rx="2.5" fill="#bdb5aa"/><rect x="${x + 7}" y="${y + h - 11}" width="26" height="4" rx="2" fill="#ddd6cc"/>`;
        y += h + 7;
      });
    });
    return s;
  })();
  const pencilSketch = (x, y) => `
    <g transform="translate(${x} ${y})" fill="none" stroke="#5d564d" stroke-linecap="round" stroke-linejoin="round" opacity=".78">
      <path d="M30 120V70a32 32 0 0 1 64 0v50" stroke-width="2.2"/>
      <path d="M33 118V72a29 29 0 0 1 58 0v46" stroke-width="1" opacity=".5"/>
      <path d="M62 40v80" stroke-width="1.2" opacity=".6"/>
      <path d="M130 120V82a22 22 0 0 1 44 0v38" stroke-width="2"/>
      <path d="M200 120V96a14 14 0 0 1 28 0v24" stroke-width="1.8"/>
      <path d="M20 132h220" stroke-width="1" opacity=".5"/>
      <path d="M26 158c14-6 30-6 46 0s32 6 48 0" stroke-width="1.4" opacity=".6"/>
      <text x="26" y="196" font-family="Caveat,'Comic Neue','Segoe Print',cursive" font-style="italic" font-size="19" fill="#5d564d" stroke="none" opacity=".85">harbour — arch study</text>
      <path d="M150 170l22 8M172 178l-6-10M172 178l-11 3" stroke-width="1.3" opacity=".6"/>
      <circle cx="248" cy="40" r="16" stroke-width="1.2" opacity=".5"/>
      <path d="M240 40h16M248 32v16" stroke-width="1" opacity=".5"/>
    </g>`;
  const swatchFan = (cx, cy) => {
    const cols = ["#2f5b70", "#3f6f63", "#c6a77c", "#b9603f", "#e8dfcf", "#1f2a33"];
    const names = ["2189 C", "5545 C", "7502 C", "7591 C", "9224 C", "Black 6"];
    return cols
      .map(
        (c, i) => `<g transform="translate(${cx} ${cy}) rotate(${-38 + i * 13})">
      <rect x="-26" y="-210" width="52" height="210" rx="5" fill="#fbf8f2" filter="url(#sh1)"/>
      <rect x="-22" y="-205" width="44" height="120" rx="3" fill="${c}"/>
      <rect x="-18" y="-76" width="30" height="4" rx="2" fill="#8d867c"/>
      <text x="-18" y="-60" font-family="Inter" font-size="8.5" font-weight="600" fill="#6d665c">${names[i]}</text>
      <circle cx="0" cy="-14" r="5" fill="#d8d0c3"/></g>`
      )
      .join("");
  };
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <defs>
    <linearGradient id="wood" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#c9a27a"/><stop offset=".5" stop-color="#b98f66"/><stop offset="1" stop-color="#a67d56"/></linearGradient>
    <filter id="grain" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.012 0.42" numOctaves="3" seed="7"/><feColorMatrix values="0 0 0 0 0.35  0 0 0 0 0.22  0 0 0 0 0.12  0 0 0 0.55 0"/><feComposite in2="SourceGraphic" operator="in"/></filter>
    <filter id="noise"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="3"/><feColorMatrix values="0 0 0 0 0.5  0 0 0 0 0.4  0 0 0 0 0.3  0 0 0 0.10 0"/></filter>
    <filter id="sh1" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="6" dy="10" stdDeviation="9" flood-color="#3b2614" flood-opacity=".28"/></filter>
    <filter id="sh2" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="10" dy="18" stdDeviation="16" flood-color="#3b2614" flood-opacity=".34"/></filter>
    <radialGradient id="light" cx=".3" cy=".1" r=".9"><stop offset="0" stop-color="#fff6e6" stop-opacity=".42"/><stop offset=".6" stop-color="#fff6e6" stop-opacity="0"/><stop offset="1" stop-color="#1c120a" stop-opacity=".28"/></radialGradient>
    <radialGradient id="coffee" cx=".45" cy=".4" r=".6"><stop offset="0" stop-color="#7a4a2a"/><stop offset=".8" stop-color="#4b2a16"/><stop offset="1" stop-color="#3a2010"/></radialGradient>
    <radialGradient id="crema" cx=".5" cy=".5" r=".5"><stop offset=".55" stop-color="#c08a5a" stop-opacity="0"/><stop offset=".9" stop-color="#c79563" stop-opacity=".75"/><stop offset="1" stop-color="#a87445" stop-opacity=".4"/></radialGradient>
    <linearGradient id="screen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fbfaf8"/><stop offset="1" stop-color="#f3f0eb"/></linearGradient>
    <linearGradient id="alu" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#d9dadb"/><stop offset="1" stop-color="#b9bbbd"/></linearGradient>
    <linearGradient id="leaf" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#6f8f5e"/><stop offset="1" stop-color="#3f5f3a"/></linearGradient>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#wood)"/>
  <rect width="${W}" height="${H}" filter="url(#grain)" opacity=".55"/>
  ${[90, 230, 410, 560, 700].map((y) => `<path d="M0 ${y}C400 ${y - 14} 900 ${y + 18} 1600 ${y - 6}" stroke="#8d6440" stroke-opacity=".10" stroke-width="2" fill="none"/>`).join("")}

  <!-- sketch paper, left -->
  <g transform="translate(70 70) rotate(-6)" filter="url(#sh1)">
    <rect width="380" height="470" rx="3" fill="#f7f2e8"/>
    ${Array.from({ length: 22 }, (_, i) => `<path d="M24 ${40 + i * 20}h332" stroke="#c9d6dc" stroke-width=".8" opacity=".5"/>`).join("")}
  </g>
  <g transform="translate(70 70) rotate(-6)">${pencilSketch(50, 40)}
    <g transform="translate(60 270)" fill="none" stroke="#5d564d" stroke-linecap="round" opacity=".7">
      <rect x="0" y="0" width="120" height="80" rx="3" stroke-width="1.4"/><path d="M14 58h50M14 66h34" stroke-width="1.6"/><path d="M14 18h44" stroke-width="5" opacity=".7"/>
      <rect x="150" y="0" width="120" height="80" rx="3" stroke-width="1.4"/><path d="M164 18h30M164 26h60M164 34h48" stroke-width="1.3"/><circle cx="246" cy="58" r="12" stroke-width="1.3"/>
      <path d="M0 110h270" stroke-width=".8" opacity=".5"/>
      <text x="0" y="140" font-family="Caveat,'Comic Neue',cursive" font-style="italic" font-size="17" fill="#5d564d" stroke="none">poster grid — 6 col / 12 mm gutter</text>
    </g>
  </g>
  <!-- pencil -->
  <g transform="translate(330 560) rotate(-28)" filter="url(#sh1)">
    <rect x="0" y="-7" width="250" height="14" fill="#2f4a3f"/><rect x="0" y="-7" width="250" height="4" fill="#3f6153"/>
    <rect x="250" y="-7" width="18" height="14" fill="#c9c3b6"/><path d="M268 -7L300 0L268 7z" fill="#e7cfa8"/><path d="M290 -2.3L300 0L290 2.3z" fill="#2b2622"/>
    <rect x="-16" y="-7" width="16" height="14" rx="2" fill="#d98a7a"/>
  </g>

  <!-- laptop -->
  <g transform="translate(560 64)" filter="url(#sh2)">
    <rect width="560" height="372" rx="18" fill="url(#alu)"/>
    <rect x="12" y="12" width="536" height="348" rx="10" fill="#141310"/>
    <rect x="20" y="20" width="520" height="332" rx="4" fill="url(#screen)"/>
    <!-- app chrome -->
    <rect x="20" y="20" width="62" height="332" fill="#f2efea"/>
    <rect x="30" y="32" width="14" height="14" rx="4" fill="#1f1c18"/>
    ${[60, 74, 88, 112, 126, 140, 154].map((y, i) => `<rect x="30" y="${y}" width="${[34, 28, 30, 38, 32, 40, 26][i]}" height="5" rx="2.5" fill="${i === 3 ? "#2e6b5c" : "#cfc8bd"}"/>`).join("")}
    <rect x="82" y="20" width="458" height="30" fill="#fff"/><path d="M82 50h458" stroke="#ebe6df"/>
    <rect x="92" y="31" width="110" height="7" rx="3.5" fill="#1f1c18" opacity=".8"/>
    <rect x="490" y="28" width="40" height="14" rx="4" fill="#2e6b5c"/>
    <g transform="translate(-6 -6)">${mini}</g>
    <path d="M300 20h40" stroke="#2a2621" stroke-width="3" stroke-linecap="round" opacity=".6"/>
  </g>
  <g transform="translate(520 436)" filter="url(#sh2)">
    <path d="M40 0h560l40 30a10 10 0 0 1-8 16H8a10 10 0 0 1-8-16z" fill="url(#alu)"/>
    <path d="M40 0h560" stroke="#9fa1a3" stroke-width="2"/>
    <rect x="280" y="34" width="80" height="6" rx="3" fill="#a5a7a9"/>
  </g>
  <rect x="560" y="64" width="560" height="372" rx="18" fill="url(#light)" opacity=".5"/>

  <!-- swatches -->
  <g>${swatchFan(1260, 560)}</g>

  <!-- mug 1 -->
  <g transform="translate(1440 150)">
    <ellipse cx="10" cy="14" rx="82" ry="82" fill="#3b2614" opacity=".22" filter="url(#sh1)"/>
    <path d="M60 -10a34 34 0 0 1 0 60" stroke="#ece6dc" stroke-width="18" fill="none" stroke-linecap="round" filter="url(#sh1)"/>
    <circle cx="0" cy="0" r="74" fill="#efe9df" filter="url(#sh1)"/>
    <circle cx="0" cy="0" r="74" fill="none" stroke="#d9d1c4" stroke-width="2"/>
    <circle cx="0" cy="0" r="62" fill="url(#coffee)"/>
    <circle cx="0" cy="0" r="62" fill="url(#crema)"/>
    <path d="M-20 -10c10-14 30-12 36 2 4 10-8 22-20 18" stroke="#e4c39c" stroke-width="5" fill="none" stroke-linecap="round" opacity=".55"/>
    <ellipse cx="-24" cy="-30" rx="18" ry="8" fill="#fff" opacity=".18" transform="rotate(-30 -24 -30)"/>
  </g>
  <!-- mug 2 (glazed, empty-ish) -->
  <g transform="translate(1250 120)">
    <path d="M-46 30a26 26 0 0 1 -6 -52" stroke="#3f5f6e" stroke-width="14" fill="none" stroke-linecap="round" filter="url(#sh1)"/>
    <circle cx="0" cy="0" r="54" fill="#3f5f6e" filter="url(#sh1)"/>
    <circle cx="0" cy="0" r="54" fill="none" stroke="#557584" stroke-width="3"/>
    <circle cx="0" cy="0" r="44" fill="#e9e3d6"/>
    <circle cx="4" cy="6" r="30" fill="#d9cbb6" opacity=".6"/>
    <circle cx="8" cy="10" r="12" fill="#b9946a" opacity=".35"/>
  </g>
  <!-- plant leaves corner -->
  <g transform="translate(1560 610)" opacity=".95">
    ${[[-150, -40, -60], [-110, -140, -20], [-40, -170, 10], [-190, -110, -40]].map(([x, y, r]) => `<path d="M0 0C${x * 0.4} ${y * 0.1} ${x * 0.9} ${y * 0.5} ${x} ${y}C${x * 0.5} ${y * 0.9} ${x * 0.1} ${y * 0.4} 0 0z" fill="url(#leaf)" filter="url(#sh1)"/>`).join("")}
  </g>
  <!-- paper clips and eraser -->
  <g transform="translate(1110 520) rotate(18)" filter="url(#sh1)"><rect width="54" height="24" rx="4" fill="#f1ede6"/><rect width="22" height="24" rx="4" fill="#5f86a0"/></g>
  <g fill="none" stroke="#8f9294" stroke-width="2.4" stroke-linecap="round">
    <path transform="translate(480 470) rotate(30)" d="M0 0v34a8 8 0 0 0 16 0V6a5 5 0 0 0-10 0v26"/>
    <path transform="translate(510 494) rotate(-10)" d="M0 0v34a8 8 0 0 0 16 0V6a5 5 0 0 0-10 0v26"/>
  </g>
  <!-- sticky note -->
  <g transform="translate(1150 300) rotate(7)" filter="url(#sh1)">
    <rect width="120" height="112" fill="#f4dc8b"/><rect width="120" height="18" fill="#efd27a"/>
    <text x="12" y="48" font-family="Caveat,'Comic Neue',cursive" font-style="italic" font-size="17" fill="#5a4a1c">print proofs</text>
    <text x="12" y="70" font-family="Caveat,'Comic Neue',cursive" font-style="italic" font-size="17" fill="#5a4a1c">→ Thu 10:00</text>
    <path d="M12 86h60" stroke="#5a4a1c" stroke-width="1.2" opacity=".5"/>
  </g>
  <rect width="${W}" height="${H}" fill="url(#light)"/>
  <rect width="${W}" height="${H}" filter="url(#noise)"/>
</svg>`;
  screens["studio-desk"] = `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Studio desk · Atelier</title>
<style>*{margin:0;padding:0}html,body{width:${W}px;height:${H}px;overflow:hidden;background:#b98f66}svg{display:block}</style></head><body>${svg}</body></html>
`;
}

// ---------------------------------------------------------------------------
// Release banner (1600x640)

{
  const frag = (inner, w, h, x, y, r) =>
    `<div class="frag" style="width:${w}px;height:${h}px;left:${x}px;top:${y}px;transform:rotate(${r}deg)">${inner}</div>`;
  const tlFrag = `<div class="fh"><span class="d" style="background:#2e6b5c"></span>Harbour Museum rebrand<span class="sp"></span><span class="seg"><span>Day</span><span class="on">Week</span><span>Quarter</span></span></div>
    <div class="fb">${[
      ["Wordmark refinement", 10, 170, "teal"],
      ["Exhibition poster series", 130, 150, "rose"],
      ["Website wireframes", 40, 190, "sky"],
      ["Print vendor quotes", 150, 120, "sand"],
      ["Gallery label copy", 100, 200, "sage"],
    ]
      .map(([t, l, w, c], i) => {
        const [bg, bd, k, tx] = BAR_COLORS[c];
        return `<div class="b" style="left:${l}px;width:${w}px;top:${14 + i * 34}px;--b:${bg};--bd:${bd};--k:${k};--t:${tx}">${t}</div>`;
      })
      .join("")}<div class="tday"></div></div>`;
  const upFrag = `<div class="fh">${icon("share", 14)}Uploading 3 files<span class="sp"></span><span style="color:var(--green);font-weight:600">Resumed</span></div>
    <div class="ups">${[
      ["Moon-jar-04.tif", "182 MB", 100],
      ["Catalogue-proof-v7.pdf", "48 MB", 72],
      ["Studio-portraits.zip", "1.2 GB", 31],
    ]
      .map(([n, s, p]) => `<div class="up"><span class="ft">${n.split(".").pop().toUpperCase()}</span><div style="flex:1"><div class="un">${n}<span>${s}</span></div><div class="pb"><i style="width:${p}%"></i></div></div></div>`)
      .join("")}</div>`;
  const inFrag = `<div class="fh">${icon("inbox", 14)}Inbox<span class="sp"></span><span class="chip">By project</span></div>
    <div class="ib">${[
      ["Harbour Museum rebrand", "#2e6b5c", ["AH", "Aiko approved Wordmark, final weights"], ["IM", "Inês uploaded 6 posters"]],
      ["Kiln &amp; Co. catalogue", "#c07a3b", ["SL", "Sofia commented on Cover, option B"]],
    ]
      .map(([p, c, ...items]) => `<div class="ig"><span class="d" style="background:${c}"></span>${p}</div>${items.map(([k, t]) => `<div class="ii">${av(k, 20)}<span>${t}</span></div>`).join("")}`)
      .join("")}</div>`;
  screens["release-banner"] = `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Atelier 3.2</title>
<style>${BASE_CSS}
html,body{width:1600px;height:640px;overflow:hidden}
body{background:#1d2a26;position:relative}
.bg{position:absolute;inset:0;background:radial-gradient(900px 520px at 78% 30%,#2f5a4e 0%,rgba(47,90,78,0) 70%),radial-gradient(700px 500px at 10% 110%,#3a3227 0%,rgba(58,50,39,0) 70%),linear-gradient(135deg,#1c2925,#17201d)}
.grid{position:absolute;inset:0;background-image:linear-gradient(rgba(255,255,255,.035) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.035) 1px,transparent 1px);background-size:40px 40px;mask-image:radial-gradient(800px 500px at 70% 50%,#000,transparent)}
.copy{position:absolute;left:96px;top:0;bottom:0;display:flex;flex-direction:column;justify-content:center;color:#f3efe7;z-index:5}
.brand{display:flex;align-items:center;gap:12px;font-size:22px;font-weight:600;letter-spacing:-.02em;color:#f3efe7}
.ver{font-family:"Inter Display",Inter,sans-serif;font-size:250px;font-weight:600;letter-spacing:-.06em;line-height:.86;margin:26px 0 22px -10px;background:linear-gradient(180deg,#fbf7f0 30%,#c9d9d2);-webkit-background-clip:text;color:transparent}
.tag{font-size:23px;line-height:1.4;color:#c9c3b8;max-width:470px;letter-spacing:-.012em}
.tag b{color:#fff;font-weight:600}
.meta{display:flex;gap:10px;margin-top:28px}
.meta span{height:30px;padding:0 13px;border-radius:15px;display:inline-flex;align-items:center;gap:7px;font-size:13.5px;font-weight:500;color:#e5dfd5;background:rgba(255,255,255,.07);box-shadow:inset 0 0 0 1px rgba(255,255,255,.1)}
.meta .am{color:#1f1c18;background:#e2981a;box-shadow:none;font-weight:600}
.frag{position:absolute;background:var(--surface);border-radius:14px;overflow:hidden;box-shadow:0 0 0 1px rgba(0,0,0,.2),0 40px 80px -20px rgba(0,0,0,.6),0 12px 24px -8px rgba(0,0,0,.35);z-index:2}
.fh{height:42px;display:flex;align-items:center;gap:8px;padding:0 14px;border-bottom:1px solid var(--line);font-weight:600;font-size:13px;color:var(--text)}
.fh .i{color:var(--muted)}
.fh .sp{flex:1}
.d{width:9px;height:9px;border-radius:3px;display:inline-block}
.fb{position:relative;height:100%;background:repeating-linear-gradient(90deg,transparent 0 47px,var(--line-3) 47px 48px)}
.b{position:absolute;height:26px;border-radius:7px;background:var(--b);color:var(--t);box-shadow:inset 0 0 0 1px var(--bd);font-size:12px;font-weight:550;display:flex;align-items:center;padding-left:12px;white-space:nowrap;overflow:hidden}
.b::before{content:"";position:absolute;left:3px;top:4px;bottom:4px;width:3px;border-radius:2px;background:var(--k)}
.tday{position:absolute;left:206px;top:0;bottom:0;width:2px;background:#e2981a}
.ups{padding:8px 14px;display:flex;flex-direction:column;gap:12px}
.up{display:flex;gap:11px;align-items:center}
.ft{width:34px;height:34px;border-radius:8px;background:var(--line-3);font-size:9px;font-weight:700;color:var(--text-2);display:grid;place-items:center;letter-spacing:.04em}
.un{display:flex;justify-content:space-between;font-size:12.5px;font-weight:550}
.un span{color:var(--muted);font-weight:500}
.pb{height:5px;border-radius:3px;background:var(--line);margin-top:6px;overflow:hidden}
.pb i{display:block;height:100%;background:var(--accent);border-radius:3px}
.ib{padding:6px 10px}
.ig{display:flex;align-items:center;gap:8px;font-size:11.5px;font-weight:600;color:var(--muted);padding:8px 4px 4px}
.ii{display:flex;align-items:center;gap:9px;font-size:12.5px;padding:6px 4px;color:var(--text)}
.ii .av{--s:20px}
</style></head><body>
<div class="bg"></div><div class="grid"></div>
<div class="copy">
  <div class="brand">${atelierMark(34)}Atelier</div>
  <div class="ver">3.2</div>
  <div class="tag"><b>Twenty small things.</b> Quicker uploads, a calmer inbox, and fixes from your reports.</div>
  <div class="meta"><span class="am">14 October 2026</span><span>Desktop</span><span>Web</span><span>iOS</span></div>
</div>
${frag(tlFrag, 520, 236, 830, 52, -3)}
${frag(upFrag, 380, 196, 1170, 300, 4)}
${frag(inFrag, 360, 210, 760, 352, 2)}
</body></html>
`;
}

// ---------------------------------------------------------------------------
// Search tips PDF source (A4)

screens["search-tips"] = `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Search tips · Atelier</title>
<style>${BASE_CSS}
@page{size:A4;margin:0}
html,body{background:#fff;height:auto}
.sheet{width:210mm;height:297mm;padding:20mm 20mm 16mm;display:flex;flex-direction:column;position:relative;overflow:hidden}
.band{position:absolute;left:0;right:0;top:0;height:6mm;background:var(--accent)}
.brand{display:flex;align-items:center;gap:9px;font-weight:600;font-size:14px;margin-top:4mm}
h1{font-family:"Inter Display",Inter,sans-serif;font-size:38px;font-weight:650;letter-spacing:-.035em;margin:12mm 0 3mm}
.lead{font-size:14px;color:var(--text-2);max-width:135mm;line-height:1.55}
h2{font-size:12px;text-transform:uppercase;letter-spacing:.08em;color:var(--accent);margin:10mm 0 4mm;font-weight:700}
table{width:100%;border-collapse:collapse;font-size:12.5px}
td{padding:9px 0;border-top:1px solid var(--line);vertical-align:top}
td:first-child{width:62mm}
code{font-family:"JetBrains Mono",monospace;font-size:11.5px;background:var(--line-3);border:1px solid var(--line);border-radius:5px;padding:2px 6px;color:var(--text)}
.ex{color:var(--muted);font-size:11.5px;margin-top:2px}
.cols{display:grid;grid-template-columns:1fr 1fr;gap:8mm}
.box{border:1px solid var(--line);border-radius:10px;padding:5mm;font-size:12.5px;line-height:1.55;color:var(--text-2)}
.box b{color:var(--text)}
.keys{display:flex;flex-direction:column;gap:8px;font-size:12.5px}
.keys div{display:flex;align-items:center;gap:6px}
.keys .kbd{height:22px;min-width:22px;font-size:11.5px}
.keys span.t{margin-left:auto;color:var(--text-2)}
mark{background:#fbe7a6}
.foot{margin-top:auto;display:flex;justify-content:space-between;color:var(--muted);font-size:10.5px;border-top:1px solid var(--line);padding-top:4mm}
</style></head><body><div class="sheet"><div class="band"></div>
<div class="brand">${atelierMark(24)}Atelier</div>
<h1>Search tips</h1>
<p class="lead">Search answers as you type, forgives a typo and reads the words inside your PDFs. Press <span class="kbd">⌘</span> <span class="kbd">K</span> anywhere, then narrow it down with the filters below.</p>
<h2>Filters</h2>
<table>
<tr><td><code>in:files</code></td><td>Only files, including words inside PDFs.<div class="ex">brochure in:files</div></td></tr>
<tr><td><code>project:harbour</code></td><td>Only one project. A part of its name is enough.<div class="ex">poster project:harbour</div></td></tr>
<tr><td><code>from:aiko</code></td><td>Cards, notes and comments by one person.<div class="ex">approved from:sofia</div></td></tr>
<tr><td><code>due:this-week</code></td><td>Cards due this week. Also <code>due:overdue</code> and <code>due:2026-11</code>.</td></tr>
<tr><td><code>type:pdf</code></td><td>Files of one type: pdf, image, video, sketch.</td></tr>
<tr><td><code>"exact words"</code></td><td>Quotes match the words in that order.<div class="ex">"harbour blue"</div></td></tr>
<tr><td><code>-word</code></td><td>Leave out results with that word.<div class="ex">logo -draft</div></td></tr>
</table>
<div class="cols" style="margin-top:10mm">
<div><h2 style="margin-top:0">Keyboard</h2><div class="keys">
<div><span class="kbd">⌘</span><span class="kbd">K</span><span class="t">Open search</span></div>
<div><span class="kbd">/</span><span class="t">Search this project</span></div>
<div><span class="kbd">↑</span><span class="kbd">↓</span><span class="t">Move through results</span></div>
<div><span class="kbd">⌘</span><span class="kbd">↵</span><span class="t">Open in a new tab</span></div>
<div><span class="kbd">Tab</span><span class="t">Next filter</span></div>
</div></div>
<div><h2 style="margin-top:0">Typos and PDFs</h2><div class="box">Search for <b>harbur</b> and Atelier shows results for <mark>harbour</mark>. Results from inside a PDF show the page they're on: open one and Atelier jumps to that page with the words marked.</div></div>
</div>
<div class="foot"><span>Atelier 3.2 · October 2026</span><span>atelier.test/docs/search</span></div>
</div></body></html>
`;

// ---------------------------------------------------------------------------

export function buildScreens() {
  mkdirSync(outDir, { recursive: true });
  for (const [name, html] of Object.entries(screens)) writeFileSync(join(outDir, `${name}.html`), html);
  return Object.keys(screens);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  console.log(buildScreens().join("\n"));
}
