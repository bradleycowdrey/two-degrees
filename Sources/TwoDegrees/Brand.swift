import Foundation

/// Single source of truth for branding. Change these to rebrand the app.
enum Brand {
    static let appName = "Two Degrees"
    static let tagline = "The weather in °F and °C at once."
    static let author = "Bradley Cowdrey"
    static let websiteHost = "bradcowdrey.com"
    static let website = URL(string: "https://bradcowdrey.com")!
    static let legal = URL(string: "https://bradcowdrey.com/legal")!
    /// Bump when the terms change materially, so everyone is asked to agree again.
    static let termsVersion = "2026-10-21"
    static let repository = URL(string: "https://github.com/bradleycowdrey/two-degrees")!
    static let shareMessage = "Two Degrees: the weather in °F and °C at once, right in your Mac's Dock and menu bar. Free and open source, by Bradley Cowdrey."
    static let releasesAPI = URL(string: "https://api.github.com/repos/bradleycowdrey/two-degrees/releases/latest")!
    static let issues = URL(string: "https://github.com/bradleycowdrey/two-degrees/issues")!
    static let dataCredit = URL(string: "https://open-meteo.com/")!
    static let copyright = "© 2026 Bradley Cowdrey · bradcowdrey.com"
}
