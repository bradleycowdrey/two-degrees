import SwiftUI
import AppKit
import WidgetKit
import CoreServices

@main
struct TwoDegreesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var store = WeatherStore.shared
    @ObservedObject private var updater = Updater.shared

    init() {
        // For CI: print the updater's install script, so the update-in-place test runs the real one.
        if CommandLine.arguments.contains("--print-install-script") {
            print(Updater.installScript)
            exit(0)
        }
        FontRegistry.registerBundledFonts()
        Task { @MainActor in Updater.shared.start() }
    }

    var body: some Scene {
        // The Dock app's window. Clicking the Dock icon brings it back.
        Window(Brand.appName, id: "main") {
            WeatherPanel()
                .environmentObject(store)
                .environmentObject(updater)
                .background(WindowConfigurator(floatOnTop: store.floatOnTop))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Weather") {
                Button("Refresh") { Task { await store.refresh() } }
                    .keyboardShortcut("r")
                Button("Show °F Large") { store.unit = .fahrenheit }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button("Show °C Large") { store.unit = .celsius }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Divider()
                Button("Copy Current Reading") { store.copyReading() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Divider()
                Button("Larger") { store.stepSize(1) }
                    .keyboardShortcut("+")
                Button("Smaller") { store.stepSize(-1) }
                    .keyboardShortcut("-")
            }
        }

        // The menu bar reading, with the same panel underneath.
        MenuBarExtra {
            WeatherPanel(compact: true)
                .environmentObject(store)
                .environmentObject(updater)
        } label: {
            MenuBarLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(store).environmentObject(updater)
        }
    }
}

extension WeatherStore {
    /// One store for the window, the menu bar, the Dock tile and the Dock menu.
    static let shared = WeatherStore()
}

struct MenuBarLabel: View {
    @EnvironmentObject private var store: WeatherStore
    @ObservedObject private var updater = Updater.shared

    /// The menu bar text for a reading: "57° · 14°", "57°", or nil for icon only.
    static func reading(_ celsius: Double, unit: TempUnit, style: MenuBarStyle) -> String? {
        switch style {
        case .both: return "\(unit.value(celsius))° · \(unit.other.value(celsius))°"
        case .primary: return "\(unit.value(celsius))°"
        case .icon: return nil
        }
    }

    var body: some View {
        // A trailing dot whenever an update is waiting.
        let dot = updater.latest == nil ? "" : " •"
        if let forecast = store.activeForecast, let reading = Self.reading(forecast.now.temperature, unit: store.unit, style: store.menuBarStyle) {
            HStack(spacing: 4) {
                Image(systemName: Condition.symbol(forecast.now.code, isDay: forecast.now.isDay))
                Text(reading + dot).monospacedDigit()
            }
        } else {
            Text("\(Image(systemName: "thermometer.medium"))\(dot)")
        }
    }
}

/// Keeps the app alive in the menu bar when the window closes, and gives the Dock icon a
/// right-click menu with every saved city's reading.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        WeatherStore.shared.refreshDock()   // the cached reading, until fresh numbers arrive
        // Make sure LaunchServices has this exact build registered. macOS checks the widget's version
        // against it and throws the widget's content away on a mismatch (an app swapped in place by an
        // update keeps the old record), which leaves the widget blank. Re-registering heals that.
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        // Then redraw the widgets, so after an update they show the new version right away instead of
        // at their next scheduled refresh.
        WidgetCenter.shared.reloadAllTimelines()
        Terms.askIfNeeded()   // first run only, and after a material change to the terms
    }

    @MainActor
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let store = WeatherStore.shared
        let menu = NSMenu()
        for city in store.cities {
            var title = city.name
            if let forecast = store.forecasts[city.id] {
                let t = forecast.now.temperature
                title += "   \(TempUnit.fahrenheit.value(t))°F / \(TempUnit.celsius.value(t))°C"
            }
            let item = NSMenuItem(title: title, action: #selector(selectCity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = city.id
            item.state = city.id == store.activeID ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)
        return menu
    }

    @MainActor @objc private func selectCity(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String,
              let city = WeatherStore.shared.cities.first(where: { $0.id == id }) else { return }
        WeatherStore.shared.select(city)
    }

    @MainActor @objc private func refresh() {
        Task { await WeatherStore.shared.refresh() }
    }
}

/// Reaches the hosting NSWindow to float it above other windows and drag it by its background.
private struct WindowConfigurator: NSViewRepresentable {
    let floatOnTop: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = floatOnTop ? .floating : .normal
            window.collectionBehavior = floatOnTop ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.managed]
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(Palette.bg)
            if window.frameAutosaveName.isEmpty { window.setFrameAutosaveName("TwoDegreesWindow") }
        }
    }
}
