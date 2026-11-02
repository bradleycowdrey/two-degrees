import Charts
import SwiftUI
import WebKit

// 0.5 on iPhone: severe weather alerts, the next two hours, the rain map, more detail tiles, and the
// day detail. Rules and words are in design/weather-features.md and WeatherExtras.swift.

// MARK: - Severe weather alerts

/// One card per active alert, most severe first; tap for the full text.
struct AlertCards: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let city: City
    @State private var open: WeatherAlert?

    var body: some View {
        ForEach(store.alerts[city.id] ?? []) { alert in
            Button { open = alert } label: {
                HStack(alignment: .top, spacing: ui.pt(10)) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(ui.font(18, .semibold))
                        .foregroundStyle(Color(hex: alert.colorHex))
                    VStack(alignment: .leading, spacing: ui.pt(2)) {
                        Text(alert.event).font(ui.font(17, .semibold))
                        Text([alert.untilText, alert.sender].compactMap { $0 }.joined(separator: " · "))
                            .font(ui.font(13)).opacity(0.75)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(ui.font(13, .semibold)).opacity(0.5)
                }
                .foregroundStyle(.white)
                .padding(ui.pt(14))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: alert.colorHex).opacity(0.22), in: RoundedRectangle(cornerRadius: ui.pt(16), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ui.pt(16), style: .continuous).strokeBorder(Color(hex: alert.colorHex).opacity(0.6), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(alert.severity) alert: \(alert.event). \(alert.untilText ?? "")")
        }
        .sheet(item: $open) { alert in AlertDetail(alert: alert) }
    }
}

private struct AlertDetail: View {
    let alert: WeatherAlert
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(alert.headline).font(.headline)
                    if let until = alert.untilText { Text(until).foregroundStyle(.secondary) }
                    Text(alert.description).font(.body)
                    if let instruction = alert.instruction, !instruction.isEmpty {
                        Text("What to do").font(.headline)
                        Text(instruction)
                    }
                    Link("More at weather.gov", destination: URL(string: "https://www.weather.gov")!)
                    Text("From the US National Weather Service (\(alert.sender)). Alerts can be late or missing: follow official warnings.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(alert.event)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - The next two hours

/// Shown only when there's precipitation now or in the next two hours: 15-minute bars and one line.
struct NextHoursCard: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let forecast: Forecast

    var body: some View {
        if let steps = forecast.steps, let sentence = NextHours.sentence(forecast) {
            let peak = max(steps.map(\.precipitation).max() ?? 0, 0.5)
            let snow = Condition.isSnow(forecast.now.code)
            Card(title: "Next 2 hours", icon: snow ? "cloud.snow.fill" : "cloud.rain.fill") {
                Text(sentence).font(ui.font(15))
                HStack(alignment: .bottom, spacing: ui.pt(6)) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        VStack(spacing: ui.pt(4)) {
                            Capsule()
                                .fill(snow ? Color.white : Palette.rain)
                                .frame(height: max(ui.pt(3), ui.pt(54) * CGFloat(step.precipitation / peak)))
                                .opacity(step.precipitation >= NextHours.wetStep ? 1 : 0.25)
                            Text(index == 0 ? "Now" : (index % 2 == 0 ? "\(index * 15)m" : " "))
                                .font(ui.font(11)).opacity(0.7).lineLimit(1).fixedSize()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: ui.pt(76), alignment: .bottom)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(sentence)
                let total = steps.prefix(4).map(\.precipitation).reduce(0, +)
                if total > 0 {
                    Text("About \(store.rainUnit.text(total, temp: store.unit).main) in the next hour")
                        .font(ui.font(13)).opacity(0.7)
                }
            }
        }
    }
}

// MARK: - Rain map

struct MapCard: View {
    @Environment(\.metrics) private var ui
    @EnvironmentObject private var store: WeatherStore
    let city: City
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: ui.pt(12)) {
                Image(systemName: "map.fill").font(ui.font(20)).foregroundStyle(Palette.rain)
                VStack(alignment: .leading, spacing: ui.pt(2)) {
                    Text("Rain Map").font(ui.font(17, .semibold))
                    Text("Radar for the last two hours").font(ui.font(13)).opacity(0.7)
                }
                Spacer()
                Image(systemName: "chevron.right").font(ui.font(13, .semibold)).opacity(0.5)
            }
            .foregroundStyle(.white)
            .padding(ui.pt(14))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ui.pt(16), style: .continuous))
            .environment(\.colorScheme, .dark)
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showing) { RadarScreen(city: city, unit: store.unit) }
    }
}

/// The shared rain map page (web/radar.html) in a web view, with Done.
struct RadarScreen: View {
    let city: City
    let unit: TempUnit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            WebPage(url: Self.url(for: city, unit: unit)).ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .foregroundStyle(.white)
            .padding(.leading, 12)
            .padding(.top, 4)
            .accessibilityLabel("Close the map")
        }
        .background(Palette.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    static func url(for city: City, unit: TempUnit) -> URL {
        URL(string: String(format: "https://bradleycowdrey.github.io/two-degrees/radar.html?lat=%.2f&lon=%.2f&z=7&units=%@", city.latitude, city.longitude, unit.rawValue))!
    }
}

