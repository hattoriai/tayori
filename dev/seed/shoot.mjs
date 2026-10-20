// Renders the Atelier screens in dev/seed/screens/ to images in dev/seed/images/,
// and builds dev/seed/files/ (search-tips.pdf, drag-task.mp4 when ffmpeg exists).
//
//   node dev/seed/shoot.mjs
//
// Needs the e2e Playwright install and its Chromium. PNGs are quantised with
// ImageMagick (`convert`) when it is on the PATH, to stay under ~150 KB.

import { chromium } from "/home/user/tayori/e2e/node_modules/playwright/index.mjs";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, statSync, rmSync, renameSync, mkdtempSync } from "node:fs";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath, pathToFileURL } from "node:url";
import { buildScreens } from "./build-screens.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const screensDir = join(here, "screens");
const imagesDir = join(here, "images");
const filesDir = join(here, "files");
const LIMIT = 150 * 1024;

const APP = { width: 1280, height: 800 };
const BANNER = { width: 1600, height: 640 };

// name → viewport and format. "jpeg" for photo-like art.
const SHOTS = [
  ["timeline", APP, "png"],
  ["timeline-day", APP, "png"],
  ["timeline-week", APP, "png"],
  ["timeline-quarter", APP, "png"],
  ["api-tokens", APP, "png"],
  ["share-dialog", APP, "png"],
  ["client-board", APP, "png"],
  ["search-before", APP, "png"],
  ["search-after", APP, "png"],
  ["export-menu", APP, "png"],
  ["calendar", APP, "png"],
  ["studio-desk", BANNER, "jpeg"],
  ["release-banner", BANNER, "jpeg"],
];

const has = (cmd) => spawnSync("sh", ["-c", `command -v ${cmd}`]).status === 0;
const kb = (p) => `${Math.round(statSync(p).size / 1024)} KB`;
const url = (name) => pathToFileURL(join(screensDir, `${name}.html`)).href;

// Quantise a PNG to a palette; at 2x first, then at 1x if still too big.
function squeezePng(file) {
  if (!has("convert")) return;
  const tmp = file + ".tmp.png";
  for (const [resize, colors] of [[null, 256], [null, 128], ["50%", 256], ["50%", 128]]) {
    const args = [file];
    if (resize) args.push("-filter", "Lanczos", "-resize", resize);
    args.push("-strip", "-dither", "None", "-colors", String(colors), "-define", "png:compression-level=9", `PNG8:${tmp}`);
    execFileSync("convert", args);
    if (statSync(tmp).size <= LIMIT) break;
  }
  renameSync(tmp, file);
}

async function main() {
  buildScreens();
  for (const d of [imagesDir, filesDir]) mkdirSync(d, { recursive: true });

  const browser = await chromium.launch({ executablePath: "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });

  for (const [name, viewport, type] of SHOTS) {
    const ctx = await browser.newContext({ viewport, deviceScaleFactor: 2 });
    const page = await ctx.newPage();
    await page.goto(url(name));
    await page.evaluate(() => document.fonts.ready);
    if (type === "jpeg") {
      const out = join(imagesDir, `${name}.jpg`);
      let q = 82;
      await page.screenshot({ path: out, type: "jpeg", quality: q });
      while (statSync(out).size > LIMIT && q > 60) {
        q -= 6;
        await page.screenshot({ path: out, type: "jpeg", quality: q });
      }
      console.log(`${name}.jpg  ${kb(out)}  (q${q})`);
    } else {
      const out = join(imagesDir, `${name}.png`);
      await page.screenshot({ path: out, type: "png" });
      squeezePng(out);
      console.log(`${name}.png  ${kb(out)}`);
    }
    await ctx.close();
  }

  // One-page PDF.
  {
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    await page.goto(url("search-tips"));
    await page.evaluate(() => document.fonts.ready);
    const out = join(filesDir, "search-tips.pdf");
    await page.pdf({ path: out, format: "A4", printBackground: true, pageRanges: "1" });
    console.log(`search-tips.pdf  ${kb(out)}`);
    await ctx.close();
  }

  // The drag as an MP4 (needs ffmpeg). The CSS animation is stepped frame by
  // frame through the Web Animations API, so every frame is sharp.
  if (has("ffmpeg")) {
    const FPS = 30;
    const DURATION = 4.2; // seconds of animation
    const HOLD = 0.3; // still frames before it starts
    const frameDir = mkdtempSync(join(tmpdir(), "atelier-frames-"));
    const ctx = await browser.newContext({ viewport: APP, deviceScaleFactor: 1 });
    const page = await ctx.newPage();
    await page.goto(url("timeline-drag"));
    await page.evaluate(() => document.fonts.ready);
    await page.evaluate(() => {
      document.body.classList.add("play");
      for (const a of document.getAnimations()) a.pause();
    });
    const total = Math.round((HOLD + DURATION + 0.2) * FPS);
    for (let f = 0; f < total; f++) {
      const t = Math.max(0, f / FPS - HOLD) * 1000;
      await page.evaluate((ms) => {
        for (const a of document.getAnimations()) a.currentTime = ms;
      }, t);
      await page.screenshot({ path: join(frameDir, `f${String(f).padStart(4, "0")}.png`) });
    }
    await ctx.close();
    const out = join(filesDir, "drag-task.mp4");
    execFileSync("ffmpeg", [
      "-y", "-loglevel", "error", "-framerate", String(FPS), "-i", join(frameDir, "f%04d.png"),
      "-c:v", "libx264", "-preset", "slow", "-crf", "24", "-pix_fmt", "yuv420p", "-tune", "stillimage",
      "-movflags", "+faststart", "-an", out,
    ]);
    rmSync(frameDir, { recursive: true, force: true });
    console.log(`drag-task.mp4  ${kb(out)}`);
  } else {
    console.log("ffmpeg not found: skipped drag-task.mp4");
  }

  await browser.close();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
