import SwiftUI

// The panel's parts, shared by the Mac app (WeatherPanel) and the iPhone app (PhoneView): header
// controls, cities, now, the next 24 hours, five days, and the small pieces they're built from.

// MARK: - Header controls

/// °F | °C: picks which unit is shown large. Both are always on screen.
struct UnitToggle: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TempUnit.allCases) { unit in
                let on = store.unit == unit
                Button { store.unit = unit } label: {
                    Text(unit.symbol)
                        .font(ui.font(13, .medium))
                        .foregroundStyle(on ? Palette.bg : Palette.textSecondary)
                        .frame(width: ui.pt(44), height: ui.pt(26))
                        .background(Capsule().fill(on ? Palette.cream : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Show \(unit.symbol) large")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(ui.pt(3))
        .background(Capsule().fill(Palette.raisedTile))
        .overlay(Capsule().strokeBorder(Palette.borderStrong, lineWidth: 0.5))
        .animation(.easeOut(duration: 0.15), value: store.unit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Larger unit")
    }
}

/// Outlined circle button matching the ⋯ menu, for header actions.
struct HeaderCircleButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HeaderCircle(symbol: symbol)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The round header control's look, shared by its buttons and the Share link.
struct HeaderCircle: View {
    @Environment(\.metrics) private var ui
    @Environment(\.isEnabled) private var isEnabled
    let symbol: String
    @State private var hovering = false

    var body: some View {
        Image(systemName: symbol)
            .font(ui.font(13, .semibold))
            .foregroundStyle(hovering && isEnabled ? Palette.textPrimary : Palette.textSecondary)
            .frame(width: ui.pt(32), height: ui.pt(32))
            .background(Circle().fill(hovering && isEnabled ? Palette.border : Palette.raisedTile))
            .overlay(Circle().strokeBorder(Palette.borderStrong, lineWidth: 0.5))
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - Cities

struct CityChips: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    @Binding var adding: Bool
    @Binding var editing: Bool

    var body: some View {
        FlowLayout(spacing: ui.pt(6)) {
            ForEach(store.cities) { city in
                let on = city.id == store.activeID
                Button { store.select(city) } label: {
                    HStack(spacing: ui.pt(6)) {
                        // Always as wide as the semibold (selected) name, so selecting a city never
                        // changes the row's width and the Add | Edit capsule stays put.
                        ZStack {
                            Text(city.name).font(ui.font(13, .semibold)).hidden()
                            Text(city.name).font(ui.font(13, on ? .semibold : .medium))
                        }
                        if let forecast = store.forecasts[city.id] {
                            Text("\(store.unit.value(forecast.now.temperature))°")
                                .font(ui.font(13, .medium))
                                .monospacedDigit()
                                .opacity(0.72)
                        }
                    }
                }
                .buttonStyle(ChipStyle(on: on))
                .overlay(alignment: .topTrailing) {
                    if editing && store.cities.count > 1 {
                        Button { withAnimation(.snappy) { store.remove(city) } } label: {
                            Image(systemName: "xmark")
                                .font(ui.font(9, .bold))
                                .foregroundStyle(.white)
                                .frame(width: ui.pt(20), height: ui.pt(20))
                                .background(Circle().fill(Palette.crimson))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: ui.pt(6), y: -ui.pt(6))
                        .help("Remove \(city.name)")
                        .accessibilityLabel("Remove \(city.name)")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .contextMenu {
                    Button("Remove \(city.name)", role: .destructive) { store.remove(city) }
                        .disabled(store.cities.count < 2)
                }
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            ListControls(adding: $adding, editing: $editing)
        }
        .padding(.top, editing ? ui.pt(6) : 0)
    }
}

/// Meridian's Add | Edit capsule, icon-only so the city row stays on one line.
struct ListControls: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    @Binding var adding: Bool
    @Binding var editing: Bool

    var body: some View {
        HStack(spacing: 0) {
            Segment(
                symbol: adding ? "checkmark" : "plus",
                active: adding,
                enabled: store.canAdd || adding,
                help: adding ? "Done adding" : (store.canAdd ? "Add a city" : "You can track up to \(WeatherStore.maxCities) cities")
            ) {
                withAnimation(.snappy) { adding.toggle(); if adding { editing = false } }
            }
            Palette.borderStrong.frame(width: 1, height: ui.pt(14))
                .opacity(adding || editing ? 0 : 1)
            Segment(
                symbol: editing ? "checkmark" : "pencil",
                active: editing,
                enabled: store.cities.count > 1 || editing,
                help: editing ? "Done editing" : "Remove cities"
            ) {
                withAnimation(.snappy) { editing.toggle(); if editing { adding = false } }
            }
        }
        .padding(ui.pt(2))   // 26 + 2 × 2 = 30, the chips' height
        .background(Capsule().fill(Palette.raisedTile))
        .overlay(Capsule().strokeBorder(Palette.borderStrong, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Manage cities")
    }

    private struct Segment: View {
        @Environment(\.metrics) private var ui
        let symbol: String
        let active: Bool
        let enabled: Bool
        let help: String
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(ui.font(11, .semibold))
                    .frame(width: ui.pt(32), height: ui.pt(26))
                    .foregroundStyle(active ? Palette.bg : (enabled ? (hovering ? Palette.textPrimary : Palette.textSecondary) : Palette.textFaint))
                    .background(
                        Capsule().fill(active ? Palette.cream : (hovering && enabled ? Palette.border : .clear))
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(.snappy, value: active)
            .help(help)
            .accessibilityLabel(help)
        }
    }
}

struct ChipStyle: ButtonStyle {
    var on: Bool

    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration, on: on)
    }

    private struct ChipBody: View {
        let configuration: ButtonStyleConfiguration
        let on: Bool
        @Environment(\.metrics) private var ui
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, ui.pt(12))
                .frame(height: ui.pt(30))
                .foregroundStyle(on ? Palette.bg : (hovering ? Palette.textPrimary : Palette.textSecondary))
                .background(Capsule().fill(on ? Palette.cream : (hovering ? Palette.borderStrong : Palette.border)))
                .opacity(configuration.isPressed ? 0.8 : 1)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }
}

struct CitySearchField: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    @Binding var adding: Bool
    @State private var query = ""
    @State private var results: [City] = []
    @State private var searching = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ui.s) {
            HStack(spacing: ui.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.textMuted)
                TextField("Add a city", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { if let first = results.first { add(first) } }
                if searching { ProgressView().controlSize(.small) }
            }
            .font(ui.font(15))
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, ui.m)
            .frame(height: ui.pt(44))
            .background(RoundedRectangle(cornerRadius: ui.cellRadius, style: .continuous).fill(Palette.bg))
            .overlay(
                RoundedRectangle(cornerRadius: ui.cellRadius, style: .continuous)
                    .strokeBorder(focused ? Palette.textFaint : Palette.borderStrong, lineWidth: 1)
            )

            if !results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(results) { city in
                        Button { add(city) } label: {
                            HStack(spacing: ui.m) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(city.name).font(ui.body).foregroundStyle(Palette.textPrimary)
                                    Text(city.region).font(ui.meta).foregroundStyle(Palette.textMuted)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .font(ui.font(17))
                                    .foregroundStyle(Palette.textMuted)
                            }
                            .padding(.horizontal, ui.m)
                            .frame(height: ui.pt(52))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
            } else if query.count >= 2 && !searching {
                Text("No match for “\(query)”. Try a larger nearby city.")
                    .font(ui.meta)
                    .foregroundStyle(Palette.textMuted)
                    .padding(.horizontal, ui.m)
            }
        }
        .onAppear { focused = true }
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespaces)
            guard text.count >= 2 else { results = []; return }
            try? await Task.sleep(for: .milliseconds(280))   // wait for typing to pause
            guard !Task.isCancelled else { return }
            searching = true
            let found = (try? await OpenMeteo.search(text)) ?? []
            if !Task.isCancelled { results = Array(found.prefix(6)) }
            searching = false
        }
    }

    private func add(_ city: City) {
        store.add(city)
        query = ""
        adding = false
    }
}

