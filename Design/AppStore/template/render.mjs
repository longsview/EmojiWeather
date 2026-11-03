// Renders the marketing frames in frames.json with headless Chromium (Playwright).
// Usage, from Design/AppStore:  node template/render.mjs [iphone|ipad]
// Reads raw screenshots from raw/<device>/ and writes final/<device>/<id>.png at App Store size.
import { chromium } from "playwright";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const root = process.cwd();
const config = JSON.parse(fs.readFileSync(path.join(root, "template/frames.json"), "utf8"));
const devices = process.argv[2] ? [process.argv[2]] : Object.keys(config);
const browser = await chromium.launch();
for (const device of devices) {
  const { size: [w, h], frames } = config[device];
  const out = path.join(root, "final", device);
  fs.mkdirSync(out, { recursive: true });
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
  for (const frame of frames) {
    const shotPath = path.join(root, frame.shot);
    if (!fs.existsSync(shotPath)) { console.warn(`skip ${device}/${frame.id}: missing ${frame.shot}`); continue; }
    const f = { ...frame, shotURL: pathToFileURL(shotPath).href };
    const url = pathToFileURL(path.join(root, "template/frame.html")).href +
      `?device=${device}&size=${w}x${h}&f=${encodeURIComponent(JSON.stringify(f))}`;
    await page.goto(url);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForFunction(() => document.getElementById("shot").complete);
    await page.screenshot({ path: path.join(out, `${frame.id}.png`) });
    console.log(`wrote final/${device}/${frame.id}.png`);
  }
  await page.close();
}
await browser.close();
