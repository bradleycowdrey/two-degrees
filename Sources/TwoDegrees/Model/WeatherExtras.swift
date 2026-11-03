import Foundation

// 0.5's weather details, shared by the Mac and iPhone apps: units for wind and rain; the
// moon; air quality and pollen; normals and records; severe weather alerts; and the words for each.
// Rules and wording follow design/weather-features.md, so the Android and web apps say the same.

// MARK: - Units

enum WindUnit: String, CaseIterable, Identifiable {
    case auto, kmh, mph, ms, kn
    var id: String { rawValue }
    var label: String { ["auto": "Automatic", "kmh": "km/h", "mph": "mph", "ms": "m/s", "kn": "knots"][rawValue]! }

    func resolved(_ temp: TempUnit) -> WindUnit { self == .auto ? (temp == .fahrenheit ? .mph : .kmh) : self }

    func value(_ kmh: Double) -> Int {
        switch self {
        case .mph: return Int((kmh * 0.621371).rounded())
        case .ms: return Int((kmh / 3.6).rounded())
        case .kn: return Int((kmh * 0.539957).rounded())
        default: return Int(kmh.rounded())
        }
    }

    /// "12 mph", with "19 km/h" beside it for mph and km/h ("" otherwise).
    func text(_ kmh: Double, temp: TempUnit) -> (main: String, other: String?) {
        let unit = resolved(temp)
        let main = "\(unit.value(kmh)) \(unit.label)"
        switch unit {
        case .mph: return (main, "\(WindUnit.kmh.value(kmh)) km/h")
        case .kmh: return (main, "\(WindUnit.mph.value(kmh)) mph")
        default: return (main, nil)
        }
    }

    /// Distances follow the wind unit's system: miles with mph, kilometres otherwise.
    func usesMiles(_ temp: TempUnit) -> Bool { resolved(temp) == .mph }
}

enum RainUnit: String, CaseIterable, Identifiable {
    case auto, mm, inch = "in"
    var id: String { rawValue }
    var label: String { ["auto": "Automatic", "mm": "mm", "in": "in"][rawValue]! }

    func resolved(_ temp: TempUnit) -> RainUnit { self == .auto ? (temp == .fahrenheit ? .inch : .mm) : self }

    /// "0.12 in" or "3 mm" (one decimal under 10 mm).
    static func format(_ mm: Double, _ unit: RainUnit) -> String {
        if unit == .inch {
            let inches = mm / 25.4
            return inches > 0 && inches < 0.01 ? "<0.01 in" : String(format: "%.2f in", inches)
        }
        return mm > 0 && mm < 0.1 ? "<0.1 mm" : (mm < 10 ? String(format: "%.1f mm", mm) : "\(Int(mm.rounded())) mm")
    }

    func text(_ mm: Double, temp: TempUnit) -> (main: String, other: String) {
        let unit = resolved(temp)
        return (Self.format(mm, unit), Self.format(mm, unit == .inch ? .mm : .inch))
    }
}

// MARK: - Words for the detail tiles

// MARK: - Sunrise and sunset colour

/// How colourful a sunrise or sunset is likely to be, from the clouds forecast for that hour. Colour
/// comes from high and mid-level cloud catching the low sun; thick low cloud near the horizon blocks
/// it, rain and fog hide it, and a clear sky gives a clean but plain glow. Same rule on every platform
/// (design/weather-features.md, "Sky colour").
enum SkyColour {
    enum Rating: Int, Comparable { case poor, fair, good, great
        static func < (a: Rating, b: Rating) -> Bool { a.rawValue < b.rawValue }
        var word: String { ["Poor", "Fair", "Good", "Great"][rawValue] }
        /// "Great colour likely", "Good colour likely", "Some colour possible", "Little colour expected".
        var line: String { ["Little colour expected", "Some colour possible", "Good colour likely", "Great colour likely"][rawValue] }
    }
    struct Outlook: Equatable { let rating: Rating; let reason: String }

