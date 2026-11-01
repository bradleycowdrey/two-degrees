import AppKit
import SwiftUI

// 0.5 in the Mac panel: severe weather alerts, the next two hours, the details grid, the rain map
// and the day detail. Rules and words are in design/weather-features.md and WeatherExtras.swift.

/// One line per active alert, most severe first; click for the full text.
struct AlertsTile: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let city: City
    @State private var open: WeatherAlert?

    var body: some View {
        ForEach(store.alerts[city.id] ?? []) { alert in
            Button { open = alert } label: {
                HStack(spacing: ui.s) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(hex: alert.colorHex))
                    Text(alert.event).font(ui.font(14, .semibold)).foregroundStyle(Palette.textPrimary)
                    Text([alert.untilText, alert.sender].compactMap { $0 }.joined(separator: " · "))
                        .font(ui.meta).foregroundStyle(Palette.textMuted).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(ui.pt(10))
                .background(RoundedRectangle(cornerRadius: ui.cellRadius, style: .continuous).fill(Color(hex: alert.colorHex).opacity(0.18)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(item: Binding(get: { open?.id == alert.id ? open : nil }, set: { open = $0 })) { alert in
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
    }
}

/// The next two hours in 15-minute bars, only when there's precipitation now or soon.
struct NextHoursTile: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let forecast: Forecast

    var body: some View {
        if let steps = forecast.steps, let sentence = NextHours.sentence(forecast) {
            let peak = max(steps.map(\.precipitation).max() ?? 0, 0.5)
            let snow = Condition.isSnow(forecast.now.code)
            Tile {
                VStack(alignment: .leading, spacing: ui.s) {
                    Eyebrow(title: "Next 2 hours", aside: "")
                    Text(sentence).font(ui.font(14)).foregroundStyle(Palette.textSecondary)
                    HStack(alignment: .bottom, spacing: ui.pt(5)) {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            VStack(spacing: ui.pt(3)) {
                                Capsule().fill(snow ? Color.white : Palette.rain)
                                    .frame(height: max(ui.pt(2), ui.pt(36) * CGFloat(step.precipitation / peak)))
                                    .opacity(step.precipitation >= NextHours.wetStep ? 1 : 0.25)
                                Text(index == 0 ? "Now" : (index % 2 == 0 ? "\(index * 15)m" : " "))
                                    .font(ui.font(10)).foregroundStyle(Palette.textMuted).fixedSize()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: ui.pt(52), alignment: .bottom)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(sentence)
                }
            }
        }
    }
}

/// Air quality (with pollen where it's measured), averages, visibility, precipitation, clouds and the
/// moon, three across. Every city shows all six; one whose data isn't there yet shows a dash.
struct DetailsTile: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let city: City
    let forecast: Forecast

    var body: some View {
        let stats = items
        Tile {
            VStack(alignment: .leading, spacing: ui.s) {
                Eyebrow(title: "Details", aside: "")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ui.s), count: 3), spacing: ui.s) {
                    ForEach(stats, id: \.key) { Stat(key: $0.key, value: $0.value, sub: $0.sub).help($0.help) }
                }
            }
        }
    }

    private struct Item { let key: String; let value: String; let sub: String; let help: String }

    private func missing(_ key: String) -> Item { Item(key: key, value: "–", sub: "Not available", help: "Not available right now.") }

    private var items: [Item] {
        let now = forecast.now, unit = store.unit
        var list: [Item] = []
        let inUS = WeatherAlert.inUS(latitude: city.latitude, longitude: city.longitude)
        let air = store.airQuality[city.id]
        if let reading = air?.reading(inUS: inUS) {
            let pollen = air?.pollenSummary.map { " Pollen: \($0.top.lowercased()) \($0.level.lowercased())." } ?? ""
            list.append(Item(key: "Air quality", value: "\(reading.value)", sub: reading.category, help: "\(reading.scale). \(reading.note)" + pollen))
        } else {
            list.append(missing("Air quality"))
        }
        if let today = forecast.days.first?.including(now.temperature), let entry = store.climate[city.id]?.entry(for: today.date),
           let normalHigh = entry.normalHigh, let normalLow = entry.normalLow {
            list.append(Item(key: "Averages", value: Climate.comparison(high: today.high, normal: normalHigh, unit: unit),
                             sub: "\(unit.value(normalLow))–\(unit.value(normalHigh))\(unit.symbol) normal",
                             help: "Normal high \(unit.other.spaced(unit.other.value(normalHigh))), low \(unit.other.spaced(unit.other.value(normalLow)))"))
        } else {
            list.append(missing("Averages"))
        }
        if let metres = now.visibility {
            let v = Details.visibility(metres, miles: store.windUnit.usesMiles(unit))
            list.append(Item(key: "Visibility", value: v.value, sub: v.note.replacingOccurrences(of: ".", with: ""), help: v.note))
        } else {
            list.append(missing("Visibility"))
        }
        if let mm = forecast.days.first?.precipitation {
            let text = store.rainUnit.text(mm, temp: unit)
            list.append(Item(key: "Precipitation", value: text.main, sub: "\(text.other) today", help: Details.next24Hours(forecast).map { "Next 24 hours: \(store.rainUnit.text($0, temp: unit).main)" } ?? ""))
        } else {
            list.append(missing("Precipitation"))
        }
        if let cover = now.cloudCover {
            list.append(Item(key: "Cloud cover", value: "\(Int(cover.rounded()))%", sub: Details.clouds(cover), help: ""))
        } else {
            list.append(missing("Cloud cover"))
        }
        let moon = Moon.phase(at: Date())
        list.append(Item(key: "Moon", value: "\(moon.illumination)% lit", sub: moon.name, help: moon.name))
        return list
    }
}

