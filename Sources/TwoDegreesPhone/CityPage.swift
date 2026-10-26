import SwiftUI

/// One city, laid out like Apple's Weather: a large centred reading that shrinks into a one-line bar as
/// you scroll, then frosted cards for the next 24 hours and 10 days, then a grid of detail tiles.
/// Two Degrees' difference throughout: every temperature in both units, the larger one first.
struct CityPage: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let city: City
    /// How far the header has scrolled up (0 at rest, negative as it goes).
    @State private var offset: CGFloat = 0
    /// Height of the pinned one-line header; the page is hidden beneath it, as in Apple's Weather.
    @State private var bandHeight: CGFloat = 0

    var body: some View {
        let forecast = store.forecasts[city.id]
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                VStack(spacing: ui.pt(10)) {
                    header(forecast)
                        .padding(.top, ui.pt(36))
                        .padding(.bottom, ui.pt(26))
                        // Where the header is in the scroll view, read on every scroll.
                        .onGeometryChange(for: CGFloat.self) { proxy in proxy.frame(in: .named("page")).minY } action: { offset = $0 }
                    if let forecast {
                        HourlyCard(forecast: forecast)
                        DailyCard(forecast: forecast).id("days")
                        DetailTiles(forecast: forecast).id("tiles")
                        footer
                    } else {
                        Card(title: "Forecast", icon: "clock") {
                            HStack(spacing: ui.m) {
                                if store.failed.contains(city.id) {
                                    Image(systemName: "wifi.exclamationmark")
                                    Text("Couldn’t reach Open-Meteo. Pull down to try again.")
                                } else {
                                    ProgressView()
                                    Text("Loading the forecast for \(city.name)…")
                                }
                            }
                            .font(ui.font(15))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, ui.pt(16))
                .padding(.bottom, ui.pt(72))             // room above the bottom bar
                .frame(maxWidth: ui.pt(600))             // iPad: a readable column, scaled with the text
                .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: "page")
            .refreshable { await store.refresh() }
            // Once the one-line header is pinned, the page scrolls away under it instead of showing through.
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: collapse > 0.75 ? bandHeight : 0)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: collapse > 0.75 ? ui.pt(10) : 0)
                    Color.black
                }
            }
            .overlay(alignment: .top) { compactHeader(forecast) }
            .task {
                if PhoneSelfTest.showDays && city.id == store.activeID {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { reader.scrollTo("days", anchor: .top) }
                }
                if PhoneSelfTest.showTiles && city.id == store.activeID {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { reader.scrollTo("tiles", anchor: .bottom) }
                }
            }
        }
    }

    /// 0 at rest, 1 once the header has scrolled away.
    private var collapse: CGFloat { min(max(-offset / ui.pt(150), 0), 1) }

    private func header(_ forecast: Forecast?) -> some View {
        let unit = store.unit, other = unit.other
        return VStack(spacing: ui.pt(2)) {
            Text(city.name)
                .font(ui.font(34))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let forecast {
                let now = forecast.now
                // Tap the reading to swap which unit is large.
                Button { withAnimation(.snappy) { store.toggleUnit() } } label: {
                    // As in the widgets: the big number with its unit smaller and raised, then the other
                    // unit whole, on the same baseline.
                    HStack(alignment: .firstTextBaseline, spacing: ui.pt(8)) {
                        Reading.text(unit.value(now.temperature), unit, size: ui.pt(96), weight: .thin, unitWeight: .light)
                            .tracking(-2)
                        Text("\(other.value(now.temperature))\(other.symbol)")
                            .font(.system(size: ui.pt(96 * 0.45), weight: .light))
                            .opacity(0.7)
                    }
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Speech.temperature(now.temperature))
                .accessibilityHint("Double-tap to show \(other.symbol) large")
                Text(Condition.name(now.code))
                    .font(ui.font(20, .medium))
                    .opacity(0.9)
                if let today = forecast.days.first?.including(now.temperature) {
                    Text("H:\(unit.value(today.high))\(unit.symbol)  L:\(unit.value(today.low))\(unit.symbol)")
                        .font(ui.font(20, .medium))
                    Text("H:\(other.value(today.high))\(other.symbol)  L:\(other.value(today.low))\(other.symbol)")
                        .font(ui.font(15))
                        .opacity(0.65)
                }
            } else {
                Text("––°").font(.system(size: ui.pt(96), weight: .thin)).opacity(0.5)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .opacity(1 - collapse * 1.3)
        .frame(maxWidth: .infinity)
    }

    /// The reading on one line, pinned at the top once the big header has scrolled away.
    @ViewBuilder
    private func compactHeader(_ forecast: Forecast?) -> some View {
        if let forecast, collapse > 0.75 {
            let now = forecast.now, unit = store.unit, other = unit.other
            VStack(spacing: ui.pt(2)) {
                Text(city.name).font(ui.font(28))
                Text("\(unit.value(now.temperature))\(unit.symbol) · \(other.value(now.temperature))\(other.symbol)  |  \(Condition.name(now.code))")
                    .font(ui.font(16, .medium))
                    .monospacedDigit()
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, ui.pt(16))
            .padding(.top, ui.pt(6))
            .padding(.bottom, ui.pt(10))
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bandHeight = $0 }
            .opacity(Double((collapse - 0.75) * 4))
            .accessibilityHidden(true)
        }
    }

    private var footer: some View {
        VStack(spacing: ui.pt(6)) {
            HStack(spacing: ui.pt(4)) {
                Text("Weather for \(city.name)")
                Text("·")
                Link("Open-Meteo", destination: Brand.dataCredit).underline()
            }
            if let fetched = store.forecasts[city.id]?.fetchedAt {
                Text(store.failed.contains(city.id) ? "Offline · from \(fetched.formatted(date: .omitted, time: .shortened))"
                                                    : "Updated \(fetched.formatted(date: .omitted, time: .shortened))")
            }
            Link(destination: Brand.website) { Text("Made by \(Brand.author). Free. Forever.") }
        }
        .font(ui.font(13))
        .foregroundStyle(.white.opacity(0.6))
        .frame(maxWidth: .infinity)
        .padding(.top, ui.pt(8))
    }
}

