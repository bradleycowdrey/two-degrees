import Foundation

/// The cities search falls back on when Open-Meteo can't be reached: every place with at least 15,000
/// people, from GeoNames (Resources/Cities.tsv, built by scripts/make_cities.py), most populous first.
/// So you can pick a city with the internet out; its weather loads once you're back online.
enum OfflineCities {
    struct Entry {
        let name: String
        let region: String
        let latitude: Double
        let longitude: Double
        /// The name and its ASCII spelling, folded for matching ("Zürich" and "Zurich" both match "zur").
        let keys: [String]
    }

    /// The bundled list, read the first time it's needed. Empty where it isn't bundled (`swift test`).
    static let all: [Entry] = {
        guard let url = Bundle.main.url(forResource: "Cities", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }()

    /// One city per line: name, ASCII name (empty when the same), state or province, country code,
    /// latitude, longitude. The country's name is in the iPhone's or Mac's own language.
    static func parse(_ text: String, locale: Locale = .current) -> [Entry] {
        var countries: [String: String] = [:]
        return text.split(separator: "\n").compactMap { line in
            let c = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard c.count >= 6, let lat = Double(c[4]), let lon = Double(c[5]) else { return nil }
            let country = countries[c[3]] ?? {
                let name = locale.localizedString(forRegionCode: c[3]) ?? c[3]
                countries[c[3]] = name
                return name
            }()
            return Entry(name: c[0], region: [c[2], country].filter { !$0.isEmpty }.joined(separator: ", "),
                         latitude: lat, longitude: lon,
                         keys: [c[0], c[1]].filter { !$0.isEmpty }.map(fold))
        }
    }

    /// Cities whose name starts with the query, exact names first, then the most populous. Text after
    /// a comma narrows by state or country ("Portland, Maine").
    static func search(_ query: String, in list: [Entry] = all, limit: Int = 8) -> [City] {
        let parts = query.split(separator: ",", maxSplits: 1).map { fold(String($0)) }
        guard let name = parts.first, !name.isEmpty else { return [] }
        let place = parts.count > 1 ? parts[1] : ""
        var exact: [Entry] = [], starts: [Entry] = []
        for entry in list where place.isEmpty || fold(entry.region).contains(place) {
            if entry.keys.contains(name) {
                exact.append(entry)
            } else if entry.keys.contains(where: { $0.hasPrefix(name) }) && starts.count < limit {
                starts.append(entry)
            }
        }
        return (exact + starts).prefix(limit).map {
            City(name: $0.name, region: $0.region, latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    /// The listed city nearest a point: names where you are when the system can't (offline, or no
    /// geocoder), within 50 km.
    static func nearest(latitude: Double, longitude: Double, in list: [Entry] = all) -> City? {
        let k = cos(latitude * .pi / 180)
        var best: (entry: Entry, d: Double)?
        for entry in list {
            let dy = entry.latitude - latitude
            var dx = abs(entry.longitude - longitude)
            if dx > 180 { dx = 360 - dx }
            let d = dy * dy + (dx * k) * (dx * k)
            if best == nil || d < best!.d { best = (entry, d) }
        }
        guard let best, best.d.squareRoot() * 111 <= 50 else { return nil }
        return City(name: best.entry.name, region: best.entry.region, latitude: latitude, longitude: longitude)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }
}
