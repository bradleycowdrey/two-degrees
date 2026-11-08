import SwiftUI
import WidgetKit

/// CI: `--selftest` runs the iPhone app against live data in the Simulator and writes report.txt and
/// PNGs of every widget size (Home Screen and Lock Screen) to the app's Documents folder, which the
/// workflow copies out. The app's screens themselves are photographed by the Simulator.
@MainActor
enum PhoneSelfTest {
    nonisolated static let isActive = ProcessInfo.processInfo.arguments.contains("--selftest")
    /// Scrolls the city page down to the 10-day forecast, for a screenshot.
    nonisolated static let showDays = ProcessInfo.processInfo.arguments.contains("--show-days")
    /// Scrolls the city page to the bottom of its detail tiles, for a screenshot.
    nonisolated static let showTiles = ProcessInfo.processInfo.arguments.contains("--show-tiles")
    /// Opens the city list at launch, for a screenshot.
    nonisolated static let showList = ProcessInfo.processInfo.arguments.contains("--show-list")
    /// Opens tomorrow's day detail at launch, for a screenshot.
    nonisolated static let showDay = ProcessInfo.processInfo.arguments.contains("--show-day")
    /// Checks Use My Location (CI grants the permission and sets the Simulator's location first).
    nonisolated static let locate = ProcessInfo.processInfo.arguments.contains("--locate")
    /// Shows the "Show the weather where you are?" question, for a screenshot.
    nonisolated static let showLocationPrompt = ProcessInfo.processInfo.arguments.contains("--show-location-prompt")

    private static var lines: [String] = []
    private static var failures = 0

    private static func check(_ ok: Bool, _ what: String) {
        lines.append("\(ok ? "PASS" : "FAIL") \(what)")
        if !ok { failures += 1 }
    }

    static func run(store: WeatherStore) async {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        // 1. Every starter city's forecast loads, with the ten days the iPhone shows.
        for _ in 0..<40 where store.cities.contains(where: { store.forecasts[$0.id] == nil }) {
            try? await Task.sleep(for: .milliseconds(500))
        }
        for city in store.cities {
            let forecast = store.forecasts[city.id]
            check(forecast != nil && (forecast?.days.count ?? 0) >= 10 && (forecast?.upcomingHours.count ?? 0) >= 24,
                  "forecast loads for \(city.name): \(forecast?.days.count ?? 0) days, \(forecast?.upcomingHours.count ?? 0) hours")
        }

        if let forecast = store.activeForecast {
            check(forecast.days.first?.uvIndex != nil && forecast.now.windDirection != nil,
                  "UV index and wind direction arrive (UV \(forecast.days.first?.uvIndex.map { String($0) } ?? "none"), wind from \(forecast.now.windDirection.map(Meteo.compass) ?? "none"))")
        }

        // 0.5's details, with live data for the first city.
        let first = store.cities[0]
        if let f = store.forecasts[first.id] {
            check(f.steps?.count == 8, "\(first.name): the next two hours in 15-minute steps (\(f.steps?.count ?? 0))")
            check(f.now.pressure != nil && f.now.cloudCover != nil && f.days.first?.precipitation != nil, "\(first.name): pressure, cloud cover and today's precipitation arrive")
        }
        for _ in 0..<60 where store.airQuality[first.id] == nil || store.climate[first.id] == nil { try? await Task.sleep(for: .milliseconds(500)) }
        let reading = store.airQuality[first.id]?.reading(inUS: WeatherAlert.inUS(latitude: first.latitude, longitude: first.longitude))
        check(reading != nil, "\(first.name): air quality \(reading.map { "\($0.value) \($0.category)" } ?? "missing")")
        let (entry, limited) = await WeatherServices.climateForCheck(first, store: store)
        check(entry?.normalHigh != nil || (entry == nil && limited),
              entry == nil && limited ? "\(first.name): normals and records skipped: the archive service is limiting or not answering" : "\(first.name): normals and records load")
        check(WeatherStore.maxCities == 20, "up to 20 cities")

        // 2. Unit switch, both ways.
        let unit = store.unit
        store.unit = unit.other
        check(store.unit == unit.other, "switch the larger unit to \(unit.other.symbol)")
        store.unit = unit
        check(store.unit == unit, "switch it back to \(unit.symbol)")

        // Use My Location: where the Simulator says you are, first in the list and shown, and gone again
        // when the setting is turned off.
        if locate {
            store.locate = { await LocationService.shared.currentCity() }
            check(store.needsLocationPrompt, "a first launch asks whether to use your location")
            store.answerLocationPrompt(true)
            await store.updateLocation()
            let here = store.cities.first
            check(store.locationStatus == .found && here?.isCurrent == true && store.activeID == here?.id,
                  "Use My Location finds \(here?.isCurrent == true ? here!.name + ", " + here!.region : "nothing (\(store.locationStatus))") and shows it first")
            for _ in 0..<20 where store.forecasts[City.currentID] == nil { try? await Task.sleep(for: .milliseconds(500)) }
            check(store.forecasts[City.currentID] != nil, "where you are: its forecast loads")
            try? await Task.sleep(for: .seconds(2))   // a moment on screen for the screenshot
            store.useLocation = false
            for _ in 0..<10 where store.cities.contains(where: \.isCurrent) { try? await Task.sleep(for: .milliseconds(200)) }
            check(!store.cities.contains(where: \.isCurrent), "turning Use My Location off removes it")
            store.useLocation = true   // and back on, so the screenshots show it
            await store.updateLocation()
            check(store.cities.first?.isCurrent == true, "turning it back on brings it back")
            store.select(store.cities[0])
        }

        // 3. Search, add and remove a city.
        let before = store.cities.count
        let found = (try? await OpenMeteo.search("Denver")) ?? []
        check(!found.isEmpty, "city search finds Denver (\(found.first?.region ?? "nothing"))")
        let offline = OfflineCities.search("Denver")
        check(OfflineCities.all.count > 20000 && offline.first?.name == "Denver",
              "offline city search: \(OfflineCities.all.count) cities bundled, finds Denver (\(offline.first?.region ?? "nothing"))")
        if let denver = found.first {
            store.add(denver)
            for _ in 0..<20 where store.forecasts[denver.id] == nil { try? await Task.sleep(for: .milliseconds(500)) }
            check(store.forecasts[denver.id] != nil && store.activeID == denver.id, "add Denver: selected and its forecast loads")
            if locate {
                // The Simulator is in Denver: Denver becomes My Location instead of a second card.
                check(store.hereID == denver.id && !store.cities.contains(where: \.isCurrent),
                      "adding the city you're in makes it My Location, with no second card")
            }
            store.remove(denver)
            check(store.cities.count == before, "remove Denver")
            if locate { check(store.cities.first?.isCurrent == true, "removing it brings back My Location as its own card") }
        }
        widgetLinks(store)

        // 4. The widget's data path, as the widget runs it, and every size drawn.
        let defaults = UserDefaults(suiteName: "TwoDegrees.selftest.widget") ?? .standard
        let sizes: [(WidgetFamily, CGSize, String)] = [
            (.systemSmall, CGSize(width: 170, height: 170), "small"),
            (.systemMedium, CGSize(width: 364, height: 170), "medium"),
            (.systemLarge, CGSize(width: 364, height: 382), "large"),
            (.accessoryCircular, CGSize(width: 76, height: 76), "lock-circular"),
            (.accessoryRectangular, CGSize(width: 172, height: 76), "lock-rectangular"),
            (.accessoryInline, CGSize(width: 257, height: 26), "lock-inline"),
        ]
        for query in ["Denver", "Zürich"] {
            let started = Date()
            guard let first = await WidgetData.search(query, suggestions: []).first,
                  let picked = WidgetData.city(fromID: WidgetData.id(for: first)) else {
                check(false, "widget search finds \(query)"); continue
            }
            let entry = await WidgetData.entry(city: picked, unit: .fahrenheit, defaults: defaults)
            check(!entry.failed && !entry.unavailable && entry.forecast.days.count >= 5,
                  "widget loads \(picked.name) (\(String(format: "%.1f", Date().timeIntervalSince(started))) s)")
            let slug = picked.name.lowercased().filter(\.isLetter)
            for (family, size, name) in sizes {
                check(render(widget(entry, family, size), to: dir.appendingPathComponent("widget-\(slug)-\(name).png")),
                      "\(name) widget draws \(picked.name)")
            }
        }

        lines.insert("\(failures == 0 ? "ALL PASSED" : "\(failures) FAILED") (\(lines.filter { $0.hasPrefix("PASS") }.count) passed)", at: 0)
        try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    }