// MARK: - Cards

/// A frosted card with a small uppercase title, as in Apple's Weather.
struct Card<Content: View>: View {
    @Environment(\.metrics) private var ui
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ui.pt(10)) {
            Label(title.uppercased(), systemImage: icon)
                .font(ui.font(12, .semibold))
                .foregroundStyle(.white.opacity(0.6))
            content
        }
        .foregroundStyle(.white)
        .padding(ui.pt(14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ui.pt(16), style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

private struct HourlyCard: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let forecast: Forecast

    var body: some View {
        let unit = store.unit, other = unit.other
        let hours = forecast.upcomingHours
        Card(title: "Next 24 hours", icon: "clock") {
            let summary = Summary.line(forecast, unit: unit)
            if !summary.isEmpty {
                Text(summary).font(ui.font(15)).fixedSize(horizontal: false, vertical: true)
                Divider().overlay(Color.white.opacity(0.2))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                        let temperature = index == 0 ? forecast.now.temperature : hour.temperature
                        VStack(spacing: ui.pt(8)) {
                            Text(index == 0 ? "Now" : Forecast.format(hour.time, "j"))
                                .font(ui.font(15, .semibold))
                            VStack(spacing: ui.pt(1)) {
                                WeatherSymbol(code: index == 0 ? forecast.now.code : hour.code, isDay: hour.isDay, size: ui.pt(22))
                                    .frame(height: ui.pt(26))
                                Text(hour.rainChance >= 20 ? "\(hour.rainChance)%" : " ")
                                    .font(ui.font(11, .semibold))
                                    .foregroundStyle(Palette.rain)
                            }
                            Text("\(unit.value(temperature))°").font(ui.font(18, .medium))
                            Text("\(other.value(temperature))\(other.symbol)").font(ui.font(13)).opacity(0.6)
                        }
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: ui.pt(62))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(index == 0 ? "Now" : Forecast.format(hour.time, "j")): \(Condition.name(hour.code)), \(Speech.temperature(temperature))")
                    }
                }
            }
        }
    }
}

private struct DailyCard: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let forecast: Forecast

    var body: some View {
        let days = Array(forecast.days.prefix(10))
        let now = forecast.now.temperature
        let low = min(now, days.map(\.low).min() ?? now), high = max(now, days.map(\.high).max() ?? now)
        Card(title: "\(days.count)-day forecast", icon: "calendar") {
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Divider().overlay(Color.white.opacity(0.2))
                    DailyRow(day: index == 0 ? day.including(now) : day, isToday: index == 0,
                             scaleLow: low, scaleHigh: high, now: index == 0 ? now : nil)
                }
            }
        }
    }
}