/// A day in full, in a popover from the day's row: the charts and the facts.
struct DayDetailPopover: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let city: City
    let forecast: Forecast
    let day: Forecast.Day
    let isToday: Bool

    var body: some View {
        let unit = store.unit, other = unit.other
        let hours = forecast.hours(on: day)
        let time = { (date: Date?) in date.map { Forecast.format($0, "jmm") } ?? "–" }
        ScrollView {
            VStack(alignment: .leading, spacing: ui.m) {
                HStack(spacing: ui.m) {
                    WeatherSymbol(code: day.code, isDay: true, size: ui.pt(32))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Forecast.format(day.date, "EEEEMMMd")).font(ui.font(17, .semibold))
                        Text("\(Condition.name(day.code)) · H:\(unit.value(day.high))\(unit.symbol) L:\(unit.value(day.low))\(unit.symbol) · H:\(other.value(day.high))\(other.symbol) L:\(other.value(day.low))\(other.symbol)")
                            .font(ui.meta).foregroundStyle(Palette.textSecondary)
                    }
                }
                if !hours.isEmpty {
                    Eyebrow(title: "Temperature", aside: "")
                    TemperatureChart(hours: hours, now: isToday ? forecast.now.time : nil)
                    Eyebrow(title: "Rain\(day.precipitation.map { " · " + store.rainUnit.text($0, temp: unit).main } ?? "")", aside: "")
                    RainChart(hours: hours)
                    if hours.contains(where: { $0.wind != nil }) {
                        Eyebrow(title: "Wind\(day.windDirection.map { " · mostly from the " + Meteo.compassName($0) } ?? "")", aside: "")
                        WindChart(hours: hours)
                    }
                }
                VStack(alignment: .leading, spacing: ui.xs) {
                    fact("Sunrise", time(day.sunrise))
                    fact("Sunset", time(day.sunset))
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
            .padding(ui.l)
            .foregroundStyle(Palette.textPrimary)
        }
        .frame(width: ui.pt(420))
        .frame(maxHeight: ui.pt(640))
        .background(Palette.bg)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.textMuted)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(ui.font(13))
    }
}

enum RainMap {
    /// Opens the shared rain map page at a city in the browser.
    static func open(_ city: City, unit: TempUnit) {
        let url = String(format: "https://bradleycowdrey.github.io/two-degrees/radar.html?lat=%.2f&lon=%.2f&z=7&units=%@", city.latitude, city.longitude, unit.rawValue)
        NSWorkspace.shared.open(URL(string: url)!)
    }
}
