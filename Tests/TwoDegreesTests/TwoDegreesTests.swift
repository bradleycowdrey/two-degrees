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
        XCTAssertEqual(TempUnit.fahrenheit.symbol, "\u{200A}°\u{200A}F")
        XCTAssertEqual(TempUnit.fahrenheit.label, "°F")
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
        XCTAssertTrue(line.contains(TempUnit.celsius.symbol) && line.contains(TempUnit.fahrenheit.symbol), line)
    }
}

// MARK: - Stubbed network

/// Answers requests from a table instead of the network, so updater flows run hermetically.
final class StubProtocol: URLProtocol {
    /// url prefix → (status, body, final URL after redirects)
    nonisolated(unsafe) static var routes: [(String, Int, Data, URL?)] = []
    /// Seconds to wait before answering, to hold a request "in flight".
    nonisolated(unsafe) static var delay: TimeInterval = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!.absoluteString
        guard let route = Self.routes.first(where: { url.hasPrefix($0.0) }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: route.3 ?? request.url!, statusCode: route.1, httpVersion: nil, headerFields: nil)!
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay) {
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: route.2)
            self.client?.urlProtocolDidFinishLoading(self)
        }
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

    override func setUp() { StubProtocol.delay = 0 }

    func testUserCheckDuringAutomaticCheckIsAnswered() async throws {
        StubProtocol.routes = [(api, 200, release("0.2.2"), nil)]
        StubProtocol.delay = 0.4
        let u = updater("0.2.2")
        let automatic = Task { await u.check(userInitiated: false) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(u.phase, .checking)
        await u.check(userInitiated: true)
        XCTAssertTrue(u.userChecking, "shows Checking… instead of ignoring the click")
        await automatic.value
        XCTAssertTrue(u.notice?.text.contains("up to date") ?? false, "the user hears the result")
    }

    func testUserCheckDuringInstallIsAnswered() async {
        let u = updater("0.2.2")
        u.selfTestShow(phase: .downloading)
        await u.check(userInitiated: true)
        XCTAssertTrue(u.notice?.text.contains("already being installed") ?? false)
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

    func testWidgetsFollowTheAppsCities() {
        let ny = City(name: "New York", region: "", latitude: 40.71, longitude: -74.01)
        let sf = City(name: "San Francisco", region: "", latitude: 37.77, longitude: -122.42)
        let snapshot = SharedCities.Snapshot(cities: [ny, sf], activeID: sf.id)
        // "The city showing in Two Degrees" follows the app; a saved city stays put.
        XCTAssertEqual(SharedCities.resolve(SharedCities.currentID, in: snapshot), sf)
        XCTAssertEqual(SharedCities.resolve(nil, in: snapshot), sf)
        XCTAssertEqual(SharedCities.resolve(ny.id, in: snapshot), ny)
        // A city since removed from the app falls back to the one showing.
        XCTAssertEqual(SharedCities.resolve("1.00,1.00", in: snapshot), sf)
        // Round trip through the shared defaults.
        let defaults = UserDefaults(suiteName: "TwoDegrees.tests.shared")!
        defaults.removePersistentDomain(forName: "TwoDegrees.tests.shared")
        SharedCities.save(snapshot, to: defaults)
        XCTAssertEqual(SharedCities.load(from: defaults), snapshot)
    }

    func testWeatherTerms() {
        // Magnus formula: 20 °C at 50 % → about 9.3 °C; saturated air → the temperature itself.
        XCTAssertEqual(Meteo.dewPoint(celsius: 20, humidity: 50), 9.3, accuracy: 0.1)
        XCTAssertEqual(Meteo.dewPoint(celsius: 15, humidity: 100), 15, accuracy: 0.05)
        XCTAssertEqual([0.0, 2.9, 3, 6, 8, 11].map(Meteo.uvLevel), ["Low", "Low", "Moderate", "High", "Very high", "Extreme"])
        XCTAssertEqual([0.0, 22, 23, 90, 180, 270, 337, 350, 359, -10].map(Meteo.compass), ["N", "N", "NE", "E", "S", "W", "NW", "N", "N", "N"])
        XCTAssertEqual([0.0, 135, 315].map(Meteo.compassName), ["north", "southeast", "northwest"])
    }

    func testMenuBarPanelCentersUnderItsItem() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        // Centred under the item.
        XCTAssertEqual(MenuBarPlacement.centeredX(itemMidX: 1000, width: 400, visible: screen), 800)
        // Near a screen edge it stays on screen.
        XCTAssertEqual(MenuBarPlacement.centeredX(itemMidX: 1400, width: 400, visible: screen), 1040)
        XCTAssertEqual(MenuBarPlacement.centeredX(itemMidX: 50, width: 400, visible: screen), 0)
        // A second display to the right.
        XCTAssertEqual(MenuBarPlacement.centeredX(itemMidX: 2000, width: 300, visible: CGRect(x: 1440, y: 0, width: 1920, height: 1055)), 1850)
    }
}

