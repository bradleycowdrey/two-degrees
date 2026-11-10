import SwiftUI

// The Mac panel's own controls, drawn on the city's sky: the header buttons, the row of city chips,
// adding a city, and the small pieces they're built from. (The city page itself is in CityCards.swift
// and Tiles.swift, shared with the iPhone.) Also here, for both apps: the app mark and the summary line.

/// The controls' tones on the sky: translucent white capsules, solid white with dark text when chosen.
enum SkyControl {
    static let fill = Color.white.opacity(0.14)
    static let hover = Color.white.opacity(0.24)
    static let on = Color.white
    /// Text and icons on a solid white control.
    static let ink = Color.black.opacity(0.8)
    /// Text and icons on the sky or a translucent control: full white under the pointer.
    static func text(_ hovering: Bool = false) -> Color { Color.white.opacity(hovering ? 1 : 0.85) }
}

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
                    Text(unit.label)
                        .font(ui.font(13, .medium))
                        .foregroundStyle(on ? SkyControl.ink : SkyControl.text())
                        .frame(width: ui.pt(44), height: ui.pt(26))
                        .background(Capsule().fill(on ? SkyControl.on : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Show \(unit.label) large")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(ui.pt(3))
        .background(Capsule().fill(SkyControl.fill))
        .animation(.easeOut(duration: 0.15), value: store.unit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Larger unit")
    }
}

/// Round translucent button matching the ⋯ menu, for header actions.
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
            .foregroundStyle(SkyControl.text(hovering && isEnabled))
            .frame(width: ui.pt(32), height: ui.pt(32))
            .background(Circle().fill(hovering && isEnabled ? SkyControl.hover : SkyControl.fill))
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
                        if store.isHere(city) {
                            Image(systemName: "location.fill")
                                .font(ui.font(10, .semibold))
                                .accessibilityLabel("My Location:")
                        }
                        // Always as wide as the semibold (selected) name, so selecting a city never
                        // changes the row's width and the chips after it stay put.
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
                .help(Self.about(city, store.forecasts[city.id]))
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
                    if city.isCurrent {
                        Button("Stop Using My Location") { store.useLocation = false }
                    } else {
                        Button("Remove \(city.name)", role: .destructive) { store.remove(city) }
                            .disabled(store.cities.count < 2)
                    }
                }
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.top, editing ? ui.pt(6) : 0)
    }

    /// Where a city is and its local time ("England, United Kingdom · 1:15 AM"): each chip's tooltip, and
    /// the line under the open city's name.
    nonisolated static func about(_ city: City, _ forecast: Forecast?) -> String {
        [city.region, forecast.map { Forecast.format($0.now.time, "jmm") } ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Meridian's Add | Edit capsule, icon-only, in the header between Share and the °F | °C toggle.
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
            Color.white.opacity(0.25).frame(width: 1, height: ui.pt(14))
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
        .background(Capsule().fill(SkyControl.fill))
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
                    .foregroundStyle(active ? SkyControl.ink : (enabled ? SkyControl.text(hovering) : Color.white.opacity(0.4)))
                    .background(
                        Capsule().fill(active ? SkyControl.on : (hovering && enabled ? SkyControl.hover : .clear))
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
                .foregroundStyle(on ? SkyControl.ink : SkyControl.text(hovering))
                .background(Capsule().fill(on ? SkyControl.on : (hovering ? SkyControl.hover : SkyControl.fill)))
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
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
                TextField("Add a city", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { if let first = results.first { add(first) } }
                if searching { ProgressView().controlSize(.small) }
            }
            .font(ui.font(15))
            .foregroundStyle(.white)
            .padding(.horizontal, ui.m)
            .frame(height: ui.pt(44))
            .background(RoundedRectangle(cornerRadius: ui.cellRadius, style: .continuous).fill(Color.black.opacity(0.2)))
            .overlay(
                RoundedRectangle(cornerRadius: ui.cellRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(focused ? 0.5 : 0.2), lineWidth: 1)
            )

            if !results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(results) { city in
                        Button { add(city) } label: {
                            HStack(spacing: ui.m) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(city.name).font(ui.body).foregroundStyle(.white)
                                    Text(city.region).font(ui.meta).foregroundStyle(.white.opacity(0.6))
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .font(ui.font(17))
                                    .foregroundStyle(.white.opacity(0.6))
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
                    .foregroundStyle(.white.opacity(0.6))
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

// MARK: - Shared bits

/// Small in-app mark, as the app icon (scripts/make-icon.py): two degree rings, cream and a sunset
/// coral-to-pink, on the dusk sky.
struct AppMark: View {
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(stops: [.init(color: Color(hex: 0x627A98), location: 0),
                                         .init(color: Color(hex: 0x2C364A), location: 0.62),
                                         .init(color: Color(hex: 0x3A2E32), location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                ZStack {
                    Circle()
                        .strokeBorder(Palette.cream, lineWidth: size * 0.086)
                        .frame(width: size * 0.41, height: size * 0.41)
                        .offset(x: -size * 0.13, y: -size * 0.086)
                    Circle()
                        .strokeBorder(LinearGradient(colors: [Color(hex: 0xF7A870), Color(hex: 0xE24A7A)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: size * 0.079)
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
                .foregroundStyle(SkyControl.text(hovering))
                .frame(width: ui.pt(small ? 28 : 34), height: ui.pt(small ? 28 : 34))
                .background(Circle().fill(hovering ? SkyControl.hover : SkyControl.fill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// apple.com-style pill: solid white for the primary action, translucent white for secondary.
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
                .foregroundStyle(prominent ? SkyControl.ink : Color.white.opacity(isEnabled ? 1 : 0.5))
                .background(
                    Capsule().fill(prominent ? Color.white.opacity(hovering ? 0.88 : 1) : (hovering && isEnabled ? SkyControl.hover : SkyControl.fill))
                )
                .opacity(configuration.isPressed ? 0.8 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
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
                        .fill(Color.white.opacity(configuration.isPressed ? 0.2 : (hovering ? 0.1 : 0)))
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
