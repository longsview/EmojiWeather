// Renders the App Store product page header and search results art from banner.html.
// Usage, from Design/AppStore:  node template/render-banners.mjs [lang|all]
// Writes final/banners/<lang>/{header-3840x1646,search-3840x2560,universal-5244x2950}.png
// as opaque PNGs (App Store Connect rejects an alpha channel).
import { chromium } from "playwright";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const root = process.cwd();
const config = JSON.parse(fs.readFileSync(path.join(root, "template/banners.json"), "utf8"));
const arg = process.argv[2] || "all";
const langs = arg === "all" ? Object.keys(config.taglines) : [arg];
const icon = pathToFileURL(path.resolve(root, "../../EmojiWeather/Assets.xcassets/AppIcon.appiconset/AppIcon.png")).href;
const browser = await chromium.launch();
for (const lang of langs) {
  const out = path.join(root, "final", "banners", lang);
  fs.mkdirSync(out, { recursive: true });
  for (const [kind, [w, h]] of Object.entries(config.sizes)) {
    const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
    const url = pathToFileURL(path.join(root, "template/banner.html")).href +
      `?size=${w}x${h}&lang=${lang}&icon=${encodeURIComponent(icon)}&t=${encodeURIComponent(JSON.stringify(config.taglines[lang]))}`;
    await page.goto(url);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForFunction(() => document.getElementById("icon").complete);
    const file = path.join(out, `${kind}-${w}x${h}.png`);
    await page.screenshot({ path: file, omitBackground: false });
    await page.close();
    console.log(`wrote final/banners/${lang}/${kind}-${w}x${h}.png`);
  }
}
await browser.close();
