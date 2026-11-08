import Foundation

/// When to ask for the Terms of Use and Privacy: always the first time; again when they change, but no
/// more than once a month (a second change within the month waits until the month is up). Shared by
/// the Mac and iPhone apps; the Android app has the same rule.
enum TermsSchedule {
    static let key = "terms.accepted"          // the version last agreed to
    static let dateKey = "terms.acceptedAt"    // when (seconds since 1970)
    static let interval: TimeInterval = 30 * 24 * 60 * 60

    static func shouldAsk(acceptedVersion: String?, acceptedAt: Date?, current: String = Brand.termsVersion, now: Date = Date()) -> Bool {
        guard let acceptedVersion, !acceptedVersion.isEmpty else { return true }   // never agreed
        guard acceptedVersion != current else { return false }
        guard let acceptedAt else { return true }   // agreed before the date was kept
        return now.timeIntervalSince(acceptedAt) >= interval
    }

    static func shouldAsk(in defaults: UserDefaults, now: Date = Date()) -> Bool {
        let at = defaults.double(forKey: dateKey)
        return shouldAsk(acceptedVersion: defaults.string(forKey: key), acceptedAt: at > 0 ? Date(timeIntervalSince1970: at) : nil, now: now)
    }

    static func agree(in defaults: UserDefaults, now: Date = Date()) {
        defaults.set(Brand.termsVersion, forKey: key)
        defaults.set(now.timeIntervalSince1970, forKey: dateKey)
    }
}
