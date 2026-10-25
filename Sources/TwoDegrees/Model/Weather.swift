import Foundation

/// A saved place. Coordinates are what Open-Meteo needs; the name is what people see.
struct City: Codable, Hashable, Identifiable {
    var name: String
    var region: String
    var latitude: Double
    var longitude: Double

    var id: String { String(format: "%.2f,%.2f", latitude, longitude) }
}

enum TempUnit: String, Codable, CaseIterable, Identifiable {
    case fahrenheit = "F", celsius = "C"

    var id: String { rawValue }
    var symbol: String { "°" + rawValue }
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
    }

    struct Hour: Codable, Identifiable {
        var time: Date
        var temperature: Double
        var code: Int
        var rainChance: Int
        var isDay: Bool
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
    static func name(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45: return "Fog"
        case 48: return "Freezing fog"
        case 51: return "Light drizzle"
        case 53: return "Drizzle"
        case 55: return "Heavy drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61: return "Light rain"
        case 63: return "Rain"
        case 65: return "Heavy rain"
        case 66, 67: return "Freezing rain"
        case 71: return "Light snow"
        case 73: return "Snow"
        case 75: return "Heavy snow"
        case 77: return "Snow grains"
        case 80, 81: return "Showers"
        case 82: return "Heavy showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorms"
        case 96, 99: return "Thunderstorms, hail"
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
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,is_day"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max"),
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

    static func search(_ query: String, session: URLSession = OpenMeteo.session) async throws -> [City] {
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
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double?]
            let weather_code: [Int?]
            let precipitation_probability: [Int?]
            let is_day: [Int?]
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
        }
        let timezone: String
        let current: Current
        let hourly: Hourly
        let daily: Daily

        func forecast() -> Forecast {
            let now = Forecast.Now(
                time: OpenMeteo.date(current.time) ?? Date(),
                temperature: current.temperature_2m, feelsLike: current.apparent_temperature,
                humidity: current.relative_humidity_2m, wind: current.wind_speed_10m,
                code: current.weather_code, isDay: current.is_day == 1, windDirection: current.wind_direction_10m)
            let hours: [Forecast.Hour] = hourly.time.indices.compactMap { i in
                guard let time = OpenMeteo.date(hourly.time[i]), let t = hourly.temperature_2m[i] else { return nil }
                return .init(time: time, temperature: t, code: hourly.weather_code[i] ?? 3,
                             rainChance: hourly.precipitation_probability[i] ?? 0, isDay: (hourly.is_day[i] ?? 1) == 1)
            }
            let days: [Forecast.Day] = daily.time.indices.compactMap { i in
                guard let date = OpenMeteo.date(daily.time[i]), let hi = daily.temperature_2m_max[i], let lo = daily.temperature_2m_min[i] else { return nil }
                return .init(date: date, code: daily.weather_code[i] ?? 3, high: hi, low: lo,
                             rainChance: daily.precipitation_probability_max[i] ?? 0,
                             sunrise: daily.sunrise[i].flatMap(OpenMeteo.date), sunset: daily.sunset[i].flatMap(OpenMeteo.date),
                             uvIndex: daily.uv_index_max.flatMap { i < $0.count ? $0[i] : nil })
            }
            return Forecast(now: now, hours: hours, days: days, timeZone: timezone, fetchedAt: Date())
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
        "\(TempUnit.fahrenheit.value(celsius)) degrees Fahrenheit, \(TempUnit.celsius.value(celsius)) Celsius"
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

    /// "N", "NE", … for a direction in degrees.
    static func compass(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let i = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8
        return points[i]
    }
}
