<p align="center"><img src="docs/icon.png" width="128" alt="Two Degrees icon"></p>

<h1 align="center">Two Degrees</h1>
<p align="center"><b>The weather in °F and °C at once.</b><br>
A tiny, free, open-source weather app for your Mac's Dock and menu bar.<br>
Made by <a href="https://bradcowdrey.com">Bradley Cowdrey · bradcowdrey.com</a></p>

<p align="center">
  <a href="https://github.com/bradleycowdrey/two-degrees/releases/latest/download/TwoDegrees.dmg"><b>Download for Mac</b></a> ·
  <a href="https://bradcowdrey.com/two-degrees">Web app</a> ·
  <a href="https://github.com/bradleycowdrey/two-degrees/issues">Report an issue</a>
</p>

---

Two Degrees shows every temperature twice, °F and °C side by side, so nobody has to do the math.
Pick which unit is large; the other always sits right next to it.

## Features

- **Both units, always**: the current temperature, feels-like, today's range, every hour and every day, in °F and °C.
- **Lives in the Dock**: the Dock icon shows the live reading (`57°` over `14°C`) and the sky. Right-click it for every saved city.
- **And the menu bar**: `☁ 57° · 14°`, with the full panel one click away. Larger unit only, or icon only, if you prefer.
- **Next 24 hours**: a scrolling strip with a temperature line, icons, and rain chance when it's 20% or more.
- **5-day forecast**: lows and highs in both units, on range bars drawn to one shared scale, with a dot for right now.
- **One plain sentence**: "Rain likely around 3 PM (60%)" or "Warming to 68°F / 20°C by 2 PM".
- **Up to five cities**: search any place on Earth; switch with one click; right-click a city to remove it.
- **Share**: the same Share button as Meridian and Cowdrey.MD.
- **The details**: five sizes (⌘+ / ⌘−), SF Pro or Inter, keep-on-top window, open at login, `F` / `C` keys to swap units, VoiceOver reads both units.
- **Automatic updates** from GitHub Releases, SHA-256 verified, one click to install.
- No account, no API key, no tracking. Weather data from [Open-Meteo](https://open-meteo.com) (CC BY 4.0), refreshed every 15 minutes.

Native SwiftUI, universal binary (Apple silicon + Intel), macOS 14 Sonoma or later.

## Web app

[`docs/index.html`](docs/index.html) (built from `docs/app.html` by `scripts/build-web.sh`) is the same panel as a single web page: live Open-Meteo data, saved cities, and a
share link that carries your cities (`?c=Denver~39.739~-104.990|London~51.507~-0.128`). Serve the `docs/` folder with
GitHub Pages or any static host. Where it can't reach Open-Meteo (offline, or a sandboxed preview), it says so and
shows a labelled sample forecast.

## Install (sideload)

Two Degrees is distributed directly, not through the Mac App Store.

1. Download [TwoDegrees.dmg](https://github.com/bradleycowdrey/two-degrees/releases/latest/download/TwoDegrees.dmg) (all versions are on [Releases](https://github.com/bradleycowdrey/two-degrees/releases)).
2. Open the DMG and drag **Two Degrees** to **Applications**.
3. First launch: if macOS says it can't verify the app, **right-click Two Degrees → Open → Open**, or run
   `xattr -dr com.apple.quarantine /Applications/TwoDegrees.app`
4. Add your cities with the **+** button.

## Build from source

Requires Xcode 15.3+ (Swift 5.10) on macOS 14+.

```sh
git clone https://github.com/bradleycowdrey/two-degrees.git
cd two-degrees
swift run                         # run in development
scripts/build-app.sh 0.1.0        # dist/TwoDegrees.app (universal)
scripts/make-dmg.sh 0.1.0         # dist/TwoDegrees-0.1.0.dmg
```

## Releasing

Bump the number in `VERSION` and push to `main`. GitHub Actions builds a universal app, packages a DMG and publishes it as release `v<VERSION>`, plus a stable `TwoDegrees.dmg` that the download links always point to.

## Inspired by

[Meteorologist](https://sourceforge.net/projects/heat-meteo/) (multiple locations in the menu bar), WeatherDock (a SwiftUI popover),
[DatWeatherDoe](https://github.com/inderdhir/DatWeatherDoe) (simple, dark-mode friendly) and [wego](https://github.com/schachmat/wego) (weather that gets out of the way).

## License

MIT. See [LICENSE](LICENSE). Inter is under the SIL Open Font License.
