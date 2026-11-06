# App Store screenshots

1. Capture raw screenshots into `Design/AppStore/raw/iphone/` and `raw/ipad/` with the
   names in `frames.json` (Debug build; see `EmojiWeather/App/ScreenshotMode.swift` for the
   launch arguments that set up each screen).
2. From `Design/AppStore`: `npm install playwright && npx playwright install chromium` (once),
   then `node template/render.mjs` (or `node template/render.mjs iphone`).
3. Finished frames land in `final/<device>/`, or `final/<lang>/<device>/` with
   `node template/render.mjs all <lang>` (en, fr, es, pt-BR, zh-Hans, ja, ar; captions in
   `frames-l10n.json`, localized captures read from `raw/<lang>/<device>/` when present).

| Folder | Size | App Store Connect slot |
| --- | --- | --- |
| `iphone` | 1320×2868 | iPhone 6.9" (Dynamic Island, large) |
| `iphone-6.3` | 1206×2622 | iPhone 6.3" (Dynamic Island, medium), **required** |
| `ipad` | 2064×2752 | iPad 13" |
| `duo-inner` | 2853×2007 | iPhone Duo, inner display (required from April 2027 for iOS 27.1 SDK builds) |
| `duo-outer` | 1398×2034 | iPhone Duo, outer display |

`iphone-6.3` and `duo-outer` reuse the iPhone frames; `duo-outer` reads real folded captures
from `raw/duo-outer/` (same names as `raw/iphone/`). `duo-inner` is landscape (2853×2007, which
App Store Connect accepts for the Duo inner display) with its own frames, from real open-Duo
captures in `raw/duo-inner/`: sunny, storm, map, quiz, snow. On the open Duo the app shows the
city pager on the left half and the full forecast on the right half, meeting at the fold.

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
