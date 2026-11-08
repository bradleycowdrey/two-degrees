import SwiftUI

/// The sky behind a city: a vertical gradient for its weather and time of day, as in Apple's
/// Weather, in Two Degrees' warmer, quieter tones.
enum Sky {
    static func colors(code: Int, isDay: Bool) -> (top: Color, bottom: Color) {
        switch (code, isDay) {
        case (95...99, _): return (Color(hex: 0x3A3346), Color(hex: 0x16131B))                 // storm
        case (_, _) where Condition.isSnow(code): return isDay ? (Color(hex: 0x7C8EA0), Color(hex: 0x3E4A57)) : (Color(hex: 0x323B47), Color(hex: 0x14181E))
        case (51...82, true): return (Color(hex: 0x4F5E70), Color(hex: 0x232A33))               // rain, day
        case (51...82, false): return (Color(hex: 0x252C36), Color(hex: 0x101317))              // rain, night
        case (45, true), (48, true), (3, true): return (Color(hex: 0x667585), Color(hex: 0x2E3640)) // overcast or fog, day
        case (0, true), (1, true): return (Color(hex: 0x3D74B0), Color(hex: 0x1C3A5E))          // clear, day
        case (2, true): return (Color(hex: 0x4F78A3), Color(hex: 0x24384F))                     // partly cloudy, day
        case (0, false), (1, false): return (Color(hex: 0x141E3C), Color(hex: 0x0A0E1C))        // clear, night
        default: return (Color(hex: 0x262A33), Color(hex: 0x111317))                            // cloudy, night
        }
    }
}

struct SkyBackground: View {
    let code: Int
    let isDay: Bool

    var body: some View {
        let sky = Sky.colors(code: code, isDay: isDay)
        LinearGradient(colors: [sky.top, sky.bottom], startPoint: .top, endPoint: .bottom)
    }
}

extension Forecast {
    /// The sky to draw for this forecast right now.
    var sky: (code: Int, isDay: Bool) { (now.code, now.isDay) }
}
