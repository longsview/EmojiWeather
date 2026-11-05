# App Store screenshots

1. Capture raw screenshots into `Design/AppStore/raw/iphone/` and `raw/ipad/` with the
   names in `frames.json` (Debug build; see `EmojiWeather/App/ScreenshotMode.swift` for the
   launch arguments that set up each screen).
2. From `Design/AppStore`: `npm install playwright && npx playwright install chromium` (once),
   then `node template/render.mjs` (or `node template/render.mjs iphone`).
3. Finished frames land in `final/iphone/` (1320×2868) and `final/ipad/` (2064×2752).

Edit headlines, colors and stickers in `frames.json`. Themes are defined at the top of `frame.html`.

## Product page header and search results art

`banner.html` + `banners.json` + `render-banners.mjs` make the optional App Store Connect
"Product page header" and "Search results" images (iOS 27+). From Design/AppStore:

    node template/render-banners.mjs all      # or one language, e.g. ja

Writes opaque PNGs to `final/banners/<lang>/`:
- `header-3840x1646.png` (21:9, Product page header)
- `search-3840x2560.png` (3:2, Search results)
- `universal-5244x2950.png` (16:9, one file for both; emoji kept inside the area both crops keep)

Render on the Mac so the emoji are Apple's, and check both crops in App Store Connect's Preview.