// MARK: - Now

struct NowTile: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let city: City
    let forecast: Forecast

    var body: some View {
        let now = forecast.now
        let unit = store.unit, other = store.unit.other
        let today = forecast.days.first?.including(now.temperature)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: ui.s) {
                Text(city.name)
                    .font(ui.font(21, .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Palette.textPrimary)
                Text([city.region, Forecast.format(now.time, "jmm")].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(ui.meta)
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: ui.pt(14)) {
                WeatherSymbol(code: now.code, isDay: now.isDay, size: ui.pt(50))
                    .frame(width: ui.pt(64), height: ui.pt(64))
                    .accessibilityHidden(true)
                // As in the widgets: the big number with its unit smaller and raised, then the other unit
                // whole, on the same baseline.
                HStack(alignment: .firstTextBaseline, spacing: ui.pt(8)) {
                    (Text("\(unit.value(now.temperature))").font(ui.font(64, .semibold))
                        + Text("\u{200A}" + unit.symbol).font(ui.font(64 * 0.42, .medium)).baselineOffset(ui.pt(64) * 0.36).tracking(ui.pt(64) * 0.012))
                        .tracking(-ui.pt(64) * 0.03)
                        .foregroundStyle(Palette.textPrimary)
                    Text(other.spaced(other.value(now.temperature)))
                        .font(ui.font(64 * 0.45, .medium))
                        .foregroundStyle(Palette.textMuted)
                }
                .monospacedDigit()
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Speech.temperature(now.temperature))
            }
            .padding(.top, ui.pt(6))
            .padding(.bottom, ui.pt(4))

            Text(Condition.name(now.code))
                .font(ui.font(17, .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text(Summary.line(forecast, unit: unit))
                .font(ui.font(14))
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: ui.s) {
                Stat(key: "Feels like", value: "\(unit.value(now.feelsLike))\(unit.symbol)", sub: "\(other.value(now.feelsLike))\(other.symbol)")
                if let today {
                    Stat(key: "Today", value: "\(unit.value(today.low))–\(unit.value(today.high))\(unit.symbol)",
                         sub: "\(other.value(today.low))–\(other.value(today.high))\(other.symbol)")
                }
                Stat(key: "Wind", value: "\(Int((now.wind * 0.621371).rounded())) mph", sub: "\(Int(now.wind.rounded())) km/h")
                Stat(key: "Rain today", value: "\(today?.rainChance ?? 0)%", sub: "\(Int(now.humidity.rounded()))% humid")
            }
            .padding(.top, ui.m)
        }
        .padding(ui.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The glow is an overlay, so its fixed size can never change the tile's size.
        .background(
            RoundedRectangle(cornerRadius: ui.tileRadius, style: .continuous)
                .fill(Palette.raisedTile)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(RadialGradient(colors: [Glow.color(code: now.code, isDay: now.isDay), .clear], center: .center, startRadius: 0, endRadius: ui.pt(160)))
                        .frame(width: ui.pt(320), height: ui.pt(320))
                        .offset(x: ui.pt(110), y: -ui.pt(150))
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: ui.tileRadius, style: .continuous))
        )
    }
}