private struct WebPage: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isOpaque = false
        view.backgroundColor = UIColor(Palette.bg)
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

// MARK: - More detail tiles

/// Air quality (with pollen where it's measured), averages, visibility, precipitation, clouds and the
/// moon, after the first six tiles. Every city shows all six, so every city has the same twelve tiles:
/// one whose data isn't there yet shows a dash instead of disappearing.
struct ExtraTiles: View {
    @EnvironmentObject private var store: WeatherStore
    let forecast: Forecast
    let city: City

    private static let missing = "Not available right now."

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
            DetailTile(title: "Averages", icon: "chart.line.uptrend.xyaxis",
                       value: Climate.comparison(high: today.high, normal: normalHigh, unit: unit), sub: nil,
                       note: "Normal high \(unit.spaced(unit.value(normalHigh))) · \(unit.other.spaced(unit.other.value(normalHigh))), low \(unit.spaced(unit.value(normalLow))) · \(unit.other.spaced(unit.other.value(normalLow))).").accent(TileAccent.versusNormal(today.high - normalHigh))
        } else {
            DetailTile(title: "Averages", icon: "chart.line.uptrend.xyaxis", value: "–", sub: nil, note: Self.missing).accent(TileAccent.neutral)
        }
        if let metres = now.visibility {
            let v = Details.visibility(metres, miles: store.windUnit.usesMiles(unit))
            DetailTile(title: "Visibility", icon: "eye.fill", value: v.value, sub: nil, note: v.note).accent(TileAccent.visibility)
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
            DetailTile(title: "Cloud cover", icon: "cloud.fill", value: "\(Int(cover.rounded()))%", sub: Details.clouds(cover), note: Details.cloudLayers(forecast) ?? "").accent(TileAccent.cloud)
        } else {
            DetailTile(title: "Cloud cover", icon: "cloud.fill", value: "–", sub: nil, note: Self.missing).accent(TileAccent.cloud)
        }
        let moon = Moon.phase(at: Date())
        DetailTile(title: "Moon", icon: "moon.fill", value: moon.name, sub: "\(moon.illumination)% lit", note: Moon.next(at: Date()),
                   accessory: AnyView(MoonDisc(fraction: Moon.fraction(at: Date())))).accent(TileAccent.moon)
    }
}

// MARK: - Day detail

