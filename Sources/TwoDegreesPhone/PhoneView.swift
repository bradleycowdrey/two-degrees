import SwiftUI

/// The app's layout, after Apple's Weather: one full-screen page per city that you swipe between, on
/// that city's sky, with a bottom bar of page dots, Share and the city list.
struct PhoneView: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(Terms.key) private var agreedVersion = ""
    @AppStorage(TermsSchedule.dateKey) private var agreedAt: Double = 0
    /// The city list. `--show-list` (CI screenshots) opens it at launch.
    @State private var showingList = PhoneSelfTest.showList

    var body: some View {
        // The iPhone's own text size (Settings → Display & Brightness → Text Size) scales everything, on top
        // of the app's Text Size choice.
        // On iPad (full width), everything is larger, so the page reads at arm's length.
        let ui = Metrics(scale: store.uiSize.scale * Self.scale(for: dynamicType) * (sizeClass == .regular ? 1.4 : 1), family: store.appFont)
        let sky = store.activeForecast?.sky ?? (code: 3, isDay: true)
        TabView(selection: Binding(get: { store.activeID }, set: { id in
            if let city = store.cities.first(where: { $0.id == id }) { store.select(city) }
        })) {
            ForEach(store.cities) { city in
                CityPage(city: city).tag(city.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(SkyBackground(code: sky.code, isDay: sky.isDay).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.6), value: store.activeID)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(ui) }
        .environment(\.metrics, ui)
        .preferredColorScheme(.dark)
        .tint(.white)
        .fullScreenCover(isPresented: $showingList) {
            CityList().environment(\.metrics, ui)
        }
        // First launch: the terms, then "Show the weather where you are?". Changed terms are asked
        // again, at most once a month.
        .fullScreenCover(isPresented: .constant(PhoneSelfTest.showLocationPrompt || (!PhoneSelfTest.isActive && (needsTerms || store.needsLocationPrompt)))) {
            if needsTerms && !PhoneSelfTest.showLocationPrompt {
                TermsView { agreedVersion = Brand.termsVersion; agreedAt = Date().timeIntervalSince1970 }
            } else {
                LocationPromptView { store.answerLocationPrompt($0) }
            }
        }
        .task {
            if PhoneSelfTest.isActive { await PhoneSelfTest.run(store: store) }
        }
        // Use My Location, once the terms are agreed (the self-test checks it itself).
        .task(id: needsTerms) {
            guard !needsTerms, !PhoneSelfTest.isActive else { return }
            store.locate = { await LocationService.shared.currentCity() }
            await store.updateLocation()
        }
    }

    private var needsTerms: Bool {
        TermsSchedule.shouldAsk(acceptedVersion: agreedVersion, acceptedAt: agreedAt > 0 ? Date(timeIntervalSince1970: agreedAt) : nil)
    }

    /// Share · page dots · city list, on a thin frosted bar.
    private func bottomBar(_ ui: Metrics) -> some View {
        HStack {
            ShareLink(item: Brand.productPage, subject: Text("Two Degrees"), message: Text(Brand.phoneShareMessage)) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Share Two Degrees")
            Spacer()
            HStack(spacing: 8) {
                ForEach(store.cities) { city in
                    let opacity = city.id == store.activeID ? 1 : 0.35
                    if city.isCurrent {
                        // Where you are gets an arrow, as in Apple's Weather.
                        Image(systemName: "location.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.white.opacity(opacity))
                            .frame(width: 9, height: 9)
                    } else {
                        Circle()
                            .fill(Color.white.opacity(opacity))
                            .frame(width: 7, height: 7)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(store.active.name), city \((store.cities.firstIndex { $0.id == store.activeID } ?? 0) + 1) of \(store.cities.count)")
            Spacer()
            Button { showingList = true } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Cities and settings")
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(0.15)) }
        .environment(\.colorScheme, .dark)
    }
}

extension PhoneView {
    /// How much each system text size scales the layout. The largest accessibility sizes are capped so
    /// a city page still fits the screen's width.
    static func scale(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: return 0.86
        case .small: return 0.9
        case .medium: return 0.95
        case .large: return 1.0
        case .xLarge: return 1.07
        case .xxLarge: return 1.14
        case .xxxLarge: return 1.21
        default: return 1.3   // accessibility sizes
        }
    }
}

extension AppFont {
    /// The Mac says "SF Pro"; on iPhone the system font is simply the iPhone's own.
    var phoneLabel: String { self == .system ? "System" : label }
}
