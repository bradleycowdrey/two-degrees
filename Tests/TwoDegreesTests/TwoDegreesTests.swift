import XCTest
@testable import TwoDegrees

final class UpdaterTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(Updater.isNewer("0.2.2", than: "0.2.1"))
        XCTAssertTrue(Updater.isNewer("0.2.10", than: "0.2.9"))
        XCTAssertTrue(Updater.isNewer("1.0", than: "0.9.9"))
        XCTAssertTrue(Updater.isNewer("0.2.2", than: "0.0.0-selftest"))
        XCTAssertFalse(Updater.isNewer("0.2.2", than: "0.2.2"))
        XCTAssertFalse(Updater.isNewer("0.2.1", than: "0.2.2"))
        XCTAssertFalse(Updater.isNewer("0.2", than: "0.2.0"))
    }

    /// The real GitHub API response for the v0.2.2 release.
    func testParsesRealRelease() throws {
        let json = #"""
{"assets":[{"browser_download_url":"https://github.com/bradleycowdrey/two-degrees/releases/download/v0.2.2/TwoDegrees-0.2.2.dmg","name":"TwoDegrees-0.2.2.dmg"},{"browser_download_url":"https://github.com/bradleycowdrey/two-degrees/releases/download/v0.2.2/TwoDegrees-0.2.2.dmg.sha256","name":"TwoDegrees-0.2.2.dmg.sha256"},{"browser_download_url":"https://github.com/bradleycowdrey/two-degrees/releases/download/v0.2.2/TwoDegrees.dmg","name":"TwoDegrees.dmg"}],"body":"Download the DMG, open it and drag Two Degrees into Applications. First launch: right-click Two Degrees, then Open. Made by Bradley Cowdrey · bradcowdrey.com","draft":false,"html_url":"https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.2.2","prerelease":false,"tag_name":"v0.2.2"}
"""#
        let release = try Updater.parse(Data(json.utf8))
        XCTAssertEqual(release.version, "0.2.2")
        XCTAssertEqual(release.dmg.lastPathComponent, "TwoDegrees-0.2.2.dmg", "prefers the versioned DMG")
        XCTAssertEqual(release.sha256?.lastPathComponent, "TwoDegrees-0.2.2.dmg.sha256")
    }

    func testFallbackReadsVersionFromReleasePage() throws {
        let release = try Updater.release(fromTagPage: URL(string: "https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.3.0")!)
        XCTAssertEqual(release.version, "0.3.0")
        XCTAssertEqual(release.dmg.absoluteString, "https://github.com/bradleycowdrey/two-degrees/releases/download/v0.3.0/TwoDegrees-0.3.0.dmg")
        XCTAssertEqual(release.sha256?.lastPathComponent, "TwoDegrees-0.3.0.dmg.sha256")
        XCTAssertThrowsError(try Updater.release(fromTagPage: URL(string: "https://github.com/bradleycowdrey/two-degrees/releases")!))
    }

    func testReleaseWithoutDMGIsAnError() {
        let json = #"{"tag_name":"v9.9.9","html_url":"https://example.com","assets":[]}"#
        XCTAssertThrowsError(try Updater.parse(Data(json.utf8)))
    }
}

final class WeatherTests: XCTestCase {
    func testUnits() {
        XCTAssertEqual(TempUnit.fahrenheit.value(0), 32)
        XCTAssertEqual(TempUnit.fahrenheit.value(100), 212)
        XCTAssertEqual(TempUnit.fahrenheit.value(-40), -40)
        XCTAssertEqual(TempUnit.fahrenheit.value(37), 99)   // 98.6 rounds to 99
        XCTAssertEqual(TempUnit.celsius.value(17.6), 18)
        XCTAssertEqual(TempUnit.celsius.other, .fahrenheit)
        XCTAssertEqual(TempUnit.fahrenheit.symbol, "°F")
    }

    func testDateParsingIsCityLocal() throws {
        let date = try XCTUnwrap(OpenMeteo.date("2026-10-17T14:00"))
        XCTAssertEqual(Forecast.localCalendar.component(.hour, from: date), 14)
        XCTAssertNotNil(OpenMeteo.date("2026-10-17"))
        XCTAssertNil(OpenMeteo.date("not a date"))
    }

    func testDecodesOpenMeteoAndPicksUpcomingHours() throws {
        let forecast = try OpenMeteo.decodeForecast(Data(Fixtures.forecast.utf8))
        XCTAssertEqual(forecast.timeZone, "America/New_York")
        XCTAssertEqual(forecast.now.temperature, 17.8, accuracy: 0.001)
        XCTAssertEqual(forecast.days.count, 6)
        XCTAssertEqual(forecast.hours.count, 48)
        let upcoming = forecast.upcomingHours
        XCTAssertEqual(upcoming.count, 24)
        XCTAssertEqual(Forecast.localCalendar.component(.hour, from: upcoming[0].time), 23, "starts at the current hour")
        XCTAssertEqual(upcoming[1].rainChance, 60)
    }

    func testDecodesNullsInArrays() throws {
        let json = Fixtures.forecast.replacingOccurrences(of: "\"precipitation_probability_max\":[10,", with: "\"precipitation_probability_max\":[null,")
        let forecast = try OpenMeteo.decodeForecast(Data(json.utf8))
        XCTAssertEqual(forecast.days[0].rainChance, 0)
    }

    func testTodayIncludesNow() {
        let day = Forecast.Day(date: Date(), code: 1, high: 20, low: 10, rainChance: 0, sunrise: nil, sunset: nil)
        XCTAssertEqual(day.including(8).low, 8)
        XCTAssertEqual(day.including(25).high, 25)
        XCTAssertEqual(day.including(15).low, 10)
    }

    func testConditions() {
        XCTAssertEqual(Condition.name(0), "Clear")
        XCTAssertEqual(Condition.symbol(0, isDay: false), "moon.stars.fill")
        XCTAssertEqual(Condition.symbol(95, isDay: true), "cloud.bolt.rain.fill")
        XCTAssertTrue(Condition.isSnow(73))
        XCTAssertFalse(Condition.isSnow(63))
        XCTAssertEqual(Condition.name(12345), "Cloudy")
    }
}

final class PanelLogicTests: XCTestCase {
    func testTicks() {
        // 0–25°C is 32–77°F: ticks at 40, 50, 60, 70°F.
        XCTAssertEqual(Ticks.make(low: 0, high: 25, unit: .fahrenheit).map(\.label), [40, 50, 60, 70])
        XCTAssertEqual(Ticks.make(low: 0, high: 25, unit: .celsius).map(\.label), [5, 10, 15, 20])
        // Ticks within 5% of either end are dropped so they never sit on a bar's cap.
        XCTAssertFalse(Ticks.make(low: 10, high: 20, unit: .celsius).map(\.label).contains(10))
    }

    func testSummaryMentionsRainFirst() throws {
        let forecast = try OpenMeteo.decodeForecast(Data(Fixtures.forecast.utf8))
        XCTAssertTrue(Summary.line(forecast, unit: .fahrenheit).hasPrefix("Rain likely around"), Summary.line(forecast, unit: .fahrenheit))
    }

    func testSummaryShowsBothUnits() throws {
        let dry = Fixtures.forecast.replacingOccurrences(of: "60,", with: "0,")
        let forecast = try OpenMeteo.decodeForecast(Data(dry.utf8))
        let line = Summary.line(forecast, unit: .celsius)
        XCTAssertTrue(line.contains("°C") && line.contains("°F"), line)
    }
}