/// A day in full: the reading, then temperature, rain and wind charts, and the facts. Arrows move
/// between days.
struct DayDetailView: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    @Environment(\.dismiss) private var dismiss
    let city: City
    let days: [Forecast.Day]
    @Binding var selection: Date?

    var body: some View {
        let forecast = store.forecasts[city.id]
        let index = days.firstIndex { $0.date == selection } ?? 0
        NavigationStack {
            // Swipe left and right between days, as well as the arrows.
            TabView(selection: Binding(get: { selection ?? days.first?.date ?? Date() }, set: { selection = $0 })) {
                ForEach(Array(days.enumerated()), id: \.element.date) { i, day in
                    ScrollView {
                        if let forecast {
                            DayDetailContent(forecast: forecast, day: i == 0 ? day.including(forecast.now.temperature) : day,
                                             isToday: i == 0, city: city)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 32)
                                .frame(maxWidth: ui.pt(600))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .tag(day.date)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(days.indices.contains(index) ? Forecast.format(days[index].date, "EEEEMMMd") : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { selection = days[index - 1].date } label: { Image(systemName: "chevron.left") }
                        .disabled(index == 0).accessibilityLabel("Previous day")
                    Button { selection = days[index + 1].date } label: { Image(systemName: "chevron.right") }
                        .disabled(index >= days.count - 1).accessibilityLabel("Next day")
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
    }
}

private struct DayDetailContent: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let forecast: Forecast
    let day: Forecast.Day
    let isToday: Bool
    let city: City

    var body: some View {
        let unit = store.unit, other = unit.other
        let hours = forecast.hours(on: day)
        VStack(alignment: .leading, spacing: ui.pt(12)) {
            HStack(alignment: .center, spacing: ui.pt(12)) {
                WeatherSymbol(code: day.code, isDay: true, size: ui.pt(40))
                VStack(alignment: .leading, spacing: ui.pt(2)) {
                    Text(Condition.name(day.code)).font(ui.font(20, .semibold))
                    Text("H:\(unit.value(day.high))\(unit.symbol)  L:\(unit.value(day.low))\(unit.symbol)").font(ui.font(17, .medium))
                    Text("H:\(other.value(day.high))\(other.symbol)  L:\(other.value(day.low))\(other.symbol)").font(ui.font(14)).opacity(0.65)
                }
                Spacer()
                if day.rainChance > 0 {
                    VStack(spacing: 0) {
                        Text("\(day.rainChance)%").font(ui.font(20, .semibold)).foregroundStyle(Palette.rain)
                        Text("rain").font(ui.font(12)).opacity(0.7)
                    }
                }
            }
            .padding(.top, ui.pt(12))
            .foregroundStyle(.white)

            if !hours.isEmpty {
                Card(title: "Temperature", icon: "thermometer.medium") { TemperatureChart(hours: hours, now: isToday ? forecast.now.time : nil) }
                Card(title: "Rain", icon: "drop.fill") {
                    RainChart(hours: hours)
                    if let mm = day.precipitation {
                        Text("Total \(store.rainUnit.text(mm, temp: unit).main) · \(store.rainUnit.text(mm, temp: unit).other)").font(ui.font(14)).opacity(0.8)
                    }
                }
                if hours.contains(where: { $0.wind != nil }) {
                    Card(title: "Wind", icon: "wind") {
                        WindChart(hours: hours)
                        if let direction = day.windDirection {
                            Text("Mostly from the \(Meteo.compassName(direction))").font(ui.font(14)).opacity(0.8)
                        }
                    }
                }
            }
            Card(title: "Details", icon: "list.bullet") { facts }
        }
    }

    @ViewBuilder
    private var facts: some View {
        let unit = store.unit, other = unit.other
        let time = { (date: Date?) in date.map { Forecast.format($0, "jmm") } ?? "–" }
        let sky = { (date: Date?) -> String in
            guard let date else { return "–" }
            return time(date) + (SkyColour.outlook(forecast, at: date).map { " · \($0.rating.word) colour" } ?? "")
        }
        VStack(spacing: ui.pt(8)) {
            fact("Sunrise", sky(day.sunrise))
            fact("Sunset", sky(day.sunset))
            if let uv = day.uvIndex { fact("UV index", "\(Int(uv.rounded())) · \(Meteo.uvLevel(uv))") }
            if let gust = day.gustMax { fact("Strongest gust", store.windUnit.text(gust, temp: unit).main) }
            if let entry = store.climate[city.id]?.entry(for: day.date) {
                if let h = entry.normalHigh, let l = entry.normalLow {
                    fact("Normal", "H:\(unit.value(h))\(unit.symbol) L:\(unit.value(l))\(unit.symbol) · H:\(other.value(h))\(other.symbol) L:\(other.value(l))\(other.symbol)")
                }
                if let h = entry.recordHigh, let year = entry.recordHighYear {
                    fact("Record high", "\(unit.spaced(unit.value(h))) · \(other.spaced(other.value(h))) (\(String(year)))")
                }
                if let l = entry.recordLow, let year = entry.recordLowYear {
                    fact("Record low", "\(unit.spaced(unit.value(l))) · \(other.spaced(other.value(l))) (\(String(year)))")
                }
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(ui.font(15)).opacity(0.7)
            Spacer()
            Text(value).font(ui.font(15, .medium)).multilineTextAlignment(.trailing)
        }
        .monospacedDigit()
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tile pictures

/// A thin bar in a scale's colours with a dot at the reading (0–1): air quality and UV.
struct ScaleBar: View {
    let colors: [Color]
    let position: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)).frame(height: 5)
                Circle().fill(.white).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1))
                    .offset(x: max(0, min(geo.size.width - 9, geo.size.width * position - 4.5)))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    static let uv: [Color] = [Color(hex: 0x3EA72D), Color(hex: 0xFFF300), Color(hex: 0xF18B00), Color(hex: 0xE53210), Color(hex: 0xB567A4)]
    static let usAQI: [Color] = [Color(hex: 0x00E400), Color(hex: 0xFFFF00), Color(hex: 0xFF7E00), Color(hex: 0xFF0000), Color(hex: 0x8F3F97), Color(hex: 0x7E0023)]
    static let europeanAQI: [Color] = [Color(hex: 0x50F0E6), Color(hex: 0x50CCAA), Color(hex: 0xF0E641), Color(hex: 0xFF5050), Color(hex: 0x960032), Color(hex: 0x7D2181)]
}

/// The moon as it looks tonight: the lit part over a dim disc (0 new, 0.5 full).
struct MoonDisc: View {
    let fraction: Double
    var size: CGFloat = 26

    var body: some View {
        Canvas { context, canvas in
            let r = min(canvas.width, canvas.height) / 2, c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.18)))
            let k = cos(2 * .pi * fraction), waxing = fraction < 0.5
            var lit = Path()
            // The lit half…
            lit.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: !waxing)
            // …then the terminator back up: an ellipse half, bulging toward the lit side for a crescent.
            let rx = abs(k) * r
            let steps = 32
            for i in 0...steps {
                let t = Double.pi / 2 - Double.pi * Double(i) / Double(steps)   // from bottom (π/2) to top (−π/2)
                let bulgeLit = (k > 0) // crescent: terminator on the lit side
                let side: CGFloat = (waxing ? 1 : -1) * (bulgeLit ? 1 : -1)
                lit.addLine(to: CGPoint(x: c.x + side * rx * CGFloat(cos(t)), y: c.y + r * CGFloat(sin(t))))
            }
            lit.closeSubpath()
            context.fill(lit, with: .color(Color(hex: 0xF4E9D8)))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
