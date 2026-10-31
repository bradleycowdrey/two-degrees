import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            CitiesSettings().tabItem { Label("Cities", systemImage: "mappin.and.ellipse") }
            AboutView().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 440)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var store: WeatherStore

    var body: some View {
        Form {
            Picker("Larger unit", selection: $store.unit) {
                Text("°F, with °C beside it").tag(TempUnit.fahrenheit)
                Text("°C, with °F beside it").tag(TempUnit.celsius)
            }
            Picker("Menu bar shows", selection: $store.menuBarStyle) {
                ForEach(MenuBarStyle.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Show the weather on the Dock icon", isOn: $store.dockShowsWeather)
            Picker("Size", selection: $store.uiSize) {
                ForEach(UISize.allCases) { Text($0.label).tag($0) }
            }
            Picker("Font", selection: $store.appFont) {
                ForEach(AppFont.allCases) { Text($0.label).tag($0) }
            }
            LocationSetting()
            Toggle("Keep window on top", isOn: $store.floatOnTop)
            Toggle("Open at login", isOn: Binding(get: { store.opensAtLogin }, set: { store.opensAtLogin = $0 }))
            UpdateSettings()
        }
        .formStyle(.grouped)
    }
}

private struct CitiesSettings: View {
    @EnvironmentObject private var store: WeatherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            List {
                ForEach($store.cities) { $city in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        TextField("Name", text: $city.name)
                            .textFieldStyle(.plain)
                            .font(.body.weight(.medium))
                        Spacer()
                        if let forecast = store.forecasts[city.id] {
                            let t = forecast.now.temperature
                            Text("\(TempUnit.fahrenheit.value(t))\(TempUnit.fahrenheit.symbol) · \(TempUnit.celsius.value(t))\(TempUnit.celsius.symbol)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            store.remove(city)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.cities.count < 2)
                        .help("Remove")
                    }
                    .padding(.vertical, 2)
                }
                .onMove { store.move(from: $0, to: $1) }
            }
            .listStyle(.bordered)
            Text("Drag to reorder. Click a name to rename it. Add cities with + Add city in the panel (up to \(WeatherStore.maxCities)).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

private struct UpdateSettings: View {
    @EnvironmentObject private var updater: Updater

    var body: some View {
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: $updater.automatic)
            LabeledContent("Version \(updater.currentVersion)") {
                Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                    .disabled(updater.isBusy || !updater.canSelfUpdate)
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var status: String {
        switch updater.phase {
        case .checking: return "Checking…"
        case .downloading: return "Downloading the update…"
        case .installing: return "Installing…"
        case .available: return "Two Degrees \(updater.latest?.version ?? "") is available."
        case .failed(let message): return message
        default:
            guard updater.canSelfUpdate else { return "Updates work in the installed app, not in a development build." }
            guard let date = updater.lastChecked else { return "Not checked yet." }
            return "Up to date. Last checked " + date.formatted(.relative(presentation: .named)) + "."
        }
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            AppMark(size: 72)
            Text(Brand.appName).font(.title.bold())
            Text(Brand.tagline).foregroundStyle(.secondary)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .font(.caption).foregroundStyle(.tertiary)
            Divider().frame(width: 200).padding(.vertical, 6)
            Text("Made by \(Brand.author)")
            HStack(spacing: 16) {
                Link(Brand.websiteHost, destination: Brand.website)
                Link("Source on GitHub", destination: Brand.repository)
                Link("Terms & Privacy", destination: Brand.legal)
            }
            Text("Free and open source (MIT). Weather data by Open-Meteo.com, city list by GeoNames.org (both CC BY 4.0).").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Use My Location, with a note when macOS isn't letting Two Degrees use it.
private struct LocationSetting: View {
    @EnvironmentObject private var store: WeatherStore

    var body: some View {
        Toggle(isOn: $store.useLocation) {
            Text("Use My Location")
            Text(note)
        }
        if store.useLocation && store.locationStatus == .denied {
            Button("Open Location Services Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
            }
        }
    }

    private var note: String {
        guard store.useLocation else { return "Show the weather where you are, first in your cities." }
        switch store.locationStatus {
        case .denied: return "Location Services are off for Two Degrees. Turn them on in System Settings."
        case .unavailable: return "Couldn’t find where you are just now. It tries again when your Mac wakes."
        case .locating: return "Finding where you are…"
        default:
            let here = store.cities.first(where: \.isCurrent)
            return here.map { "Showing \($0.name), first in your cities." } ?? "Show the weather where you are, first in your cities."
        }
    }
}
