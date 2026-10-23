import SwiftUI
import AppKit

/// The whole app in one panel: header, cities, now, next 24 hours, five days, footer.
/// Used by both the menu bar popover and the Dock app's window.
struct WeatherPanel: View {
    @EnvironmentObject private var store: WeatherStore
    var compact = false

    var body: some View {
        let ui = Metrics(scale: store.uiSize.scale, family: store.appFont)
        WeatherPanelContent(compact: compact)
            .frame(width: ui.panelWidth + 2 * ui.xl)
            .environment(\.metrics, ui)
    }
}

private struct WeatherPanelContent: View {
    @EnvironmentObject private var store: WeatherStore
    @EnvironmentObject private var updater: Updater
    @Environment(\.metrics) private var ui
    @Environment(\.openWindow) private var openWindow
    let compact: Bool
    @State private var adding = false
    @State private var editing = false
    /// The five-day forecast starts closed every time the app opens.
    @State private var daysOpen = false
    @State private var contentHeight: CGFloat = 0
    /// Height of the window's hidden title bar. The panel draws under it (so the crimson rule
    /// is at the very top), and SwiftUI still adds it to the window height, so it's subtracted
    /// at the bottom to keep the window exactly the size of the panel.
    @State private var titleBarInset: CGFloat = 0
    @State private var host = HostWindow()