@MainActor
final class StoreTests: XCTestCase {
    var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "TwoDegreesTests-\(UUID().uuidString)")
        StubProtocol.delay = 0
        StubProtocol.routes = [("https://api.open-meteo.com/v1/forecast", 200, Data(Fixtures.forecast.utf8), nil)]
        OpenMeteo.session = StubProtocol.session()
    }

    func testStartsWithThreeCitiesAndRestoresTheActiveOne() {
        let store = WeatherStore(defaults: defaults, autoRefresh: false)
        XCTAssertEqual(store.cities.map(\.name), ["New York", "London", "Tokyo"])
        store.activeID = store.cities[2].id
        let again = WeatherStore(defaults: defaults, autoRefresh: false)
        XCTAssertEqual(again.active.name, "Tokyo")
    }

    func testAddLimitRemoveAndPersistence() {
        let store = WeatherStore(defaults: defaults, autoRefresh: false)
        store.add(City(name: "Paris", region: "France", latitude: 48.85, longitude: 2.35))
        XCTAssertEqual(store.active.name, "Paris")
        store.add(City(name: "Paris", region: "France", latitude: 48.85, longitude: 2.35))
        XCTAssertEqual(store.cities.count, 4, "no duplicates")
        store.add(City(name: "Rome", region: "Italy", latitude: 41.9, longitude: 12.5))
        XCTAssertFalse(store.canAdd)
        store.add(City(name: "Cairo", region: "Egypt", latitude: 30, longitude: 31))
        XCTAssertEqual(store.cities.count, 5, "the limit holds")
        store.remove(store.active)
        XCTAssertEqual(store.active.name, "New York", "removing the active city selects the first")
        XCTAssertEqual(WeatherStore(defaults: defaults, autoRefresh: false).cities.count, 4, "cities persist")
        while store.cities.count > 1 { store.remove(store.cities.last!) }
        store.remove(store.cities[0])
        XCTAssertEqual(store.cities.count, 1, "the last city stays")
    }

    func testRefreshLoadsEveryCity() async {
        let store = WeatherStore(defaults: defaults, autoRefresh: false)
        await store.refresh()
        XCTAssertEqual(store.forecasts.count, 3)
        XCTAssertFalse(store.isOffline)
    }

    func testRemovingACityWhileItLoadsLeavesNothingBehind() async throws {
        let store = WeatherStore(defaults: defaults, autoRefresh: false)
        StubProtocol.delay = 0.4
        let paris = City(name: "Paris", region: "France", latitude: 48.85, longitude: 2.35)
        store.add(paris)
        store.remove(paris)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertNil(store.forecasts[paris.id], "a late forecast for a removed city is dropped")
        let saved = WeatherStore(defaults: defaults, autoRefresh: false)
        XCTAssertNil(saved.forecasts[paris.id], "and never saved")
    }

    func testFailedFetchMarksOffline() async {
        StubProtocol.routes = [("https://api.open-meteo.com/v1/forecast", 500, Data(), nil)]
        let store = WeatherStore(defaults: defaults, autoRefresh: false)
        await store.refresh()
        XCTAssertTrue(store.isOffline)
        XCTAssertNil(store.activeForecast)
    }

    func testMenuBarText() {
        XCTAssertEqual(MenuBarLabel.reading(17.6, unit: .fahrenheit, style: .both), "64° · 18°")
        XCTAssertEqual(MenuBarLabel.reading(17.6, unit: .celsius, style: .both), "18° · 64°")
        XCTAssertEqual(MenuBarLabel.reading(17.6, unit: .fahrenheit, style: .primary), "64°")
        XCTAssertNil(MenuBarLabel.reading(17.6, unit: .fahrenheit, style: .icon))
    }
}

