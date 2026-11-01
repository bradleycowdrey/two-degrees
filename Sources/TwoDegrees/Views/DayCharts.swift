import Charts
import SwiftUI

// The day detail's charts, shared by the Mac and iPhone apps (design/weather-features.md, section 7).

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
        .overlay(alignment: .topTrailing) {
            Text("\(unit.label) · gusts lighter").font(ui.font(11)).opacity(0.6)
        }
        .accessibilityLabel("Wind by the hour, in \(unit.label)")
    }
}
