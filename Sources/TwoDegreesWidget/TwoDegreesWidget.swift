import WidgetKit
import SwiftUI
import AppIntents

// Desktop and Notification Center widget: one city's weather in °F and °C at once.
// Each widget picks its own city (search any place), so it needs no shared storage with the app.

@main
struct TwoDegreesWidgets: WidgetBundle {
    var body: some Widget {
        TwoDegreesWidget()
    }
}

struct TwoDegreesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TwoDegreesWidget", intent: WidgetSettings.self, provider: Provider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    ZStack(alignment: .top) {
                        Palette.bg
                        Palette.crimson.frame(height: 3)
                    }
                }
        }
        .configurationDisplayName("Two Degrees")
        .description("The weather in °F and °C at once.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Settings

struct WidgetSettings: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Two Degrees"
    static var description = IntentDescription("Choose a city and which unit is shown large.")

    @Parameter(title: "City")
    var city: CityEntity?

    @Parameter(title: "Larger unit", default: .fahrenheit)
    var unit: UnitChoice
}

enum UnitChoice: String, AppEnum {
    case fahrenheit, celsius

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Unit"
    static var caseDisplayRepresentations: [UnitChoice: DisplayRepresentation] = [
        .fahrenheit: "°F, with °C beside it",
        .celsius: "°C, with °F beside it",
    ]

    var unit: TempUnit { self == .fahrenheit ? .fahrenheit : .celsius }
}

struct CityEntity: AppEntity {
    let city: City

    /// "name|region|lat|lon", so a saved widget can rebuild its city without the network.
    var id: String { [city.name, city.region, String(city.latitude), String(city.longitude)].joined(separator: "|") }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "City"
    static var defaultQuery = CityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(city.name)", subtitle: "\(city.region)")
    }

    init(_ city: City) { self.city = city }

    init?(id: String) {
        let parts = id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, let lat = Double(parts[2]), let lon = Double(parts[3]) else { return nil }
        city = City(name: parts[0], region: parts[1], latitude: lat, longitude: lon)
    }
}

struct CityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CityEntity] {
        identifiers.compactMap(CityEntity.init(id:))
    }

    func entities(matching string: String) async throws -> [CityEntity] {
        try await OpenMeteo.search(string).map(CityEntity.init)
    }

    func suggestedEntities() async throws -> [CityEntity] {
        WidgetDefaults.cities.map(CityEntity.init)
    }
}

enum WidgetDefaults {
    static let cities: [City] = [
        City(name: "New York", region: "New York, United States", latitude: 40.7128, longitude: -74.006),
        City(name: "London", region: "England, United Kingdom", latitude: 51.5072, longitude: -0.1276),
        City(name: "Tokyo", region: "Japan", latitude: 35.6762, longitude: 139.6503),
        City(name: "Los Angeles", region: "California, United States", latitude: 34.0522, longitude: -118.2437),
        City(name: "Paris", region: "France", latitude: 48.8566, longitude: 2.3522),
        City(name: "Sydney", region: "New South Wales, Australia", latitude: -33.8688, longitude: 151.2093),
    ]
}

// MARK: - Timeline

struct WeatherEntry: TimelineEntry {
    let date: Date
    let city: City
    let unit: TempUnit
    let forecast: Forecast
    var isPlaceholder = false
    var failed = false
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: Date(), city: WidgetDefaults.cities[0], unit: .localeDefault, forecast: .placeholder, isPlaceholder: true)
    }

    func snapshot(for configuration: WidgetSettings, in context: Context) async -> WeatherEntry {
        if context.isPreview { return placeholder(in: context) }
        return await entry(for: configuration)
    }

    func timeline(for configuration: WidgetSettings, in context: Context) async -> Timeline<WeatherEntry> {
        let entry = await entry(for: configuration)
        // Fresh numbers every 30 minutes; sooner after a failed fetch.
        let next = Date().addingTimeInterval(entry.failed ? 10 * 60 : 30 * 60)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func entry(for configuration: WidgetSettings) async -> WeatherEntry {
        let city = configuration.city?.city ?? WidgetDefaults.cities[0]
        let unit = configuration.unit.unit
        do {
            let forecast = try await OpenMeteo.forecast(for: city)
            return WeatherEntry(date: Date(), city: city, unit: unit, forecast: forecast)
        } catch {
            return WeatherEntry(date: Date(), city: city, unit: unit, forecast: .placeholder, isPlaceholder: true, failed: true)
        }
    }
}

extension Forecast {
    /// Shape-only data for the widget gallery and loading state (shown redacted).
    static var placeholder: Forecast {
        let start = Forecast.localCalendar.startOfDay(for: Date())
        let hours = (0..<48).map { i in
            Forecast.Hour(time: start.addingTimeInterval(Double(i) * 3600), temperature: 14 + 5 * sin(Double(i - 9) / 24 * 2 * .pi),
                          code: i % 7 == 0 ? 2 : 1, rainChance: 0, isDay: (7..<19).contains(i % 24))
        }
        let days = (0..<6).map { i in
            Forecast.Day(date: start.addingTimeInterval(Double(i) * 86400), code: [1, 2, 3, 61, 1, 2][i],
                         high: 19 + Double(i % 3), low: 9 + Double(i % 2), rainChance: i == 3 ? 60 : 0, sunrise: nil, sunset: nil)
        }
        let now = Forecast.Now(time: start.addingTimeInterval(14 * 3600), temperature: 18, feelsLike: 17, humidity: 60, wind: 12, code: 1, isDay: true)
        return Forecast(now: now, hours: hours, days: days, timeZone: "UTC", fetchedAt: Date())
    }
}

// MARK: - Views

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium: MediumView(entry: entry)
            case .systemLarge: LargeView(entry: entry)
            default: SmallView(entry: entry)
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
            if let today = entry.forecast.days.first?.including(now.temperature) {
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
            }
        }
    }
}

private struct DaysList: View {
    let entry: WeatherEntry

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
                    Text("\(unit.value(day.low))°")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 30, alignment: .trailing)
                    GeometryReader { proxy in
                        let span = max(high - low, 1)
                        let x = { (t: Double) in CGFloat((t - low) / span) * proxy.size.width }
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.raisedTile)
                            Capsule()
                                .fill(LinearGradient(colors: [Palette.temperature(day.low), Palette.temperature(day.high)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(x(day.high) - x(day.low), 4))
                                .offset(x: x(day.low))
                            if index == 0 {
                                Circle().fill(Color.white)
                                    .overlay(Circle().stroke(Palette.bg, lineWidth: 2))
                                    .frame(width: 8, height: 8)
                                    .offset(x: x(now) - 4)
                            }
                        }
                    }
                    .frame(height: 5)
                    Text("\(unit.value(day.high))°")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 30, alignment: .leading)
                    Text("\(other.value(day.low))–\(other.value(day.high))\(other.symbol)")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                        .frame(width: 52, alignment: .trailing)
                }
                .monospacedDigit()
                .lineLimit(1)
            }
        }
    }
}
