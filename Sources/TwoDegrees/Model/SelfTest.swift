import SwiftUI
import AppKit
import WidgetKit
import CoreServices

/// Functional self-test, used by CI on a real Mac: `TwoDegrees --selftest <dir>` opens the
/// window with live data and exercises every function at every size, checking each result,
/// saving a PNG of each state and writing report.txt (PASS / FAIL lines), then quits.
/// Inert unless that launch argument is present.
@MainActor
enum SelfTest {
    nonisolated static let outputDir: URL? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }()

    nonisolated static var isActive: Bool { outputDir != nil }

    private static var started = false
    /// The panel's own measurements, reported by WeatherPanel as it lays out.
    private static var contentHeight: CGFloat = 0
    private static var maxBodyHeight: CGFloat = 0
    private static var panelWidth: CGFloat = 0

    static func panelMeasured(content: CGFloat, maxBody: CGFloat, width: CGFloat) {
        contentHeight = content
        maxBodyHeight = maxBody
        panelWidth = width
    }
    private static var lines: [String] = []
    private static var failures = 0

    private static func check(_ ok: Bool, _ what: String) {
        if !ok { failures += 1 }
        lines.append("\(ok ? "PASS" : "FAIL") \(what)")
    }

    private static func note(_ text: String) { lines.append("     \(text)") }

    static func run(store: WeatherStore, adding: Binding<Bool>, editing: Binding<Bool>, daysOpen: Binding<Bool>, host: HostWindow) async {
        guard let dir = outputDir, !started else { return }
        started = true
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        note("screen visible frame \(Int(screen.width))x\(Int(screen.height)), version \(Updater.shared.currentVersion)")

        // 1. Live data for every saved city.
        for _ in 0..<40 where store.cities.contains(where: { store.forecasts[$0.id] == nil }) {
            try? await Task.sleep(for: .milliseconds(500))
        }
        for city in store.cities {
            let f = store.forecasts[city.id]
            check(f != nil, "forecast loaded for \(city.name)")
            if let f {
                check(f.upcomingHours.count == 24, "\(city.name): 24 upcoming hours (got \(f.upcomingHours.count))")
                check(f.days.count >= 5, "\(city.name): at least 5 days (got \(f.days.count))")
                check((-60...60).contains(f.now.temperature), "\(city.name): plausible temperature \(f.now.temperature)°C")
                check(f.days.allSatisfy { $0.low <= $0.high }, "\(city.name): every day's low is at or below its high")
            }
        }

        check(!daysOpen.wrappedValue, "5-day forecast starts closed")

        // 2. Every size × state: base (forecast closed), forecast open, adding, editing, °C. Window must fit its content and stay on screen.
        let states: [(String, () -> Void)] = [
            ("base", { adding.wrappedValue = false; editing.wrappedValue = false; daysOpen.wrappedValue = false; store.unit = .fahrenheit }),
            ("forecast-open", { daysOpen.wrappedValue = true }),
            ("adding", { editing.wrappedValue = false; adding.wrappedValue = true }),
            ("editing", { adding.wrappedValue = false; editing.wrappedValue = true }),
            ("celsius", { editing.wrappedValue = false; store.unit = .celsius }),
            ("forecast-closed-again", { daysOpen.wrappedValue = false }),
        ]
        for (index, size) in UISize.allCases.enumerated() {
            store.uiSize = size
            for (name, apply) in states {
                apply()
                try? await Task.sleep(for: .seconds(1.2))
                layoutCheck(host: host, screen: screen, label: "\(size.rawValue) \(name)")
                snapshot(host: host, dir: dir, name: "panel-\(index)-\(size.rawValue)-\(name).png")
            }
        }
        store.uiSize = .medium
        store.unit = .fahrenheit
        adding.wrappedValue = false
        editing.wrappedValue = false

        // 3. Unit toggle and city switching.
        store.toggleUnit()
        check(store.unit == .celsius, "unit toggles to °C")
        store.toggleUnit()
        check(store.unit == .fahrenheit, "unit toggles back to °F")
        for city in store.cities {
            store.select(city)
            try? await Task.sleep(for: .seconds(0.8))
            check(store.activeID == city.id, "select \(city.name)")
            snapshot(host: host, dir: dir, name: "city-\(city.name.replacingOccurrences(of: " ", with: "-")).png")
        }
        store.select(store.cities[0])

        // 4. Add and remove a city (search goes to Open-Meteo's geocoder).
        let before = store.cities.count
        let found = (try? await OpenMeteo.search("Denver")) ?? []
        check(!found.isEmpty, "city search finds Denver (\(found.first?.region ?? "nothing"))")
        let offline = OfflineCities.search("Denver")
        check(OfflineCities.all.count > 20000 && offline.first?.name == "Denver",
              "offline city search: \(OfflineCities.all.count) cities bundled, finds Denver (\(offline.first?.region ?? "nothing"))")
        if let denver = found.first {
            store.add(denver)
            check(store.cities.count == before + 1 && store.activeID == denver.id, "add Denver and select it")
            for _ in 0..<20 where store.forecasts[denver.id] == nil { try? await Task.sleep(for: .milliseconds(500)) }
            check(store.forecasts[denver.id] != nil, "forecast loads for added city")
            store.add(denver)
            check(store.cities.count == before + 1, "adding the same city twice doesn't duplicate it")
            store.remove(denver)
            check(store.cities.count == before && store.activeID != denver.id, "remove Denver")
        }
        while store.canAdd { store.add(City(name: "Test \(store.cities.count)", region: "", latitude: Double(store.cities.count), longitude: 0)) }
        check(store.cities.count == WeatherStore.maxCities && !store.canAdd, "city limit is \(WeatherStore.maxCities)")
        for city in store.cities where city.name.hasPrefix("Test ") { store.remove(city) }
        check(store.cities.count == before, "test cities removed")

        // 5. Window position: each request lands flush with that edge (16pt margin), top-aligned.
        for placement in WindowPlacement.allCases {
            WindowPlacement.request(.edge(placement))
            try? await Task.sleep(for: .seconds(1.2))
            guard let window = host.window else { check(false, "position \(placement.rawValue): no window"); continue }
            let f = window.frame
            let expectedX: CGFloat
            switch placement {
            case .left: expectedX = screen.minX + 16
            case .center: expectedX = (screen.midX - f.width / 2).rounded()
            case .right: expectedX = screen.maxX - f.width - 16
            }
            check(abs(f.minX - expectedX) <= 1 && abs(f.maxY - (screen.maxY - 16)) <= 1,
                  "position \(placement.rawValue): x \(Int(f.minX)) expected \(Int(expectedX)), top \(Int(f.maxY)) expected \(Int(screen.maxY - 16))")
        }

        // 6. Updates: a real check against GitHub, then a real download, checksum and unpack.
        let updater = Updater.shared
        await updater.check(userInitiated: true)
        try? await Task.sleep(for: .seconds(0.6))
        check(updater.latest != nil, "update check finds the latest release (\(updater.latest?.version ?? "none"); phase \(updater.phase))")
        snapshot(host: host, dir: dir, name: "update-1-available.png")
        let staged = await updater.selfTestStage()
        check(staged.hasPrefix("PASS"), "update download, checksum and unpack: \(staged)")
        updater.selfTestShow(phase: .downloading)
        try? await Task.sleep(for: .seconds(0.6))
        snapshot(host: host, dir: dir, name: "update-2-downloading.png")
        let newest = updater.latest?.version ?? "?"
        updater.selfTestShow(phase: .upToDate, notice: "You’re up to date. Two Degrees \(newest) is the newest version.", clearLatest: true)
        try? await Task.sleep(for: .seconds(0.6))
        snapshot(host: host, dir: dir, name: "update-3-up-to-date.png")
        updater.selfTestShow(phase: .failed("x"), notice: "Couldn’t check for updates. GitHub didn’t respond.", error: true)
        try? await Task.sleep(for: .seconds(0.6))
        snapshot(host: host, dir: dir, name: "update-4-error.png")
        updater.selfTestShow(phase: .idle, notice: nil)

        // 7. Dock tile and widgets, rendered offscreen at 2x; each must have real content.
        if let forecast = store.activeForecast {
            for (t, name) in [(forecast.now.temperature, "dock-tile.png"), (-23.4, "dock-tile-negative.png"), (40.6, "dock-tile-105F.png")] {
                let ok = render(DockTileView(primary: TempUnit.fahrenheit.value(t), primaryUnit: .fahrenheit,
                                             secondary: TempUnit.celsius.value(t), code: forecast.now.code, isDay: forecast.now.isDay)
                    .frame(width: 128, height: 128), dir: dir, name: name)
                check(ok, "Dock tile renders \(TempUnit.fahrenheit.value(t))°F / \(TempUnit.celsius.value(t))°C (\(name))")
            }
            let entry = WeatherEntry(date: Date(), city: store.active, unit: store.unit, forecast: forecast)
            var offline = entry
            offline.failed = true
            let sizes: [(WidgetFamily, CGSize, String)] = [
                (.systemSmall, CGSize(width: 170, height: 170), "small"),
                (.systemMedium, CGSize(width: 364, height: 170), "medium"),
                (.systemLarge, CGSize(width: 364, height: 382), "large"),
            ]
            for (family, size, name) in sizes {
                for (variant, e) in [("", entry), ("-offline", offline)] {
                    let ok = render(WidgetView(entry: e, family: family)
                        .padding(16)
                        .frame(width: size.width, height: size.height)
                        .background(WidgetBackground())
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)),
                                    dir: dir, name: "widget-\(name)\(variant).png")
                    check(ok, "\(name) widget\(variant.isEmpty ? "" : " (offline)") renders")
                }
            }
        } else {
            check(false, "dock tile and widgets: no forecast")
        }

        // 8. The widget's own data path, run the way the widget runs it: a city searched for and
        //    picked in the widget's settings, stored as its setting, rebuilt from it, loaded and drawn
        //    in every size, within the few seconds a widget gets. Then offline with nothing saved.
        let widgetSizes: [(WidgetFamily, CGSize, String)] = [
            (.systemSmall, CGSize(width: 170, height: 170), "small"),
            (.systemMedium, CGSize(width: 364, height: 170), "medium"),
            (.systemLarge, CGSize(width: 364, height: 382), "large"),
        ]
        func drawWidget(_ e: WeatherEntry, _ family: WidgetFamily, _ size: CGSize, _ name: String) -> Bool {
            render(WidgetView(entry: e, family: family)
                .padding(16)
                .frame(width: size.width, height: size.height)
                .background(WidgetBackground())
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)), dir: dir, name: name)
        }
        let widgetDefaults = UserDefaults(suiteName: "TwoDegrees.selftest.widget") ?? .standard
        widgetDefaults.removePersistentDomain(forName: "TwoDegrees.selftest.widget")
        for city in [City(name: "São Paulo", region: "São Paulo, Brazil", latitude: -23.5475, longitude: -46.63611),
                     City(name: "Pipe | Town", region: "A|B", latitude: -0.0001, longitude: 179.99)] {
            let back = WidgetData.city(fromID: WidgetData.id(for: city))
            check(back?.latitude == city.latitude && back?.longitude == city.longitude && back?.name == city.name.replacingOccurrences(of: "|", with: "/"),
                  "widget setting reads back for \(city.name)")
        }
        check(await WidgetData.search(" ", suggestions: [store.active]).map(\.name) == [store.active.name], "widget search under two letters shows the suggestions")
        for query in ["Denver", "Sao Paulo", "Zürich", "Reykjavík"] {
            let started = Date()
            let found = await WidgetData.search(query, suggestions: [])
            guard let first = found.first else { check(false, "widget search finds \(query)"); continue }
            check(true, "widget search finds \(query): \(first.name), \(first.region)")
            guard let picked = WidgetData.city(fromID: WidgetData.id(for: first)) else { check(false, "\(first.name): widget setting doesn't read back"); continue }
            let entry = await WidgetData.entry(city: picked, unit: .celsius, defaults: widgetDefaults)
            let seconds = Date().timeIntervalSince(started)
            check(!entry.failed && !entry.unavailable && entry.forecast.days.count >= 5 && entry.forecast.upcomingHours.count >= 6,
                  "widget loads \(picked.name) after picking it (\(String(format: "%.1f", seconds)) s)")
            check(seconds < 12, "widget has \(picked.name)'s numbers within 12 s")
            let slug = picked.name.lowercased().filter(\.isLetter)
            for (family, size, name) in widgetSizes {
                check(drawWidget(entry, family, size, "widget-picked-\(slug)-\(name).png"), "\(name) widget draws \(picked.name)")
            }
        }
        let offlineConfig = URLSessionConfiguration.ephemeral
        offlineConfig.protocolClasses = [OfflineProtocol.self]
        let nowhere = City(name: "Nowhere Yet", region: "", latitude: 10, longitude: 10)
        let unreachable = await WidgetData.entry(city: nowhere, unit: .fahrenheit, defaults: widgetDefaults, session: URLSession(configuration: offlineConfig))
        check(unreachable.unavailable && !unreachable.isPlaceholder && WidgetData.refreshInterval(for: unreachable) <= 5 * 60,
              "widget offline with nothing saved says it couldn't load (not blank) and retries within 5 minutes")
        for (family, size, name) in widgetSizes {
            check(drawWidget(unreachable, family, size, "widget-unavailable-\(name).png"), "\(name) widget draws the couldn't-load message")
        }

        // The app re-registers its exact build at launch, so macOS never judges the widget against a stale version.
        check(LSRegisterURL(Bundle.main.bundleURL as CFURL, true) == noErr, "app registers its own build with LaunchServices")

        // The first-launch Terms prompt: the real dialog on screen, photographed, then I Agree pressed.
        let termsDefaults = UserDefaults(suiteName: "TwoDegrees.selftest.terms") ?? .standard
        termsDefaults.removePersistentDomain(forName: "TwoDegrees.selftest.terms")
        check(!Terms.accepted(in: termsDefaults), "terms: a first launch hasn't agreed yet, so it asks")
        var termsButtons: [String] = []
        var termsText = ""
        let agreed = Terms.ask(defaults: termsDefaults, quit: false) { alert in
            termsButtons = alert.buttons.map(\.title)
            termsText = alert.messageText + " " + alert.informativeText
            if let content = alert.window.contentView, let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("terms-prompt.png"))
            }
            alert.buttons.first?.performClick(nil)
        }
        check(termsButtons == ["I Agree", "Read the Terms", "Quit"], "terms: the dialog offers I Agree, Read the Terms and Quit (\(termsButtons.joined(separator: ", ")))")
        check(termsText.contains("bradcowdrey.com/legal") && termsText.contains("Open-Meteo"), "terms: the dialog names the terms page and where locations go")
        check(agreed && Terms.accepted(in: termsDefaults), "terms: I Agree is remembered, so it isn't asked again")
        termsDefaults.set("an-older-version", forKey: Terms.key)
        check(Terms.accepted(in: termsDefaults), "terms: a change within a month of agreeing waits (at most one ask a month)")
        termsDefaults.set(Date().addingTimeInterval(-31 * 24 * 3600).timeIntervalSince1970, forKey: TermsSchedule.dateKey)
        check(!Terms.accepted(in: termsDefaults), "terms: after the terms change, and a month on, it asks again")

        // 8b. The menu bar panel: click the menu bar item, and the panel opens centred under it.
        if let item = NSApp.windows.first(where: { $0.className.contains("StatusBarWindow") && $0.isVisible }),
           let button = findStatusButton(in: item.contentView) {
            let others = Set(NSApp.windows.map(ObjectIdentifier.init))
            button.performClick(nil)
            var panel: NSWindow?
            for _ in 0..<20 where panel == nil {
                try? await Task.sleep(for: .milliseconds(250))
                panel = NSApp.windows.first { !others.contains(ObjectIdentifier($0)) && $0.isVisible && $0.frame.width > 100 }
                    ?? NSApp.windows.first { $0.isVisible && $0.className.contains("MenuBarExtra") }
            }
            try? await Task.sleep(for: .seconds(0.8))
            if let panel, let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
                let expected = MenuBarPlacement.centeredX(itemMidX: item.frame.midX, width: panel.frame.width, visible: visible)
                check(abs(panel.frame.minX - expected) <= 1 && panel.frame.maxY <= item.frame.minY + 1,
                      "menu bar panel opens centred under its item: item centre \(Int(item.frame.midX)), panel \(Int(panel.frame.minX))–\(Int(panel.frame.maxX)) (centre \(Int(panel.frame.midX))), expected left \(Int(expected))")
                if let content = panel.contentView, let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                    content.cacheDisplay(in: content.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("menu-bar-panel.png"))
                }
                panel.orderOut(nil)
            } else {
                check(false, "menu bar panel: clicking the menu bar item opened no panel")
            }
        } else {
            check(false, "menu bar panel: no menu bar item found")
        }

        // 9. Logic checks that need no UI.
        let fromTag = try? Updater.release(fromTagPage: URL(string: "https://github.com/bradleycowdrey/two-degrees/releases/tag/v1.2.3")!)
        check(fromTag?.version == "1.2.3" && fromTag?.dmg.lastPathComponent == "TwoDegrees-1.2.3.dmg", "update fallback reads the version from the release page")
        check(Updater.isNewer("0.2.10", than: "0.2.9") && !Updater.isNewer("0.2.0", than: "0.2.0") && Updater.isNewer("1.0", than: "0.9.9-dev"),
              "version comparison")
        let ticks = Ticks.make(low: 0, high: 25, unit: .fahrenheit)
        check(ticks.map(\.label) == [40, 50, 60, 70], "five-day scale ticks every 10°F (got \(ticks.map(\.label)))")

        lines.insert("\(failures == 0 ? "ALL PASSED" : "\(failures) FAILED") (\(lines.filter { $0.hasPrefix("PASS") }.count) passed)", at: 0)
        try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    /// The window must be exactly the panel's width, fully on screen, and only scroll when the
    /// panel is taller than the screen allows.
    private static func layoutCheck(host: HostWindow, screen: CGRect, label: String) {
        guard let window = host.window, let content = window.contentView else {
            check(false, "\(label): no window")
            return
        }
        let bounds = content.bounds
        let widthOK = panelWidth > 0 && abs(panelWidth - bounds.width) <= 1
        let onScreen = screen.isEmpty || screen.insetBy(dx: -1, dy: -1).contains(window.frame)
        let scrolls = contentHeight > maxBodyHeight + 1
        let screenFull = window.frame.height >= screen.height - 80
        // On a normal laptop screen (800pt+ tall), the closed panel must fit without scrolling.
        let roomy = screen.height >= 800 && !label.contains("forecast-open") && !label.contains("adding")
        check(widthOK && onScreen && contentHeight > 0 && (!scrolls || screenFull) && !(roomy && scrolls),
              "\(label): window \(Int(window.frame.width))x\(Int(window.frame.height)), panel \(Int(panelWidth)) wide, content \(Int(contentHeight)) tall"
              + (scrolls ? " (scrolls: screen allows \(Int(maxBodyHeight)))" : " (fits)")
              + (widthOK ? "" : " WIDTH MISMATCH") + (onScreen ? "" : " OFFSCREEN"))
    }

    private static func findStatusButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        for sub in view.subviews { if let b = findStatusButton(in: sub) { return b } }
        return nil
    }

    private static func snapshot(host: HostWindow, dir: URL, name: String) {
        guard let content = host.window?.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
    }

    /// Renders offscreen at 2x, saves the PNG, and returns whether it has real content
    /// (more than one colour), so a blank render fails.
    @discardableResult
    private static func render<V: View>(_ view: V, dir: URL, name: String) -> Bool {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return false }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        try? png.write(to: dir.appendingPathComponent(name))
        var colours = Set<UInt32>()
        for y in stride(from: 0, to: rep.pixelsHigh, by: max(1, rep.pixelsHigh / 24)) {
            for x in stride(from: 0, to: rep.pixelsWide, by: max(1, rep.pixelsWide / 24)) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                colours.insert(UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255))
            }
        }
        return colours.count > 3
    }
}

/// Fails every request as if offline, for the widget's no-network check.
final class OfflineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
