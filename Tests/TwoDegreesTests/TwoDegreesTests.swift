import XCTest
import AppKit
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

// MARK: - Stubbed network

/// Answers requests from a table instead of the network, so updater flows run hermetically.
final class StubProtocol: URLProtocol {
    /// url prefix → (status, body, final URL after redirects)
    nonisolated(unsafe) static var routes: [(String, Int, Data, URL?)] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!.absoluteString
        guard let route = Self.routes.first(where: { url.hasPrefix($0.0) }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: route.3 ?? request.url!, statusCode: route.1, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: route.2)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }
}

@MainActor
final class UpdaterFlowTests: XCTestCase {
    let api = "https://api.github.com/repos/bradleycowdrey/two-degrees/releases/latest"
    let page = "https://github.com/bradleycowdrey/two-degrees/releases/latest"

    func release(_ version: String) -> Data {
        Data(#"{"tag_name":"v\#(version)","html_url":"https://github.com/x","assets":[{"name":"TwoDegrees-\#(version).dmg","browser_download_url":"https://github.com/d/TwoDegrees-\#(version).dmg"},{"name":"TwoDegrees-\#(version).dmg.sha256","browser_download_url":"https://github.com/d/TwoDegrees-\#(version).dmg.sha256"}]}"#.utf8)
    }

    func updater(_ version: String) -> Updater {
        let updater = Updater(currentVersion: version)
        updater.session = StubProtocol.session()
        return updater
    }

    func testNewerReleaseIsOffered() async {
        StubProtocol.routes = [(api, 200, release("0.3.0"), nil)]
        let u = updater("0.2.2")
        await u.check(userInitiated: true)
        XCTAssertEqual(u.latest?.version, "0.3.0")
        XCTAssertEqual(u.phase, .available)
        XCTAssertFalse(u.userChecking)
    }

    func testSameVersionSaysUpToDate() async {
        StubProtocol.routes = [(api, 200, release("0.2.2"), nil)]
        let u = updater("0.2.2")
        await u.check(userInitiated: true)
        XCTAssertNil(u.latest)
        XCTAssertEqual(u.phase, .upToDate)
        XCTAssertEqual(u.notice?.isError, false)
        XCTAssertTrue(u.notice?.text.contains("up to date") ?? false)
    }

    func testRateLimitedAPIFallsBackToReleasePage() async {
        let tag = URL(string: "https://github.com/bradleycowdrey/two-degrees/releases/tag/v0.4.1")!
        StubProtocol.routes = [(api, 403, Data(), nil), (page, 200, Data(), tag)]
        let u = updater("0.2.2")
        await u.check(userInitiated: true)
        XCTAssertEqual(u.latest?.version, "0.4.1")
        XCTAssertEqual(u.latest?.dmg.lastPathComponent, "TwoDegrees-0.4.1.dmg")
    }

    func testBothFailingShowsAnErrorTheUserCanSee() async {
        StubProtocol.routes = [(api, 403, Data(), nil), (page, 503, Data(), nil)]
        let u = updater("0.2.2")
        await u.check(userInitiated: true)
        XCTAssertEqual(u.notice?.isError, true)
        XCTAssertTrue(u.notice?.text.contains("HTTP 503") ?? false, u.notice?.text ?? "")
    }

    func testFailedRecheckKeepsAFoundUpdate() async {
        StubProtocol.routes = [(api, 200, release("0.3.0"), nil)]
        let u = updater("0.2.2")
        await u.check(userInitiated: false)
        StubProtocol.routes = [(api, 500, Data(), nil), (page, 500, Data(), nil)]
        await u.check(userInitiated: false)
        XCTAssertEqual(u.phase, .available, "a failed re-check must not hide the update")
        XCTAssertEqual(u.latest?.version, "0.3.0")
    }

    func testAutomaticCheckIsQuiet() async {
        StubProtocol.routes = [(api, 200, release("0.2.2"), nil)]
        let u = updater("0.2.2")
        await u.check(userInitiated: false)
        XCTAssertNil(u.notice)
    }

    func testMissingChecksumRefusesToInstall() async {
        StubProtocol.routes = [("https://github.com/d/TwoDegrees-0.3.0.dmg.sha256", 404, Data("Not Found".utf8), nil),
                               ("https://github.com/d/TwoDegrees-0.3.0.dmg", 200, Data("dmg".utf8), nil)]
        let u = updater("0.2.2")
        let release = Updater.Release(version: "0.3.0", notes: "", dmg: URL(string: "https://github.com/d/TwoDegrees-0.3.0.dmg")!,
                                      sha256: URL(string: "https://github.com/d/TwoDegrees-0.3.0.dmg.sha256")!, page: URL(string: "https://github.com/x")!)
        do {
            _ = try await u.stage(release)
            XCTFail("staged without a checksum")
        } catch {
            XCTAssertEqual(error.localizedDescription, UpdateError.noChecksum.localizedDescription)
        }
    }

    func testTamperedDownloadFailsChecksum() async {
        StubProtocol.routes = [("https://github.com/d/TwoDegrees-0.3.0.dmg.sha256", 200, Data((String(repeating: "a", count: 64) + "  TwoDegrees-0.3.0.dmg\n").utf8), nil),
                               ("https://github.com/d/TwoDegrees-0.3.0.dmg", 200, Data("not the real dmg".utf8), nil)]
        let u = updater("0.2.2")
        let release = Updater.Release(version: "0.3.0", notes: "", dmg: URL(string: "https://github.com/d/TwoDegrees-0.3.0.dmg")!,
                                      sha256: URL(string: "https://github.com/d/TwoDegrees-0.3.0.dmg.sha256")!, page: URL(string: "https://github.com/x")!)
        do {
            _ = try await u.stage(release)
            XCTFail("staged a tampered download")
        } catch {
            XCTAssertEqual(error.localizedDescription, UpdateError.checksum.localizedDescription)
        }
    }

    func testChecksumLineParsing() {
        XCTAssertEqual(Updater.expectedChecksum(Data("ABCdef  TwoDegrees.dmg\n".utf8)), "abcdef")
        XCTAssertEqual(Updater.expectedChecksum(Data()), "")
    }
}

final class MoreLogicTests: XCTestCase {
    func testHalvesRoundAwayFromZeroLikeTheWebApp() {
        XCTAssertEqual(TempUnit.celsius.value(-2.5), -3)
        XCTAssertEqual(TempUnit.celsius.value(2.5), 3)
        XCTAssertEqual(TempUnit.fahrenheit.value(-19.7), -3)   // -3.46°F
    }

