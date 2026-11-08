import BackgroundTasks
import SwiftUI
import WidgetKit

/// Two Degrees for iPhone: the Mac app's panel as a full screen, with Home Screen and Lock Screen
/// widgets. Cities, settings and forecasts work exactly as on the Mac (same store and parts).
@main
struct TwoDegreesPhoneApp: App {
    @StateObject private var store = WeatherStore.shared
    @Environment(\.scenePhase) private var phase
    static let refreshTask = "com.bradcowdrey.twodegrees.refresh"

    init() {
        FontRegistry.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            PhoneView()
                .environmentObject(store)
                // After an update, redraw the widgets in the new version's design right away.
                .task { WidgetCenter.shared.reloadAllTimelines() }
        }
        .onChange(of: phase) { _, phase in
            if phase == .background { Self.scheduleRefresh() }
        }
        // In the background, iOS wakes the app now and then (when it sees fit) to refresh, so the
        // severe weather and rain notifications can go out.
        .backgroundTask(.appRefresh(Self.refreshTask)) {
            await Self.scheduleRefresh()
            await WeatherStore.shared.refresh()
        }
    }

    /// Asks for the next background refresh, in about 30 minutes, only when a notification is on.
    @MainActor
    static func scheduleRefresh() {
        guard WeatherStore.shared.notifySevere || WeatherStore.shared.notifyRain else { return }
        let request = BGAppRefreshTaskRequest(identifier: refreshTask)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

extension WeatherStore {
    /// One store for the whole app.
    static let shared = WeatherStore()
}
