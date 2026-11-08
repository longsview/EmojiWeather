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
const captions = lang && lang !== "en" ? JSON.parse(fs.readFileSync(path.join(root, "template/frames-l10n.json"), "utf8"))[lang] : null;
if (lang && lang !== "en" && !captions) throw new Error(`No captions for ${lang} in frames-l10n.json`);
const browser = await chromium.launch();
for (const device of devices) {
  // A device can reuse another's frames ("frames": "iphone"), take its layout from another
  // ("layout": "ipad") and read raw shots from its own folder ("shots": "duo-inner"), falling
  // back to the frames' own shots when that folder has no capture. "stickers" overrides a
  // frame's stickers by id when they would cover the capture on that device.
  const entry = config[device];
  const [w, h] = entry.size;
  const frames = typeof entry.frames === "string" ? config[entry.frames].frames : entry.frames;
  const layout = entry.layout || device;
  const captionDevice = typeof entry.frames === "string" ? entry.frames : device;
  const out = lang ? path.join(root, "final", lang, device) : path.join(root, "final", device);
  fs.mkdirSync(out, { recursive: true });
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
  for (const frame of frames) {
    // A localized capture (raw/<lang>/...) wins over the English one.
    const shot = entry.shots ? frame.shot.replace(/^raw\/[^/]+\//, `raw/${entry.shots}/`) : frame.shot;
    const candidates = [
      lang && path.join(root, shot.replace(/^raw\//, `raw/${lang}/`)),
      path.join(root, shot),
      lang && path.join(root, frame.shot.replace(/^raw\//, `raw/${lang}/`)),
      path.join(root, frame.shot),
    ].filter(Boolean);
    const shotPath = candidates.find(p => fs.existsSync(p)) ?? path.join(root, frame.shot);
    if (!fs.existsSync(shotPath)) { console.warn(`skip ${device}/${frame.id}: missing ${frame.shot}`); continue; }
    const name = frame.id.replace(/^\d+-/, "");
    const text = !captions ? null : captions[`${device}-${frame.id}`] ?? captions[`${captionDevice}-${frame.id}`] ?? (captionDevice === "iphone" ? captions[frame.id] : null)
      ?? Object.entries(captions).find(([key]) => /^\d/.test(key) && key.replace(/^\d+-/, "") === name)?.[1];
    const f = { ...frame, ...(entry.subs?.[frame.id] ? { sub: entry.subs[frame.id] } : {}), ...(entry.stickers?.[frame.id] ? { stickers: entry.stickers[frame.id] } : {}), screenAspect: entry.screenAspect, fold: entry.fold, shotURL: pathToFileURL(shotPath).href, ...(text ? { headline: text[0], sub: text[1] } : {}) };
    const url = pathToFileURL(path.join(root, "template/frame.html")).href +
      `?device=${layout}&size=${w}x${h}&lang=${lang || "en"}&f=${encodeURIComponent(JSON.stringify(f))}`;
    await page.goto(url);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForFunction(() => document.body.dataset.ready === "1");
    await page.screenshot({ path: path.join(out, `${frame.id}.png`) });
    console.log(`wrote final/${device}/${frame.id}.png`);
  }
  await page.close();
}
await browser.close();