    func testUpcomingHoursStartAtTheCurrentHourEvenOffTheHour() throws {
        // "now" at 23:15 must still start at the 23:00 hour, not midnight.
        let json = Fixtures.forecast.replacingOccurrences(of: #""time":"2026-10-17T23:00","temperature_2m":17.8"#, with: #""time":"2026-10-17T23:15","temperature_2m":17.8"#)
        let forecast = try OpenMeteo.decodeForecast(Data(json.utf8))
        XCTAssertEqual(Forecast.localCalendar.component(.hour, from: forecast.upcomingHours[0].time), 23)
    }

    func testUnreadableNowIsRefused() {
        let json = Fixtures.forecast.replacingOccurrences(of: #""time":"2026-10-17T23:00","temperature_2m":17.8"#, with: #""time":"later","temperature_2m":17.8"#)
        XCTAssertThrowsError(try OpenMeteo.decodeForecast(Data(json.utf8)))
    }

    func testWindowPlacement() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 492, height: 600)
        XCTAssertEqual(WindowPlacement.topLeft(for: .edge(.left), size: size, visible: screen), NSPoint(x: 16, y: 884))
        XCTAssertEqual(WindowPlacement.topLeft(for: .edge(.center), size: size, visible: screen), NSPoint(x: 474, y: 884))
        XCTAssertEqual(WindowPlacement.topLeft(for: .edge(.right), size: size, visible: screen), NSPoint(x: 932, y: 884))
    }
}
