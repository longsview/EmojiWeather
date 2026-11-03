# App Store screenshots

1. Capture raw screenshots into `Design/AppStore/raw/iphone/` and `raw/ipad/` with the
   names in `frames.json` (Debug build; see `EmojiWeather/App/ScreenshotMode.swift` for the
   launch arguments that set up each screen).
2. From `Design/AppStore`: `npm install playwright && npx playwright install chromium` (once),
   then `node template/render.mjs` (or `node template/render.mjs iphone`).
3. Finished frames land in `final/iphone/` (1320×2868) and `final/ipad/` (2064×2752).

Edit headlines, colors and stickers in `frames.json`. Themes are defined at the top of `frame.html`.