    /// Tapping a widget: a saved city's link shows that city; a new city's link adds it and shows it.
    private static func widgetLinks(_ store: WeatherStore) {
        let saved = store.cities[store.cities.count - 1]
        store.select(store.cities[0])
        if let url = WidgetLink.url(for: saved), let city = WidgetLink.city(from: url) { store.openFromWidget(city) }
        check(store.activeID == saved.id, "a widget for \(saved.name) opens \(saved.name)")
        let before = store.cities.count
        let lima = City(name: "Lima", region: "Peru", latitude: -12.0464, longitude: -77.0428)
        if let url = WidgetLink.url(for: lima), let city = WidgetLink.city(from: url) { store.openFromWidget(city) }
        check(store.cities.count == before + 1 && store.activeID == lima.id, "a widget for a city not in the list adds it and opens it")
        if let added = store.cities.first(where: { $0.id == lima.id }) { store.remove(added) }
        store.select(store.cities[0])
    }

    /// A widget as the system shows it: Home Screen sizes on the widget background, Lock Screen
    /// sizes in white on a wallpaper-dark backdrop (the Lock Screen tints them).
    private static func widget(_ entry: WeatherEntry, _ family: WidgetFamily, _ size: CGSize) -> some View {
        let home = ([.systemSmall, .systemMedium, .systemLarge] as [WidgetFamily]).contains(family)
        return WidgetView(entry: entry, family: family)
            .padding(home ? 16 : 0)
            .frame(width: size.width, height: size.height)
            .foregroundStyle(.white)
            .background { if home { WidgetBackground(sky: entry.unavailable ? nil : entry.forecast.sky) } else { Color(white: 0.12) } }
            .clipShape(RoundedRectangle(cornerRadius: home ? 22 : (family == .accessoryCircular ? 38 : 10), style: .continuous))
    }

    /// Renders at 2x, saves the PNG, and says whether it has real content (more than a few colours).
    private static func render<V: View>(_ view: V, to url: URL) -> Bool {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.uiImage, let png = image.pngData(), let cg = image.cgImage,
              let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return false }
        try? png.write(to: url)
        var colours = Set<UInt32>()
        let bpp = cg.bitsPerPixel / 8
        for y in stride(from: 0, to: cg.height, by: max(1, cg.height / 24)) {
            for x in stride(from: 0, to: cg.width, by: max(1, cg.width / 24)) {
                let i = y * cg.bytesPerRow + x * bpp
                colours.insert(UInt32(bytes[i]) << 16 | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]))
            }
        }
        return colours.count > 3
    }
}