    /// Tallest the scrolling body may be so the whole panel stays on screen at any size.
    private var maxBodyHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        let chrome = 3 + ui.pt(compact ? 21 : 34) + ui.pt(32) + ui.pt(10)   // crimson rule + header
        return max(ui.pt(320), screen - chrome - ui.pt(compact ? 32 : 64))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Crimson rule and header together act as the window's title bar: drag anywhere
            // that isn't a button to move the window.
            VStack(alignment: .leading, spacing: 0) {
                // bradcowdrey.com's signature crimson rule.
                Palette.crimson.frame(height: 3)

                header
                    .padding(.horizontal, ui.pt(18))
                    // The window's traffic lights sit in the band above the header.
                    .padding(.top, compact ? ui.pt(21) : ui.pt(34))
                    .padding(.bottom, ui.pt(10))
            }
            // Window: drag to move. Menu bar panel (which macOS pins under its icon): drag to
            // tear it off into a movable window at the same spot.
            .background(WindowDragHandle(onTearOff: compact ? { tearOff() } : nil))
            .help(compact ? "Drag to detach into a window" : "")

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ui.pt(10)) {
                    // Only takes space when there's something to say.
                    if updater.latest != nil || updater.notice != nil || updater.userChecking {
                        UpdateBanner()
                    }
                    CityChips(adding: $adding, editing: $editing)
                    if adding {
                        Tile { CitySearchField(adding: $adding) }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let forecast = store.activeForecast {
                        NowTile(city: store.active, forecast: forecast)
                        HoursTile(forecast: forecast)
                        DaysTile(forecast: forecast, open: $daysOpen)
                    } else {
                        Tile {
                            HStack(spacing: ui.m) {
                                if store.isOffline {
                                    Image(systemName: "wifi.exclamationmark").foregroundStyle(Palette.textMuted)
                                    Text("Couldn’t reach Open-Meteo. Check your connection, then press Refresh.")
                                } else {
                                    ProgressView().controlSize(.small)
                                    Text("Loading the forecast for \(store.active.name)…")
                                }
                            }
                            .font(ui.meta)
                            .foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    footer
                }
                .padding(.horizontal, ui.pt(18))
                .padding(.bottom, ui.l)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: contentHeight > 0 ? min(contentHeight, maxBodyHeight) : nil)
            .onPreferenceChange(ContentHeightKey.self) { height in
                contentHeight = height
                if SelfTest.isActive && !compact { SelfTest.panelMeasured(content: height, maxBody: maxBodyHeight, width: ui.panelWidth + 2 * ui.xl) }
            }
        }
        // Watch the panel's own size and fit the hosting window to it.
        .onGeometryChange(for: CGSize.self) { proxy in proxy.size } action: { size in
            fitWindow(to: size)
        }
        .padding(.bottom, -titleBarInset)
        .background(Palette.bg)
        // Use the full window: the crimson rule sits at the very top, under the hidden title bar.
        .ignoresSafeArea()
        .background(Palette.bg.ignoresSafeArea())
        .background(HostWindowReader(box: { host.isDesktop = !compact; return host }()) { window in
            guard !compact else { return }
            window.backgroundColor = NSColor(Palette.bg)
            let inset = max(0, window.frame.height - window.contentLayoutRect.height)
            if abs(inset - titleBarInset) > 0.5 { titleBarInset = inset }
        })
        .environment(\.colorScheme, .dark)
        .animation(.snappy, value: adding)
        .animation(.snappy, value: editing)
        .onAppear { Task { await updater.checkIfDue() } }
        .task {
            if !compact && SelfTest.isActive {
                await SelfTest.run(store: store, adding: $adding, editing: $editing, daysOpen: $daysOpen, host: host)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(characters: CharacterSet(charactersIn: "fFcC"), phases: .down) { press in
            guard !adding, press.modifiers.isEmpty || press.modifiers == .shift else { return .ignored }
            store.unit = press.characters.lowercased() == "f" ? .fahrenheit : .celsius
            return .handled
        }
        .onKeyPress(.escape) {
            guard adding || editing else { return .ignored }
            adding = false
            editing = false
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "+=-"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            store.stepSize(press.characters == "-" ? -1 : 1)
            return .handled
        }
    }

    private var header: some View {
        HStack(spacing: ui.m) {
            AppMark(size: ui.pt(28))
            Text(Brand.appName)
                .font(ui.title)
                .tracking(-0.2)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
            Spacer(minLength: ui.s)
            HStack(spacing: ui.s) {
                shareButton
                UnitToggle()
                HeaderCircleButton(symbol: "arrow.clockwise", help: "Refresh") {
                    Task { await store.refresh() }
                }
                .disabled(store.loading)
                if compact {
                    HeaderCircleButton(symbol: "macwindow", help: "Open as Window") { tearOff() }
                }
                MoreMenu(compact: compact, closeHost: { host.window?.close() })
            }
        }
    }

    /// Resizes the hosting window to exactly the panel's size, keeping its top edge where it is
    /// and the whole window on screen.
    private func fitWindow(to size: CGSize, attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.1)) {
            guard size.width > 1, size.height > 1 else { return }
            guard let window = host.window, let content = window.contentView else {
                // The window reference arrives a moment after first layout; try again briefly.
                if attempt < 10 { fitWindow(to: size, attempt: attempt + 1) }
                return
            }
            let chrome = CGSize(width: window.frame.width - content.bounds.width,
                                height: window.frame.height - content.bounds.height)
            var frame = window.frame
            let top = frame.maxY
            frame.size = CGSize(width: size.width + chrome.width, height: size.height + chrome.height)
            frame.origin.y = top - frame.height
            if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
                frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
                if frame.minY < visible.minY { frame.origin.y = visible.minY }
                if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
            }
            if abs(frame.width - window.frame.width) > 0.5 || abs(frame.height - window.frame.height) > 0.5
                || abs(frame.minX - window.frame.minX) > 0.5 || abs(frame.minY - window.frame.minY) > 0.5 {
                window.setFrame(frame, display: true)
            }
            host.keepOnScreen()
        }
    }

    /// Detaches the menu bar panel into the desktop window, placed where the panel was.
    private func tearOff() {
        if let frame = host.window?.frame {
            WindowPlacement.request(.topLeft(NSPoint(x: frame.minX, y: frame.maxY)))
        }
        openWindow(id: "main")           // placed before it's shown, then fades in
        NSApp.activate(ignoringOtherApps: true)
        host.window?.close()             // the panel goes away in the same beat
    }

    /// The status line, the credit on its own full-width line beneath.
    private var footer: some View {
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

    private var shareButton: some View {
        ShareLink(
            item: Brand.repository,
            subject: Text("Two Degrees for Mac"),
            message: Text(Brand.shareMessage)
        ) {
            HeaderCircle(symbol: "square.and.arrow.up")
        }
        .buttonStyle(.plain)
        .help("Share Two Degrees")
        .accessibilityLabel("Share Two Degrees")
    }
}

/// Shown only when a newer version is out: one line and one button.
private struct UpdateBanner: View {
    @EnvironmentObject private var updater: Updater
    @Environment(\.metrics) private var ui

