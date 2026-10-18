import WidgetKit
import SwiftUI

// Widget views, shared by the widget extension and the app (whose self-test renders them).

struct WeatherEntry: TimelineEntry {
    let date: Date
    let city: City
    let unit: TempUnit
    let forecast: Forecast
    var isPlaceholder = false
    var failed = false
    /// No forecast at all (offline and nothing saved): the widget says so instead of going blank.
    var unavailable = false
}

/// Warm near-black with the crimson rule; the rule steps aside in tinted and clear modes.
struct WidgetBackground: View {
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        ZStack(alignment: .top) {
            Palette.bg
            if mode == .fullColor { Palette.crimson.frame(height: 3) }
        }
    }
}

extension Forecast {
    /// Shape-only data for the widget gallery and loading state (shown redacted).
    static var placeholder: Forecast {
        let start: Date = Forecast.localCalendar.startOfDay(for: Date())
        var hours: [Forecast.Hour] = []
        for i in 0..<48 {
            let phase: Double = Double(i - 9) / 24.0 * 2.0 * Double.pi
            let temperature: Double = 14.0 + 5.0 * sin(phase)
            let time: Date = start.addingTimeInterval(Double(i) * 3600.0)
            let isDay: Bool = (7..<19).contains(i % 24)
            hours.append(Forecast.Hour(time: time, temperature: temperature, code: 1, rainChance: 0, isDay: isDay))
        }
        let codes: [Int] = [1, 2, 3, 61, 1, 2]
        var days: [Forecast.Day] = []
        for i in 0..<6 {
            let date: Date = start.addingTimeInterval(Double(i) * 86400.0)
            let high: Double = 19.0 + Double(i % 3)
            let low: Double = 9.0 + Double(i % 2)
            days.append(Forecast.Day(date: date, code: codes[i], high: high, low: low, rainChance: i == 3 ? 60 : 0, sunrise: nil, sunset: nil))
        }
        let now = Forecast.Now(time: start.addingTimeInterval(14.0 * 3600.0), temperature: 18, feelsLike: 17, humidity: 60, wind: 12, code: 1, isDay: true)
        return Forecast(now: now, hours: hours, days: days, timeZone: "UTC", fetchedAt: Date())
    }
}

// MARK: - Views