/// "57°F" with the unit set small and raised, the way weather apps print it.
struct DegreeText: View {
    let value: Int
    let unit: TempUnit
    let size: CGFloat
    let weight: Font.Weight
    let color: Color
    var unitColor: Color? = nil
    @Environment(\.metrics) private var ui

    var body: some View {
        HStack(alignment: .top, spacing: size * 0.04) {
            Text("\(value)")
                .font(ui.font(size / ui.scale, weight))
                .tracking(-size * 0.04)
                .monospacedDigit()
                .foregroundStyle(color)
            Text(unit.symbol)
                .font(ui.font(size * 0.42 / ui.scale, .medium))
                .foregroundStyle(unitColor ?? Palette.textSecondary)
                .padding(.top, size * 0.08)
        }
    }
}

struct Stat: View {
    @Environment(\.metrics) private var ui
    let key: String
    let value: String
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: ui.pt(3)) {
            Text(key)
                .font(ui.font(12, .medium))
                .foregroundStyle(Palette.textMuted)
            Text(value)
                .font(ui.font(14, .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
            Text(sub)
                .font(ui.font(12))
                .monospacedDigit()
                .foregroundStyle(Palette.textMuted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, ui.pt(10))
        .padding(.vertical, ui.pt(8))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ui.cellRadius, style: .continuous).fill(Palette.raised))
    }
}

