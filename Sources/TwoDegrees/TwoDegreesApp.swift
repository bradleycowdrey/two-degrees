import SwiftUI
import AppKit
import WidgetKit
import CoreServices

@main
struct TwoDegreesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var store = WeatherStore.shared
    #if !MAC_APP_STORE
    @ObservedObject private var updater = Updater.shared
    #endif

    init() {
        #if !MAC_APP_STORE
        // For CI: print the updater's install script, so the update-in-place test runs the real one.
        if CommandLine.arguments.contains("--print-install-script") {
            print(Updater.installScript)
            exit(0)
        }
        #endif
        FontRegistry.registerBundledFonts()
        #if !MAC_APP_STORE
        Task { @MainActor in Updater.shared.start() }
        #endif
    }

    var body: some Scene {
        // The Dock app's window. Clicking the Dock icon brings it back.
        Window(Brand.appName, id: "main") {
            WeatherPanel()
                .environmentObject(store)
                #if !MAC_APP_STORE
                .environmentObject(updater)
                #endif
                .background(WindowConfigurator(floatOnTop: store.floatOnTop))
                // A tapped widget: its city, in this window, brought forward.
                .onOpenURL { url in
                    guard let city = WidgetLink.city(from: url) else { return }
                    store.openFromWidget(city)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .handlesExternalEvents(matching: [WidgetLink.scheme])
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
                #if !MAC_APP_STORE
                .environmentObject(updater)
                #endif
        } label: {
            MenuBarLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            #if MAC_APP_STORE
            SettingsView().environmentObject(store)
            #else
            SettingsView().environmentObject(store).environmentObject(updater)
            #endif
        }
    }
}

extension WeatherStore {
    /// One store for the window, the menu bar, the Dock tile and the Dock menu.
    static let shared = WeatherStore()
}

struct MenuBarLabel: View {
    @EnvironmentObject private var store: WeatherStore
    #if !MAC_APP_STORE
    @ObservedObject private var updater = Updater.shared
    #endif

    /// The menu bar text for a reading: "57° · 14°", "57°", or nil for icon only.
    static func reading(_ celsius: Double, unit: TempUnit, style: MenuBarStyle) -> String? {
        switch style {
        case .both: return "\(unit.value(celsius))° · \(unit.other.value(celsius))°"
        case .primary: return "\(unit.value(celsius))°"
        case .icon: return nil
        }
    }

    var body: some View {
        // A trailing dot whenever an update is waiting (never in the App Store build, which has no updater).
        #if MAC_APP_STORE
        let dot = ""
        #else
        let dot = updater.latest == nil ? "" : " •"
        #endif
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
        #if !MAC_APP_STORE
        // Make sure LaunchServices has this exact build registered. macOS checks the widget's version
        // against it and throws the widget's content away on a mismatch (an app swapped in place by an
        // update keeps the old record), which leaves the widget blank. Re-registering heals that.
        // The App Store installs and registers its build itself, and the sandbox allows neither step.
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        // A widget process left over from before an update keeps running the old code, and its network is
        // cut, so widgets go grey (and a newly picked city never loads). End it; macOS starts this
        // version's widget as soon as a widget needs it.
        Self.endWidgetProcesses()
        #endif
        // Then redraw the widgets, so after an update they show the new version right away instead of
        // at their next scheduled refresh.
        WidgetCenter.shared.reloadAllTimelines()
        Terms.askIfNeeded()   // first run only, and after a material change to the terms
        // Use My Location, once the terms are agreed (never in the unattended self-test).
        if !SelfTest.isActive {
            let store = WeatherStore.shared
            store.locate = { await LocationService.shared.currentCity() }
            if store.needsLocationPrompt { store.answerLocationPrompt(Self.askAboutLocation()) }
            Task { await store.updateLocation() }
        }
    }

    /// Asked once, right after the terms: Use My Location (recommended, the default button) or Not Now.
    @MainActor
    static func askAboutLocation() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Show the weather where you are?"
        alert.informativeText = "Two Degrees can put the place you’re in first in your cities and keep it up to date. Recommended.\n\nYour location is rounded to about a kilometre and used only to get its weather. You can change this anytime in Settings."
        alert.icon = NSImage(systemSymbolName: "location.circle.fill", accessibilityDescription: nil)
        alert.addButton(withTitle: "Use My Location")
        alert.addButton(withTitle: "Not Now")
        return alert.runModal() == .alertFirstButtonReturn
    }

    #if !MAC_APP_STORE
    static func endWidgetProcesses() {
        guard !SelfTest.isActive else { return }
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-x", "TwoDegreesWidget"]
        try? pkill.run()
        pkill.waitUntilExit()
    }
    #endif

    @MainActor
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let store = WeatherStore.shared
        let menu = NSMenu()
        for city in store.cities {
            var title = city.name
            if let forecast = store.forecasts[city.id] {
                let t = forecast.now.temperature
                title += "   \(TempUnit.fahrenheit.value(t))\(TempUnit.fahrenheit.symbol) / \(TempUnit.celsius.value(t))\(TempUnit.celsius.symbol)"
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
            if window.frameAutosaveName.isEmpty { window.setFrameAutosaveName("TwoDegreesWindow") }
        }
    }
}
