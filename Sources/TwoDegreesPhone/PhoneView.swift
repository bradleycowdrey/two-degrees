import SwiftUI

/// The app's layout, after Apple's Weather: one full-screen page per city that you swipe between, on
/// that city's sky, with a bottom bar of page dots, Share and the city list.
struct PhoneView: View {
    @EnvironmentObject private var store: WeatherStore
    @AppStorage(Terms.key) private var agreedVersion = ""
    /// The city list. `--show-list` (CI screenshots) opens it at launch.
    @State private var showingList = PhoneSelfTest.showList

    var body: some View {
        let ui = Metrics(scale: store.uiSize.scale, family: store.appFont)
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
        .fullScreenCover(isPresented: .constant(agreedVersion != Brand.termsVersion && !PhoneSelfTest.isActive)) {
            TermsView { agreedVersion = Brand.termsVersion }
        }
        .task {
            if PhoneSelfTest.isActive { await PhoneSelfTest.run(store: store) }
        }
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
                    Circle()
                        .fill(Color.white.opacity(city.id == store.activeID ? 1 : 0.35))
                        .frame(width: 7, height: 7)
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

extension AppFont {
    /// The Mac says "SF Pro"; on iPhone the system font is simply the iPhone's own.
    var phoneLabel: String { self == .system ? "System" : label }
}