/// The install helper script swaps the app in, or rolls back if the copy fails.
final class InstallScriptTests: XCTestCase {
    func run(target: URL, new: URL, in dir: URL) throws {
        let script = dir.appendingPathComponent("install.sh")
        // Don't actually relaunch anything.
        try Updater.installScript
            .replacingOccurrences(of: "/usr/bin/open \"$TARGET\"", with: "true")
            .write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, "999999", target.path, new.path]   // a pid that isn't running
        try process.run()
        process.waitUntilExit()
    }

    func makeApp(_ url: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try marker.write(to: url.appendingPathComponent("Contents/marker"), atomically: true, encoding: .utf8)
    }

    func marker(_ url: URL) -> String? { try? String(contentsOf: url.appendingPathComponent("Contents/marker"), encoding: .utf8) }

    func testUpdateEndsTheOldWidgetProcess() {
        // The old version's widget process must not outlive the update (its widgets would stay grey).
        let script = Updater.installScript
        XCTAssertTrue(script.contains("/usr/bin/pkill -x TwoDegreesWidget"))
        XCTAssertLessThan(script.range(of: "pkill")!.lowerBound, script.range(of: "/usr/bin/open")!.lowerBound)
    }

    func testRegistersTheNewVersionWithLaunchServices() {
        // Without this, macOS keeps the old build number and rejects the widget's content.
        XCTAssertTrue(Updater.installScript.contains("lsregister -f \"$TARGET\""))
    }

    func testSwapsInTheNewApp() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = dir.appendingPathComponent("TwoDegrees.app"), new = dir.appendingPathComponent("staged/TwoDegrees.app")
        try makeApp(target, marker: "old")
        try makeApp(new, marker: "new")
        try run(target: target, new: new, in: dir)
        XCTAssertEqual(marker(target), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path + ".old"))
    }

    func testRollsBackWhenTheCopyFails() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = dir.appendingPathComponent("TwoDegrees.app"), missing = dir.appendingPathComponent("nothing-here.app")
        try makeApp(target, marker: "old")
        try run(target: target, new: missing, in: dir)
        XCTAssertEqual(marker(target), "old", "the old app is restored")
    }
}

/// The widget's data path (WidgetData): its city setting, search, and what it shows when the network fails.
final class WidgetDataTests: XCTestCase {
    private let forecastURL = "https://api.open-meteo.com/v1/forecast"
    private let searchURL = "https://geocoding-api.open-meteo.com/v1/search"

    override func setUp() { StubProtocol.delay = 0 }