// MARK: - Next 24 hours

struct HoursTile: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let forecast: Forecast

    var body: some View {
        let hours = forecast.upcomingHours
        let temps = hours.map(\.temperature)
        let low = temps.min() ?? 0, high = temps.max() ?? 1
        let unit = store.unit
        Tile {
            VStack(alignment: .leading, spacing: ui.s) {
                Eyebrow(title: "Next 24 hours", aside: "\(unit.value(low))–\(unit.value(high))\(unit.symbol) · \(unit.other.value(low))–\(unit.other.value(high))\(unit.other.symbol)")
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 0) {
                            ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                                HourColumn(hour: hour, index: index)
                            }
                        }
                        Sparkline(temperatures: temps, column: ui.hourWidth, height: ui.sparkHeight)
                            .offset(y: ui.pt(16) + ui.pt(30))   // under the label and icon slot
                            .allowsHitTesting(false)
                    }
                    .padding(.trailing, ui.xl)
                }
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.86), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
            }
        }
    }
}

struct HourColumn: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let hour: Forecast.Hour
    let index: Int

    var body: some View {
        let unit = store.unit, other = store.unit.other
        let midnight = index > 0 && Forecast.localCalendar.component(.hour, from: hour.time) == 0
        let label = index == 0 ? "Now" : (midnight ? Forecast.format(hour.time, "EEE") : Forecast.format(hour.time, "j"))
        VStack(spacing: 0) {
            Text(label)
                .font(ui.font(12, index == 0 ? .semibold : .medium))
                .foregroundStyle(index == 0 ? Palette.cream : Palette.textMuted)
                .frame(height: ui.pt(16))
            // An hour with rain shrinks its icon to make room for the % beneath it, in the same
            // 30pt slot, so the sparkline below never moves.
            if hour.rainChance >= 20 {
                WeatherSymbol(code: hour.code, isDay: hour.isDay, size: ui.pt(15))
                    .frame(width: ui.pt(26), height: ui.pt(20))
                Text("\(hour.rainChance)%")
                    .font(ui.font(10, .semibold))
                    .foregroundStyle(Palette.rain)
                    .frame(height: ui.pt(10))
            } else {
                WeatherSymbol(code: hour.code, isDay: hour.isDay, size: ui.pt(17))
                    .frame(width: ui.pt(26), height: ui.pt(30))
            }
            Color.clear.frame(height: ui.sparkHeight)
            Text("\(unit.value(hour.temperature))°")
                .font(ui.font(15, .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("\(other.value(hour.temperature))\(other.symbol)")
                .font(ui.font(12))
                .foregroundStyle(Palette.textMuted)
        }
        .monospacedDigit()
        .frame(width: ui.hourWidth)
        .overlay(alignment: .leading) {
            if midnight { Rectangle().fill(Palette.borderStrong).frame(width: 1) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(Condition.name(hour.code)), \(Speech.temperature(hour.temperature))\(hour.rainChance >= 20 ? ", \(hour.rainChance) percent chance of rain" : "")")
    }
}

/// The temperature line under the hourly icons, drawn to one scale across all 24 columns.
struct Sparkline: View {
    let temperatures: [Double]
    let column: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { context, size in
            guard temperatures.count > 1, let low = temperatures.min(), let high = temperatures.max() else { return }
            let pad: CGFloat = 4
            let span = max(high - low, 1)
            let points = temperatures.enumerated().map { i, t in
                CGPoint(x: CGFloat(i) * column + column / 2, y: pad + (1 - CGFloat((t - low) / span)) * (height - pad * 2))
            }
            var line = Path()
            line.addLines(points)
            var area = line
            area.addLine(to: CGPoint(x: points.last!.x, y: height))
            area.addLine(to: CGPoint(x: points[0].x, y: height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(Gradient(colors: [Palette.cream.opacity(0.16), Palette.cream.opacity(0)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: height)))
            context.stroke(line, with: .color(Palette.cream.opacity(0.85)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            for (i, p) in points.enumerated() {
                let r: CGFloat = i == 0 ? 3.6 : 2
                let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                if i == 0 { context.stroke(dot, with: .color(Palette.raisedTile), lineWidth: 4) }
                context.fill(dot, with: .color(i == 0 ? .white : Palette.cream))
            }
        }
        .frame(width: CGFloat(temperatures.count) * column, height: height)
    }
}

// MARK: - Five days

/// The five-day forecast as an accordion, closed when the app opens: closed, one row with the
/// five-day range in both units; open, the bars on their shared, labelled scale.
struct DaysTile: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let forecast: Forecast
    @Binding var open: Bool
    @State private var hovering = false

    var body: some View {
        // One shared scale for all five bars (including right now), with ticks every 10°F or 5°C.
        let days = Array(forecast.days.prefix(5))
        let now = forecast.now.temperature
        let low = min(now, days.map(\.low).min() ?? now), high = max(now, days.map(\.high).max() ?? now)
        let ticks = Ticks.make(low: low, high: high, unit: store.unit)
        let unit = store.unit, other = store.unit.other
        let dLow = days.map(\.low).min() ?? now, dHigh = days.map(\.high).max() ?? now
        Tile {
            VStack(alignment: .leading, spacing: ui.xs) {
                Button { withAnimation(.snappy) { open.toggle() } } label: {
                    HStack(spacing: ui.pt(10)) {
                        Text("5-day forecast")
                            .font(ui.eyebrow)
                            .foregroundStyle(hovering ? Palette.textPrimary : Palette.textMuted)
                            .frame(width: ui.pt(52) + ui.pt(10) + ui.pt(32) + ui.pt(10) + DayScale.labelRoom(ui) - ui.pt(10), alignment: .leading)   // ticks start where the bars' scale does
                        if open {
                            GeometryReader { proxy in
                                ForEach(ticks, id: \.label) { tick in
                                    Text("\(tick.label)°")
                                        .font(ui.font(11, .medium))
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.textFaint)
                                        .fixedSize()
                                        .position(x: CGFloat((tick.celsius - low) / max(high - low, 1)) * proxy.size.width, y: proxy.size.height / 2)
                                }
                            }
                            .frame(height: ui.pt(14))
                            .accessibilityHidden(true)
                        } else {
                            Text("\(unit.value(dLow))–\(unit.value(dHigh))\(unit.symbol) · \(other.value(dLow))–\(other.value(dHigh))\(other.symbol)")
                                .font(ui.font(13, .medium))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textFaint)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        Image(systemName: "chevron.down")
                            .font(ui.font(11, .semibold))
                            .foregroundStyle(hovering ? Palette.textPrimary : Palette.textMuted)
                            .rotationEffect(.degrees(open ? 180 : 0))
                            .frame(width: DayScale.labelRoom(ui) - ui.pt(10), alignment: .trailing)   // and end where it does
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .accessibilityLabel(open ? "Hide 5-day forecast" : "Show 5-day forecast")
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, open ? ui.xs : 0)

                if open {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        if index > 0 { Rectangle().fill(Palette.borderStrong).frame(height: 0.5) }
                        DayRow(day: index == 0 ? day.including(now) : day, isToday: index == 0, low: low, high: high, ticks: ticks.map(\.celsius),
                               now: index == 0 ? now : nil)
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}

struct DayRow: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let day: Forecast.Day
    let isToday: Bool
    let low: Double
    let high: Double
    let ticks: [Double]
    let now: Double?

    var body: some View {
        let unit = store.unit, other = store.unit.other
        let name = isToday ? "Today" : Forecast.format(day.date, "EEE")
        HStack(spacing: ui.pt(10)) {
            Text(name)
                .font(ui.font(15, .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: ui.pt(52), alignment: .leading)
            WeatherSymbol(code: day.code, isDay: true, size: ui.pt(17))
                .frame(width: ui.pt(32))
                .overlay(alignment: .bottom) {
                    if day.rainChance >= 20 {
                        Text("\(day.rainChance)%")
                            .font(ui.font(10, .semibold))
                            .foregroundStyle(Palette.rain)
                            .fixedSize()
                            .offset(y: ui.pt(10))
                    }
                }
            RangeBar(low: day.low, high: day.high, scaleLow: low, scaleHigh: high, ticks: ticks, now: now) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(unit.value(day.low))°").font(ui.font(15, .semibold)).foregroundStyle(Palette.textSecondary)
                    Text("\(other.value(day.low))\(other.symbol)").font(ui.font(12)).foregroundStyle(Palette.textMuted)
                }
            } highLabel: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(unit.value(day.high))°").font(ui.font(15, .semibold)).foregroundStyle(Palette.textPrimary)
                    Text("\(other.value(day.high))\(other.symbol)").font(ui.font(12)).foregroundStyle(Palette.textMuted)
                }
            }
            .frame(height: ui.pt(36))
        }
        .monospacedDigit()
        .frame(minHeight: ui.pt(40))   // compact rows: the two-line labels fill the height
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(Condition.name(day.code)). Low \(Speech.temperature(day.low)). High \(Speech.temperature(day.high)).\(day.rainChance >= 20 ? " \(day.rainChance) percent chance of rain." : "")")
    }
}

/// One day's low-to-high on the shared five-day scale, coloured by temperature.
enum DayScale {
    /// Room kept either side of the five-day scale for a low or high label at its far end.
    static func labelRoom(_ ui: Metrics) -> CGFloat { ui.pt(46) }
}

/// One day's range on the shared scale, with its low and high riding the ends of the bar so the bar reads as
/// that day's range.
struct RangeBar<Low: View, High: View>: View {
    @Environment(\.metrics) private var ui
    let low: Double
    let high: Double
    let scaleLow: Double
    let scaleHigh: Double
    let ticks: [Double]
    let now: Double?
    @ViewBuilder let lowLabel: () -> Low
    @ViewBuilder let highLabel: () -> High

    var body: some View {
        GeometryReader { proxy in
            let room = DayScale.labelRoom(ui), gap = ui.pt(8), bar = ui.pt(6)
            let width = max(proxy.size.width - 2 * room, 1)
            let span = max(scaleHigh - scaleLow, 1)
            let x = { (t: Double) in room + CGFloat((t - scaleLow) / span) * width }
            ZStack(alignment: .leading) {
                // No empty track: the ticks carry the scale.
                ForEach(ticks, id: \.self) { t in
                    Rectangle().fill(Palette.borderStrong)
                        .frame(width: 1, height: bar + 8)
                        .offset(x: x(t) - 0.5)
                }
                Capsule()
                    .fill(LinearGradient(colors: [Palette.temperature(low), Palette.temperature(high)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(x(high) - x(low), bar), height: bar)
                    .offset(x: x(low))
                if let now {
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Palette.raisedTile, lineWidth: 2.5))
                        .frame(width: 10, height: 10)
                        .offset(x: x(now) - 5)
                }
                // The tile colour behind each label hides any tick it sits on.
                lowLabel()
                    .fixedSize()
                    .padding(.trailing, gap)
                    .background(Palette.raisedTile)
                    .frame(width: x(low), alignment: .trailing)
                highLabel()
                    .fixedSize()
                    .padding(.leading, gap)
                    .background(Palette.raisedTile)
                    .frame(width: proxy.size.width - x(high), alignment: .leading)
                    .offset(x: x(high))
            }
            .frame(height: proxy.size.height)
        }
    }
}

// MARK: - Status

struct StatusLine: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui

    var body: some View {
        HStack(spacing: ui.s) {
            Circle()
                .fill(store.isOffline ? Palette.crimson : (store.activeForecast == nil ? Palette.textFaint : Color(hex: 0x6FD39C)))
                .frame(width: ui.pt(7), height: ui.pt(7))
            Text(text).truncationMode(.tail)
            Text("·").accessibilityHidden(true)
            Link("Data: Open-Meteo", destination: Brand.dataCredit)
                .help("Weather data by Open-Meteo.com")
                .fixedSize()
        }
        .font(ui.font(12))
        .foregroundStyle(Palette.textMuted)
        .lineLimit(1)
    }

    private var text: String {
        if store.loading && store.activeForecast == nil { return "Loading…" }
        guard let forecast = store.activeForecast else { return "Offline" }
        let time = forecast.fetchedAt.formatted(date: .omitted, time: .shortened)
        return store.isOffline ? "Offline · from \(time)" : "Updated \(time)"
    }
}

// MARK: - Shared bits

struct Eyebrow: View {
    @Environment(\.metrics) private var ui
    let title: String
    let aside: String

    var body: some View {
        HStack {
            Text(title).font(ui.eyebrow).foregroundStyle(Palette.textMuted)
            Spacer()
            Text(aside).font(ui.font(13, .medium)).monospacedDigit().foregroundStyle(Palette.textFaint)
        }
    }
}

/// Small in-app mark: two degree rings, cream and pink, on the warm-black tile.
struct AppMark: View {
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(Palette.subtle)
            .overlay {
                ZStack {
                    Circle()
                        .strokeBorder(Palette.cream, lineWidth: size * 0.086)
                        .frame(width: size * 0.41, height: size * 0.41)
                        .offset(x: -size * 0.13, y: -size * 0.086)
                    Circle()
                        .strokeBorder(Palette.pink, lineWidth: size * 0.079)
                        .frame(width: size * 0.30, height: size * 0.30)
                        .offset(x: size * 0.164, y: size * 0.086)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct IconButton: View {
    @Environment(\.metrics) private var ui
    let symbol: String
    let help: String
    var small = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(ui.font(small ? 12 : 14, .semibold))
                .foregroundStyle(hovering ? Palette.textPrimary : Palette.textSecondary)
                .frame(width: ui.pt(small ? 28 : 34), height: ui.pt(small ? 28 : 34))
                .background(Circle().fill(hovering ? Palette.borderStrong : Palette.border))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// apple.com-style pill: white for the primary action, warm grey for secondary.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent, small: small)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let small: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.metrics) private var ui
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(ui.font(small ? 13 : 14, .semibold))
                .padding(.horizontal, ui.pt(small ? 14 : 20))
                .frame(height: ui.pt(small ? 28 : 34))
                .foregroundStyle(prominent ? Palette.bg : (isEnabled ? Palette.textPrimary : Palette.textMuted))
                .background(
                    Capsule().fill(prominent ? (hovering ? Palette.cream : Color.white) : (hovering && isEnabled ? Palette.borderStrong : Palette.border))
                )
                .opacity(configuration.isPressed ? 0.8 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }
}

/// Large rounded raised surface, like the product tiles on apple.com.
struct Tile<Content: View>: View {
    @Environment(\.metrics) private var ui
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(ui.tilePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: ui.tileRadius, style: .continuous).fill(Palette.raisedTile))
    }
}

struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowHover(configuration: configuration)
    }

    private struct RowHover: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.metrics) private var ui
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: ui.cellRadius, style: .continuous)
                        .fill(configuration.isPressed ? Palette.borderStrong : (hovering ? Palette.border : .clear))
                )
                .onHover { hovering = $0 }
        }
    }
}

