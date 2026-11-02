# What's new in Two Degrees

Two Degrees updates itself: when a new version is out, the app shows a banner with an **Update** button
(or use **Check for Updates** in the ⋯ menu). Every version is on [Releases](https://github.com/bradleycowdrey/two-degrees/releases).

Version numbers follow [Semantic Versioning](https://semver.org) from 2.0.0 on: **major.minor.patch**.
A **patch** (2.0.1) fixes things, a **minor** version (2.1.0) adds features, and a **major** version
(3.0.0) is a big redesign or a change that stops something working the way it did. The build number
counts every change ever made, so each build is higher than the last.

## [2.1.1] - 2026-11-02

- **Use My Location, asked the way Apple prefers**: after the terms, one screen explains it, then iOS
  asks; choose Allow or Don't Allow there. Turn it on or off anytime in the ⋯ menu.
- **Clearer privacy wording**: the location request and the terms now say your location goes to the
  weather services for the weather and alerts where you are, rounded to about a kilometre. The
  updated terms are asked for once, no more than once a month.
- **Privacy manifest** for the iPhone and iPad app and its widgets.

## [2.1.0] - 2026-11-02

- **Sunrise and sunset colour**: a forecast of how good the next sunrise and sunset will look, from
  the clouds at each height: Great, Good, Some colour or Little colour, with the reason ("High and
  mid-level clouds to catch the colour", "Low cloud will likely block it"). On the sun tile, as Sunrise
  and Sunset tiles on the Mac and web, and beside the times in every day.
- **Back to the top**: swipe to another city and back, and the page starts at the top again.
- **Swipe between days**: in a day's detail, swipe left and right to move between days, as well as
  the arrows.
- **Better tiles**: UV and air quality scales, the moon's shape and when the next full or new moon
  is, and which heights the clouds are at.
- **A touch of colour**: each tile has its own accent on its icon and title, with a faint glow at
  the top. Some follow the reading: Feels like goes from blue to coral with the warmth, UV and air
  quality take their level's colour, and Averages is warm above normal and cool below.
- **Cleaner widgets**: the reading sits right under the city, with the sky and the day's range below.
- **One footer**: the city list ends like a city page, with where the weather comes from and when it
  was updated.
- **Polish**: the wind chart's legend no longer overlaps its numbers, rounder chart steps on Android,
  and tidier wrapping in the footers and the rain map's credits.

## [2.0.0] - 2026-11-01

Two Degrees 2.0: everything since 0.4 adds up to a new app, on Mac, iPhone, iPad, Android and the web.

- **The same tiles for every city**: air quality, averages, visibility, precipitation, cloud cover and
  the moon show for every city, so each city page has the same layout. Pollen, measured only in some
  places, is a line on the air quality tile, and a reading that isn't in yet shows a dash.
- **Since 0.4**: severe weather alerts and notifications, a rain map, rain in the next two hours, air
  quality, averages and records, a full day view, wind and rain units, up to 20 cities, Use My
  Location without duplicate cards, city search that works offline, and Two Degrees for Android.

## [0.5.1] - 2026-11-01

- **Rain map fixed**: it now uses a free dark map from OpenFreeMap, so the map shows instead of an
  "API key required" notice. The zoom buttons moved to the top right, clear of the close button.
- **Pressure removed**: the pressure tile and its unit setting are gone, for a cleaner city page.

## [0.5.0] - 2026-11-01

- **Severe weather alerts**: warnings, watches and advisories from the US National Weather Service show
  at the top of a city, most serious first; tap one for the full text and what to do. Turn on
  **Notifications** to hear about new alerts and rain starting soon (off unless you turn them on).
- **Rain map**: live radar for the past two hours, centred on your city, with a short look ahead when the radar service offers one.
- **Next two hours**: when rain or snow is near, see when it starts and stops in 15-minute steps.
- **Air quality and pollen**: the US AQI in the US and the European AQI elsewhere, with what's driving
  it, plus tree, grass and weed pollen where it's measured.
- **More details**: pressure and whether it's rising or falling, visibility, cloud cover, the day's rain
  or snow, wind gusts and the moon.
- **Tap a day** for its temperature, rain and wind through the day, sunrise and sunset, UV and the
  strongest gust.
- **Averages and records**: how today compares with the 1991–2020 normal, and the record high and low
  for the date, with the year.
- **Your units**: choose wind in km/h, mph, m/s or knots, rain in mm or inches, and pressure in hPa,
  inHg or mmHg. Temperatures are always in both, as ever.
- **Up to 20 cities**, up from 5.

## [0.4.7] - 2026-11-01

- **No more duplicate cards**: when where you are is a city you've saved, that city's card shows My
  Location (with the arrow) instead of a second card for the same place. Move somewhere else and My
  Location gets its own card again.

## [0.4.6] - 2026-10-31

- **Use My Location**: after you agree to the terms, Two Degrees asks once whether to show the weather
  where you are (recommended). Say yes and the place you're in comes first in your cities, kept up to
  date as you move, with an arrow beside it. Say no and it never asks again. Change it anytime in
  Settings (Mac) or the ⋯ menu. Your location is rounded to about a kilometre and used only to get its
  weather.
- **Pick cities with the internet out**: search falls back on a built-in list of 34,000 cities.
- **Updated terms**: they now cover Use My Location, so you'll be asked to agree once more. When the
  terms change, Two Degrees asks again no more than once a month.
- **Two Degrees for Android**: the same app and widgets, as an APK from bradcowdrey.com/two-degrees.

## [0.4.5] - 2026-10-26

- **Widgets can follow your Two Degrees cities**, like Meridian's: edit a widget and turn on **Use Two
  Degrees' Cities** to show the city showing in Two Degrees (or pick one of your cities), or turn it off
  to choose a city of its own.
- **Large widget**: laid out like Apple's Weather, with the sky and its name beside the big reading, and
  a sixth day.
- **The big reading in the app matches the widgets**: a smaller raised °F, then 18 °C whole beside it.
- Readings are spaced a little more (18 ° C), and conditions read like Apple's (Partly Cloudy).
- Mac ⋯ menu: real keyboard shortcuts for Refresh, Larger and Smaller.

## [0.4.4] - 2026-10-25

- **Cleaner numbers**: the big reading shows its unit smaller and raised (55°F), as in the Mac app; the
  hours and days show just 52° beside the other unit (11°C). In every widget and in the iPhone app.

## [0.4.3] - 2026-10-25

- **Fixed: Mac widgets could stay grey after an update**, and a newly picked city never loaded. The
  widget process from before the update kept running the old code with its network cut off. Updating
  and opening Two Degrees now end that process, so macOS starts the new widget right away.

## [0.4.2] - 2026-10-25

- iPad: Two Degrees fills the screen, with larger text and a wider column.

## [0.4.1] - 2026-10-25

- **°F and °C on every number**, in the iPhone app and in every widget on Mac and iPhone (it used to be
  70° next to 21°C).
- iPhone: a **UV index** tile (today's peak, its level and whether to cover up), the **dew point** under
  humidity, and the wind's **direction**.
- iPhone: follows your iPhone's text size, the 10-day forecast's temperatures and a 100% rain chance stay
  on one line, city cards show today's high and low in both units, and the page scrolls away cleanly
  under the pinned header.
- The rain tile and the hourly summary now always agree on when rain is likely.

## [0.4.0] - 2026-10-25

- **Two Degrees for iPhone**, laid out like Apple's Weather: swipe between your cities, each on its own
  sky, with a large reading in °F and °C that shrinks into one line as you scroll, the next 24 hours, a
  10-day forecast, and tiles for feels like, humidity, wind, rain and sunrise or sunset. Tap the reading
  to swap which unit is large. The city list lets you search, reorder and swipe cities away.
- **iPhone widgets**: small, medium and large on the Home Screen, plus three Lock Screen widgets.
- Available through TestFlight while it's in testing.

## [0.3.9] - 2026-10-22

- **Share is in the header now**, the first round button, left of °F | °C (it used to sit in the footer).
- **A more compact 5-day forecast.** Opened, each day takes less height, so all five fit in less space.
- Web app: the header fits on the narrowest phones; below 360px the logo stands in for the name.

## [0.3.8] - 2026-10-22

- **The menu bar panel opens centred under Two Degrees' menu bar item**, instead of hanging off to one side of
  it. Near the edge of the screen it stays fully on screen.
- Fixed: picking a different city moved the **+** | **✎** buttons (and could push them onto their own line),
  because the selected city's name is bolder and wider. Each city now keeps the same width whether it's selected or
  not, so nothing in the row moves. Same in the web app.

## [0.3.7] - 2026-10-21

- **Signed and notarized by Apple.** Two Degrees is now signed with a Developer ID and checked by Apple, so it opens
  with a double-click (no "Open Anyway", no Terminal) and macOS runs its widget without second thoughts.
- **Terms of Use and Privacy.** Two Degrees asks you to agree once, the first time it opens. The terms are always
  one click away under ⋯ → **Terms & Privacy** (in the app and on the web), in **Settings**, and at
  [bradcowdrey.com/legal](https://bradcowdrey.com/legal).

## [0.3.5] - 2026-10-18

- **Fixed: widgets stayed blank after an update.** The updater swapped in the new app without telling macOS, so
  macOS still had the old version on record and threw the widget's content away. The updater now registers each new
  version, and the app re-registers itself every time it opens, which also repairs Macs already affected: open
  Two Degrees once and its widgets fill in.

## [0.3.4] - 2026-10-18

- **Fixed: a widget could go blank after you picked a different city.** If the new city's forecast didn't arrive in
  the few seconds macOS gives a widget, the widget fell back to an empty-looking placeholder. Now it gives up quickly,
  shows the last forecast it has (marked offline), or says "Couldn't load the weather" and tries again within 5
  minutes. It never goes blank.
- City search in a widget's settings no longer shows an error when the network is slow, and a place whose name
  contains "|" can be picked.

## [0.3.3] - 2026-10-18

- **Widgets redraw right after an update.** Opening Two Degrees now refreshes its widgets at once, so they show the
  new version's design immediately instead of up to 30 minutes later.

Also new on [bradcowdrey.com/two-degrees](https://bradcowdrey.com/two-degrees) since 0.3.2:

- **A product page**, like Meridian's: the real app running in the page, a °F/°C ruler, features, install steps,
  and Share buttons in the nav, the hero and the closing section.
- **The widgets, live**, in a "Right on your desktop" section. They follow the app above them: change its city or
  unit and they change too.
- The page comes straight from this repo through GitHub Pages, so it's always the latest version.
- Fixed: on a phone, the closed 5-day forecast's range ran into its title.

## [0.3.2] - 2026-10-17

- **Clearer 5-day forecast.** Each day's low and high now sit at the two ends of its bar, so a bar reads as that
  day's range on the shared scale. The empty track is gone; faint ticks every 10°F (or 5°C) carry the scale and line
  up with the labels above. Same in the app, the web app and the large widget.

## [0.3.1] - 2026-10-17

- Checking for updates while an update installs now says so instead of doing nothing.
- Fixed: a forecast that arrived after its city was removed could be kept and saved. Removing a city now clears its
  saved forecast, and adding it back loads a fresh one.

## [0.3.0] - 2026-10-17

- **Update banner**: checking, up to date, or an update with an **Update** button, download and install progress,
  and errors in full with Retry. **Check for Updates** used to show no result.
- **Updates are always verified**: every download's SHA-256 is checked before it installs, and checking works even
  when GitHub's API turns the request away.
- **5-day forecast as an accordion**, closed when the app opens. Closed, it shows the five-day range in both units.
- Fixed: a manual update check during an automatic one was dropped, and a failed re-check could hide an update
  that was already found.
- Fixed: the next 24 hours could start at midnight instead of the current hour.
- Fixed: the web app and the Mac app rounded a half degree differently (−2.5°C).
- Web app: adding a city shows it loading instead of the previous city's numbers, and Escape closes search from
  anywhere.

## [0.2.2] - 2026-10-17

- Fixed: the tiles at the top of the window could overlap.

## [0.2.1] - 2026-10-17

- Design polish: one offline wording everywhere ("Offline · from 3:40 PM"), a larger moon icon, and more room
  around Add | Edit on phones.

## [0.2.0] - 2026-10-17

- **macOS widgets**: small, medium and large, for the desktop and Notification Center. Each picks its own city and
  which unit is large. They work in tinted and clear modes, with VoiceOver, and offline.
- **Borrowed from Meridian**: Add | Edit city controls, tear the panel off into a window, window position, keep on
  top, five sizes and SF Pro or Inter.
- 5-day bars drawn on one shared, labelled scale.

## [0.1.0] - 2026-10-17

- First release: the weather in °F and °C at once, in the Dock (a live temperature on the icon) and the menu bar,
  with the next 24 hours, a 5-day forecast, up to five cities and a Share button. Data from Open-Meteo.

[0.4.5]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.4.5
[0.4.4]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.4.4
[0.4.3]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.4.3
[0.4.2]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.4.2
[0.4.1]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.4.1
[0.4.0]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.4.0
[0.3.9]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.3.9
[0.3.8]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.3.8
[0.3.7]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.3.7
[0.3.5]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.3.5
[0.3.4]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.3.4
[0.3.3]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.3.3
[0.3.2]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.3.2
[0.3.1]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.3.1
[0.3.0]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.3.0
[0.2.2]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.2.2
[0.2.1]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.2.1
[0.2.0]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.2.0
[0.1.0]: https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.1.0
