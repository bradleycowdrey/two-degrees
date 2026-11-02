import Foundation

/// A saved place. Coordinates are what Open-Meteo needs; the name is what people see.
struct City: Codable, Hashable, Identifiable {
    var name: String
    var region: String
    var latitude: Double
    var longitude: Double
    /// Where you are now (Use My Location), kept up to date by the app, rather than a city you added.
    var isCurrent = false

    init(name: String, region: String, latitude: Double, longitude: Double, isCurrent: Bool = false) {
        self.name = name
        self.region = region
        self.latitude = latitude
        self.longitude = longitude
        self.isCurrent = isCurrent
    }

    // Cities saved before Use My Location have no isCurrent.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        region = try c.decode(String.self, forKey: .region)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        isCurrent = try c.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
    }

    /// Where you are has one ID wherever you go, so the page, its forecast and widgets following it stay put.
    var id: String { isCurrent ? City.currentID : String(format: "%.2f,%.2f", latitude, longitude) }
    static let currentID = "here"

    /// Whether two cities are the same place: the same name within 25 km, or anything within 2 km. Where
    /// you are and a saved city that's the same place share one card.
    static func samePlace(_ a: City, _ b: City) -> Bool {
        let k = cos(a.latitude * .pi / 180)
        var dx = abs(a.longitude - b.longitude)
        if dx > 180 { dx = 360 - dx }
        let km = ((a.latitude - b.latitude) * (a.latitude - b.latitude) + (dx * k) * (dx * k)).squareRoot() * 111
        let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        return km <= 2 || (km <= 25 && fold(a.name) == fold(b.name))
    }
}

enum TempUnit: String, Codable, CaseIterable, Identifiable {
    case fahrenheit = "F", celsius = "C"

    var id: String { rawValue }
    /// A reading's unit: hair spaces either side of the degree sign, the thinnest there are, so the
    /// number, the degree sign and the letter don't crowd.
    var symbol: String { "\u{200A}°\u{200A}" + rawValue }

    /// "°F" with no spacing: for controls and labels (the °F | °C switch, menus, hints) and copied text.
    var label: String { "°" + rawValue }

    /// A reading with its unit ("18 °C"). The spacing is in `symbol`, so every reading gets it.
    func spaced(_ value: Int) -> String { "\(value)\(symbol)" }
    var other: TempUnit { self == .fahrenheit ? .celsius : .fahrenheit }

    /// Whole degrees in this unit, from Celsius.
    func value(_ celsius: Double) -> Int {
        Int((self == .fahrenheit ? celsius * 9 / 5 + 32 : celsius).rounded())
    }

    /// °F where the locale measures in Fahrenheit (US and a few others), otherwise °C.
    static var localeDefault: TempUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }
}

/// One city's forecast, in Celsius and km/h, with times as the city's local wall-clock.
struct Forecast: Codable {
    struct Now: Codable {
        var time: Date
        var temperature: Double
        var feelsLike: Double
        var humidity: Double
        var wind: Double
        var code: Int
        var isDay: Bool
        /// Degrees the wind comes from (0 = north). Absent in forecasts saved before it was fetched.
        var windDirection: Double? = nil
        // 0.5's details. Each is absent in older saved forecasts, which hides its tile.
        var pressure: Double? = nil        // hPa, at sea level
        var cloudCover: Double? = nil      // %
        var gusts: Double? = nil           // km/h
        var visibility: Double? = nil      // m
        var precipitation: Double? = nil   // mm in the last hour
    }

    struct Hour: Codable, Identifiable {
        var time: Date
        var temperature: Double
        var code: Int
        var rainChance: Int
        var isDay: Bool
        var precipitation: Double? = nil   // mm
        var wind: Double? = nil            // km/h
        var gusts: Double? = nil           // km/h
        var pressure: Double? = nil        // hPa
        var cloudLow: Double? = nil        // % of the sky, low cloud (up to ~2 km)
        var cloudMid: Double? = nil        // %, mid-level cloud (~2–6 km)
        var cloudHigh: Double? = nil       // %, high cloud (above ~6 km)
        var visibility: Double? = nil      // metres
        var id: Date { time }
    }

