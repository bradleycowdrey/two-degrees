import SwiftUI
import WebKit

// The iPhone's own parts of a city's page: the rain map in the app, and the day detail sheet. The cards
// and tiles themselves are shared with the Mac (Sources/TwoDegrees/Views: CityCards, Tiles, DayCharts).

// MARK: - Rain map

/// The Rain Map card, opening the radar full screen.
struct MapCard: View {
    @EnvironmentObject private var store: WeatherStore
    let city: City
    @State private var showing = false

    var body: some View {
        RainMapCard { showing = true }
            .fullScreenCover(isPresented: $showing) { RadarScreen(city: city, unit: store.unit) }
    }
}

/// The shared rain map page (web/radar.html) in a web view, with Done.
struct RadarScreen: View {
    let city: City
    let unit: TempUnit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            WebPage(url: Self.url(for: city, unit: unit)).ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .foregroundStyle(.white)
            .padding(.leading, 12)
            .padding(.top, 4)
            .accessibilityLabel("Close the map")
        }
        .background(Palette.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    static func url(for city: City, unit: TempUnit) -> URL {
        URL(string: String(format: "https://bradleycowdrey.github.io/two-degrees/radar.html?lat=%.2f&lon=%.2f&z=7&units=%@", city.latitude, city.longitude, unit.rawValue))!
    }
}

private struct WebPage: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isOpaque = false
        view.backgroundColor = UIColor(Palette.bg)
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

// MARK: - Day detail

/// A day in full: the reading, then temperature, rain and wind charts, and the facts. Arrows move
/// between days.
struct DayDetailView: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    @Environment(\.dismiss) private var dismiss
    let city: City
    let days: [Forecast.Day]
    @Binding var selection: Date?

    var body: some View {
        let forecast = store.forecasts[city.id]
        let index = days.firstIndex { $0.date == selection } ?? 0
        NavigationStack {
            // Swipe left and right between days, as well as the arrows.
            TabView(selection: Binding(get: { selection ?? days.first?.date ?? Date() }, set: { selection = $0 })) {
                ForEach(Array(days.enumerated()), id: \.element.date) { i, day in
                    ScrollView {
                        if let forecast {
                            DayDetailContent(forecast: forecast, day: i == 0 ? day.including(forecast.now.temperature) : day,
                                             isToday: i == 0, city: city)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 32)
                                .frame(maxWidth: ui.pt(600))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .tag(day.date)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(days.indices.contains(index) ? Forecast.format(days[index].date, "EEEEMMMd") : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { selection = days[index - 1].date } label: { Image(systemName: "chevron.left") }
                        .disabled(index == 0).accessibilityLabel("Previous day")
                    Button { selection = days[index + 1].date } label: { Image(systemName: "chevron.right") }
                        .disabled(index >= days.count - 1).accessibilityLabel("Next day")
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
    }
}
