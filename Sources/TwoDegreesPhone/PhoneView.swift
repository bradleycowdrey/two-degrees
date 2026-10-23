import SwiftUI

/// The whole app on one screen: header, cities, now, the next 24 hours, five days, footer. The same
/// parts as the Mac panel, full width, with pull to refresh.
struct PhoneView: View {
    @EnvironmentObject private var store: WeatherStore
    @State private var adding = false
    @State private var editing = false
    /// Closed when the app opens, as on the Mac. `--show-days` (CI screenshots) opens it.
    @State private var daysOpen = PhoneSelfTest.showDays
    @AppStorage(Terms.key) private var agreedVersion = ""

    var body: some View {
        let ui = Metrics(scale: store.uiSize.scale, family: store.appFont)
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ui.pt(10)) {
                    header(ui)
                        .padding(.top, ui.pt(10))
                        .padding(.bottom, ui.pt(4))
                    CityChips(adding: $adding, editing: $editing)
                    if adding {
                        Tile { CitySearchField(adding: $adding) }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let forecast = store.activeForecast {
                        NowTile(city: store.active, forecast: forecast)
                        HoursTile(forecast: forecast)
                        DaysTile(forecast: forecast, open: $daysOpen)
                            .id("days")
                    } else {
                        Tile {
                            HStack(spacing: ui.m) {
                                if store.isOffline {
                                    Image(systemName: "wifi.exclamationmark").foregroundStyle(Palette.textMuted)
                                    Text("Couldn’t reach Open-Meteo. Check your connection, then pull down to refresh.")
                                } else {
                                    ProgressView()
                                    Text("Loading the forecast for \(store.active.name)…")
                                }
                            }
                            .font(ui.meta)
                            .foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    footer(ui)
                }
                .padding(.horizontal, ui.pt(16))
                .padding(.bottom, ui.xl)
                .frame(maxWidth: 560)            // iPad: a readable column, centred
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.refresh() }
            .task {
                if PhoneSelfTest.showDays {
                    try? await Task.sleep(for: .seconds(2))
                    reader.scrollTo("days", anchor: .bottom)
                }
            }
        }
        // bradcowdrey.com's signature crimson rule, just under the status bar.
        .safeAreaInset(edge: .top, spacing: 0) { Palette.crimson.frame(height: 3) }
        .background(Palette.bg.ignoresSafeArea())
        .environment(\.metrics, ui)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .tint(Palette.cream)
        .animation(.snappy, value: adding)
        .animation(.snappy, value: editing)
        .fullScreenCover(isPresented: .constant(agreedVersion != Brand.termsVersion && !PhoneSelfTest.isActive)) {
            TermsView { agreedVersion = Brand.termsVersion }
        }
        .task {
            if PhoneSelfTest.isActive { await PhoneSelfTest.run(store: store) }
        }
    }

    private func header(_ ui: Metrics) -> some View {
        HStack(spacing: ui.m) {
            AppMark(size: ui.pt(28))
            Text(Brand.appName)
                .font(ui.title)
                .tracking(-0.2)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
            Spacer(minLength: ui.s)
            HStack(spacing: ui.s) {
                ShareLink(item: Brand.productPage, subject: Text("Two Degrees"), message: Text(Brand.phoneShareMessage)) {
                    HeaderCircle(symbol: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share Two Degrees")
                UnitToggle()
                PhoneMoreMenu()
            }
        }
    }

    private func footer(_ ui: Metrics) -> some View {
        VStack(alignment: .leading, spacing: ui.s) {
            StatusLine()
                .frame(maxWidth: .infinity, alignment: .leading)
            Link(destination: Brand.website) {
                Text("Made by \(Brand.author). Free. Forever. · \(Brand.websiteHost) ↗")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(ui.font(12))
            .foregroundStyle(Palette.textMuted)
        }
        .padding(.top, ui.pt(2))
    }
}

/// ⋯: the iPhone's share of the Mac's menu (no Dock, windows or updates: the App Store updates it).
private struct PhoneMoreMenu: View {
    @EnvironmentObject private var store: WeatherStore

    var body: some View {
        Menu {
            Button { store.copyReading() } label: { Label("Copy Current Reading", systemImage: "doc.on.doc") }
                .disabled(store.activeForecast == nil)
            Button { Task { await store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            Button(role: .destructive) { store.remove(store.active) } label: { Label("Remove \(store.active.name)", systemImage: "trash") }
                .disabled(store.cities.count < 2)
            Divider()
            Picker(selection: $store.uiSize) {
                ForEach(UISize.allCases) { Text($0.label).tag($0) }
            } label: { Label("Text Size", systemImage: "textformat.size") }
                .pickerStyle(.menu)
            Picker(selection: $store.appFont) {
                ForEach(AppFont.allCases) { Text($0.phoneLabel).tag($0) }
            } label: { Label("Font", systemImage: "textformat") }
                .pickerStyle(.menu)
            Divider()
            Link(destination: Brand.macDownload) { Label("Get Two Degrees for Mac", systemImage: "laptopcomputer") }
            Link(destination: Brand.legal) { Label("Terms & Privacy", systemImage: "doc.text") }
            Link(destination: Brand.issues) { Label("Report an Issue", systemImage: "exclamationmark.bubble") }
        } label: {
            HeaderCircle(symbol: "ellipsis")
        }
        .accessibilityLabel("More")
    }
}

extension AppFont {
    /// The Mac says "SF Pro"; on iPhone the system font is simply the iPhone's own.
    var phoneLabel: String { self == .system ? "System" : label }
}