    static func outlook(low: Double, mid: Double, high: Double, precipitation: Double, code: Int, visibility: Double?) -> Outlook {
        if precipitation >= 0.2 || [45, 48].contains(code) || code >= 51 {
            return Outlook(rating: .poor, reason: [45, 48].contains(code) ? "Fog will likely hide it." : "Rain or snow will likely hide it.")
        }
        if low >= 70 { return Outlook(rating: .poor, reason: "Low cloud will likely block it.") }
        let canvas = max(mid, high)
        var score = 30.0, reason: String
        switch canvas {
        case ..<5: score += 15; reason = "Clear sky: a clean, simple glow."
        case ..<20: score += 22; reason = "A few high clouds may catch some colour."
        case ...80: score += 42; reason = "High and mid-level clouds to catch the colour."
        default: score += 12; reason = "A thick cloud layer may mute it."
        }
        score -= low * 0.5
        if low >= 40 { reason = "Low cloud may block some of it." }
        if let visibility, visibility < 5000 { score -= 15; reason = "Haze may dull it." }
        let rating: Rating = score >= 65 ? .great : score >= 50 ? .good : score >= 35 ? .fair : .poor
        return Outlook(rating: rating, reason: reason)
    }

    /// The outlook for a sunrise or sunset, from the forecast hour nearest it (within 90 minutes).
    static func outlook(_ forecast: Forecast, at time: Date) -> Outlook? {
        guard let hour = forecast.hours.min(by: { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }),
              abs(hour.time.timeIntervalSince(time)) <= 90 * 60,
              let low = hour.cloudLow, let mid = hour.cloudMid, let high = hour.cloudHigh else { return nil }
        return outlook(low: low, mid: mid, high: high, precipitation: hour.precipitation ?? 0, code: hour.code, visibility: hour.visibility)
    }

    /// The next sunrise or sunset after `now`: (is it sunset, its time).
    static func next(_ forecast: Forecast) -> (isSunset: Bool, time: Date)? {
        let now = forecast.now.time
        for day in forecast.days {
            if let rise = day.sunrise, rise > now { return (false, rise) }
            if let set = day.sunset, set > now { return (true, set) }
        }
        return nil
    }
}

enum Details {
    /// Which clouds there are now, from the hour's layers: "Mostly high, thin cloud."
    static func cloudLayers(_ forecast: Forecast) -> String? {
        let now = forecast.now.time
        guard let hour = forecast.hours.min(by: { abs($0.time.timeIntervalSince(now)) < abs($1.time.timeIntervalSince(now)) }),
              let low = hour.cloudLow, let mid = hour.cloudMid, let high = hour.cloudHigh else { return nil }
        return words(low: low, mid: mid, high: high)
    }

    static func words(low: Double, mid: Double, high: Double) -> String {
        if max(low, mid, high) < 10 { return "No cloud at any height." }
        if [low, mid, high].filter({ $0 >= 50 }).count >= 2 { return "Cloud at several heights." }
        if low >= mid && low >= high { return "Mostly low cloud." }
        if mid >= high { return "Mostly mid-level cloud." }
        return "Mostly high, thin cloud."
    }

    /// Visibility in both systems, the chosen one first: "8 mi" and "13 km"; under a mile or a kilometre,
    /// feet and metres ("1,600 ft", "490 m"). The same rule on every platform.
    static func visibility(_ metres: Double, miles: Bool) -> (value: String, other: String, note: String) {
        let km = metres / 1000
        let note = km >= 10 ? "Clear view." : (km >= 2 ? "Haze is cutting the view." : "Fog is cutting the view.")
        let imperial = distance(metres, imperial: true), metric = distance(metres, imperial: false)
        return miles ? (imperial, metric, note) : (metric, imperial, note)
    }

    static func distance(_ metres: Double, imperial: Bool) -> String {
        let grouped = { (n: Int) in n.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US"))) }
        if imperial {
            let mi = metres / 1609.344
            if mi >= 10 { return "\(Int(mi.rounded())) mi" }
            if mi >= 1 { return String(format: "%.1f mi", mi).replacingOccurrences(of: ".0 ", with: " ") }
            return "\(grouped(Int((metres * 3.28084 / 100).rounded()) * 100)) ft"
        }
        let km = metres / 1000
        if km >= 10 { return "\(Int(km.rounded())) km" }
        if km >= 1 { return String(format: "%.1f km", km).replacingOccurrences(of: ".0 ", with: " ") }
        return "\(Int((metres / 10).rounded()) * 10) m"
    }

    static func clouds(_ percent: Double) -> String {
        switch percent {
        case ..<10: return "Clear"
        case ..<30: return "Mostly clear"
        case ..<60: return "Partly cloudy"
        case ..<90: return "Mostly cloudy"
        default: return "Overcast"
        }
    }

    /// The precipitation the hourly forecast expects over the next 24 hours, in mm.
    static func next24Hours(_ forecast: Forecast) -> Double? {
        let hours = forecast.upcomingHours.compactMap(\.precipitation)
        return hours.isEmpty ? nil : hours.reduce(0, +)
    }
}

// MARK: - The next two hours

enum NextHours {
    static let wetStep = 0.1   // mm in 15 minutes

