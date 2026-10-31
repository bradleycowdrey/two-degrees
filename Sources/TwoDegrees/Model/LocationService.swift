import CoreLocation
import Foundation

/// Use My Location: one rough fix (to about a kilometre), named by the system's geocoder, or by the
/// bundled city list when that can't (offline). Asks for permission the first time.
enum LocationResult: Equatable {
    case found(City)
    /// Location Services are off, or Two Degrees isn't allowed to use them.
    case denied
    /// No fix in time (indoors, airplane mode).
    case unavailable
}

/// Where Use My Location stands, for the settings.
enum LocationStatus: Equatable {
    case idle, locating, found, denied, unavailable, off
}

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    private var fixWaiters: [CheckedContinuation<CLLocation?, Never>] = []
    /// Counts requests, so a timeout only ends the request it belongs to.
    private var request = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    func currentCity() async -> LocationResult {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { authorizationWaiters.append($0); manager.requestWhenInUseAuthorization() }
        }
        guard !isDenied, manager.authorizationStatus != .notDetermined else { return .denied }
        guard let location = await fix() else { return .unavailable }
        return .found(await Self.name(location))
    }

    /// A fresh enough fix, or one requested now, within 15 seconds.
    private func fix() async -> CLLocation? {
        if let last = manager.location, -last.timestamp.timeIntervalSinceNow < 10 * 60 { return last }
        return await withCheckedContinuation { continuation in
            fixWaiters.append(continuation)
            guard fixWaiters.count == 1 else { return }
            request += 1
            let this = request
            manager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                if self.request == this { self.finishFix(nil) }
            }
        }
    }

    private func finishFix(_ location: CLLocation?) {
        request += 1
        let waiters = fixWaiters
        fixWaiters = []
        waiters.forEach { $0.resume(returning: location) }
    }

    /// The place's name and region; its coordinates rounded to about a kilometre, which is all the
    /// forecast needs.
    static func name(_ location: CLLocation) async -> City {
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        return name(lat: lat, lon: lon, placemark: placemark)
    }

    static func name(lat: Double, lon: Double, placemark: CLPlacemark?) -> City {
        if let placemark, let name = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.name {
            let region = [placemark.administrativeArea, placemark.country].compactMap { $0 }.filter { $0 != name }
            return City(name: name, region: region.joined(separator: ", "), latitude: lat, longitude: lon, isCurrent: true)
        }
        var city = OfflineCities.nearest(latitude: lat, longitude: lon)
            ?? City(name: "My Location", region: "", latitude: lat, longitude: lon)
        city.isCurrent = true
        return city
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard manager.authorizationStatus != .notDetermined else { return }
            let waiters = authorizationWaiters
            authorizationWaiters = []
            waiters.forEach { $0.resume() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in finishFix(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finishFix(nil) }
    }
}