struct WidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: WeatherEntry
    /// Set by the app's self-test, which renders widgets outside WidgetKit.
    var family: WidgetFamily? = nil

    var body: some View {
        Group {
            if entry.unavailable {
                UnavailableView(entry: entry)
            } else {
                switch family ?? environmentFamily {
                case .systemMedium: MediumView(entry: entry)
                case .systemLarge: LargeView(entry: entry)
                default: SmallView(entry: entry)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }
}

/// City, both temperatures, condition, today's range.
private struct NowBlock: View {
    let entry: WeatherEntry
    var big: CGFloat = 40

    var body: some View {
        let now = entry.forecast.now, unit = entry.unit, other = entry.unit.other
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Text(entry.city.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                WeatherSymbol(code: now.code, isDay: now.isDay, size: 15)
            }
            Spacer(minLength: 2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(unit.value(now.temperature))°")
                    .font(.system(size: big, weight: .semibold))
                    .tracking(-big * 0.03)
                    .foregroundStyle(Palette.textPrimary)
                    .widgetAccentable()
                Text("\(other.value(now.temperature))\(other.symbol)")
                    .font(.system(size: big * 0.45, weight: .medium))
                    .foregroundStyle(Palette.textMuted)
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(TempUnit.fahrenheit.value(now.temperature)) degrees Fahrenheit, \(TempUnit.celsius.value(now.temperature)) Celsius")
            Text(Condition.name(now.code))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            if entry.failed && !entry.isPlaceholder {
                Text("Offline · from \(entry.forecast.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
            } else if let today = entry.forecast.days.first?.including(now.temperature) {
                Text("\(unit.value(today.low))–\(unit.value(today.high))\(unit.symbol) · \(other.value(today.low))–\(other.value(today.high))\(other.symbol)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

/// Offline with nothing saved yet: the city, and a plain message that it will try again.
private struct UnavailableView: View {
    let entry: WeatherEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.city.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Image(systemName: "icloud.slash")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Palette.textMuted)
            Text("Couldn’t load the weather")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Trying again in a few minutes")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SmallView: View {
    let entry: WeatherEntry
    var body: some View { NowBlock(entry: entry) }
}

/// Now on the left, the next five hours on the right.
private struct MediumView: View {
    let entry: WeatherEntry

    var body: some View {
        HStack(spacing: 14) {
            NowBlock(entry: entry)
                .frame(width: 128)
            Rectangle().fill(Palette.borderStrong).frame(width: 0.5)
            HoursRow(entry: entry, count: 5)
        }
    }
}

/// Now, the next six hours, and five days on one shared scale.
private struct LargeView: View {
    let entry: WeatherEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NowBlock(entry: entry, big: 44)
                .frame(height: 104)
            Rectangle().fill(Palette.borderStrong).frame(height: 0.5)
            HoursRow(entry: entry, count: 6)
            Rectangle().fill(Palette.borderStrong).frame(height: 0.5)
            DaysList(entry: entry)
        }
    }
}

private struct HoursRow: View {
    let entry: WeatherEntry
    let count: Int

    var body: some View {
        let unit = entry.unit, other = entry.unit.other
        let hours = Array(entry.forecast.upcomingHours.prefix(count))
        HStack(spacing: 0) {
            ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                VStack(spacing: 3) {
                    Text(index == 0 ? "Now" : Forecast.format(hour.time, "j"))
                        .font(.system(size: 10, weight: index == 0 ? .semibold : .medium))
                        .foregroundStyle(index == 0 ? Palette.cream : Palette.textMuted)
                    WeatherSymbol(code: hour.code, isDay: hour.isDay, size: 14)
                        .frame(height: 18)
                    Text("\(unit.value(hour.temperature))°")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text("\(other.value(hour.temperature))\(other.symbol)")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                }
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(index == 0 ? "Now" : Forecast.format(hour.time, "j")): \(Condition.name(hour.code)), \(TempUnit.fahrenheit.value(hour.temperature)) degrees Fahrenheit, \(TempUnit.celsius.value(hour.temperature)) Celsius")
            }
        }
    }
}

private struct DaysList: View {
    let entry: WeatherEntry

    static func speech(_ day: Forecast.Day, isToday: Bool) -> String {
        let name = isToday ? "Today" : Forecast.format(day.date, "EEEE")
        let low = "\(TempUnit.fahrenheit.value(day.low)) degrees Fahrenheit, \(TempUnit.celsius.value(day.low)) Celsius"
        let high = "\(TempUnit.fahrenheit.value(day.high)) degrees Fahrenheit, \(TempUnit.celsius.value(day.high)) Celsius"
        return "\(name): \(Condition.name(day.code)). Low \(low). High \(high)."
    }

    var body: some View {
        let unit = entry.unit, other = entry.unit.other
        let days = Array(entry.forecast.days.prefix(5))
        let now = entry.forecast.now.temperature
        let low = min(now, days.map(\.low).min() ?? now), high = max(now, days.map(\.high).max() ?? now)
        VStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, raw in
                let day = index == 0 ? raw.including(now) : raw
                HStack(spacing: 8) {
                    Text(index == 0 ? "Today" : Forecast.format(day.date, "EEE"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 42, alignment: .leading)
                    WeatherSymbol(code: day.code, isDay: true, size: 13)
                        .frame(width: 20)
                    // The low and high ride the ends of the bar, on one scale shared by all five days.
                    GeometryReader { proxy in
                        let room: CGFloat = 30, gap: CGFloat = 4
                        let width = max(proxy.size.width - 2 * room, 1), span = max(high - low, 1)
                        let x = { (t: Double) in room + CGFloat((t - low) / span) * width }
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(LinearGradient(colors: [Palette.temperature(day.low), Palette.temperature(day.high)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(x(day.high) - x(day.low), 5), height: 5)
                                .offset(x: x(day.low))
                            if index == 0 {
                                Circle().fill(Color.white)
                                    .overlay(Circle().stroke(Palette.bg, lineWidth: 2))
                                    .frame(width: 8, height: 8)
                                    .offset(x: x(now) - 4)
                            }
                            Text("\(unit.value(day.low))°")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize()
                                .padding(.trailing, gap)
                                .frame(width: x(day.low), alignment: .trailing)
                            Text("\(unit.value(day.high))°")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.textPrimary)
                                .fixedSize()
                                .padding(.leading, gap)
                                .frame(width: proxy.size.width - x(day.high), alignment: .leading)
                                .offset(x: x(day.high))
                        }
                        .frame(height: proxy.size.height)
                    }
                    .frame(height: 16)
                    Text("\(other.value(day.low))–\(other.value(day.high))\(other.symbol)")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                        .frame(width: 52, alignment: .trailing)
                }
                .monospacedDigit()
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(DaysList.speech(day, isToday: index == 0))
            }
        }
    }
}