    /// Whether the card shows: precipitation now or in the next two hours.
    static func shows(_ forecast: Forecast) -> Bool {
        (forecast.steps ?? []).contains { $0.precipitation >= wetStep }
    }

    /// "Rain starting around 3:15 PM", "Rain stopping around 3:45 PM", "Rain for the next two hours" or
    /// "Light rain on and off".
    static func sentence(_ forecast: Forecast) -> String? {
        guard let steps = forecast.steps, !steps.isEmpty, shows(forecast) else { return nil }
        let what = Condition.isSnow(forecast.now.code) || forecast.hours.first(where: { $0.time >= forecast.now.time }).map { Condition.isSnow($0.code) } == true ? "Snow" : "Rain"
        let wet = steps.map { $0.precipitation >= wetStep }
        let time = { (i: Int) in Forecast.format(steps[i].time, "jmm") }
        if wet.allSatisfy({ $0 }) { return "\(what) for the next two hours" }
        if !wet[0], let start = wet.firstIndex(of: true) { return "\(what) starting around \(time(start))" }
        if wet[0], let stop = wet.firstIndex(of: false), !wet[stop...].contains(true) { return "\(what) stopping around \(time(stop))" }
        return "Light \(what.lowercased()) on and off"
    }
}

// MARK: - Moon

enum Moon {
    static let synodicMonth = 29.530588853
    /// The new moon of 2000-01-06 18:14 UTC.
    static let reference = Date(timeIntervalSince1970: 947_182_440)

    /// The phase's name and how much of the moon is lit (0–100).
    static func phase(at date: Date) -> (name: String, illumination: Int) {
        let days = date.timeIntervalSince(reference) / 86400
        let age = (days.truncatingRemainder(dividingBy: synodicMonth) + synodicMonth).truncatingRemainder(dividingBy: synodicMonth)
        let fraction = age / synodicMonth
        let illumination = Int(((1 - cos(2 * .pi * fraction)) / 2 * 100).rounded())
        let names = ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
                     "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"]
        return (names[Int((fraction * 8 + 0.5).rounded(.down)) % 8], illumination)
    }

    /// 0 at new moon, 0.5 at full.
    static func fraction(at date: Date) -> Double {
        let days = date.timeIntervalSince(reference) / 86400
        return ((days / synodicMonth).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
    }

    /// The next full or new moon, whichever comes first: "Full moon in 5 days", "New moon tomorrow".
    static func next(at date: Date) -> String {
        let f = fraction(at: date)
        let toFull = ((0.5 - f + 1).truncatingRemainder(dividingBy: 1)) * synodicMonth
        let toNew = ((1 - f).truncatingRemainder(dividingBy: 1)) * synodicMonth
        let (name, days) = toFull <= toNew ? ("Full moon", toFull) : ("New moon", toNew)
        let n = Int(days.rounded())
        return n == 0 ? "\(name) today." : n == 1 ? "\(name) tomorrow." : "\(name) in \(n) days."
    }
}

// MARK: - Air quality and pollen

struct AirQuality: Codable, Equatable {
    var usAQI: Double?
    var europeanAQI: Double?
    var pm25: Double?
    var pm10: Double?
    var ozone: Double?
    var nitrogenDioxide: Double?
    /// Grains per m³, Europe only: name → value.
    var pollen: [String: Double]
    /// The same hour yesterday, for "better or worse than yesterday".
    var usAQIYesterday: Double?
    var europeanAQIYesterday: Double?
    var fetchedAt: Date

    struct Reading: Equatable {
        let value: Int
        let category: String
        let scale: String        // "US AQI" or "European AQI"
        let position: Double     // 0–1 along the scale bar
        let note: String
    }

    /// The local scale: US AQI in the United States, the European AQI elsewhere.
    func reading(inUS: Bool) -> Reading? {
        let value = inUS ? usAQI : europeanAQI
        guard let value else { return nil }
        let yesterday = inUS ? usAQIYesterday : europeanAQIYesterday
        let category = inUS ? Self.usCategory(value) : Self.europeanCategory(value)
        var note: String
        if let yesterday {
            let change = value - yesterday
            note = abs(change) <= 5 ? "About the same as yesterday." : (change < 0 ? "Better than yesterday." : "Worse than yesterday.")
        } else {
            note = mainPollutant.map { "Mostly \($0)." } ?? ""
        }
        if note.isEmpty { note = category }
        return Reading(value: Int(value.rounded()), category: category, scale: inUS ? "US AQI" : "European AQI",
                       position: min(max(value / (inUS ? 300 : 100), 0), 1), note: note)
    }

