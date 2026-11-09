import SwiftUI

// The twelve detail tiles under a city's forecast, two across, shared by the iPhone and Mac apps. Their
// small pictures are in TileGraphics.swift; rules and words are in design/weather-features.md and
// WeatherExtras.swift.

// MARK: - Detail tiles

/// Square tiles two across, like the bottom half of Apple's Weather.
struct DetailTiles: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let forecast: Forecast
    let city: City

    var body: some View {
        let now = forecast.now, unit = store.unit, other = unit.other
        let today = forecast.days.first?.including(now.temperature)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: ui.pt(10)), GridItem(.flexible(), spacing: ui.pt(10))], spacing: ui.pt(10)) {
            DetailTile(title: "Feels like", icon: "thermometer.medium",
                 value: "\(unit.value(now.feelsLike))\(unit.symbol)", sub: "\(other.value(now.feelsLike))\(other.symbol)",
                 note: feelsNote(now)).accent(TileAccent.temperature(now.feelsLike))
            DetailTile(title: "Humidity", icon: "humidity",
                 value: "\(Int(now.humidity.rounded()))%", sub: nil,
                 note: dewNote(now)).accent(TileAccent.humidity)
            let wind = store.windUnit.text(now.wind, temp: unit)
            DetailTile(title: "Wind", icon: "wind", value: wind.main, sub: wind.other, note: windNote(now),
                       accessory: AnyView(WindCompass(direction: now.windDirection, accent: Color(hex: TileAccent.wind)))).accent(TileAccent.wind)
            DetailTile(title: "Rain", icon: "drop.fill",
                 value: "\(today?.rainChance ?? 0)%", sub: "chance today",
                 note: rainNote).accent(TileAccent.rain)
            sunTile(today)
            uvTile(today)
            ExtraTiles(forecast: forecast, city: city)
        }
    }

    private func mph(_ kmh: Double) -> Int { Int((kmh * 0.621371).rounded()) }

    private func feelsNote(_ now: Forecast.Now) -> String {
        let difference = now.feelsLike - now.temperature
        if difference <= -1.5 { return now.wind >= 15 ? "Wind is making it feel cooler." : "It feels cooler than it is." }
        if difference >= 1.5 { return "Humidity is making it feel warmer." }
        return "Similar to the actual temperature."
    }

    /// How strong, and from where: "A light breeze from the NW."
    private func windNote(_ now: Forecast.Now) -> String {
        let strength: String
        switch now.wind {
        case ..<2: return "Calm."
        case ..<12: strength = "A light breeze"
        case ..<29: strength = "A moderate breeze"
        case ..<50: strength = "A strong breeze"
        default: strength = "Gale-force wind"
        }
        let note = now.windDirection.map { "\(strength) from the \(Meteo.compassName($0))." } ?? "\(strength)."
        // Gusts, when they're well above the steady wind.
        if let gusts = now.gusts, gusts - now.wind >= 10 {
            return note + " Gusts to \(store.windUnit.text(gusts, temp: store.unit).main)."
        }
        return note
    }

    /// The dew point in both units, as Apple's Weather gives it under humidity.
    private func dewNote(_ now: Forecast.Now) -> String {
        let dew = Meteo.dewPoint(celsius: now.temperature, humidity: now.humidity)
        return "The dew point is \(store.unit.value(dew))\(store.unit.symbol) · \(store.unit.other.value(dew))\(store.unit.other.symbol) right now."
    }

    /// Today's peak UV index, its level, and whether to cover up.
    @ViewBuilder
    private func uvTile(_ today: Forecast.Day?) -> some View {
        if let uv = today?.uvIndex {
            DetailTile(title: "UV index", icon: "sun.max.fill",
                       value: "\(Int(uv.rounded()))", sub: Meteo.uvLevel(uv),
                       note: uv >= 3 ? "Use sun protection around midday." : "Low for the rest of the day.",
                       accessory: AnyView(ScaleBar(colors: ScaleBar.uv, position: min(max(uv / 11, 0), 1)))).accent(TileAccent.uv(uv))
        } else {
            DetailTile(title: "UV index", icon: "sun.max.fill", value: "–", sub: nil, note: Self.uvMissing).accent(TileAccent.neutral)
        }
    }

    /// What the UV tile says when today's index hasn't arrived.
    private static var uvMissing: String {
        #if os(iOS)
        return "Pull down to refresh."
        #else
        return ExtraTiles.missing
        #endif
    }

    private var rainNote: String {
        // Same rule and words as the hourly summary (Summary.line), so the two never disagree.
        if let wet = forecast.upcomingHours.dropFirst().prefix(12).first(where: { $0.rainChance >= 50 }) {
            let what = Condition.isSnow(wet.code) ? "Snow" : ([95, 96, 99].contains(wet.code) ? "Storms" : "Rain")
            return "\(what) likely around \(Forecast.format(wet.time, "j"))."
        }
        return "None expected in the next 12 hours."
    }

    /// The next sunrise or sunset, how colourful it's likely to be, and the other one's time.
    @ViewBuilder
    private func sunTile(_ today: Forecast.Day?) -> some View {
        let time = { (date: Date?) in date.map { Forecast.format($0, "jmm") } ?? "–" }
        if let next = SkyColour.next(forecast) {
            let outlook = SkyColour.outlook(forecast, at: next.time)
            let day = forecast.days.first { Calendar.current.isDate($0.date, inSameDayAs: next.time) }
            let other = next.isSunset ? forecast.days.first { ($0.sunrise ?? .distantPast) > next.time }?.sunrise : day?.sunset
            let accent = next.isSunset ? TileAccent.sunset : TileAccent.sunrise
            DetailTile(title: next.isSunset ? "Sunset" : "Sunrise", icon: next.isSunset ? "sunset.fill" : "sunrise.fill",
                       value: time(next.time), sub: outlook?.rating.line,
                       note: [outlook?.reason, "\(next.isSunset ? "Sunrise" : "Sunset") \(time(other))."].compactMap { $0 }.joined(separator: " "),
                       accessory: sunPath(today, accent: accent)).accent(accent)
        } else {
            DetailTile(title: "Sunset", icon: "sunset.fill", value: time(today?.sunset), sub: nil, note: "Sunrise \(time(today?.sunrise)).",
                       accessory: sunPath(today, accent: TileAccent.sunset)).accent(TileAccent.sunset)
        }
    }

    /// Today's path of the sun, whichever of sunrise or sunset the tile shows (after sunset, the dot is below the horizon).
    private func sunPath(_ today: Forecast.Day?, accent: UInt32) -> AnyView? {
        guard let sunrise = today?.sunrise, let sunset = today?.sunset else { return nil }
        return AnyView(SunPath(now: forecast.now.time, sunrise: sunrise, sunset: sunset, accent: Color(hex: accent)))
    }
}

