import Foundation

/// The widget's data path: how a chosen city is stored and how its entry is made. Compiled into the
/// widget and the app, so the app's self-test runs exactly this code with live data.
enum WidgetData {
    /// A widget gets only a few seconds per refresh, so give up quickly and fall back to the last
    /// good forecast rather than leave the widget waiting (and blank) on a slow network.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// How long until the next refresh: soon after a miss, otherwise every 30 minutes.
    static func refreshInterval(for entry: WeatherEntry) -> TimeInterval {
        entry.failed || entry.unavailable ? 5 * 60 : 30 * 60
    }

    /// A city as a widget setting, "name|region|lat|lon". Any "|" in the text becomes "/", so the
    /// setting always reads back, and the coordinates need no network to rebuild the city.
    static func id(for city: City) -> String {
        let clean = { (text: String) in text.replacingOccurrences(of: "|", with: "/") }
        return [clean(city.name), clean(city.region), String(city.latitude), String(city.longitude)].joined(separator: "|")
    }

    static func city(fromID id: String) -> City? {
        let parts = id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, !parts[0].isEmpty,
              let lat = Double(parts[2]), let lon = Double(parts[3]),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return City(name: parts[0], region: parts[1], latitude: lat, longitude: lon)
    }

    /// Search results for the widget's city picker. Never throws: a failed search shows no
    /// results instead of an error, and a query under two letters shows the suggestions.
    static func search(_ query: String, suggestions: [City], session: URLSession = WidgetData.session) async -> [City] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return suggestions }
        return (try? await OpenMeteo.search(trimmed, session: session)) ?? []
    }

    /// One widget's entry: live numbers; else the last good ones, labelled offline; else a plain
    /// "couldn't load" message. Never the redacted placeholder, which can look like an empty widget.
    static func entry(city: City, unit: TempUnit, defaults: UserDefaults = .standard, session: URLSession = WidgetData.session) async -> WeatherEntry {
        let key = "forecast." + city.id
        do {
            let forecast = try await OpenMeteo.forecast(for: city, session: session)
            if let data = try? JSONEncoder().encode(forecast) { defaults.set(data, forKey: key) }
            return WeatherEntry(date: Date(), city: city, unit: unit, forecast: forecast)
        } catch {
            if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Forecast.self, from: data) {
                return WeatherEntry(date: Date(), city: city, unit: unit, forecast: saved, failed: true)
            }
            return WeatherEntry(date: Date(), city: city, unit: unit, forecast: .placeholder, failed: true, unavailable: true)
        }
    }
}

/// The app's saved cities, shared with its widgets through an App Group, so a widget can follow the app
/// ("Use Two Degrees' Cities") instead of keeping a city of its own. Mac and iPhone alike.
enum SharedCities {
    /// App Group. On the Mac, the team ID prefix lets a Developer ID app and its widget share it without
    /// a provisioning profile; on iPhone it's a registered group, in both App IDs' profiles.
    #if os(macOS)
    static let suiteName = "2XV97FZ86G.com.bradcowdrey.twodegrees"
    #else
    static let suiteName = "group.com.bradcowdrey.twodegrees"
    #endif
    static let key = "shared.cities"
    /// "Follow whichever city is showing in Two Degrees."
    static let currentID = "current"
    /// Off for the CI self-test, whose ad-hoc signed build isn't in the team's group.
    nonisolated(unsafe) static var enabled = true

    static var defaults: UserDefaults? { enabled ? UserDefaults(suiteName: suiteName) : nil }

    struct Snapshot: Codable, Equatable {
        var cities: [City]
        var activeID: String
    }

    static func save(_ snapshot: Snapshot, to defaults: UserDefaults? = SharedCities.defaults) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func load(from defaults: UserDefaults? = SharedCities.defaults) -> Snapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// The city a widget following the app shows: the one showing in Two Degrees, or a saved city by
    /// ID. A saved city that has since been removed falls back to the one showing.
    static func resolve(_ choice: String?, in snapshot: Snapshot) -> City? {
        let active = snapshot.cities.first { $0.id == snapshot.activeID } ?? snapshot.cities.first
        guard let choice, choice != currentID else { return active }
        return snapshot.cities.first { $0.id == choice } ?? active
    }
}
