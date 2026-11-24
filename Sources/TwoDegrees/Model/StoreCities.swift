import Foundation

/// App Store pictures (the Mac and iPhone self-tests with `--store`): well-known cities, each with its
/// time zone, and the five nearest 1 pm local time, so every picture is daytime. One list for both apps.
/// No Denver: both self-tests add and remove it.
@MainActor
enum StoreCities {
    static let all: [(City, String)] = [
        (City(name: "Sydney", region: "New South Wales, Australia", latitude: -33.8688, longitude: 151.2093), "Australia/Sydney"),
        (City(name: "Auckland", region: "New Zealand", latitude: -36.8485, longitude: 174.7633), "Pacific/Auckland"),
        (City(name: "Tokyo", region: "Japan", latitude: 35.6762, longitude: 139.6503), "Asia/Tokyo"),
        (City(name: "Singapore", region: "Singapore", latitude: 1.3521, longitude: 103.8198), "Asia/Singapore"),
        (City(name: "Bangkok", region: "Thailand", latitude: 13.7563, longitude: 100.5018), "Asia/Bangkok"),
        (City(name: "Mumbai", region: "Maharashtra, India", latitude: 19.076, longitude: 72.8777), "Asia/Kolkata"),
        (City(name: "Dubai", region: "Dubai, United Arab Emirates", latitude: 25.2048, longitude: 55.2708), "Asia/Dubai"),
        (City(name: "Cape Town", region: "Western Cape, South Africa", latitude: -33.9249, longitude: 18.4241), "Africa/Johannesburg"),
        (City(name: "Paris", region: "Île-de-France, France", latitude: 48.8566, longitude: 2.3522), "Europe/Paris"),
        (City(name: "Barcelona", region: "Catalonia, Spain", latitude: 41.3874, longitude: 2.1686), "Europe/Madrid"),
        (City(name: "London", region: "England, United Kingdom", latitude: 51.5072, longitude: -0.1276), "Europe/London"),
        (City(name: "Rio de Janeiro", region: "Rio de Janeiro, Brazil", latitude: -22.9068, longitude: -43.1729), "America/Sao_Paulo"),
        (City(name: "New York", region: "New York, United States", latitude: 40.7128, longitude: -74.006), "America/New_York"),
        (City(name: "Mexico City", region: "Mexico", latitude: 19.4326, longitude: -99.1332), "America/Mexico_City"),
        (City(name: "San Francisco", region: "California, United States", latitude: 37.7749, longitude: -122.4194), "America/Los_Angeles"),
        (City(name: "Vancouver", region: "British Columbia, Canada", latitude: 49.2827, longitude: -123.1207), "America/Vancouver"),
        (City(name: "Honolulu", region: "Hawaii, United States", latitude: 21.3069, longitude: -157.8583), "Pacific/Honolulu"),
    ]

    /// The cities (three unless told) whose local time is nearest 13:00 at `now`, nearest first (a tie goes to the earlier in the list).
    static func pick(at now: Date = Date(), count: Int = 3) -> [City] {
        func distance(_ zone: String) -> Int {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone) ?? TimeZone(secondsFromGMT: 0)!
            let parts = calendar.dateComponents([.hour, .minute], from: now)
            let d = abs((parts.hour ?? 0) * 60 + (parts.minute ?? 0) - 13 * 60)
            return min(d, 24 * 60 - d)
        }
        let ranked = all.enumerated().sorted { a, b in
            let da = distance(a.element.1), db = distance(b.element.1)
            return da != db ? da < db : a.offset < b.offset
        }
        return ranked.prefix(count).map { $0.element.0 }
    }

    /// How good a city's sky looks right now: clear daytime best, then partly cloudy, then overcast.
    static func sunniness(_ forecast: Forecast?) -> Int {
        guard let now = forecast?.now else { return -1 }
        let sky = now.code == 0 ? 3 : now.code <= 2 ? 2 : now.code == 3 ? 1 : 0
        return sky + (now.isDay ? 4 : 0)
    }

    /// The cities in order of sunniness, keeping list order for ties.
    static func sunniestFirst(_ cities: [City], _ forecasts: [String: Forecast]) -> [City] {
        cities.enumerated().sorted { a, b in
            let sa = sunniness(forecasts[a.element.id]), sb = sunniness(forecasts[b.element.id])
            return sa != sb ? sa > sb : a.offset < b.offset
        }.map(\.element)
    }

    /// `--store-at <unix seconds>`: picks as at that moment, so every launch in one CI run shows the same cities.
    nonisolated static let time: Date = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--store-at"), i + 1 < args.count, let t = TimeInterval(args[i + 1]) else { return Date() }
        return Date(timeIntervalSince1970: t)
    }()

    /// `--selftest --store`: App Store pictures are being taken (the footer leaves out "Updated …").
    nonisolated static let active: Bool = {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--selftest") && args.contains("--store")
    }()

    // MARK: Frozen forecasts

    /// `--store-snapshot <path>` (with `--store`): a JSON file of the chosen cities and their forecasts,
    /// written by the first launch and read by every later one (and by the iPad, which CI gives a copy), so
    /// every App Store picture shows the same cities and the same numbers.
    nonisolated static let snapshotURL: URL? = {
        let args = ProcessInfo.processInfo.arguments
        guard active, let i = args.firstIndex(of: "--store-snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1])
    }()

    struct Snapshot: Codable {
        /// The cities shown, sunniest first, once chosen.
        var cities: [City]? = nil
        /// Forecasts by city ID.
        var forecasts: [String: Forecast] = [:]
    }

    private static func readSnapshot() -> Snapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private static func writeSnapshot(_ change: (inout Snapshot) -> Void) {
        guard let url = snapshotURL else { return }
        var snapshot = readSnapshot() ?? Snapshot()
        change(&snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot) { try? data.write(to: url, options: .atomic) }
    }

    /// The city's forecast from the snapshot, if it has one (nil without `--store-snapshot`).
    static func frozenForecast(for city: City) -> Forecast? {
        readSnapshot()?.forecasts[city.id]
    }

    /// Keeps a freshly fetched forecast in the snapshot, unless it already has one for that city.
    static func freeze(_ forecast: Forecast, for city: City) {
        guard snapshotURL != nil else { return }
        writeSnapshot { if $0.forecasts[city.id] == nil { $0.forecasts[city.id] = forecast } }
    }

    /// The cities an earlier launch chose, in order (nil until one has).
    static var frozenCities: [City]? {
        guard let cities = readSnapshot()?.cities, !cities.isEmpty else { return nil }
        return cities
    }

    /// Records the chosen cities, once: later launches use these instead of choosing again.
    static func freezeCities(_ cities: [City]) {
        guard snapshotURL != nil else { return }
        writeSnapshot { if $0.cities?.isEmpty ?? true { $0.cities = cities } }
    }
}
