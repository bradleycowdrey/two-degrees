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
                .containerBackground(for: .widget) { WidgetBackground() }
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
        let key = "forecast." + city.id
        do {
            let forecast = try await OpenMeteo.forecast(for: city)
            if let data = try? JSONEncoder().encode(forecast) { UserDefaults.standard.set(data, forKey: key) }
            return WeatherEntry(date: Date(), city: city, unit: unit, forecast: forecast)
        } catch {
            // Offline: show the last good forecast, clearly labelled with its time.
            if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode(Forecast.self, from: data) {
                return WeatherEntry(date: Date(), city: city, unit: unit, forecast: saved, failed: true)
            }
            return WeatherEntry(date: Date(), city: city, unit: unit, forecast: .placeholder, isPlaceholder: true, failed: true)
        }
    }
}