    static func usCategory(_ v: Double) -> String {
        switch v {
        case ..<51: return "Good"
        case ..<101: return "Moderate"
        case ..<151: return "Unhealthy for Sensitive Groups"
        case ..<201: return "Unhealthy"
        case ..<301: return "Very Unhealthy"
        default: return "Hazardous"
        }
    }

    static func europeanCategory(_ v: Double) -> String {
        switch v {
        case ..<20: return "Good"
        case ..<40: return "Fair"
        case ..<60: return "Moderate"
        case ..<80: return "Poor"
        case ..<100: return "Very Poor"
        default: return "Extremely Poor"
        }
    }

    /// The pollutant furthest above its WHO-style guide level.
    var mainPollutant: String? {
        let ratios: [(String, Double?)] = [("PM2.5", pm25.map { $0 / 15 }), ("PM10", pm10.map { $0 / 45 }),
                                           ("ozone", ozone.map { $0 / 100 }), ("NO₂", nitrogenDioxide.map { $0 / 25 })]
        return ratios.compactMap { name, r in r.map { (name, $0) } }.max { $0.1 < $1.1 }?.0
    }

    static func pollenLevel(_ grains: Double) -> String {
        switch grains {
        case ..<10: return "Low"
        case ..<50: return "Moderate"
        case ..<200: return "High"
        default: return "Very High"
        }
    }

    /// The highest pollen and its level, and the others above Low; nil outside Europe.
    var pollenSummary: (top: String, level: String, others: [String])? {
        let present = pollen.filter { $0.value >= 0 }.sorted { $0.value > $1.value }
        guard let top = present.first else { return nil }
        let others = present.dropFirst().filter { $0.value >= 10 }.map { "\($0.key) \(Self.pollenLevel($0.value).lowercased())" }
        return (top.key, Self.pollenLevel(top.value), others)
    }
}

// MARK: - Normals and records

/// For each month-day: the 1991–2020 normal high and low (°C) and the record high and low with years.
struct Climate: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var normalHigh: Double?
        var normalLow: Double?
        var recordHigh: Double?
        var recordHighYear: Int?
        var recordLow: Double?
        var recordLowYear: Int?
    }
    /// Keyed "MM-dd".
    var days: [String: Entry]
    var fetchedAt: Date

    static func key(_ date: Date) -> String {
        let c = Forecast.localCalendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d-%02d", c.month ?? 1, c.day ?? 1)
    }

    func entry(for date: Date) -> Entry? { days[Self.key(date)] }

    /// Builds the table from the archive's daily series ("yyyy-MM-dd", max, min).
    static func build(dates: [String], highs: [Double?], lows: [Double?], fetchedAt: Date = Date()) -> Climate {
        struct Acc { var highs: [Double] = []; var lows: [Double] = []; var rh: (Double, Int)?; var rl: (Double, Int)? }
        var byDay: [String: Acc] = [:]
        var normals: [String: Acc] = [:]
        // Every month-day of a leap year, in order, so ±3 days is index arithmetic (wrapping at the year's end).
        let order: [String] = (0..<366).map { offset in
            key(Forecast.localCalendar.date(byAdding: .day, value: offset, to: Date(timeIntervalSince1970: 946_684_800))!)
        }
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        for (i, text) in dates.enumerated() {
            guard text.count >= 10, let year = Int(text.prefix(4)) else { continue }
            let key = String(text.dropFirst(5).prefix(5))
            var acc = byDay[key, default: Acc()]
            if let h = i < highs.count ? highs[i] : nil, acc.rh == nil || h > acc.rh!.0 { acc.rh = (h, year) }
            if let l = i < lows.count ? lows[i] : nil, acc.rl == nil || l < acc.rl!.0 { acc.rl = (l, year) }
            byDay[key] = acc
            // Normals: 1991–2020, each day counted toward its neighbours within ±3 days.
            guard (1991...2020).contains(year), let at = position[key] else { continue }
            for offset in -3...3 {
                let k = order[(at + offset + 366) % 366]
                var n = normals[k, default: Acc()]
                if let h = i < highs.count ? highs[i] : nil { n.highs.append(h) }
                if let l = i < lows.count ? lows[i] : nil { n.lows.append(l) }
                normals[k] = n
            }
        }
        var days: [String: Entry] = [:]
        for key in Set(byDay.keys).union(normals.keys) {
            let n = normals[key], r = byDay[key]
            let mean = { (v: [Double]) in v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
            days[key] = Entry(normalHigh: n.flatMap { mean($0.highs) }, normalLow: n.flatMap { mean($0.lows) },
                              recordHigh: r?.rh?.0, recordHighYear: r?.rh?.1, recordLow: r?.rl?.0, recordLowYear: r?.rl?.1)
        }
        return Climate(days: days, fetchedAt: fetchedAt)
    }

    /// "4° above normal", "3° below normal" or "About normal": today's high against the normal high,
    /// in whole degrees of the larger unit.
    static func comparison(high: Double, normal: Double, unit: TempUnit) -> String {
        let difference = unit.value(high) - unit.value(normal)
        if abs(difference) <= 1 { return "About normal" }
        return "\(abs(difference))° \(difference > 0 ? "above" : "below") normal"
    }
}

