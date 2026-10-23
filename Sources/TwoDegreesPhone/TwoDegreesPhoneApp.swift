import SwiftUI
import WidgetKit

/// Two Degrees for iPhone: the Mac app's panel as a full screen, with Home Screen and Lock Screen
/// widgets. Cities, settings and forecasts work exactly as on the Mac (same store and parts).
@main
struct TwoDegreesPhoneApp: App {
    @StateObject private var store = WeatherStore.shared

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
    }
}

extension WeatherStore {
    /// One store for the whole app.
    static let shared = WeatherStore()
}