    /// One 15-minute step of the next two hours.
    struct Step: Codable, Identifiable {
        var time: Date
        var precipitation: Double          // mm in the 15 minutes
        var id: Date { time }
    }

    struct Day: Codable, Identifiable {
        var date: Date
        var code: Int
        var high: Double
        var low: Double
        var rainChance: Int
        var sunrise: Date?
        var sunset: Date?
        /// The day's highest UV index. Absent in forecasts saved before it was fetched.
        var uvIndex: Double? = nil
        var precipitation: Double? = nil   // mm, rain and melted snow
        var snowfall: Double? = nil        // cm
        var windMax: Double? = nil         // km/h
        var gustMax: Double? = nil         // km/h
        var windDirection: Double? = nil   // dominant, degrees
        var id: Date { date }

        /// This day with its range widened to include a reading, so today never contradicts "now".
        func including(_ celsius: Double) -> Day {
            var day = self
            day.low = min(low, celsius)
            day.high = max(high, celsius)
            return day
        }
    }

    var now: Now
    var hours: [Hour]
    var days: [Day]
    var timeZone: String
    var fetchedAt: Date
    /// The next two hours in 15-minute steps (precipitation only). Absent in older saved forecasts.
    var steps: [Step]? = nil

    /// The hours of one day (by its date), for the day detail.
    func hours(on day: Day) -> [Hour] {
        let calendar = Forecast.localCalendar
        return hours.filter { calendar.isDate($0.time, inSameDayAs: day.date) }
    }

    /// The next 24 hours starting with the current one.
    var upcomingHours: [Hour] {
        // The first hour at or after the start of the current hour (never midnight by accident).
        let calendar = Forecast.localCalendar
        let hourStart = calendar.dateInterval(of: .hour, for: now.time)?.start ?? now.time
        let start = hours.firstIndex { $0.time >= hourStart } ?? hours.count
        return Array(hours.dropFirst(start).prefix(24))
    }

    /// Times arrive as local wall-clock strings, so they're stored as if they were GMT and
    /// always formatted in GMT. That keeps "3 PM" meaning 3 PM in that city, wherever you are.
    static let localCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func format(_ date: Date, _ template: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

/// WMO weather codes as names and SF Symbols.
enum Condition {
    /// In title case, as Apple's Weather shows conditions ("Partly Cloudy").
    static func name(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45: return "Fog"
        case 48: return "Freezing Fog"
        case 51: return "Light Drizzle"
        case 53: return "Drizzle"
        case 55: return "Heavy Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61: return "Light Rain"
        case 63: return "Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71: return "Light Snow"
        case 73: return "Snow"
        case 75: return "Heavy Snow"
        case 77: return "Snow Grains"
        case 80, 81: return "Showers"
        case 82: return "Heavy Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorms"
        case 96, 99: return "Thunderstorms with Hail"
        default: return "Cloudy"
        }
    }

    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 80, 81: return isDay && code >= 80 ? "cloud.sun.rain.fill" : "cloud.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func isWet(_ code: Int) -> Bool { code >= 51 }
    static func isSnow(_ code: Int) -> Bool { [71, 73, 75, 77, 85, 86].contains(code) }
}

/// Open-Meteo: free, open source, no key. https://open-meteo.com
enum OpenMeteo {
    /// Swapped for a stubbed session in unit tests.
    nonisolated(unsafe) static var session: URLSession = .shared

