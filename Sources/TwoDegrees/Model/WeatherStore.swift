import SwiftUI
import WidgetKit
#if os(macOS)
import AppKit
import ServiceManagement
#else
import UIKit
#endif

/// What the menu bar shows next to (or instead of) the icon.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case both, primary, icon

    var id: String { rawValue }
    var label: String {
        switch self {
        case .both: return "Both units (57° · 14°)"
        case .primary: return "Larger unit only (57°)"
        case .icon: return "Icon only"
        }
    }
}

/// Saved cities, settings and forecasts. Shared by the menu bar, the window and the Dock tile.
@MainActor
final class WeatherStore: ObservableObject {
    static let maxCities = 5
    static let refreshInterval: TimeInterval = 15 * 60

    @Published var cities: [City] { didSet { save(cities, "cities"); shareWithWidgets() } }
    @Published var activeID: String { didSet { defaults.set(activeID, forKey: "activeID"); refreshDock(); shareWithWidgets() } }
    @Published var unit: TempUnit { didSet { defaults.set(unit.rawValue, forKey: "unit"); refreshDock() } }
    @Published var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: "menuBarStyle") } }
    @Published var dockShowsWeather: Bool { didSet { defaults.set(dockShowsWeather, forKey: "dockShowsWeather"); refreshDock() } }
    @Published var uiSize: UISize { didSet { defaults.set(uiSize.rawValue, forKey: "uiSize") } }
    @Published var appFont: AppFont { didSet { defaults.set(appFont.rawValue, forKey: "appFont") } }
    @Published var floatOnTop: Bool { didSet { defaults.set(floatOnTop, forKey: "floatOnTop") } }
    /// Use My Location: keep a page for where you are, first in the list. On unless turned off.
    @Published var useLocation: Bool {
        didSet {
            defaults.set(useLocation, forKey: "useLocation")
            if !locationAsked { locationAsked = true }   // choosing it in settings answers the question too
            if useLocation != oldValue { Task { await updateLocation() } }
        }
    }
    @Published private(set) var locationStatus: LocationStatus = .idle
    /// Whether the person has been asked "Show the weather where you are?" (after the terms, once).
    @Published private(set) var locationAsked: Bool { didSet { defaults.set(locationAsked, forKey: "locationAsked") } }
    var needsLocationPrompt: Bool { !locationAsked }
    /// Finds where you are. Set by the app once the terms are agreed; never in unit tests or the self-test.
    var locate: (@MainActor () async -> LocationResult)?

    @Published private(set) var forecasts: [String: Forecast] = [:]
    @Published private(set) var failed: Set<String> = []
    @Published private(set) var loading = false

    private let defaults: UserDefaults
    private var timer: Timer?

    /// `defaults` and `autoRefresh` are for unit tests (an isolated suite, no timers).
    init(defaults: UserDefaults = .standard, autoRefresh: Bool = true) {
        self.defaults = defaults
        let saved: [City]? = Self.load("cities", from: defaults)
        let cities = saved?.isEmpty == false ? saved! : Self.starterCities
        self.cities = cities
        activeID = defaults.string(forKey: "activeID").flatMap { id in cities.contains { $0.id == id } ? id : nil } ?? cities[0].id
        unit = defaults.string(forKey: "unit").flatMap(TempUnit.init(rawValue:)) ?? .localeDefault
        menuBarStyle = defaults.string(forKey: "menuBarStyle").flatMap(MenuBarStyle.init(rawValue:)) ?? .both
        dockShowsWeather = defaults.object(forKey: "dockShowsWeather") as? Bool ?? true
        uiSize = defaults.string(forKey: "uiSize").flatMap(UISize.init(rawValue:)) ?? .medium
        appFont = defaults.string(forKey: "appFont").flatMap(AppFont.init(rawValue:)) ?? .inter
        floatOnTop = defaults.bool(forKey: "floatOnTop")
        useLocation = defaults.object(forKey: "useLocation") as? Bool ?? true
        locationAsked = defaults.bool(forKey: "locationAsked")
        if let cached: [String: Forecast] = Self.load("forecasts", from: defaults) { forecasts = cached }
        guard autoRefresh else { return }
        shareWithWidgets()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfDue() }
        }
        #if os(macOS)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.updateLocation()   // a Mac may have moved while it slept
                await self?.refresh()
            }
        }
        #else
        // Coming back to the app refreshes anything older than one refresh interval.
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.updateLocation()
                await self?.refreshIfDue()
            }
        }
        #endif
        Task { await refresh() }
    }

    static let starterCities: [City] = [
        City(name: "New York", region: "New York, United States", latitude: 40.7128, longitude: -74.006),
        City(name: "London", region: "England, United Kingdom", latitude: 51.5072, longitude: -0.1276),
        City(name: "Tokyo", region: "Japan", latitude: 35.6762, longitude: 139.6503),
    ]

    var active: City { cities.first { $0.id == activeID } ?? cities[0] }
    var activeForecast: Forecast? { forecasts[active.id] }
    /// Up to five cities of your own; where you are doesn't count.
    var canAdd: Bool { cities.filter { !$0.isCurrent }.count < Self.maxCities }

    // MARK: Cities

    func add(_ city: City) {
        if let existing = cities.first(where: { $0.id == city.id }) {
            activeID = existing.id
            if forecasts[existing.id] == nil { Task { await load(existing) } }
        } else if canAdd {
            cities.append(city)
            activeID = city.id
            Task { await load(city) }
        }
    }

    func remove(_ city: City) {
        // Removing where you are turns Use My Location off; otherwise it would come straight back.
        if city.isCurrent && useLocation { useLocation = false; return }
        guard cities.count > 1 else { return }
        cities.removeAll { $0.id == city.id }
        forecasts[city.id] = nil
        failed.remove(city.id)
        save(forecasts, "forecasts")
        if activeID == city.id { activeID = cities[0].id }
    }

    func move(from source: IndexSet, to destination: Int) {
        cities.move(fromOffsets: source, toOffset: destination)
    }

    func select(_ city: City) {
        activeID = city.id
        if isStale(city) { Task { await load(city) } }
    }

    func toggleUnit() { unit = unit.other }

    func stepSize(_ delta: Int) {
        if delta > 0, let next = uiSize.larger { uiSize = next }
        if delta < 0, let next = uiSize.smaller { uiSize = next }
    }

    // MARK: Use My Location

    /// The answer to "Show the weather where you are?": Use My Location (recommended) turns it on,
    /// Not Now turns it off. Either way it's never asked again; the setting stays in settings.
    func answerLocationPrompt(_ yes: Bool) {
        locationAsked = true
        if useLocation == yes { Task { await updateLocation() } } else { useLocation = yes }
    }

    /// Finds where you are and keeps its page up to date (first in the list), or removes it when
    /// Use My Location is off. The first time, it also shows that page.
    func updateLocation() async {
        guard useLocation else {
            removeCurrent()
            locationStatus = .off
            return
        }
        guard locationAsked, let locate, locationStatus != .locating else { return }   // not before the question
        locationStatus = .locating
        let result = await locate()
        guard useLocation else { locationStatus = .off; return }
        switch result {
        case .found(let here):
            placeCurrent(here)
            locationStatus = .found
        case .denied:
            locationStatus = .denied
        case .unavailable:
            locationStatus = .unavailable
        }
    }

    /// Puts where you are first in the list (or updates it in place), and loads its weather.
    func placeCurrent(_ place: City) {
        var here = place
        here.isCurrent = true
        if let i = cities.firstIndex(where: \.isCurrent) {
            let old = cities[i]
            guard old != here else { return }
            if old.latitude != here.latitude || old.longitude != here.longitude {
                forecasts[here.id] = nil   // the old place's weather isn't this one's
                failed.remove(here.id)
            }
            cities[i] = here
        } else {
            cities.insert(here, at: 0)
            activeID = here.id
        }
        if forecasts[here.id] == nil { Task { await load(here) } }
    }

    private func removeCurrent() {
        guard let i = cities.firstIndex(where: \.isCurrent) else { return }
        if cities.count == 1 {
            cities[0].isCurrent = false   // never leave the list empty: keep it as an ordinary city
            activeID = cities[0].id
            return
        }
        let here = cities.remove(at: i)
        forecasts[here.id] = nil
        failed.remove(here.id)
        save(forecasts, "forecasts")
        if activeID == here.id { activeID = cities[0].id }
    }

    // MARK: Forecasts

    func refresh() async {
        loading = true
        await withTaskGroup(of: Void.self) { group in
            for city in cities { group.addTask { await self.load(city) } }
        }
        loading = false
    }

    private func refreshIfDue() async {
        if cities.contains(where: isStale) { await refresh() }
    }

    private func isStale(_ city: City) -> Bool {
        guard let forecast = forecasts[city.id] else { return true }
        return Date().timeIntervalSince(forecast.fetchedAt) > Self.refreshInterval
    }

    private func load(_ city: City) async {
        do {
            let forecast = try await OpenMeteo.forecast(for: city)
            // The city may have been removed while its forecast loaded: don't keep (or save) it.
            guard cities.contains(where: { $0.id == city.id }) else { return }
            forecasts[city.id] = forecast
            failed.remove(city.id)
            save(forecasts, "forecasts")
        } catch {
            failed.insert(city.id)
        }
        if city.id == activeID { refreshDock() }
    }

    /// True when the active city's numbers are older than one refresh and the last try failed.
    var isOffline: Bool { failed.contains(active.id) }

    // MARK: Widgets

    /// Widgets using Two Degrees' cities show these: publish them, and redraw the widgets when they change.
    func shareWithWidgets() {
        #if os(macOS)
        guard !SelfTest.isActive else { return }   // the self-test's ad-hoc build isn't in the App Group
        #endif
        let snapshot = SharedCities.Snapshot(cities: cities, activeID: activeID)
        guard snapshot != SharedCities.load() else { return }
        SharedCities.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Dock

    func refreshDock() {
        #if os(macOS)
        DockTile.update(store: self)
        #endif
    }

    #if os(macOS)
    // MARK: Open at login

    var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
            objectWillChange.send()
        }
    }
    #endif

    // MARK: Share

    /// A one-line reading for the active city, both units.
    var readingText: String? {
        guard let forecast = activeForecast else { return nil }
        let f = TempUnit.fahrenheit.value(forecast.now.temperature), c = TempUnit.celsius.value(forecast.now.temperature)
        return "\(active.name): \(f)\(TempUnit.fahrenheit.label) / \(c)\(TempUnit.celsius.label), \(Condition.name(forecast.now.code).lowercased()). Via Two Degrees."
    }

    /// Copies the reading to the clipboard.
    func copyReading() {
        guard let text = readingText else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    // MARK: Persistence

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
