import SwiftUI
import AppKit

/// Draws the current reading into the app's Dock icon: both units, the sky, the crimson rule.
@MainActor
enum DockTile {
    static func update(store: WeatherStore) {
        guard let app = NSApp else { return }   // no app (unit tests)
        let tile = app.dockTile
        guard store.dockShowsWeather, let forecast = store.activeForecast else {
            if tile.contentView != nil {
                tile.contentView = nil   // back to the app icon
                tile.display()
            }
            return
        }
        let view = DockTileView(
            primary: store.unit.value(forecast.now.temperature),
            primaryUnit: store.unit,
            secondary: store.unit.other.value(forecast.now.temperature),
            code: forecast.now.code,
            isDay: forecast.now.isDay
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: tile.size)
        tile.contentView = host
        tile.display()
    }
}

struct DockTileView: View {
    let primary: Int
    let primaryUnit: TempUnit
    let secondary: Int
    let code: Int
    let isDay: Bool

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                // macOS icon grid: the artwork sits inside ~80% of the tile.
                RoundedRectangle(cornerRadius: s * 0.18, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2A2622), Palette.bg], startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .top) {
                        Palette.crimson.frame(height: s * 0.035)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: s * 0.18, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: s * 0.02, y: s * 0.01)
                    .frame(width: s * 0.82, height: s * 0.82)

                VStack(spacing: s * 0.005) {
                    WeatherSymbol(code: code, isDay: isDay, size: s * 0.15)
                    Text("\(primary)°")
                        .font(.system(size: s * 0.27, weight: .semibold, design: .rounded))
                        .tracking(-s * 0.01)
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                    Text("\(secondary)\(primaryUnit.other.symbol)")
                        .font(.system(size: s * 0.17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.cream.opacity(0.8))
                }
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: s * 0.74)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