    static func forecast(for city: City, session: URLSession = OpenMeteo.session) async throws -> Forecast {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", city.latitude)),
            .init(name: "longitude", value: String(format: "%.4f", city.longitude)),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "11"),   // the iPhone shows 10 days; the Mac and widgets 5
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day,pressure_msl,cloud_cover,wind_gusts_10m,visibility,precipitation"),
            .init(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,is_day,precipitation,wind_speed_10m,wind_gusts_10m,cloud_cover_low,cloud_cover_mid,cloud_cover_high,visibility"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max,precipitation_sum,snowfall_sum,wind_speed_10m_max,wind_gusts_10m_max,wind_direction_10m_dominant"),
            .init(name: "minutely_15", value: "precipitation"),
            .init(name: "forecast_minutely_15", value: "8"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("TwoDegrees", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try decodeForecast(data)
    }

    /// Open-Meteo's forecast JSON → Forecast (separate so it can be unit tested).
    static func decodeForecast(_ data: Data) throws -> Forecast {
        let raw = try JSONDecoder().decode(Response.self, from: data)
        // Without a readable "now", every time on screen would be wrong: refuse the response.
        guard OpenMeteo.date(raw.current.time) != nil else { throw URLError(.cannotParseResponse) }
        return raw.forecast()
    }

    /// Open-Meteo's geocoder; with the internet out, the bundled city list (OfflineCities).
    static func search(_ query: String, session: URLSession = OpenMeteo.session) async throws -> [City] {
        do {
            return try await searchOnline(query, session: session)
        } catch is URLError {
            let offline = await Task.detached(priority: .userInitiated) { OfflineCities.search(query) }.value
            if offline.isEmpty { throw URLError(.notConnectedToInternet) }
            return offline
        }
    }

    private static func searchOnline(_ query: String, session: URLSession) async throws -> [City] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            .init(name: "name", value: query),
            .init(name: "count", value: "8"),
            .init(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en"),
        ]
        let (data, _) = try await session.data(from: components.url!)
        let raw = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (raw.results ?? []).map {
            City(name: $0.name, region: [$0.admin1, $0.country].compactMap { $0 }.joined(separator: ", "),
                 latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    // MARK: Wire format

    private struct Response: Decodable {
        struct Current: Decodable {
            let time: String
            let temperature_2m: Double
            let apparent_temperature: Double
            let relative_humidity_2m: Double
            let weather_code: Int
            let wind_speed_10m: Double
            let wind_direction_10m: Double?
            let is_day: Int
            let pressure_msl: Double?
            let cloud_cover: Double?
            let wind_gusts_10m: Double?
            let visibility: Double?
            let precipitation: Double?
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double?]
            let weather_code: [Int?]
            let precipitation_probability: [Int?]
            let is_day: [Int?]
            let precipitation: [Double?]?
            let wind_speed_10m: [Double?]?
            let wind_gusts_10m: [Double?]?
            let pressure_msl: [Double?]?
            let cloud_cover_low: [Double?]?
            let cloud_cover_mid: [Double?]?
            let cloud_cover_high: [Double?]?
            let visibility: [Double?]?
        }
        struct Minutely: Decodable {
            let time: [String]
            let precipitation: [Double?]
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int?]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_probability_max: [Int?]
            let sunrise: [String?]
            let sunset: [String?]
            let uv_index_max: [Double?]?
            let precipitation_sum: [Double?]?
            let snowfall_sum: [Double?]?
            let wind_speed_10m_max: [Double?]?
            let wind_gusts_10m_max: [Double?]?
            let wind_direction_10m_dominant: [Double?]?
        }
        let timezone: String
        let current: Current
        let hourly: Hourly
        let daily: Daily
        let minutely_15: Minutely?

        func forecast() -> Forecast {
            let now = Forecast.Now(
                time: OpenMeteo.date(current.time) ?? Date(),
                temperature: current.temperature_2m, feelsLike: current.apparent_temperature,
                humidity: current.relative_humidity_2m, wind: current.wind_speed_10m,
                code: current.weather_code, isDay: current.is_day == 1, windDirection: current.wind_direction_10m,
                pressure: current.pressure_msl, cloudCover: current.cloud_cover, gusts: current.wind_gusts_10m,
                visibility: current.visibility, precipitation: current.precipitation)
            let at = { (list: [Double?]?, i: Int) -> Double? in list.flatMap { i < $0.count ? $0[i] : nil } }
            let hours: [Forecast.Hour] = hourly.time.indices.compactMap { i in
                guard let time = OpenMeteo.date(hourly.time[i]), let t = hourly.temperature_2m[i] else { return nil }
                return .init(time: time, temperature: t, code: hourly.weather_code[i] ?? 3,
                             rainChance: hourly.precipitation_probability[i] ?? 0, isDay: (hourly.is_day[i] ?? 1) == 1,
                             precipitation: at(hourly.precipitation, i), wind: at(hourly.wind_speed_10m, i),
                             gusts: at(hourly.wind_gusts_10m, i), pressure: at(hourly.pressure_msl, i),
                             cloudLow: at(hourly.cloud_cover_low, i), cloudMid: at(hourly.cloud_cover_mid, i),
                             cloudHigh: at(hourly.cloud_cover_high, i), visibility: at(hourly.visibility, i))
            }
            let days: [Forecast.Day] = daily.time.indices.compactMap { i in
                guard let date = OpenMeteo.date(daily.time[i]), let hi = daily.temperature_2m_max[i], let lo = daily.temperature_2m_min[i] else { return nil }
                return .init(date: date, code: daily.weather_code[i] ?? 3, high: hi, low: lo,
                             rainChance: daily.precipitation_probability_max[i] ?? 0,
                             sunrise: daily.sunrise[i].flatMap(OpenMeteo.date), sunset: daily.sunset[i].flatMap(OpenMeteo.date),
                             uvIndex: at(daily.uv_index_max, i), precipitation: at(daily.precipitation_sum, i),
                             snowfall: at(daily.snowfall_sum, i), windMax: at(daily.wind_speed_10m_max, i),
                             gustMax: at(daily.wind_gusts_10m_max, i), windDirection: at(daily.wind_direction_10m_dominant, i))
            }
            let steps: [Forecast.Step]? = minutely_15.map { m in
                m.time.indices.compactMap { i in
                    guard let time = OpenMeteo.date(m.time[i]) else { return nil }
                    return .init(time: time, precipitation: i < m.precipitation.count ? (m.precipitation[i] ?? 0) : 0)
                }
            }
            return Forecast(now: now, hours: hours, days: days, timeZone: timezone, fetchedAt: Date(), steps: steps)
        }
    }

    private struct SearchResponse: Decodable {
        struct Place: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }
        let results: [Place]?
    }

