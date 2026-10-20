# Dev seed assets: Atelier

These are screenshots and files from **Atelier**, a fictional project tool for studios. They go in the bodies of the eight changelog entries that `dev.exs` seeds. Atelier has its own brand: a warm neutral UI, one moss-green accent (`#2e6b5c`), amber for "today" and Inter. It is meant to look like a third-party SaaS product, not like Tayori's admin.

The research behind it is in `.claude/plans/stellar-news/research/feature-gap-report.md`, under "Seed entries for Atelier". These files are for the dev server only. Keep them out of the Hex package.

## Regenerate

```sh
node dev/seed/shoot.mjs
```

- `build-screens.mjs` writes `screens/*.html`. Each file is self-contained: inline CSS and SVG, with no scripts or external requests. It uses fonts installed on the machine: Inter, Inter Display and JetBrains Mono.
- `shoot.mjs` first runs `build-screens.mjs`. Then it renders the screens with the e2e Playwright install and the bundled Chromium (`/opt/pw-browsers/chromium-1194`).
  - It renders every image at `deviceScaleFactor: 2`.
  - It quantises PNGs with ImageMagick (`convert`, 256 colours, no dither) to keep each one under 150 KB. If a PNG is still too large, it falls back to 1x.
  - It saves the banners as JPEG. The quality starts at 82 and drops until the file is under 150 KB.
- To change a screen, edit `build-screens.mjs`, not the HTML. Running `node dev/seed/build-screens.mjs` rebuilds only the HTML.

## Images (`images/`)

| File | Size | Pixels | Shows | Entry |
|---|---|---|---|---|
| `timeline.png` | 144 KB | 2560×1600 | Timeline for "Harbour Museum rebrand": a lane per person (7 people), task bars, milestones and the amber "today" line on Tue 20 Oct. "Exhibition poster series" is mid-drag: a dashed ghost marks where it was, the bar is lifted, a tooltip reads "Fri 23 Oct → Thu 29 Oct +2 days", and the days it now covers are marked. | 1 (hero) |
| `timeline-day.png` | 120 KB | 2560×1600 | The same timeline at Day zoom, 19–30 Oct. | 1 (gallery) |
| `timeline-week.png` | 136 KB | 2560×1600 | The same timeline at Week zoom, 12 Oct – 6 Nov. | 1 (gallery) |
| `timeline-quarter.png` | 125 KB | 2560×1600 | The same timeline at Quarter zoom, Sep 2026 – Mar 2027. | 1 (gallery) |
| `api-tokens.png` | 100 KB | 2560×1600 | Settings → API tokens, dimmed behind a "New API token" dialog. The scopes `projects:read` and `files:write` are ticked, and an amber note says "Copy once". | 2 |
| `share-dialog.png` | 140 KB | 2560×1600 | "Share board" dialog for the Kiln & Co. catalogue, over the board. It has a link with a Copy button, Link on, Read only, an expiry of 30 Nov 2026, the client it was sent to, and a Pro badge. | 3 |
| `client-board.png` | 91 KB | 2560×1600 | What the client sees: the board, read only, with no Atelier chrome. A dark "Shared by Hattori Studio" bar carries a Read only pill. The studio's logo sits top-left. Cards have ceramic cover art and Approved / In review status chips. | 3 |
| `release-banner.jpg` | 143 KB | 3200×1280 | "Atelier 3.2" banner: a large "3.2" over three tilted UI fragments (timeline, inbox grouped by project, uploads that resume). | 4 (image by URL) |
| `search-before.png` | 108 KB | 2560×1600 | Search palette with the typo "harbur": a spinner, "Searching…", and "No results for 'harbur'". | 5 (gallery) |
| `search-after.png` | 136 KB | 2560×1600 | The same search answering in 35 ms with "Showing results for harbour". The results are a project, cards, a PDF hit on page 14 with the words highlighted, and a note. | 5 (gallery) |
| `export-menu.png` | 125 KB | 2560×1600 | The project's "…" menu open on "Export…" (Zip with files, notes, history). A toast says "Your export is ready — we emailed you a link". | 6 |
| `studio-desk.jpg` | 135 KB | 3200×1280 | Flat-lay illustration of a studio desk: a laptop showing an Atelier board, arch sketches, a poster grid, swatches, mugs, a pencil and a sticky note. | 7 (wide) |
| `calendar.png` | 131 KB | 2560×1600 | Calendar for October 2026, with due dates from five projects as coloured chips. It has a "Subscribe (iCal)" button and a purple "Beta" pill, and today (20 Oct) is ringed in amber. | 8 |

## Files (`files/`)

| File | Size | What | Entry |
|---|---|---|---|
| `drag-task.mp4` | 111 KB | 4.7 s, 1280×800, H.264, no audio. A cursor grabs "Exhibition poster series" and drags it two days later; the bar snaps day by day and the tooltip counts "+1 day", "+2 days". After the drop, Start and Due update in the side panel with an amber flash, and an Undo toast appears. Each frame is stepped through the Web Animations API, so frames are sharp. Source: `screens/timeline-drag.html`. | 1 (video) |
| `search-tips.pdf` | 137 KB | One A4 page, "Search tips": filters (`in:files`, `project:`, `from:`, `due:`, `type:`, quotes, `-word`), keyboard shortcuts, and how typos and PDF results work. Rendered with `page.pdf()` from `screens/search-tips.html`. | 5 (PDF) |
| `export-sample.csv` | 2 KB | A project export's `comments.csv`: 11 comments on Harbour Museum cards, with author, role, `internal`/`client` visibility and timestamps. Written by hand: `shoot.mjs` does not regenerate it. | 6 (file) |

## Screens (`screens/`)

Each HTML source matches its image. Two have no image of their own: `timeline-drag.html` is the source of the MP4 (add `class="play"` to `<body>` to run the animation in a browser), and `search-tips.html` is the source of the PDF.

## People and data

- **Studio:** Hattori Studio.
- **Team:** Aiko Hattori (creative director), Tom Okafor and Inês Moreira (designers), Ravi Shah (developer), Lena Brandt (copywriter), Mariko Sato (producer), Noah Kim (photographer).
- **Client:** Sofia Lindqvist of Kiln & Co.
- **Projects:** Harbour Museum rebrand, Kiln & Co. catalogue, Northfield Library signage, Tamsin Ceramics shop, Orchard Street Bakery.
- **Today:** Tuesday 20 October 2026.
