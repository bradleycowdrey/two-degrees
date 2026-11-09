import SwiftUI

// The small pictures inside the detail tiles (Tiles.swift), shared by the iPhone and Mac apps.

/// A thin bar in a scale's colours with a dot at the reading (0–1): air quality and UV.
struct ScaleBar: View {
    let colors: [Color]
    let position: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)).frame(height: 5)
                Circle().fill(.white).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1))
                    .offset(x: max(0, min(geo.size.width - 9, geo.size.width * position - 4.5)))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    static let uv: [Color] = [Color(hex: 0x3EA72D), Color(hex: 0xFFF300), Color(hex: 0xF18B00), Color(hex: 0xE53210), Color(hex: 0xB567A4)]
    static let usAQI: [Color] = [Color(hex: 0x00E400), Color(hex: 0xFFFF00), Color(hex: 0xFF7E00), Color(hex: 0xFF0000), Color(hex: 0x8F3F97), Color(hex: 0x7E0023)]
    static let europeanAQI: [Color] = [Color(hex: 0x50F0E6), Color(hex: 0x50CCAA), Color(hex: 0xF0E641), Color(hex: 0xFF5050), Color(hex: 0x960032), Color(hex: 0x7D2181)]
}

/// The moon as it looks tonight: the lit part over a dim disc (0 new, 0.5 full).
struct MoonDisc: View {
    let fraction: Double
    var size: CGFloat = 26

    var body: some View {
        Canvas { context, canvas in
            let r = min(canvas.width, canvas.height) / 2, c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.18)))
            let k = cos(2 * .pi * fraction), waxing = fraction < 0.5
            var lit = Path()
            // The lit half…
            lit.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: !waxing)
            // …then the terminator back up: an ellipse half, bulging toward the lit side for a crescent.
            let rx = abs(k) * r
            let steps = 32
            for i in 0...steps {
                let t = Double.pi / 2 - Double.pi * Double(i) / Double(steps)   // from bottom (π/2) to top (−π/2)
                let bulgeLit = (k > 0) // crescent: terminator on the lit side
                let side: CGFloat = (waxing ? 1 : -1) * (bulgeLit ? 1 : -1)
                lit.addLine(to: CGPoint(x: c.x + side * rx * CGFloat(cos(t)), y: c.y + r * CGFloat(sin(t))))
            }
            lit.closeSubpath()
            context.fill(lit, with: .color(Color(hex: 0xF4E9D8)))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A compass with the wind's arrow pointing where it's blowing, its tail on the side it comes from.
/// No arrow when the direction isn't known.
struct WindCompass: View {
    @Environment(\.metrics) private var ui
    let direction: Double?
    let accent: Color

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 56   // drawn at 56 pt, scaled with the text size
            let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2), r = canvas.width / 2 - 0.5
            // A point at a bearing (0 = north, clockwise) and a distance from the centre.
            func at(_ degrees: Double, _ distance: CGFloat) -> CGPoint {
                let a = degrees * .pi / 180
                return CGPoint(x: c.x + distance * CGFloat(sin(a)), y: c.y - distance * CGFloat(cos(a)))
            }
            context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.25)), lineWidth: 1)
            // A tick every 30°.
            var ticks = Path()
            for degrees in stride(from: 0.0, to: 360.0, by: 30.0) {
                ticks.move(to: at(degrees, r - 1))
                ticks.addLine(to: at(degrees, r - 4 * s))
            }
            context.stroke(ticks, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            for (letter, degrees) in [("N", 0.0), ("E", 90.0), ("S", 180.0), ("W", 270.0)] {
                var text = context.resolve(Text(letter).font(ui.font(8, .semibold)))
                text.shading = .color(.white.opacity(0.5))
                context.draw(text, at: at(degrees, r - 10 * s))
            }
            guard let direction else { return }
            // The wind comes from `direction`, so it blows toward the opposite side.
            let toward = direction + 180, length = r - 14 * s
            let a = toward * .pi / 180
            let along = CGVector(dx: CGFloat(sin(a)), dy: -CGFloat(cos(a))), across = CGVector(dx: -along.dy, dy: along.dx)
            let head = at(toward, length), tail = at(direction, length)
            let base = CGPoint(x: head.x - along.dx * 6 * s, y: head.y - along.dy * 6 * s)
            var shaft = Path()
            shaft.move(to: tail)
            shaft.addLine(to: base)
            context.stroke(shaft, with: .color(accent), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
            var tip = Path()
            tip.move(to: head)
            tip.addLine(to: CGPoint(x: base.x + across.dx * 3.5 * s, y: base.y + across.dy * 3.5 * s))
            tip.addLine(to: CGPoint(x: base.x - across.dx * 3.5 * s, y: base.y - across.dy * 3.5 * s))
            tip.closeSubpath()
            context.fill(tip, with: .color(accent))
            // A small ring at the tail, on the side the wind comes from.
            let ring = 2.5 * s
            context.stroke(Path(ellipseIn: CGRect(x: tail.x - ring, y: tail.y - ring, width: 2 * ring, height: 2 * ring)), with: .color(accent), lineWidth: 1.5 * s)
        }
        .frame(width: ui.pt(56), height: ui.pt(56))
        .accessibilityHidden(true)
    }
}

/// The sun's path across the day: a curve over the tile's width (midnight to midnight) that rises
/// through a thin horizon at sunrise and sets through it at sunset, faint below it at night, with a dot
/// where the sun is now.
struct SunPath: View {
    @Environment(\.metrics) private var ui
    let now: Date
    let sunrise: Date
    let sunset: Date
    let accent: Color

