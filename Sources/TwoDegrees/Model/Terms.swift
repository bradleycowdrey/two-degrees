import AppKit

/// Terms of Use and Privacy: asked once, and again whenever `Brand.termsVersion` changes.
/// Never asked during the CI self-test, so the test can drive the app unattended.
enum Terms {
    private static let key = "terms.accepted"

    static var accepted: Bool { UserDefaults.standard.string(forKey: key) == Brand.termsVersion }

    @MainActor
    static func askIfNeeded() {
        guard !accepted, !SelfTest.isActive else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Terms of Use and Privacy"
        alert.informativeText = "Two Degrees is free and provided as is, without warranty. It is not a safety tool: for severe weather, follow official warnings. Your cities stay on your Mac; their locations go to Open-Meteo to get the weather.\n\nBy choosing I Agree and using \(Brand.appName), you agree to the Terms of Use and Privacy at bradcowdrey.com/legal."
        alert.addButton(withTitle: "I Agree")
        alert.addButton(withTitle: "Read the Terms")
        alert.addButton(withTitle: "Quit")
        while true {
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                UserDefaults.standard.set(Brand.termsVersion, forKey: key)
                return
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(Brand.legal)
            default:
                NSApp.terminate(nil)
                return
            }
        }
    }
}
