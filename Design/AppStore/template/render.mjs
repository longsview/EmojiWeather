// Renders the marketing frames in frames.json with headless Chromium (Playwright).
// Usage, from Design/AppStore:  node template/render.mjs [iphone|ipad|all] [lang]
// Reads raw screenshots from raw/<device>/ (or raw/<lang>/<device>/ when that exists) and writes
// final/<device>/<id>.png, or final/<lang>/<device>/<id>.png with captions from frames-l10n.json.
import { chromium } from "playwright";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const root = process.cwd();
const config = JSON.parse(fs.readFileSync(path.join(root, "template/frames.json"), "utf8"));
const deviceArg = process.argv[2] && process.argv[2] !== "all" ? process.argv[2] : null;
const devices = deviceArg ? [deviceArg] : Object.keys(config);
const lang = process.argv[3] || null;
const captions = lang ? JSON.parse(fs.readFileSync(path.join(root, "template/frames-l10n.json"), "utf8"))[lang] : null;
if (lang && !captions) throw new Error(`No captions for ${lang} in frames-l10n.json`);
const browser = await chromium.launch();
for (const device of devices) {
  const { size: [w, h], frames } = config[device];
  const out = lang ? path.join(root, "final", lang, device) : path.join(root, "final", device);
  fs.mkdirSync(out, { recursive: true });
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
  for (const frame of frames) {
    // A localized capture (raw/<lang>/...) wins over the English one.
    const localShot = lang ? path.join(root, frame.shot.replace(/^raw\//, `raw/${lang}/`)) : null;
    const shotPath = localShot && fs.existsSync(localShot) ? localShot : path.join(root, frame.shot);
    if (!fs.existsSync(shotPath)) { console.warn(`skip ${device}/${frame.id}: missing ${frame.shot}`); continue; }
    const name = frame.id.replace(/^\d+-/, "");
    const text = !captions ? null : captions[`${device}-${frame.id}`] ?? (device === "iphone" ? captions[frame.id] : null)
      ?? Object.entries(captions).find(([key]) => /^\d/.test(key) && key.replace(/^\d+-/, "") === name)?.[1];
    const f = { ...frame, shotURL: pathToFileURL(shotPath).href, ...(text ? { headline: text[0], sub: text[1] } : {}) };
    const url = pathToFileURL(path.join(root, "template/frame.html")).href +
      `?device=${device}&size=${w}x${h}&lang=${lang || "en"}&f=${encodeURIComponent(JSON.stringify(f))}`;
    await page.goto(url);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForFunction(() => document.getElementById("shot").complete);
    await page.screenshot({ path: path.join(out, `${frame.id}.png`) });
    console.log(`wrote final/${device}/${frame.id}.png`);
  }
  await page.close();
}
await browser.close();
