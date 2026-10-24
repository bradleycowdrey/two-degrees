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
    /// Opens the city list at launch, for a screenshot.
    nonisolated static let showList = ProcessInfo.processInfo.arguments.contains("--show-list")

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

        // 2. Unit switch, both ways.
        let unit = store.unit
        store.unit = unit.other
        check(store.unit == unit.other, "switch the larger unit to \(unit.other.symbol)")
        store.unit = unit
        check(store.unit == unit, "switch it back to \(unit.symbol)")

        // 3. Search, add and remove a city.
        let before = store.cities.count
        let found = (try? await OpenMeteo.search("Denver")) ?? []
        check(!found.isEmpty, "city search finds Denver (\(found.first?.region ?? "nothing"))")
        if let denver = found.first {
            store.add(denver)
            for _ in 0..<20 where store.forecasts[denver.id] == nil { try? await Task.sleep(for: .milliseconds(500)) }
            check(store.forecasts[denver.id] != nil && store.activeID == denver.id, "add Denver: selected and its forecast loads")
            store.remove(denver)
            check(store.cities.count == before, "remove Denver")
        }

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

    /// A widget as the system shows it: Home Screen sizes on the widget background, Lock Screen
    /// sizes in white on a wallpaper-dark backdrop (the Lock Screen tints them).
    private static func widget(_ entry: WeatherEntry, _ family: WidgetFamily, _ size: CGSize) -> some View {
        let home = ([.systemSmall, .systemMedium, .systemLarge] as [WidgetFamily]).contains(family)
        return WidgetView(entry: entry, family: family)
            .padding(home ? 16 : 0)
            .frame(width: size.width, height: size.height)
            .foregroundStyle(.white)
            .background { if home { WidgetBackground() } else { Color(white: 0.12) } }
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
