import Foundation
import UserNotifications

/// Severe weather and rain-starting-soon notifications for where you are (or the first city), checked
/// whenever the forecast refreshes: on the Mac while the app runs, on iPhone also in the background.
/// Each alert is announced once; rain at most once every three hours.
@MainActor
final class Notifier {
    static let shared = Notifier()
    private let defaults = UserDefaults.standard
    /// Notifications need a real app (not `swift test`).
    private var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func requestPermission() {
        guard available else { return }
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    /// True when the person has turned notifications off for Two Degrees in the system's settings.
    func isDenied() async -> Bool {
        guard available else { return false }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    func check(_ store: WeatherStore, now: Date = Date()) async {
        guard available, store.notifySevere || store.notifyRain, !store.cities.isEmpty else { return }
        let city = store.notifyCity
        if store.notifySevere, let alerts = store.alerts[city.id] {
            var seen = defaults.stringArray(forKey: "notified.alerts") ?? []
            for alert in alerts where alert.notifies && !seen.contains(alert.id) {
                post(id: alert.id, title: "\(alert.event) · \(city.name)", body: alert.headline)
                seen.append(alert.id)
            }
            defaults.set(Array(seen.suffix(200)), forKey: "notified.alerts")
        }
        if store.notifyRain, let forecast = store.forecasts[city.id], let soon = Self.rainSoon(forecast) {
            let last = defaults.double(forKey: "notified.rainAt")
            if now.timeIntervalSince1970 - last >= 3 * 3600 {
                let what = Condition.isSnow(forecast.now.code) ? "Snow" : "Rain"
                post(id: "rain-\(Int(now.timeIntervalSince1970))", title: "\(what) starting soon · \(city.name)",
                     body: "\(what) is expected around \(Forecast.format(soon, "jmm")).")
                defaults.set(now.timeIntervalSince1970, forKey: "notified.rainAt")
            }
        }
    }

    /// When rain is due within about 30 minutes while it's dry now: the start of the first wet step.
    static func rainSoon(_ forecast: Forecast) -> Date? {
        guard let steps = forecast.steps, steps.count >= 3, steps[0].precipitation < NextHours.wetStep,
              (forecast.now.precipitation ?? 0) < 0.1 else { return nil }
        return steps[1...2].first { $0.precipitation >= 0.2 }?.time
    }

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