private struct DailyRow: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let day: Forecast.Day
    let isToday: Bool
    let scaleLow: Double
    let scaleHigh: Double
    let now: Double?

    var body: some View {
        let unit = store.unit, other = unit.other
        let name = isToday ? "Today" : Forecast.format(day.date, "EEE")
        HStack(spacing: ui.pt(10)) {
            Text(name)
                .font(ui.font(18, .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: ui.pt(52), alignment: .leading)
            VStack(spacing: 0) {
                WeatherSymbol(code: day.code, isDay: true, size: ui.pt(20))
                if day.rainChance >= 20 {
                    Text("\(day.rainChance)%").font(ui.font(11, .semibold)).foregroundStyle(Palette.rain).fixedSize()
                }
            }
            .frame(width: ui.pt(36))
            temperature(day.low, alignment: .trailing).opacity(0.65)
            bar
            temperature(day.high, alignment: .leading)
        }
        .monospacedDigit()
        .frame(minHeight: ui.pt(48))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(Condition.name(day.code)). Low \(Speech.temperature(day.low)). High \(Speech.temperature(day.high)).\(day.rainChance >= 20 ? " \(day.rainChance) percent chance of rain." : "")")
    }

    private func temperature(_ celsius: Double, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text("\(store.unit.value(celsius))°").font(ui.font(17, .medium))
            Text("\(store.unit.other.value(celsius))\(store.unit.other.symbol)").font(ui.font(11)).opacity(0.6)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        // Wide enough for "100°F" on one line.
        .frame(width: ui.pt(50), alignment: alignment == .leading ? .leading : .trailing)
    }

    /// This day's low to high on the ten days' shared scale, with a dot for right now on today.
    private var bar: some View {
        GeometryReader { proxy in
            let span = max(scaleHigh - scaleLow, 1)
            let x = { (t: Double) in CGFloat((t - scaleLow) / span) * proxy.size.width }
            let h = ui.pt(5)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [Palette.temperature(day.low), Palette.temperature(day.high)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(x(day.high) - x(day.low), h))
                    .offset(x: x(day.low))
                if let now {
                    Circle().fill(.white)
                        .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1.5))
                        .frame(width: h + 3, height: h + 3)
                        .offset(x: min(max(x(now) - (h + 3) / 2, 0), proxy.size.width - h - 3))
                }
            }
            .frame(height: h)
            .frame(maxHeight: .infinity)
        }
        .frame(height: ui.pt(20))
    }
}

// MARK: - Detail tiles

/// Square tiles two across, like the bottom half of Apple's Weather.
private struct DetailTiles: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let forecast: Forecast

    var body: some View {
        let now = forecast.now, unit = store.unit, other = unit.other
        let today = forecast.days.first?.including(now.temperature)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: ui.pt(10)), GridItem(.flexible(), spacing: ui.pt(10))], spacing: ui.pt(10)) {
            DetailTile(title: "Feels like", icon: "thermometer.medium",
                 value: "\(unit.value(now.feelsLike))\(unit.symbol)", sub: "\(other.value(now.feelsLike))\(other.symbol)",
                 note: feelsNote(now))
            DetailTile(title: "Humidity", icon: "humidity",
                 value: "\(Int(now.humidity.rounded()))%", sub: nil,
                 note: dewNote(now))
            DetailTile(title: "Wind", icon: "wind",
                 value: unit == .fahrenheit ? "\(mph(now.wind)) mph" : "\(Int(now.wind.rounded())) km/h",
                 sub: unit == .fahrenheit ? "\(Int(now.wind.rounded())) km/h" : "\(mph(now.wind)) mph",
                 note: windNote(now))
            DetailTile(title: "Rain", icon: "drop.fill",
                 value: "\(today?.rainChance ?? 0)%", sub: "chance today",
                 note: rainNote)
            sunTile(today)
            uvTile(today)
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
        return now.windDirection.map { "\(strength) from the \(Meteo.compassName($0))." } ?? "\(strength)."
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
                       note: uv >= 3 ? "Use sun protection around midday." : "Low for the rest of the day.")
        } else {
            DetailTile(title: "UV index", icon: "sun.max.fill", value: "–", sub: nil, note: "Pull down to refresh.")
        }
    }

    private var rainNote: String {
        // Same rule and words as the hourly summary (Summary.line), so the two never disagree.
        if let wet = forecast.upcomingHours.dropFirst().prefix(12).first(where: { $0.rainChance >= 50 }) {
            let what = Condition.isSnow(wet.code) ? "Snow" : ([95, 96, 99].contains(wet.code) ? "Storms" : "Rain")
            return "\(what) likely around \(Forecast.format(wet.time, "j"))."
        }
        return "None expected in the next 12 hours."
    }

    @ViewBuilder
    private func sunTile(_ today: Forecast.Day?) -> some View {
        let time = { (date: Date?) in date.map { Forecast.format($0, "jmm") } ?? "–" }
        if let sunset = today?.sunset, forecast.now.time < sunset {
            DetailTile(title: "Sunset", icon: "sunset.fill", value: time(sunset), sub: nil, note: "Sunrise: \(time(today?.sunrise))")
        } else {
            let tomorrow = forecast.days.dropFirst().first
            DetailTile(title: "Sunrise", icon: "sunrise.fill", value: time(tomorrow?.sunrise), sub: nil, note: "Sunset: \(time(tomorrow?.sunset))")
        }
    }
}

private struct DetailTile: View {
    @Environment(\.metrics) private var ui
    let title: String
    let icon: String
    let value: String
    let sub: String?
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: ui.pt(4)) {
            Label(title.uppercased(), systemImage: icon)
                .font(ui.font(12, .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(ui.font(32, .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, ui.pt(4))
            if let sub {
                Text(sub).font(ui.font(15)).opacity(0.7).lineLimit(1)
            }
            Spacer(minLength: ui.pt(4))
            Text(note)
                .font(ui.font(13))
                .opacity(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .monospacedDigit()
        .foregroundStyle(.white)
        .padding(ui.pt(14))
        .frame(maxWidth: .infinity, minHeight: ui.pt(160), alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ui.pt(16), style: .continuous))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }
}