// MARK: - Severe weather alerts

struct WeatherAlert: Codable, Identifiable, Equatable {
    var id: String
    var event: String
    var severity: String         // Extreme, Severe, Moderate, Minor, Unknown
    var headline: String
    var description: String
    var instruction: String?
    var expires: Date?
    var sender: String

    var rank: Int { ["Extreme": 0, "Severe": 1, "Moderate": 2, "Minor": 3][severity] ?? 4 }
    /// Worth a notification: Extreme, Severe or Moderate.
    var notifies: Bool { rank <= 2 }
    /// Red for Extreme and Severe, orange for Moderate, yellow otherwise.
    var colorHex: UInt32 { rank <= 1 ? 0xE5484D : (rank == 2 ? 0xF2A65A : 0xE9C98A) }

    /// Active alerts from the National Weather Service's GeoJSON, most severe first.
    static func parseNWS(_ data: Data, now: Date = Date()) -> [WeatherAlert] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        let alerts: [WeatherAlert] = features.compactMap { feature in
            guard let p = feature["properties"] as? [String: Any], let id = p["id"] as? String ?? feature["id"] as? String,
                  let event = p["event"] as? String else { return nil }
            let expires = ((p["ends"] as? String) ?? (p["expires"] as? String)).flatMap(iso.date(from:))
            if let expires, expires <= now { return nil }
            return WeatherAlert(id: id, event: event, severity: p["severity"] as? String ?? "Unknown",
                                headline: p["headline"] as? String ?? event, description: p["description"] as? String ?? "",
                                instruction: p["instruction"] as? String, expires: expires,
                                sender: p["senderName"] as? String ?? "National Weather Service")
        }
        return alerts.sorted { $0.rank < $1.rank }
    }

    /// Whether a point is roughly in the United States (the 50 states and territories), where the
    /// National Weather Service has alerts.
    static func inUS(latitude: Double, longitude: Double) -> Bool {
        let contiguous = (24.4...49.5).contains(latitude) && (-125...(-66.8)).contains(longitude)
        let alaska = (51...72).contains(latitude) && ((-180...(-129)).contains(longitude) || (172...180).contains(longitude))
        let hawaii = (18.8...22.4).contains(latitude) && (-160.5...(-154.6)).contains(longitude)
        let territories = ((17.8...18.6).contains(latitude) && (-67.3...(-64.5)).contains(longitude))   // Puerto Rico, USVI
            || ((13.2...20.6).contains(latitude) && (144.6...146.1).contains(longitude))                // Guam, CNMI
        // A Canadian or Mexican city inside these boxes gets an error from the NWS, which reads as "no alerts".
        return contiguous || alaska || hawaii || territories
    }

    /// Local time the alert ends, for "Until 6:15 PM" (in the viewer's time zone).
    var untilText: String? {
        guard let expires else { return nil }
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate(Calendar.current.isDateInToday(expires) ? "jmm" : "EEE jmm")
        return "Until \(f.string(from: expires))"
    }
}

// MARK: - Fetching

enum WeatherServices {
    static let userAgent = "TwoDegrees (bradcowdrey.com, legal@bradcowdrey.com)"