    var body: some View {
        Canvas { context, canvas in
            let day = 86_400.0
            // Seconds since that day's midnight (times are the city's wall clock, stored as GMT).
            let clock = { (date: Date) in date.timeIntervalSince(Forecast.localCalendar.startOfDay(for: date)) }
            let rise = clock(sunrise), length = min(max(sunset.timeIntervalSince(sunrise), 0), day)
            let noon = rise + length / 2, offset = cos(Double.pi * length / day)
            // How high the sun is: 0 at sunrise and sunset, highest at noon, lowest at midnight.
            let height = { (t: Double) in cos(2 * Double.pi * (t - noon) / day) - offset }
            let pad = ui.pt(6)
            let k = (canvas.height - 2 * pad) / 2
            let horizon = pad + k * CGFloat(1 - offset)
            let inset = ui.pt(6)   // keeps the sun's glow inside the tile near midnight
            let point = { (t: Double) in CGPoint(x: inset + (canvas.width - 2 * inset) * CGFloat(t / day), y: horizon - k * CGFloat(height(t))) }

            // The whole day, faint.
            var whole = Path()
            whole.move(to: point(0))
            for i in 1...96 { whole.addLine(to: point(day * Double(i) / 96)) }
            context.stroke(whole, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            // Daylight: the arc above the horizon, in the tile's colour.
            if length > 0 {
                var arc = Path()
                arc.move(to: point(rise))
                for i in 1...48 { arc.addLine(to: point(rise + length * Double(i) / 48)) }
                var under = arc
                under.closeSubpath()
                context.fill(under, with: .color(accent.opacity(0.15)))
                context.stroke(arc, with: .color(accent.opacity(0.6)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            var line = Path()
            line.move(to: CGPoint(x: 0, y: horizon))
            line.addLine(to: CGPoint(x: canvas.width, y: horizon))
            context.stroke(line, with: .color(.white.opacity(0.3)), lineWidth: 1)
            // The sun: bright with a glow when it's up, dim below the horizon.
            let t = clock(now), sun = point(t)
            if height(t) >= 0 {
                let glow = ui.pt(6), dot = ui.pt(3.5)
                context.fill(Path(ellipseIn: CGRect(x: sun.x - glow, y: sun.y - glow, width: 2 * glow, height: 2 * glow)), with: .color(accent.opacity(0.35)))
                context.fill(Path(ellipseIn: CGRect(x: sun.x - dot, y: sun.y - dot, width: 2 * dot, height: 2 * dot)), with: .color(.white))
            } else {
                let dot = ui.pt(3)
                context.fill(Path(ellipseIn: CGRect(x: sun.x - dot, y: sun.y - dot, width: 2 * dot, height: 2 * dot)), with: .color(.white.opacity(0.4)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: ui.pt(34))
        .accessibilityHidden(true)
    }
}

/// The normal low to high (muted) over today's low to high (in the tile's colour), on one scale that
/// just fits both, as in Apple's Weather, so the difference is easy to see.
struct RangeBars: View {
    @Environment(\.metrics) private var ui
    let normalLow: Double
    let normalHigh: Double
    let recordLow: Double?
    let recordHigh: Double?
    let todayLow: Double
    let todayHigh: Double
    let accent: Color

    var body: some View {
        Canvas { context, canvas in
            let lowest = min(normalLow, todayLow), highest = max(normalHigh, todayHigh)
            let padding = max((highest - lowest) * 0.15, 2)
            let low = lowest - padding, high = highest + padding
            let x = { (value: Double) in canvas.width * CGFloat((value - low) / (high - low)) }
            // One lane: a faint track, then the band from `from` to `to` with rounded ends.
            func lane(_ from: Double, _ to: Double, y: CGFloat, thickness: CGFloat, colour: Color) {
                let track = CGRect(x: 0, y: y, width: canvas.width, height: thickness)
                context.fill(Path(roundedRect: track, cornerRadius: thickness / 2), with: .color(.white.opacity(0.08)))
                let start = x(min(from, to)), width = max(x(max(from, to)) - start, thickness)
                let band = CGRect(x: min(start, canvas.width - width), y: y, width: width, height: thickness)
                context.fill(Path(roundedRect: band, cornerRadius: thickness / 2), with: .color(colour))
            }
            let normal = ui.pt(4), today = ui.pt(6)
            lane(normalLow, normalHigh, y: 0, thickness: normal, colour: .white.opacity(0.4))
            lane(todayLow, todayHigh, y: canvas.height - today, thickness: today, colour: accent)
        }
        .frame(maxWidth: .infinity)
        .frame(height: ui.pt(14))
        .accessibilityHidden(true)
    }
}

/// Cloud at each height, high to low, as thin bars filled to its share of the sky.
struct CloudBars: View {
    @Environment(\.metrics) private var ui
    let low: Double
    let mid: Double
    let high: Double
    let accent: Color

    var body: some View {
        VStack(spacing: ui.pt(3)) {
            row("High", high)
            row("Mid", mid)
            row("Low", low)
        }
        .accessibilityHidden(true)
    }

    private func row(_ name: String, _ percent: Double) -> some View {
        HStack(spacing: ui.pt(6)) {
            Text(name)
                .font(ui.font(10))
                .opacity(0.7)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: ui.pt(26), alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    if percent >= 0.5 {
                        Capsule().fill(accent)
                            .frame(width: max(geo.size.height, geo.size.width * CGFloat(min(percent, 100) / 100)))
                    }
                }
            }
            .frame(height: ui.pt(4))
        }
    }
}