    private func freshDefaults() -> UserDefaults {
        let name = "TwoDegrees.tests.widget.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    func testCitySettingReadsBackWithAccentsPipesAndEdgeCoordinates() {
        let cities = [City(name: "São Paulo", region: "São Paulo, Brazil", latitude: -23.5475, longitude: -46.63611),
                      City(name: "A|B", region: "C|D", latitude: 0.00001, longitude: -180),
                      City(name: "Reykjavík", region: "", latitude: 64.13548, longitude: -21.89541)]
        for city in cities {
            let back = WidgetData.city(fromID: WidgetData.id(for: city))
            XCTAssertEqual(back?.latitude, city.latitude)
            XCTAssertEqual(back?.longitude, city.longitude)
            XCTAssertEqual(back?.name, city.name.replacingOccurrences(of: "|", with: "/"))
        }
        XCTAssertNil(WidgetData.city(fromID: "Nowhere|x|abc|1"))
        XCTAssertNil(WidgetData.city(fromID: "Too|many|parts|1|2"))
        XCTAssertNil(WidgetData.city(fromID: "Off|map|95|0"))
    }

    func testPickedCityLoadsAndIsSavedForOffline() async throws {
        StubProtocol.routes = [(forecastURL, 200, Data(Fixtures.forecast.utf8), nil)]
        let defaults = freshDefaults()
        let city = WidgetData.city(fromID: WidgetData.id(for: City(name: "New York", region: "", latitude: 40.71, longitude: -74.01)))!
        let live = await WidgetData.entry(city: city, unit: .celsius, defaults: defaults, session: StubProtocol.session())
        XCTAssertFalse(live.failed || live.unavailable || live.isPlaceholder)
        XCTAssertEqual(WidgetData.refreshInterval(for: live), 30 * 60)

        StubProtocol.routes = []   // now offline: the saved forecast, marked offline
        let offline = await WidgetData.entry(city: city, unit: .celsius, defaults: defaults, session: StubProtocol.session())
        XCTAssertTrue(offline.failed)
        XCTAssertFalse(offline.unavailable)
        XCTAssertEqual(offline.forecast.days.count, live.forecast.days.count)
        XCTAssertEqual(WidgetData.refreshInterval(for: offline), 5 * 60)
    }

    func testOfflineWithNothingSavedSaysSoInsteadOfGoingBlank() async {
        StubProtocol.routes = []
        let e = await WidgetData.entry(city: City(name: "Nowhere", region: "", latitude: 1, longitude: 1),
                                       unit: .fahrenheit, defaults: freshDefaults(), session: StubProtocol.session())
        XCTAssertTrue(e.unavailable)
        XCTAssertFalse(e.isPlaceholder, "the redacted placeholder can look like an empty widget")
        XCTAssertEqual(WidgetData.refreshInterval(for: e), 5 * 60)
    }

    func testSearchNeverThrowsAndShortQueriesShowSuggestions() async {
        let suggestions = [City(name: "Paris", region: "France", latitude: 48.85, longitude: 2.35)]
        StubProtocol.routes = []
        let none = await WidgetData.search("Denver", suggestions: suggestions, session: StubProtocol.session())
        XCTAssertEqual(none.count, 0)
        let short = await WidgetData.search(" D ", suggestions: suggestions, session: StubProtocol.session())
        XCTAssertEqual(short.map(\.name), ["Paris"])
        let body = #"{"results":[{"name":"Denver","latitude":39.73915,"longitude":-104.9847,"country":"United States","admin1":"Colorado"}]}"#
        StubProtocol.routes = [(searchURL, 200, Data(body.utf8), nil)]
        let found = await WidgetData.search("Denver", suggestions: suggestions, session: StubProtocol.session())
        XCTAssertEqual(found.first?.region, "Colorado, United States")
    }
}

/// The Terms prompt asks on a first launch and after the terms change, and not otherwise.
final class TermsTests: XCTestCase {
    func testAskedOnFirstLaunchAndAfterAChangeOnly() {
        let defaults = UserDefaults(suiteName: "TwoDegrees.tests.terms.\(UUID().uuidString)")!
        XCTAssertFalse(Terms.accepted(in: defaults))
        defaults.set(Brand.termsVersion, forKey: Terms.key)
        XCTAssertTrue(Terms.accepted(in: defaults))
        defaults.set("2020-01-01", forKey: Terms.key)
        XCTAssertFalse(Terms.accepted(in: defaults))
    }
}
