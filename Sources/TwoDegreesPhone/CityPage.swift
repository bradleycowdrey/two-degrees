import SwiftUI

/// One city, laid out like Apple's Weather: a large centred reading that shrinks into a one-line bar as
/// you scroll, then frosted cards for the next 24 hours and 10 days, then a grid of detail tiles.
/// Two Degrees' difference throughout: every temperature in both units, the larger one first.
struct CityPage: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let city: City
    /// How far the header has scrolled up (0 at rest, negative as it goes).
    @State private var offset: CGFloat = 0
    /// Height of the pinned one-line header; the page is hidden beneath it, as in Apple's Weather.
    @State private var bandHeight: CGFloat = 0

    var body: some View {
        let forecast = store.forecasts[city.id]
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                VStack(spacing: ui.pt(10)) {
                    CityHeader(city: city, forecast: forecast)
                        .opacity(Double(1 - collapse * 1.3))
                        .id("top")
                        .padding(.top, ui.pt(36))
                        .padding(.bottom, ui.pt(26))
                        // Where the header is in the scroll view, read on every scroll.
                        .onGeometryChange(for: CGFloat.self) { proxy in proxy.frame(in: .named("page")).minY } action: { offset = $0 }
                    if let forecast {
                        AlertCards(city: city)
                        NextHoursCard(forecast: forecast)
                        HourlyCard(forecast: forecast)
                        PhoneDailyCard(forecast: forecast, city: city).id("days")
                        MapCard(city: city)
                        DetailTiles(forecast: forecast, city: city).id("tiles")
                        footer
                    } else {
                        Card(title: "Forecast", icon: "clock") {
                            HStack(spacing: ui.m) {
                                if store.failed.contains(city.id) {
                                    Image(systemName: "wifi.exclamationmark")
                                    Text("Couldn’t reach Open-Meteo. Pull down to try again.")
                                } else {
                                    ProgressView()
                                    Text("Loading the forecast for \(city.name)…")
                                }
                            }
                            .font(ui.font(15))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, ui.pt(16))
                .padding(.bottom, ui.pt(72))             // room above the bottom bar
                .frame(maxWidth: ui.pt(600))             // iPad: a readable column, scaled with the text
                .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: "page")
            .refreshable { await store.refresh() }
            // Once the one-line header is pinned, the page scrolls away under it instead of showing through.
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: collapse > 0.75 ? bandHeight : 0)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: collapse > 0.75 ? ui.pt(10) : 0)
                    Color.black
                }
            }
            .overlay(alignment: .top) { compactHeader(forecast) }
            // Swiping to another city puts this one back at the top, so it starts there when you return.
            // (And again on the way back, in case the page wasn't drawn when it was left.)
            .onChange(of: store.activeID) { old, new in
                if old == city.id && new != city.id { reader.scrollTo("top", anchor: .top) }
                if new == city.id && old != city.id && offset < -1 { reader.scrollTo("top", anchor: .top) }
            }
            .onDisappear { reader.scrollTo("top", anchor: .top) }
            .task {
                if PhoneSelfTest.showDays && city.id == store.activeID {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { reader.scrollTo("days", anchor: .top) }
                }
                if PhoneSelfTest.showTiles && city.id == store.activeID {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { reader.scrollTo("tiles", anchor: .bottom) }
                }
            }
        }
    }

    /// 0 at rest, 1 once the header has scrolled away.
    private var collapse: CGFloat { min(max(-offset / ui.pt(150), 0), 1) }

    /// The reading on one line, pinned at the top once the big header has scrolled away.
    @ViewBuilder
    private func compactHeader(_ forecast: Forecast?) -> some View {
        if let forecast, collapse > 0.75 {
            let now = forecast.now, unit = store.unit, other = unit.other
            VStack(spacing: ui.pt(2)) {
                Text(city.name).font(ui.font(28))
                Text("\(unit.value(now.temperature))\(unit.symbol) · \(other.value(now.temperature))\(other.symbol)  |  \(Condition.name(now.code))")
                    .font(ui.font(16, .medium))
                    .monospacedDigit()
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, ui.pt(16))
            .padding(.top, ui.pt(6))
            .padding(.bottom, ui.pt(10))
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bandHeight = $0 }
            .opacity(Double((collapse - 0.75) * 4))
            .accessibilityHidden(true)
        }
    }

    private var footer: some View {
        AppFooter(lead: "Weather for \(city.name)", fetched: store.forecasts[city.id]?.fetchedAt, offline: store.failed.contains(city.id))
    }
}

/// The 10-day card with the iPhone's day sheet: tap a row for that day in full.
private struct PhoneDailyCard: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let forecast: Forecast
    let city: City
    /// The day shown in detail (tap a row).
    @State private var selected: Date?

    var body: some View {
        let days = DailyCard.days(forecast)
        DailyCard(forecast: forecast, city: city, selected: $selected)
            .task {
                if PhoneSelfTest.showDay && city.id == store.activeID && days.count > 1 {
                    try? await Task.sleep(for: .seconds(2.5))
                    selected = days[1].date
                }
            }
            .sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
                DayDetailView(city: city, days: days, selection: $selected)
                    .environmentObject(store)
                    .environment(\.metrics, ui)
            }
    }
}