/// Lays chips out left to right, wrapping onto new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Words

/// One plain sentence about what's coming: rain soon, warming, cooling, or today's range.
enum Summary {
    static func line(_ forecast: Forecast, unit: TempUnit) -> String {
        let hours = forecast.upcomingHours
        let dual = { (c: Double) in "\(unit.value(c))\(unit.symbol) / \(unit.other.value(c))\(unit.other.symbol)" }
        let hour = { (h: Forecast.Hour) in Forecast.format(h.time, "j") }
        if let wet = hours.dropFirst().prefix(12).first(where: { $0.rainChance >= 50 }) {
            let what = Condition.isSnow(wet.code) ? "Snow" : ([95, 96, 99].contains(wet.code) ? "Storms" : "Rain")
            return "\(what) likely around \(hour(wet)) (\(wet.rainChance)%)."
        }
        let next = Array(hours.prefix(16))
        guard let first = next.first else { return "" }
        if let peak = next.max(by: { $0.temperature < $1.temperature }), peak.time != first.time, peak.temperature - forecast.now.temperature > 1.5 {
            return "Warming to \(dual(peak.temperature)) by \(hour(peak))."
        }
        if let dip = next.min(by: { $0.temperature < $1.temperature }), dip.time != first.time, forecast.now.temperature - dip.temperature > 1.5 {
            return "Cooling to \(dual(dip.temperature)) by \(hour(dip))."
        }
        guard let today = forecast.days.first else { return "" }
        return "Today \(dual(today.low)) to \(dual(today.high))."
    }
}

