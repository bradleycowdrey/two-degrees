import AppKit

/// Terms of Use and Privacy: asked once, and again when `Brand.termsVersion` changes, at most once a
/// month (TermsSchedule).
/// Never asked during the CI self-test, so the test can drive the app unattended; the self-test
/// shows the same dialog itself and clicks I Agree.
enum Terms {
    static let key = TermsSchedule.key

    static var accepted: Bool { accepted(in: .standard) }

    /// True when there's no need to ask (agreed to these terms, or to earlier ones within the month).
    static func accepted(in defaults: UserDefaults) -> Bool { !TermsSchedule.shouldAsk(in: defaults) }

    @MainActor
    static func askIfNeeded() {
        guard !accepted, !SelfTest.isActive else { return }
        ask(defaults: .standard)
    }

    /// Shows the dialog until the person agrees (true) or quits (false). `whenShown` runs once the
    /// dialog is on screen, so the self-test can photograph it and press a button.
    @MainActor @discardableResult
    static func ask(defaults: UserDefaults, quit: Bool = true, whenShown: ((NSAlert) -> Void)? = nil) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Terms of Use and Privacy"
        alert.informativeText = "Two Degrees is free and provided as is, without warranty. It is not a safety tool: for severe weather, follow official warnings. Your cities stay on your Mac; only their locations go to Open-Meteo to get the weather. If you allow it, your location is used only to show the weather where you are.\n\nBy choosing I Agree and using \(Brand.appName), you agree to the Terms of Use and Privacy at bradcowdrey.com/legal."
        alert.addButton(withTitle: "I Agree")
        alert.addButton(withTitle: "Read the Terms")
        alert.addButton(withTitle: "Quit")
        while true {
            if let whenShown {
                let timer = Timer(timeInterval: 0.5, repeats: false) { _ in MainActor.assumeIsolated { whenShown(alert) } }
                RunLoop.main.add(timer, forMode: .modalPanel)
            }
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                TermsSchedule.agree(in: defaults)
                return true
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(Brand.legal)
            default:
                if quit { NSApp.terminate(nil) }
                return false
            }
        }
    }
}
