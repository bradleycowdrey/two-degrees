# What's new in Two Degrees

Two Degrees updates itself: when a new version is out, the app shows a banner with an **Update** button
(or use **Check for Updates** in the ⋯ menu). Every version is on [Releases](https://github.com/bradleycowdrey/two-degrees/releases).

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
