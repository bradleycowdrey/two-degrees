import SwiftUI

// Shared by the app and the widget.

/// SF Symbols tinted with the brand's warm palette: cream clouds, amber sun, soft blue rain.
struct WeatherSymbol: View {
    let code: Int
    let isDay: Bool
    let size: CGFloat

    var body: some View {
        Image(systemName: Condition.symbol(code, isDay: isDay))
            .symbolRenderingMode(.palette)
            .foregroundStyle(code == 0 ? accent : Self.cloud, accent)   // clear sky: the sun or moon is the only layer
            .font(.system(size: size))
            .accessibilityLabel(Condition.name(code))
    }

    static let cloud = Color(hex: 0xCFC6BB)

    /// The symbol's second layer: sun amber, night moon, rain blue, storm amber, snow white.
    private var accent: Color {
        switch code {
        case 0: return isDay ? Palette.sun : Color(hex: 0xE9DCC8)
        case 1, 2: return isDay ? Palette.sun : Color(hex: 0xE9DCC8)
        case 95, 96, 99: return Palette.sun
        case _ where Condition.isSnow(code): return .white
        case 51...82: return Palette.rain
        default: return Self.cloud
        }
    }
}
