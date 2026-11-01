# Two Degrees: weather features (0.5)

One design for every platform (Mac, iPhone and iPad, Android, web), so they behave and read the same.
The house rules still apply everywhere: every temperature in both units (the larger unit first, the
other beside it), plain words, title-case conditions, hair-spaced readings (`18 °C`), no account, no
tracking, nothing sent to us.

## 0. Data: one Open-Meteo forecast request, plus three small ones

**Forecast** (existing request, more fields), `https://api.open-meteo.com/v1/forecast`:
- `current`: add `pressure_msl, cloud_cover, wind_gusts_10m, visibility, precipitation`.
- `hourly`: add `precipitation, wind_speed_10m, wind_gusts_10m, pressure_msl, visibility`.
- `daily`: add `precipitation_sum, rain_sum, snowfall_sum, wind_speed_10m_max, wind_gusts_10m_max, wind_direction_10m_dominant`.
- `minutely_15=precipitation` with `forecast_minutely_15=8` (the next two hours, in 15-minute steps).
- Keep `past_hours=3` out; the pressure trend uses the hourly series (now vs 3 hours ago is in the
  hourly data because hours start at midnight).
- Every new field is optional when decoding: a missing or null value hides its tile, never fails the forecast.

**Air quality**, `https://air-quality-api.open-meteo.com/v1/air-quality?latitude=..&longitude=..&timezone=auto&forecast_days=1&past_days=1`
- `current=us_aqi,european_aqi,pm2_5,pm10,ozone,nitrogen_dioxide,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen`
- `hourly=us_aqi,european_aqi` (yesterday's same hour, for "better or worse than yesterday").
- Refresh with the forecast. Failure hides the tiles.

**Normals and records** (once per city, cached 30 days), `https://archive-api.open-meteo.com/v1/archive?latitude=..&longitude=..&start_date=1940-01-01&end_date=<today − 7 days>&daily=temperature_2m_max,temperature_2m_min&timezone=auto`
- Build a 366-entry table keyed by month-day (Feb 29 included):
  - **normal high / low**: mean of daily max / min over 1991–2020, using a ±3-day window around the
    month-day (smooths it), rounded later in each unit.
  - **record high / low**: the highest max and lowest min ever on that exact month-day, with its year.
- Store only the table (small), not the raw response.

**Severe weather alerts** (United States only, for now), `https://api.weather.gov/alerts/active?point=<lat>,<lon>`
- Send a `User-Agent: TwoDegrees (bradcowdrey.com, legal@bradcowdrey.com)` header (required by the NWS).
- Only ask for places inside the US (a non-US point returns an error: treat as "no alerts here").
  Coordinates rounded to 2 decimals.
- Each feature's `properties`: `id, event, severity (Extreme|Severe|Moderate|Minor|Unknown), urgency,
  headline, description, instruction, effective, expires, senderName`.
- Refresh with the forecast. Keep only alerts whose `expires` is in the future.

**Rain map**: one hosted page, `https://bradleycowdrey.github.io/two-degrees/radar.html?lat=..&lon=..&z=7&units=F|C`
(source `web/radar.html`). Leaflet, CARTO dark base map (© OpenStreetMap contributors © CARTO),
RainViewer radar frames (past two hours and the forecast "nowcast"), with play/pause and a time slider.
Apps show it in a web view; the web app links to it.

## 1. Severe weather alerts and notifications

- **On a city's page**, above everything else: one card per active alert, most severe first.
  Colour by severity: Extreme and Severe red (`#E5484D`), Moderate orange (`#F2A65A`), Minor and Unknown
  yellow (`#E9C98A`). Shows `event` (title), "Until 6:15 PM" (local time of `expires`), and `senderName`.
  Tap → full text: `headline`, `description`, `instruction`, a "More at weather.gov" link, and the note
  "From the US National Weather Service. Alerts can be late or missing: follow official warnings."
- **In the city list**: a small warning triangle beside the city name when it has an alert.
- **Outside the US**: nothing shows (no empty card). Settings say "Severe weather alerts: United States
  only, from the National Weather Service."
- **Notifications** (Mac, iPhone, Android; not the web). Two settings, both **off** until turned on:
  - **Severe Weather**: a notification for each new Extreme, Severe or Moderate alert for **My Location**
    (or the first city when Use My Location is off). Once per alert `id`. Title "Tornado Warning ·
    Denver", body `headline`.
  - **Rain Starting Soon**: when it isn't raining now and the 15-minute forecast has ≥ 0.2 mm in one of
    the next two steps (≈ 30 minutes), for the same city. At most once every 3 hours. Title "Rain starting
    soon · Denver", body "Rain is expected around 3:15 PM." (Snow when the code says snow.)
  - Turning either on asks the system for notification permission. If denied, the setting shows
    "Notifications are off for Two Degrees in Settings" with a button to open them.
  - Checks run whenever the forecast refreshes: in the background on iPhone (background app refresh,
    best effort), on Android (the existing 30-minute WorkManager job), and on the Mac while the app runs.

## 2. Rain map

- A **Map** card on each city page (and a map button on the Mac panel and in the web app): opens the
  map at that city. Full screen on phones, a sheet/window elsewhere. Close button top left. Needs the
  internet; offline it says "The map needs an internet connection."
- Credit line on the map: "Radar © RainViewer · Map © OpenStreetMap contributors © CARTO".

## 3. Next hour (15-minute rain)

- A **Next 2 hours** card, shown only when there's precipitation now or in the next two hours (≥ 0.1 mm
  in any step). 8 bars (Now, then every 15 minutes), height by mm, rain blue (`#8DB4E2`), snow white.