struct DetailTile: View {
    @Environment(\.metrics) private var ui
    let title: String
    let icon: String
    let value: String
    let sub: String?
    let note: String
    /// A small picture under the reading: a scale bar, compass, sun path, range, cloud bars or the moon.
    var accessory: AnyView? = nil
    /// The tile's own colour (TileAccent): its icon and title, and a faint glow at the top.
    var accent: UInt32 = TileAccent.neutral

    func accent(_ colour: UInt32) -> DetailTile { var tile = self; tile.accent = colour; return tile }

    var body: some View {
        let tint = Color(hex: accent)
        VStack(alignment: .leading, spacing: ui.pt(4)) {
            Label(title.uppercased(), systemImage: icon)
                .font(ui.font(12, .semibold))
                .foregroundStyle(tint.opacity(0.9))
            // A reading in words ("18° above normal") is set smaller, on up to two lines, as on Android.
            let words = value.count > 7
            Text(value)
                .font(ui.font(words ? 22 : 32, .medium))
                .lineLimit(words ? 2 : 1)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: words)
                .padding(.top, ui.pt(4))
            if let sub {
                Text(sub).font(ui.font(15)).opacity(0.7).lineLimit(1).minimumScaleFactor(0.8)
            }
            if let accessory { accessory.padding(.top, ui.pt(4)) }
            Spacer(minLength: ui.pt(4))
            Text(note)
                .font(ui.font(13))
                .opacity(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .monospacedDigit()
        .foregroundStyle(.white)
        .padding(ui.pt(14))
        // Fills its grid row, so two tiles side by side are always the same height.
        .frame(maxWidth: .infinity, minHeight: ui.pt(160), maxHeight: .infinity, alignment: .topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: ui.pt(16), style: .continuous)
            ZStack {
                Frost(radius: ui.pt(16))
                shape.fill(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0)], startPoint: .top, endPoint: .center))
            }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - More detail tiles

/// Air quality (with pollen where it's measured), averages, visibility, precipitation, clouds and the
/// moon, after the first six tiles. Every city shows all six, so every city has the same twelve tiles:
/// one whose data isn't there yet shows a dash instead of disappearing.
struct ExtraTiles: View {
    @EnvironmentObject private var store: WeatherStore
    let forecast: Forecast
    let city: City