/// Round values for the five-day scale: every 10°F or 5°C, kept clear of the bar ends.
enum Ticks {
    struct Tick { let label: Int; let celsius: Double }

    static func make(low: Double, high: Double, unit: TempUnit) -> [Tick] {
        let step = unit == .fahrenheit ? 10 : 5
        let toC = { (v: Double) in unit == .fahrenheit ? (v - 32) * 5 / 9 : v }
        let lowInUnit = unit == .fahrenheit ? low * 9 / 5 + 32 : low
        let span = max(high - low, 1)
        var ticks: [Tick] = []
        var v = Int((lowInUnit / Double(step)).rounded(.up)) * step
        while toC(Double(v)) <= high {
            let at = (toC(Double(v)) - low) / span
            if at > 0.05 && at < 0.95 { ticks.append(Tick(label: v, celsius: toC(Double(v)))) }
            v += step
        }
        return ticks
    }
}

/// A soft glow in the corner of the Now tile, tinted by the sky.
enum Glow {
    static func color(code: Int, isDay: Bool) -> Color {
        guard isDay else { return Color(hex: 0xE9DCC8).opacity(0.10) }
        switch code {
        case 0, 1: return Palette.sun.opacity(0.20)
        case 2: return Palette.sun.opacity(0.13)
        case 95, 96, 99: return Palette.crimson.opacity(0.28)
        case 71...86 where Condition.isSnow(code): return Color.white.opacity(0.12)
        case 51...82: return Palette.rain.opacity(0.16)
        default: return Palette.cloudGlow
        }
    }
}

private extension Palette {
    static let cloudGlow = Color(hex: 0xCFC6BB).opacity(0.09)
}