- One line above the bars: "Rain starting around 3:15 PM" / "Rain stopping around 3:45 PM" /
  "Rain for the next two hours" / "Light rain on and off" (snow: "Snow …").
- Amounts in the chosen rain unit.

## 4. Air quality and pollen

- **Air Quality** tile: the AQI number and its category, in the local scale: **US AQI** where the city
  is in the US (`us_aqi`), **European AQI** elsewhere (`european_aqi`).
  - US categories: 0–50 Good, 51–100 Moderate, 101–150 Unhealthy for Sensitive Groups, 151–200
    Unhealthy, 201–300 Very Unhealthy, 301+ Hazardous.
  - European: 0–20 Good, 20–40 Fair, 40–60 Moderate, 60–80 Poor, 80–100 Very Poor, 100+ Extremely Poor.
  - A thin coloured scale bar with a dot at the value. Note: "Better than yesterday" / "Worse than
    yesterday" / "About the same as yesterday" (±5 points), else the main pollutant ("Mostly PM2.5").
- **Pollen** tile, only when any pollen value is non-null (Europe): the highest pollen type and a level:
  grains/m³ < 10 Low, < 50 Moderate, < 200 High, else Very High. Note lists other types above Low.

## 6. More detail tiles

Two across, same card style as the existing tiles. Order after the existing six:
- **Pressure**: value in the pressure unit, with the other system beside it (hPa ↔ inHg). Note:
  "Rising" / "Falling" / "Steady" (change over the last 3 hours ≥ 1 hPa).
- **Visibility**: km or mi (follows the wind unit's system), "Clear view" (≥ 10 km) / "Haze" (2–10 km) /
  "Fog" (< 2 km).
- **Wind gusts**: add to the Wind tile's note: "Gusts to 35 mph" when gusts exceed wind by ≥ 10 km/h.
- **Precipitation**: today's total in the rain unit (other system beside it), note "Expected in the
  next 24 hours: X" or "None expected".
- **Cloud cover**: "62%" with "Mostly cloudy" (0–10 Clear, –30 Mostly clear, –60 Partly cloudy, –90
  Mostly cloudy, else Overcast).
- **Moon**: phase name and illumination ("Waxing Gibbous · 78%"), computed locally (synodic month
  29.530588853 days from the new moon of 2000-01-06 18:14 UTC). Eight names: New Moon, Waxing
  Crescent, First Quarter, Waxing Gibbous, Full Moon, Waning Gibbous, Last Quarter, Waning Crescent.

## 7. Tap a day for detail

- Tapping a row in the 10-day (or 5-day) forecast opens that day: a sheet on iPhone/Mac/web, a
  full-screen page on Android, with a close button and swipe/arrow between days.
- Contents, top to bottom:
  1. "Tuesday, Nov 4", condition, high and low in both units, rain chance.
  2. **Temperature** chart: the 24 hourly temperatures as a line, larger unit's axis on the left, the
     other unit's on the right; "Now" marker on today.
  3. **Rain** chart: hourly chance as bars (%), and the day's total in the rain unit.
  4. **Wind** chart: hourly speed line and gusts as a lighter line, in the wind unit; dominant direction.
  5. Facts: sunrise, sunset, UV max and level, max gust, and (when the table is loaded) **Normal**
     high/low and **Record** high/low with years for that date.
- Charts use the same colours as the day bars (temperature gradient) and rain blue.

## 12. Unit choices

Settings (Mac Settings › General; iPhone ⋯ menu › Units; Android ⋮ menu; web ⋯ menu):
- **Wind**: Automatic (mph when °F is larger, km/h when °C), km/h, mph, m/s, knots.
- **Rain**: Automatic (in with °F, mm with °C), mm, in.
- **Pressure**: Automatic (inHg with °F, hPa with °C), hPa, inHg, mmHg.
- Display: the chosen unit, and its other-system counterpart beside it, smaller, only for
  mph↔km/h, mm↔in and hPa↔inHg (m/s, knots and mmHg stand alone).
- Saved keys: `windUnit`, `rainUnit`, `pressureUnit` (values `auto|kmh|mph|ms|kn`, `auto|mm|in`,
  `auto|hpa|inhg|mmhg`).

## 13. Averages and records

- An **Averages** tile: "4° above normal" (today's high vs the normal high, in the larger unit; "About
  normal" within ±1°), with "Normal high 64 °F · 18 °C, low 45 °F · 7 °C" below.
- A **Records** line in the day detail (section 7): "Record high 81 °F (1999) · Record low 28 °F (1957)",
  both units.
- Hidden until the table loads; never blocks the page.

## 14. More cities

- Up to **20** cities of your own (My Location doesn't count). Update every "up to 5" message.

## Terms and credits (bradcowdrey.com/legal)

New services: the US National Weather Service (alerts; receives a city's rounded coordinates),
RainViewer (radar images), CARTO and OpenStreetMap (map tiles), Leaflet (open source), and Open-Meteo's
air-quality and historical-weather services. Two Degrees is still not a safety tool; alerts are copies
of official warnings and can be late or missing.