    /// "2026-10-17T14:00" or "2026-10-17", read as GMT wall-clock (see Forecast.localCalendar).
    static func date(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = string.count > 10 ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}

/// Both units, as VoiceOver says them.
enum Speech {
    static func temperature(_ celsius: Double) -> String {
        "\(TempUnit.fahrenheit.value(celsius)) degrees Fahrenheit, \(TempUnit.celsius.value(celsius)) degrees Celsius"
    }
}

/// Weather terms shared by the apps: dew point, UV levels and compass points.
enum Meteo {
    /// Dew point in °C from temperature (°C) and relative humidity (%), by the Magnus formula.
    static func dewPoint(celsius t: Double, humidity rh: Double) -> Double {
        let a = 17.62, b = 243.12
        let gamma = log(max(rh, 1) / 100) + a * t / (b + t)
        return b * gamma / (a - gamma)
    }

    /// The WHO's UV index categories.
    static func uvLevel(_ index: Double) -> String {
        switch index {
        case ..<3: return "Low"
        case ..<6: return "Moderate"
        case ..<8: return "High"
        case ..<11: return "Very high"
        default: return "Extreme"
        }
    }

    /// "north", "northeast", … for a direction in degrees, for sentences.
    static func compassName(_ degrees: Double) -> String {
        ["N": "north", "NE": "northeast", "E": "east", "SE": "southeast",
         "S": "south", "SW": "southwest", "W": "west", "NW": "northwest"][compass(degrees)] ?? compass(degrees)
    }

    /// "N", "NE", … for a direction in degrees.
    static func compass(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let i = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8
        return points[i]
    }
}
