# EmojiWeather

Weather shown as animated scenes built only from emoji. A thunderstorm is ⛈️ falling like rain with ⚡️ bolts that flash the screen, snow is ❄️ drifting and settling, and so on.

## Getting started

Requires Xcode 26 and iOS 26.

1. Open `EmojiWeather.xcodeproj`.
2. In **Signing & Capabilities**, pick your team and change the bundle ID if `com.longsview.EmojiWeather` is taken.
3. In the [Apple Developer portal](https://developer.apple.com/account/resources/identifiers/list), open the App ID and turn on **WeatherKit** under both *Capabilities* and *App Services*. It can take up to 30 minutes before WeatherKit calls succeed.
4. Run. In debug builds the 🐞 menu on the home screen previews every scene and toggles EmojiWeather+.

The `#Preview("All scenes")` in `EmojiSceneView.swift` lets you swipe through every scene in the canvas without WeatherKit.

## How it's built

No backend. Everything uses Apple services:

| Need | Service |
| --- | --- |
| Weather data | WeatherKit (500,000 calls/month included), cached for 30 minutes |
| Current location | Core Location, "When In Use", city-level accuracy |
| City search | MapKit `MKLocalSearchCompleter` |
| Saved cities on every device | iCloud key-value store (`NSUbiquitousKeyValueStore`) |
| Purchases | StoreKit 2 (not wired up yet) |

```
EmojiWeather/
  App/        App entry point, dependency setup
  Models/     City, Place
  Services/   LocationService, CityStore (iCloud sync), WeatherProvider (WeatherKit + cache),
              CitySearchModel, PurchaseManager (free vs EmojiWeather+)
  Scenes/     WeatherScene (condition → scene), SceneSpec (scene recipes),
              EmojiParticleSystem (simulation + Canvas drawing), EmojiSceneView
  Views/      Home, forecast cards, places list, add city, paywall
```

## Apple Watch app

`EmojiWeatherWatch/` is a watchOS 26 app embedded in the iPhone app. It shares the scenes, WeatherKit cache, location service and the iCloud city list with the phone (the source files are members of both targets), fetches its own weather, and works without the phone nearby.

- Swipe sideways between My Location and saved cities (with a click haptic). The scene is the page's container background, so it stays put and cross-fades between cities.
- Scroll or turn the Digital Crown for hourly, conditions (feels like, UV, wind, humidity, rain, visibility, dew point, pressure, sunrise/sunset) and a 10-day forecast with temperature bars.
- Scenes are simulated at phone size and drawn scaled down (`EmojiSceneView.canvasScale`), run at 30 fps, and pause in always-on mode.

Complications (`EmojiWeatherComplications/`, a WidgetKit extension inside the watch app) come in circular, corner, rectangular and inline. They show My Location (or the first city) using weather the watch app saves to the App Group, and fetch their own from WeatherKit when it's over 45 minutes old.

Portal setup: the App ID `com.longsview.EmojiWeather.watchkitapp` needs **WeatherKit** (Capabilities and App Services) and **iCloud** (key-value storage) and **App Groups** (`group.com.longsview.EmojiWeather`). The complications ID `com.longsview.EmojiWeather.watchkitapp.Complications` needs **WeatherKit** and **App Groups**. The watch's key-value store identifier is the iPhone app's, so both see the same cities.

### Adding or tuning a scene

Each scene is a `SceneSpec` in `Scenes/SceneSpec.swift`: a background gradient, one or more `EmitterSpec` particle streams (emoji, rate, size, speed, angle, landing behavior) and optional `HeroSpec` fixed emoji. Lightning is a `lightningInterval`. Change the numbers and watch the preview.

## Free vs EmojiWeather+

| | Free | EmojiWeather+ |
| --- | --- | --- |
| Live emoji scenes, forecast | ✓ | ✓ |
| Saved cities | 3 | Unlimited |
| Widgets | | ✓ |
| Scene packs, custom emoji | | ✓ |
| Share clips without watermark | | ✓ |

The limits live in `PurchaseManager`.
