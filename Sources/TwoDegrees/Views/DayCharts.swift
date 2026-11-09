import Charts
import SwiftUI

// The day detail, shared by the Mac and iPhone apps (design/weather-features.md, section 7): its
// charts, then the day in full as the iPhone's sheet and the Mac's popover show it.

/// Hourly temperature: the larger unit's scale on the left, the other unit's on the right.
struct TemperatureChart: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let hours: [Forecast.Hour]
    let now: Date?

    var body: some View {
        let unit = store.unit, other = unit.other
        let values = hours.map { Double(unit.value($0.temperature)) }
        let low = (values.min() ?? 0) - 3, high = (values.max() ?? 0) + 3
        Chart {
            ForEach(hours) { hour in
                LineMark(x: .value("Time", hour.time), y: .value("Temperature", unit.value(hour.temperature)))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [Palette.temperature(hours.map(\.temperature).min() ?? 0), Palette.temperature(hours.map(\.temperature).max() ?? 0)], startPoint: .bottom, endPoint: .top))
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if let now, let hour = hours.last(where: { $0.time <= now }) {
                RuleMark(x: .value("Now", hour.time)).foregroundStyle(.white.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: low...high)
        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { value in
            AxisGridLine().foregroundStyle(.white.opacity(0.12))
            AxisValueLabel { if let date = value.as(Date.self) { Text(Forecast.format(date, "j")).font(ui.font(11)) } }
        } }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.12))
                AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))°").font(ui.font(11)) } }
            }
            AxisMarks(position: .trailing) { value in
                AxisValueLabel { if let v = value.as(Double.self) { Text("\(other.value(unit == .fahrenheit ? (v - 32) * 5 / 9 : v))°").font(ui.font(11)).foregroundStyle(.white.opacity(0.6)) } }
            }
        }
        .foregroundStyle(.white)
        .frame(height: ui.pt(170))
        .accessibilityLabel("Temperature through the day, from \(unit.spaced(Int(values.min() ?? 0))) to \(unit.spaced(Int(values.max() ?? 0)))")
    }
}

struct RainChart: View {
    @Environment(\.metrics) private var ui
    let hours: [Forecast.Hour]

    var body: some View {
        Chart(hours) { hour in
            BarMark(x: .value("Time", hour.time, unit: .hour), y: .value("Chance", hour.rainChance))
                .foregroundStyle(Palette.rain.opacity(0.85))
        }
        .chartYScale(domain: 0...100)
        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { value in
            AxisValueLabel { if let date = value.as(Date.self) { Text(Forecast.format(date, "j")).font(ui.font(11)) } }
        } }
        .chartYAxis { AxisMarks(values: [0, 50, 100]) { value in
            AxisGridLine().foregroundStyle(.white.opacity(0.12))
            AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)%").font(ui.font(11)) } }
        } }
        .foregroundStyle(.white)
        .frame(height: ui.pt(110))
        .accessibilityLabel("Chance of rain by the hour, up to \(hours.map(\.rainChance).max() ?? 0) percent")
    }
}

struct WindChart: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let hours: [Forecast.Hour]

    var body: some View {
        let unit = store.windUnit.resolved(store.unit)
        VStack(alignment: .leading, spacing: ui.pt(6)) {
        // A legend above the plot, so it never sits on the axis labels.
        HStack(spacing: ui.pt(12)) {
            legend("Wind", width: 2.5, opacity: 1)
            legend("Gusts", width: 1.5, opacity: 0.35)
            Spacer(minLength: 0)
            Text(unit.label).opacity(0.6)
        }
        .font(ui.font(11))
        .accessibilityHidden(true)
        Chart {
            ForEach(hours) { hour in
                if let gusts = hour.gusts {
                    LineMark(x: .value("Time", hour.time), y: .value("Speed", unit.value(gusts)), series: .value("Kind", "Gusts"))
                        .foregroundStyle(.white.opacity(0.35)).interpolationMethod(.catmullRom)
                }
                if let wind = hour.wind {
                    LineMark(x: .value("Time", hour.time), y: .value("Speed", unit.value(wind)), series: .value("Kind", "Wind"))
                        .foregroundStyle(.white).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.catmullRom)
                }
            }
        }
        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { value in
            AxisValueLabel { if let date = value.as(Date.self) { Text(Forecast.format(date, "j")).font(ui.font(11)) } }
        } }
        .chartYAxis { AxisMarks { value in
            AxisGridLine().foregroundStyle(.white.opacity(0.12))
            AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)").font(ui.font(11)) } }
        } }
        .foregroundStyle(.white)
        .frame(height: ui.pt(120))
        .accessibilityLabel("Wind by the hour, in \(unit.label), with gusts")
        }
    }

    private func legend(_ title: String, width: CGFloat, opacity: Double) -> some View {
        HStack(spacing: ui.pt(5)) {
            Capsule().fill(.white.opacity(opacity)).frame(width: ui.pt(14), height: width)
            Text(title).opacity(0.75)
        }
    }
}

// MARK: - The day in full

/// One day: the condition and its high and low in both units, then temperature, rain and wind charts,
/// and the facts.
struct DayDetailContent: View {
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
