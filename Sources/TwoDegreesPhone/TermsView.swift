import SwiftUI

/// Terms of Use and Privacy on iPhone: asked once, and again whenever `Brand.termsVersion` changes
/// (the same key and version as the Mac's dialog). An iPhone app can't quit, so there's no Quit:
/// the screen stays until the person agrees.
enum Terms {
    static let key = TermsSchedule.key
    static let summary = "Two Degrees is free and provided as is, without warranty. It is not a safety tool: for severe weather, follow official warnings. Your cities stay on your iPhone; only their locations go to the weather services, to get the weather and alerts. If you allow it, your location is used only to show the weather where you are."
}

struct TermsView: View {
    let agree: () -> Void

    var body: some View {
        let ui = Metrics(scale: 1)
        VStack(alignment: .leading, spacing: ui.l) {
            Spacer()
            AppMark(size: 56)
            Text("Terms of Use and Privacy")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Palette.textPrimary)
            Text(Terms.summary)
                .font(.system(size: 17))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("By choosing I Agree and using \(Brand.appName), you agree to the Terms of Use and Privacy at bradcowdrey.com/legal.")
                .font(.system(size: 15))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: agree) {
                Text("I Agree")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(Palette.bg)
                    .background(Capsule().fill(Palette.cream))
            }
            .buttonStyle(.plain)
            Link(destination: Brand.legal) {
                Text("Read the Terms")
                    .font(.system(size: 17, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(Palette.bg.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .interactiveDismissDisabled()
    }
}

/// Shown once, right after the terms: what Use My Location does, then Continue to iOS's own location
/// request, where the choice is made (Allow or Don't Allow). As Apple asks, this screen always leads to
/// the system request; it can be changed later in the ⋯ menu.
struct LocationPromptView: View {
    let answer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "location.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Palette.cream)
                .accessibilityHidden(true)
            Text("Show the weather where you are?")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Two Degrees can put the place you’re in first in your cities, updated each time you open the app. Next, iOS will ask whether to allow it.")
                .font(.system(size: 17))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your location is rounded to about a kilometre and used only to get the weather and alerts where you are. You can change this anytime in the ⋯ menu.")
                .font(.system(size: 15))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { answer(true) } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(Palette.bg)
                    .background(Capsule().fill(Palette.cream))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(Palette.bg.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .interactiveDismissDisabled()
    }
}
