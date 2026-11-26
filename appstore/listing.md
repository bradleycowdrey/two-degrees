# Two Degrees Weather: App Store listing

Everything App Store Connect asks for, ready to paste. Character limits are Apple's.

## App Information

| Field | Value |
|---|---|
| Name (30) | Two Degrees Weather |
| Subtitle (30) | °F and °C, always side by side |
| Category | Primary: **Weather**. Secondary: Utilities |
| Content rights | Does not contain, show or access third-party content |
| Age rating | Answer **None / No** to every question → **4+** |
| Copyright | 2026 Bradley Cowdrey |

## Version page (1.0)

**Promotional text (170)**
Every temperature in °F and °C at once. Swipe between your cities, see the next 24 hours and 10 days, and keep the weather on your Home Screen and Lock Screen.

**Description (4,000)**
Two Degrees shows the weather in Fahrenheit and Celsius at the same time, so you never have to convert again. Pick which unit is large; the other is always right beside it.

YOUR CITIES
• Swipe between up to five cities, each on its own sky
• Search any place in the world, reorder, and swipe a city away
• Tap the temperature to swap which unit is large

THE FORECAST
• Right now: temperature in °F and °C, condition, and today's high and low in both units
• The next 24 hours, with rain chances and a one-line summary ("Rain likely around 5 PM")
• A 10-day forecast with each day's range on one shared scale
• Feels like, humidity and dew point, wind and its direction, rain, UV index, and sunrise or sunset

WIDGETS
• Small, medium and large Home Screen widgets
• Lock Screen widgets: a line above the clock, a circle, and a rectangle
• Use your Two Degrees cities, or give each widget a city of its own

MADE TO BE READ
• Follows your iPhone's text size, with its own size and font options too
• Full VoiceOver support: every reading is spoken in both units

PRIVATE BY DESIGN
No account, no ads, no tracking. Your cities stay on your iPhone; only their locations are sent to Open-Meteo to get the forecast.

Free. Forever. Made by Bradley Cowdrey. Weather data by Open-Meteo.com.

Also on the Mac, with the weather in your menu bar and Dock: bradcowdrey.com/two-degrees

**Keywords (100)**
fahrenheit,celsius,temperature,forecast,widget,lock screen,hourly,10 day,rain,uv,both units,convert

**Support URL**: https://github.com/bradleycowdrey/two-degrees/issues
**Marketing URL**: https://bradcowdrey.com/two-degrees
**Version**: 1.0 (App Store versions are separate from the build's 0.4.x)

## App Privacy

- **Privacy Policy URL**: https://bradcowdrey.com/legal
- **Data collection**: choose **"No, we do not collect data from this app"**.
  Why that's accurate: the app has no account, analytics or ads, and the developer never receives
  anything. City coordinates go straight from the device to Open-Meteo to fetch the forecast and
  aren't linked to the person, so Apple's definition of "collect" doesn't apply.

## App Review Information

- **Sign-in required**: No
- **Contact**: Bradley Cowdrey, with your phone and email
- **Notes**:
  Two Degrees shows every temperature in Fahrenheit and Celsius at once. No account or permissions
  are needed. Weather comes from the free Open-Meteo API. To try the widgets: long-press the Home
  Screen → Edit → Add Widget → Two Degrees; long-press the Lock Screen → Customize. To add a city, tap
  the list button (bottom right), then search.

## Pricing and Availability

- Price: **Free**
- Availability: all countries
- **iPhone and iPad Apps on Apple Silicon Macs: leave unticked.** The Mac has its own app; the iPhone
  version on a Mac clashes with it (same bundle ID).

## Screenshots

On the Cowdrey family App Store standard ([`scripts/store-frames/STANDARD.md`](../scripts/store-frames/STANDARD.md)):
the real app on Two Degrees' catalog sky (`#72AAE9` to `#204294`), under an eyebrow, a Fraunces headline and a
one-line subhead in Cowdrey One's type scale. The family compositor is vendored in `scripts/store-frames/`
(`store-frames.js`, with Fraunces and Inter and their OFL licences in `fonts/`); Two Degrees' words and pictures
are in `scripts/store-frames/apps/two-degrees.json`.

`.github/workflows/appstore-screenshots.yml` (run it from the Actions tab) makes the whole set in one go:
1. photographs the iPhone and iPad apps in the Simulator (one frozen forecast for every launch) and renders their
   widgets, Home Screen and Lock Screen;
2. builds the Mac app and runs its self-test's App Store pass (`--selftest DIR --store`) with the iPhone's cities
   and forecasts, for the Mac windows and widgets;
3. `python3 scripts/store-frames/prepare-captures.py --ios DIR --mac DIR --out build/store-captures` gathers the
   captures under the config's names; the Mac screens are 2880 × 1800, two of the app's real windows side by side
   on the app's own sky;
4. `node scripts/store-frames/store-frames.js --config scripts/store-frames/apps/two-degrees.json` frames them, and
   `node scripts/store-frames/check.js` checks every size and position against the standard.

The raw captures and the framed set (`framed/`, with `measure.json`) go to the `appstore-screenshots` branch for
review; nothing is uploaded. To ship them, copy `framed/*.png` and `framed/measure.json` into
`appstore/screenshots` on main and run "App Store listing", which checks them again before it uploads.

`appstore/screenshots/` is what "App Store listing" uploads (the lists are in `appstore/metadata.json`):
- iPhone 6.9" (1320 × 2868): `iphone-1-now.png`, `iphone-2-ten-day.png`, `iphone-3-details.png`,
  `iphone-4-cities.png`, `iphone-5-widgets.png` (the Home Screen and Lock Screen widgets)
- iPad 13" (2064 × 2752): `ipad-1-now.png` … `ipad-5-widgets.png`, the same story
- Mac (2880 × 1800): `mac-1-now.png`, `mac-2-forecast.png`, `mac-3-widgets.png`

The copy never shrinks to fit: copy that is too long is an error, and is rewritten.
