import SwiftUI

// A city's page, shared by the iPhone app (CityPage) and the Mac app (WeatherPanel): the centred
// reading, the frosted cards for the next 24 hours and 10 days, alerts, the next two hours, the way to
// the rain map, and the footer. The detail tiles are in Tiles.swift.

/// The frosted surface behind every card and tile.
struct Frost: View {
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        #if os(macOS)
        // On the Mac the frost is a plain mix, matched to the iPhone's over the same skies. Only the sky
        // is ever behind a card, so there's nothing to blur, and the self-test photographs it as drawn.
        shape.fill(Color(white: 0.23).opacity(0.55))
        #else
        shape.fill(.ultraThinMaterial)
        #endif
    }
}

// MARK: - The reading

/// The top of a city's page, centred: "My Location" where you are, the city, the big reading with the
/// other unit beside it, the condition, then today's high and low in both units.
struct CityHeader: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let city: City
    let forecast: Forecast?
    /// Where the city is and its local time, under its name: the Mac, which has no city list to show them.
    var detail: String? = nil

    var body: some View {
        let unit = store.unit, other = unit.other
        VStack(spacing: ui.pt(2)) {
            if store.isHere(city) {
                Label("My Location", systemImage: "location.fill")
                    .font(ui.font(13, .semibold))
                    .textCase(.uppercase)
                    .opacity(0.8)
            }
            Text(city.name)
                .font(ui.font(34))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(ui.font(13))
                    .opacity(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let forecast {
                let now = forecast.now
                // Tap the reading to swap which unit is large.
                Button { withAnimation(.snappy) { store.toggleUnit() } } label: {
                    // As in the widgets: the big number with its unit smaller and raised, then the other
                    // unit whole, on the same baseline.
                    HStack(alignment: .firstTextBaseline, spacing: ui.pt(8)) {
                        Reading.text(unit.value(now.temperature), unit, size: ui.pt(96), weight: .thin, unitWeight: .light)
                            .tracking(-2)
                        Text(other.spaced(other.value(now.temperature)))
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
                .accessibilityHint("Shows \(other.label) large")
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
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Footer

/// The footer every screen ends with, in one style: where the weather comes from (linked), when it
/// was updated (or that it's offline), and the sign-off.
struct AppFooter: View {
    @Environment(\.metrics) private var ui
    /// "Weather for Denver"; nil for the city list, which credits the city search too.
    let lead: String?
    let fetched: Date?
    let offline: Bool

    var body: some View {
        VStack(spacing: ui.pt(6)) {
            HStack(spacing: ui.pt(4)) {
                if let lead {
                    Text(lead)
                    Text("·")
                    Link("Open-Meteo", destination: Brand.dataCredit).underline()
                } else {
                    Text("Weather by")
                    Link("Open-Meteo", destination: Brand.dataCredit).underline()
                    Text("· Places by")
                    Link("GeoNames", destination: URL(string: "https://www.geonames.org")!).underline()
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            if let fetched {
                Text(offline ? "Offline · from \(fetched.formatted(date: .omitted, time: .shortened))"
                             : "Updated \(fetched.formatted(date: .omitted, time: .shortened))")
            }
            Link(destination: Brand.website) { Text("Made by \(Brand.author). Free. Forever.") }
        }
        .font(ui.font(13))
        .foregroundStyle(.white.opacity(0.6))
        .tint(.white.opacity(0.6))
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
        .background { Frost(radius: ui.pt(16)) }
        .environment(\.colorScheme, .dark)
    }
}

struct HourlyCard: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let forecast: Forecast

    var body: some View {
        let unit = store.unit, other = unit.other
        let hours = forecast.upcomingHours
        // The chance line is kept or dropped for every column together, so they stay aligned.
        let showsChance = hours.contains { $0.rainChance >= 20 }
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
                                if showsChance {
                                    Text(hour.rainChance >= 20 ? "\(hour.rainChance)%" : " ")
                                        .font(ui.font(11, .semibold))
                                        .foregroundStyle(Palette.rain)
                                }
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

/// The 10-day forecast. A row opens that day in detail: the iPhone shows its sheet from `selected`,
/// the Mac a popover from the row.
struct DailyCard: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let forecast: Forecast
    let city: City
    /// The day shown in detail (tap or click a row).
    @Binding var selected: Date?

    /// The days the card lists.
    nonisolated static func days(_ forecast: Forecast) -> [Forecast.Day] { Array(forecast.days.prefix(10)) }

    /// One scale for every bar: the lowest low to the highest high, stretched to take in right now.
    nonisolated static func scale(_ days: [Forecast.Day], now: Double) -> (low: Double, high: Double) {
        (min(now, days.map(\.low).min() ?? now), max(now, days.map(\.high).max() ?? now))
    }

    var body: some View {
        let days = Self.days(forecast)
        let now = forecast.now.temperature
        let scale = Self.scale(days, now: now)
        Card(title: "\(days.count)-day forecast", icon: "calendar") {
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Divider().overlay(Color.white.opacity(0.2))
                    row(index == 0 ? day.including(now) : day, isToday: index == 0, scale: scale, now: index == 0 ? now : nil)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ day: Forecast.Day, isToday: Bool, scale: (low: Double, high: Double), now: Double?) -> some View {
        let button = Button { selected = day.date } label: {
            DailyRow(day: day, isToday: isToday, scaleLow: scale.low, scaleHigh: scale.high, now: now)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the day in detail")
        #if os(macOS)
        button
            .help("Show \(isToday ? "today" : Forecast.format(day.date, "EEEE")) in detail")
            .popover(isPresented: Binding(get: { selected == day.date }, set: { if !$0 { selected = nil } }), arrowEdge: .leading) {
                DayDetailPopover(city: city, forecast: forecast, day: day, isToday: isToday)
                    .environmentObject(store)
                    .environment(\.metrics, ui)
            }
        #else
        button
        #endif
    }
}

struct DailyRow: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let day: Forecast.Day
    let isToday: Bool
    let scaleLow: Double
    let scaleHigh: Double
    let now: Double?

    var body: some View {
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
            temperature(day.low, alignment: .trailing, primary: 0.65)
            bar
            temperature(day.high, alignment: .leading)
        }
        .monospacedDigit()
        .frame(minHeight: ui.pt(48))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(Condition.name(day.code)). Low \(Speech.temperature(day.low)). High \(Speech.temperature(day.high)).\(day.rainChance >= 20 ? " \(day.rainChance) percent chance of rain." : "")")
    }

    private func temperature(_ celsius: Double, alignment: HorizontalAlignment, primary: Double = 1) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text("\(store.unit.value(celsius))°").font(ui.font(17, .medium)).opacity(primary)
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

// MARK: - Severe weather alerts

/// One card per active alert, most severe first; tap or click for the full text (a sheet on iPhone, a
/// popover on the Mac).
struct AlertCards: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let city: City
    @State private var open: WeatherAlert?

    var body: some View {
        let cards = ForEach(store.alerts[city.id] ?? []) { alert in card(alert) }
        #if os(iOS)
        cards.sheet(item: $open) { alert in AlertDetail(alert: alert) }
        #else
        cards
        #endif
    }

    @ViewBuilder
    private func card(_ alert: WeatherAlert) -> some View {
        let button = Button { open = alert } label: {
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
        #if os(macOS)
        button.popover(item: Binding(get: { open?.id == alert.id ? open : nil }, set: { open = $0 })) { alert in
            AlertPopover(alert: alert)
        }
        #else
        button
        #endif
    }
}

#if os(iOS)
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
#else
private struct AlertPopover: View {
    let alert: WeatherAlert

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(alert.headline).font(.headline)
                Text(alert.description)
                if let instruction = alert.instruction, !instruction.isEmpty {
                    Text("What to do").font(.headline)
                    Text(instruction)
                }
                Link("More at weather.gov ↗", destination: URL(string: "https://www.weather.gov")!)
                Text("From the US National Weather Service. Alerts can be late or missing: follow official warnings.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 380, alignment: .leading)
        }
        .frame(maxHeight: 460)
    }
}
#endif

// MARK: - Rain map

/// The way to the rain map: the radar in the app on iPhone, the same page in the browser on the Mac.
struct RainMapCard: View {
    @Environment(\.metrics) private var ui
    /// The arrow at the trailing edge: on into the app, or out to the browser.
    var arrow = "chevron.right"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ui.pt(12)) {
                Image(systemName: "map.fill").font(ui.font(20)).foregroundStyle(Palette.rain)
                VStack(alignment: .leading, spacing: ui.pt(2)) {
                    Text("Rain Map").font(ui.font(17, .semibold))
                    Text("Radar for the last two hours").font(ui.font(13)).opacity(0.7)
                }
                Spacer()
                Image(systemName: arrow).font(ui.font(13, .semibold)).opacity(0.5)
            }
            .foregroundStyle(.white)
            .padding(ui.pt(14))
            .background { Frost(radius: ui.pt(16)) }
            .environment(\.colorScheme, .dark)
        }
        .buttonStyle(.plain)
    }
}