    private static func get(_ url: URL, session: URLSession, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    private static func coords(_ city: City) -> [URLQueryItem] {
        [.init(name: "latitude", value: String(format: "%.2f", city.latitude)),
         .init(name: "longitude", value: String(format: "%.2f", city.longitude))]
    }

    static func airQuality(for city: City, session: URLSession = OpenMeteo.session) async throws -> AirQuality {
        var c = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        let pollen = ["alder", "birch", "grass", "mugwort", "olive", "ragweed"]
        c.queryItems = coords(city) + [
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "1"), .init(name: "past_days", value: "1"),
            .init(name: "current", value: "us_aqi,european_aqi,pm2_5,pm10,ozone,nitrogen_dioxide," + pollen.map { "\($0)_pollen" }.joined(separator: ",")),
            .init(name: "hourly", value: "us_aqi,european_aqi"),
        ]
        let data = try await get(c.url!, session: session)
        return try parseAirQuality(data)
    }

    static func parseAirQuality(_ data: Data, fetchedAt: Date = Date()) throws -> AirQuality {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = root["current"] as? [String: Any] else { throw URLError(.cannotParseResponse) }
        let num = { (key: String) in (current[key] as? NSNumber)?.doubleValue }
        var pollen: [String: Double] = [:]
        for (key, name) in [("alder", "Alder"), ("birch", "Birch"), ("grass", "Grass"), ("mugwort", "Mugwort"), ("olive", "Olive"), ("ragweed", "Ragweed")] {
            if let v = num("\(key)_pollen") { pollen[name] = v }
        }
        // Yesterday at the same hour: 24 entries before the current hour in the hourly series.
        var usY: Double?, euY: Double?
        if let hourly = root["hourly"] as? [String: Any], let times = hourly["time"] as? [String], let now = current["time"] as? String,
           let i = times.firstIndex(where: { $0 >= String(now.prefix(13)) }), i >= 24 {
            usY = ((hourly["us_aqi"] as? [Any])?[i - 24] as? NSNumber)?.doubleValue
            euY = ((hourly["european_aqi"] as? [Any])?[i - 24] as? NSNumber)?.doubleValue
        }
        return AirQuality(usAQI: num("us_aqi"), europeanAQI: num("european_aqi"), pm25: num("pm2_5"), pm10: num("pm10"),
                          ozone: num("ozone"), nitrogenDioxide: num("nitrogen_dioxide"), pollen: pollen,
                          usAQIYesterday: usY, europeanAQIYesterday: euY, fetchedAt: fetchedAt)
    }

    static func climate(for city: City, session: URLSession = OpenMeteo.session, now: Date = Date()) async throws -> Climate {
        var c = URLComponents(string: "https://archive-api.open-meteo.com/v1/archive")!
        let end = Calendar(identifier: .gregorian).date(byAdding: .day, value: -7, to: now) ?? now
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        c.queryItems = coords(city) + [
            .init(name: "start_date", value: "1940-01-01"), .init(name: "end_date", value: f.string(from: end)),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"), .init(name: "timezone", value: "auto"),
        ]
        let data = try await get(c.url!, session: session)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let daily = root["daily"] as? [String: Any],
              let dates = daily["time"] as? [String] else { throw URLError(.cannotParseResponse) }
        let values = { (key: String) in (daily[key] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue } }
        return Climate.build(dates: dates, highs: values("temperature_2m_max"), lows: values("temperature_2m_min"))
    }

    /// Active NWS alerts for a city; an empty list outside the US.
    static func alerts(for city: City, session: URLSession = OpenMeteo.session) async throws -> [WeatherAlert] {
        guard WeatherAlert.inUS(latitude: city.latitude, longitude: city.longitude) else { return [] }
        let url = URL(string: String(format: "https://api.weather.gov/alerts/active?point=%.2f,%.2f", city.latitude, city.longitude))!
        let data = try await get(url, session: session, headers: ["Accept": "application/geo+json"])
        return WeatherAlert.parseNWS(data)
    }
}

// MARK: - For the self-tests

extension WeatherServices {
    /// Normals and records for a city: the store's, or fetched again (up to 3 tries, 20 s apart) when the
    /// free archive service was busy. `limited` is true when it kept refusing or timing out: that is the
    /// service's limit on shared CI machines, not the app, so the check notes it instead of failing.
    @MainActor static func climateForCheck(_ city: City, store: WeatherStore) async -> (entry: Climate.Entry?, limited: Bool) {
        if let entry = store.climate[city.id]?.entry(for: Date()) { return (entry, false) }
        var limited = false
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(20)) }
            do {
                return (try await WeatherServices.climate(for: city).entry(for: Date()), false)
            } catch let error as URLError where [.badServerResponse, .timedOut, .networkConnectionLost].contains(error.code) {
                limited = true
            } catch {
                limited = false
            }
        }
        return (nil, limited)
    }
}