    static let missing = "Not available right now."

    var body: some View {
        let now = forecast.now, unit = store.unit
        let inUS = WeatherAlert.inUS(latitude: city.latitude, longitude: city.longitude)
        let air = store.airQuality[city.id]
        if let reading = air?.reading(inUS: inUS) {
            let pollen = air?.pollenSummary.map { " Pollen: \($0.top.lowercased()) \($0.level.lowercased())." } ?? ""
            DetailTile(title: "Air quality", icon: "aqi.medium", value: "\(reading.value)", sub: reading.category,
                       note: "\(reading.scale). \(reading.note)" + pollen,
                       accessory: AnyView(ScaleBar(colors: inUS ? ScaleBar.usAQI : ScaleBar.europeanAQI, position: reading.position))).accent(TileAccent.air(reading.position))
        } else {
            DetailTile(title: "Air quality", icon: "aqi.medium", value: "–", sub: nil, note: Self.missing).accent(TileAccent.neutral)
        }
        if let today = forecast.days.first?.including(now.temperature), let entry = store.climate[city.id]?.entry(for: today.date),
           let normalHigh = entry.normalHigh, let normalLow = entry.normalLow {
            let accent = TileAccent.versusNormal(today.high - normalHigh)
            DetailTile(title: "Averages", icon: "chart.line.uptrend.xyaxis",
                       value: Climate.comparison(high: today.high, normal: normalHigh, unit: unit), sub: nil,
                       note: "Normal high \(unit.spaced(unit.value(normalHigh))) · \(unit.other.spaced(unit.other.value(normalHigh))), low \(unit.spaced(unit.value(normalLow))) · \(unit.other.spaced(unit.other.value(normalLow))).",
                       accessory: AnyView(RangeBars(normalLow: normalLow, normalHigh: normalHigh, recordLow: entry.recordLow, recordHigh: entry.recordHigh,
                                                    todayLow: today.low, todayHigh: today.high, accent: Color(hex: accent)))).accent(accent)
        } else {
            DetailTile(title: "Averages", icon: "chart.line.uptrend.xyaxis", value: "–", sub: nil, note: Self.missing).accent(TileAccent.neutral)
        }
        if let metres = now.visibility {
            let v = Details.visibility(metres, miles: store.windUnit.usesMiles(unit))
            DetailTile(title: "Visibility", icon: "eye.fill", value: v.value, sub: v.other, note: v.note).accent(TileAccent.visibility)
        } else {
            DetailTile(title: "Visibility", icon: "eye.fill", value: "–", sub: nil, note: Self.missing).accent(TileAccent.visibility)
        }
        if let mm = forecast.days.first?.precipitation {
            let text = store.rainUnit.text(mm, temp: unit)
            let next = Details.next24Hours(forecast)
            DetailTile(title: "Precipitation", icon: "drop.fill", value: text.main, sub: "\(text.other) today",
                       note: next.map { $0 >= 0.1 ? "Expected in the next 24 hours: \(store.rainUnit.text($0, temp: unit).main)." : "None expected in the next 24 hours." } ?? "").accent(TileAccent.rain)
        } else {
            DetailTile(title: "Precipitation", icon: "drop.fill", value: "–", sub: nil, note: Self.missing).accent(TileAccent.rain)
        }
        if let cover = now.cloudCover {
            DetailTile(title: "Cloud cover", icon: "cloud.fill", value: "\(Int(cover.rounded()))%", sub: Details.clouds(cover), note: Details.cloudLayers(forecast) ?? "",
                       accessory: cloudBars()).accent(TileAccent.cloud)
        } else {
            DetailTile(title: "Cloud cover", icon: "cloud.fill", value: "–", sub: nil, note: Self.missing).accent(TileAccent.cloud)
        }
        let moon = Moon.phase(at: Date())
        DetailTile(title: "Moon", icon: "moon.fill", value: moon.name, sub: "\(moon.illumination)% lit", note: Moon.next(at: Date()),
                   accessory: AnyView(MoonDisc(fraction: Moon.fraction(at: Date())))).accent(TileAccent.moon)
    }

    /// Bars for the cloud at each height in the hour nearest now (the hour Details.cloudLayers reads).
    private func cloudBars() -> AnyView? {
        let time = forecast.now.time
        guard let hour = forecast.hours.min(by: { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }),
              let low = hour.cloudLow, let mid = hour.cloudMid, let high = hour.cloudHigh else { return nil }
        return AnyView(CloudBars(low: low, mid: mid, high: high, accent: Color(hex: TileAccent.cloud)))
    }
}
