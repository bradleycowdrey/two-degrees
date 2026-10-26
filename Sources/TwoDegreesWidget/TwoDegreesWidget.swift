import WidgetKit
import SwiftUI
import AppIntents

// Mac desktop and Notification Center, iPhone Home Screen and Lock Screen: one city's weather in °F and °C at once.
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
        .supportedFamilies(Self.families)
    }

    #if os(iOS)
    /// Home Screen sizes, plus the Lock Screen's.
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular]
    #else
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
    #endif
}

// MARK: - Settings

struct WidgetSettings: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Two Degrees"
    static var description = IntentDescription("Choose a city and which unit is shown large.")

    /// On: show the app's cities (on the Mac, the menu bar and Dock), like Meridian's "Use Meridian's
    /// Cities". Off: a city of its own.
    @Parameter(title: "Use Two Degrees' Cities", default: true)
    var useAppCities: Bool

    /// With the app's cities: which one (normally the one showing in Two Degrees).
    @Parameter(title: "Showing")
    var appCity: AppCityEntity?

    @Parameter(title: "City")
    var city: CityEntity?

    @Parameter(title: "Larger unit", default: .fahrenheit)
    var unit: UnitChoice

    static var parameterSummary: some ParameterSummary {
        When(\.$useAppCities, .equalTo, true) {
            Summary {
                \.$useAppCities
                \.$appCity
                \.$unit
            }
        } otherwise: {
            Summary {
                \.$useAppCities
                \.$city
                \.$unit
            }
        }
    }

    /// The city this widget shows.
    var chosenCity: City {
        let own = city?.city
        guard useAppCities else { return own ?? WidgetDefaults.cities[0] }
        if let snapshot = SharedCities.load(), let city = SharedCities.resolve(appCity?.id, in: snapshot) { return city }
        return own ?? WidgetDefaults.cities[0]   // the app hasn't shared its cities yet
    }
}

/// What a widget using the app's cities shows: the city showing in Two Degrees (on the Mac it follows the
/// menu bar and Dock), or one of the app's saved cities.
struct AppCityEntity: AppEntity {
    let id: String
    let name: String
    let note: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Two Degrees city"
    static var defaultQuery = AppCityQuery()

    /// "San Francisco — Change it in Two Degrees": whichever city the app is showing.
    static func current(_ snapshot: SharedCities.Snapshot?) -> AppCityEntity {
        let name = snapshot.flatMap { SharedCities.resolve(nil, in: $0)?.name } ?? "The city showing in Two Degrees"
        return AppCityEntity(id: SharedCities.currentID, name: name, note: "Change it in Two Degrees")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(note)")
    }
}

struct AppCityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AppCityEntity] {
        let all = try await suggestedEntities()
        return identifiers.map { id in all.first { $0.id == id } ?? AppCityEntity.current(SharedCities.load()) }
    }

    /// The city showing in Two Degrees first, then each saved city.
    func suggestedEntities() async throws -> [AppCityEntity] {
        let snapshot = SharedCities.load()
        let saved = (snapshot?.cities ?? []).map { AppCityEntity(id: $0.id, name: $0.name, note: "Always \($0.name)") }
        return [AppCityEntity.current(snapshot)] + saved
    }

    func defaultResult() async -> AppCityEntity? { AppCityEntity.current(SharedCities.load()) }
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

    /// See WidgetData.id(for:): a saved widget rebuilds its city from this without the network.
    var id: String { WidgetData.id(for: city) }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "City"
    static var defaultQuery = CityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(city.name)", subtitle: "\(city.region)")
    }

    init(_ city: City) { self.city = city }

    init?(id: String) {
        guard let city = WidgetData.city(fromID: id) else { return nil }
        self.city = city
    }
}

struct CityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CityEntity] {
        identifiers.compactMap(CityEntity.init(id:))
    }

    func entities(matching string: String) async throws -> [CityEntity] {
        await WidgetData.search(string, suggestions: WidgetDefaults.cities).map(CityEntity.init)
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
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(WidgetData.refreshInterval(for: entry))))
    }

    private func entry(for configuration: WidgetSettings) async -> WeatherEntry {
        await WidgetData.entry(city: configuration.chosenCity, unit: configuration.unit.unit)
    }
}