    var body: some View {
        VStack(alignment: .leading, spacing: ui.s) {
            // An available update is always shown, above any other status, until it's installed.
            if let release = updater.latest {
                row {
                    Circle().fill(Palette.crimson).frame(width: ui.pt(7), height: ui.pt(7))
                    Text("Two Degrees \(release.version) is available")
                        .font(ui.font(14, .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text("You have \(updater.currentVersion)")
                        .font(ui.meta)
                        .foregroundStyle(Palette.textMuted)
                    Spacer(minLength: ui.s)
                    switch updater.phase {
                    case .downloading:
                        ProgressView().controlSize(.small)
                        message("Downloading…")
                    case .installing:
                        ProgressView().controlSize(.small)
                        message("Installing. Two Degrees will restart…")
                    default:
                        Button("Update") { Task { await updater.install() } }
                            .buttonStyle(PillButtonStyle(prominent: true))
                    }
                }
            }

            if updater.userChecking {
                row {
                    ProgressView().controlSize(.small)
                    message("Checking for updates…")
                }
            } else if let notice = updater.notice {
                // The message gets the full width; an error's actions sit on their own line below.
                VStack(alignment: .leading, spacing: ui.s) {
                    HStack(alignment: .top, spacing: ui.m) {
                        Image(systemName: notice.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .font(ui.font(14, .semibold))
                            .foregroundStyle(notice.isError ? Palette.crimson : Palette.cream)
                            .padding(.top, ui.pt(1))
                        Text(notice.text)
                            .font(ui.meta)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        IconButton(symbol: "xmark", help: "Dismiss", small: true) { updater.dismissNotice() }
                    }
                    if notice.isError {
                        HStack(spacing: ui.s) {
                            Spacer()
                            Button("Download from GitHub") { updater.openReleasePage() }
                                .buttonStyle(PillButtonStyle(small: true))
                            Button("Try Again") {
                                Task {
                                    if updater.latest != nil { await updater.install() } else { await updater.check(userInitiated: true) }
                                }
                            }
                            .buttonStyle(PillButtonStyle(prominent: true, small: true))
                        }
                    }
                }
                .padding(.leading, ui.l)
                .padding(.trailing, ui.pt(8))
                .padding(.vertical, ui.pt(10))
                .background(RoundedRectangle(cornerRadius: ui.pt(18), style: .continuous).fill(Palette.raisedTile))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: updater.notice)
        .animation(.snappy, value: updater.userChecking)
        .animation(.snappy, value: updater.latest)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(ui.meta)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: ui.m) { content() }
            .frame(maxWidth: .infinity, minHeight: ui.pt(34), alignment: .leading)
            .padding(.leading, ui.l)
            .padding(.trailing, ui.pt(6))
            .padding(.vertical, ui.pt(6))
            .background(RoundedRectangle(cornerRadius: ui.pt(22), style: .continuous).fill(Palette.raisedTile))
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct MoreMenu: View {
    @EnvironmentObject private var store: WeatherStore
    @EnvironmentObject private var updater: Updater
    @Environment(\.metrics) private var ui
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    let compact: Bool
    /// Closes the menu bar panel this menu lives in.
    let closeHost: () -> Void

    var body: some View {
        Menu {
            if let release = updater.latest {
                Button("Install Two Degrees \(release.version)…") { Task { await updater.install() } }
                    .disabled(updater.isBusy)
                Divider()
            }
            Button("Copy Current Reading") { store.copyReading() }
            Button("Remove \(store.active.name)", role: .destructive) { store.remove(store.active) }
                .disabled(store.cities.count < 2)
            Button("Refresh  ⌘R") { Task { await store.refresh() } }
            Divider()
            Picker("Size", selection: $store.uiSize) {
                ForEach(UISize.allCases) { Text($0.label).tag($0) }
            }
            Picker("Font", selection: $store.appFont) {
                ForEach(AppFont.allCases) { Text($0.label).tag($0) }
            }
            Button("Larger  ⌘+") { store.stepSize(1) }
                .disabled(store.uiSize.larger == nil)
            Button("Smaller  ⌘−") { store.stepSize(-1) }
                .disabled(store.uiSize.smaller == nil)
            Divider()
            Toggle("Show Weather in the Dock", isOn: $store.dockShowsWeather)
            Toggle("Keep Window on Top", isOn: $store.floatOnTop)
            if compact {
                Button("Open as Window") {
                    closeHost()
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            Menu("Window Position") {
                ForEach(WindowPlacement.allCases) { placement in
                    Button(placement.label) {
                        WindowPlacement.request(.edge(placement))
                        openWindow(id: "main")   // opens it, or brings the open one forward
                        NSApp.activate(ignoringOtherApps: true)
                        if compact { closeHost() }
                    }
                }
            }
            Divider()
            Button("Settings…") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Terms & Privacy") { NSWorkspace.shared.open(Brand.legal) }
            Button("Check for Updates…") { Task { await updater.check(userInitiated: true) } }
                .disabled(updater.isBusy || !updater.canSelfUpdate)
            Divider()
            Button("Quit Two Degrees") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(ui.font(13, .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: ui.pt(32), height: ui.pt(32))
                .background(Circle().fill(Palette.raisedTile))
                .overlay(Circle().strokeBorder(Palette.borderStrong, lineWidth: 0.5))
                .overlay(alignment: .topTrailing) {
                    if updater.latest != nil {
                        Circle().fill(Palette.crimson).frame(width: ui.pt(8), height: ui.pt(8))
                    }
                }
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }
}
