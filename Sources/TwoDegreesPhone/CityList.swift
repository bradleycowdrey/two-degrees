import SwiftUI

/// Every saved city as a card on its own sky, like Apple Weather's list: search to add a city, tap a
/// card to open it, swipe to remove, Edit to reorder. The ⋯ menu holds the settings.
struct CityList: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.metrics) private var ui
    @State private var query = ""
    @State private var results: [City] = []
    @State private var searching = false
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ForEach(store.cities) { city in
                        Button {
                            store.select(city)
                            dismiss()
                        } label: {
                            CityCard(city: city)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: ui.pt(5), leading: ui.pt(16), bottom: ui.pt(5), trailing: ui.pt(16)))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .deleteDisabled(store.cities.count < 2)
                    }
                    .onDelete { offsets in
                        for city in offsets.map({ store.cities[$0] }) { store.remove(city) }
                    }
                    .onMove { store.move(from: $0, to: $1) }
                    footer
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    searchResults
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Two Degrees")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for a city")
            .autocorrectionDisabled()
            .task(id: query) { await search() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { menu }
                if editMode.isEditing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { withAnimation { editMode = .inactive } }.fontWeight(.semibold)
                    }
                }
            }
            .environment(\.editMode, $editMode)
        }
        .preferredColorScheme(.dark)
        .tint(.white)
    }

    @ViewBuilder
    private var searchResults: some View {
        if !store.canAdd {
            Text("You can keep up to \(WeatherStore.maxCities) cities. Swipe one away to add another.")
                .font(ui.font(15))
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        }
        if searching && results.isEmpty {
            HStack { ProgressView(); Text("Searching…").foregroundStyle(.secondary) }
                .listRowBackground(Color.clear)
        } else if results.isEmpty && query.trimmingCharacters(in: .whitespaces).count >= 2 {
            Text("No places match “\(query)”.")
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        }
        ForEach(results) { city in
            let saved = store.cities.contains { $0.id == city.id }
            Button {
                store.add(city)
                query = ""
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(city.name).font(ui.font(17, .semibold))
                        Text(city.region).font(ui.font(14)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if saved { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!saved && !store.canAdd)
            .listRowBackground(Color.clear)
        }
    }

    private var footer: some View {
        VStack(spacing: ui.pt(6)) {
            Text("The weather in °F and °C at once. Data: Open-Meteo.")
            Text("Made by \(Brand.author) · \(Brand.websiteHost)")
        }
        .font(ui.font(13))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, ui.pt(8))
    }

    private var menu: some View {
        Menu {
            Button { withAnimation { editMode = .active } } label: { Label("Edit List", systemImage: "pencil") }
                .disabled(store.cities.count < 2)
            Divider()
            Picker(selection: $store.unit) {
                Text("°F large, °C beside").tag(TempUnit.fahrenheit)
                Text("°C large, °F beside").tag(TempUnit.celsius)
            } label: { Label("Units", systemImage: "thermometer.medium") }
            Picker(selection: $store.uiSize) {
                ForEach(UISize.allCases) { Text($0.label).tag($0) }
            } label: { Label("Text Size", systemImage: "textformat.size") }
                .pickerStyle(.menu)
            Picker(selection: $store.appFont) {
                ForEach(AppFont.allCases) { Text($0.phoneLabel).tag($0) }
            } label: { Label("Font", systemImage: "textformat") }
                .pickerStyle(.menu)
            Divider()
            ShareLink(item: Brand.productPage, subject: Text("Two Degrees"), message: Text(Brand.phoneShareMessage)) {
                Label("Share Two Degrees", systemImage: "square.and.arrow.up")
            }
            Link(destination: Brand.macDownload) { Label("Get Two Degrees for Mac", systemImage: "laptopcomputer") }
            Link(destination: Brand.legal) { Label("Terms & Privacy", systemImage: "doc.text") }
            Link(destination: Brand.issues) { Label("Report an Issue", systemImage: "exclamationmark.bubble") }
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 19))
        }
        .accessibilityLabel("More")
    }

    /// Open-Meteo's geocoder, a moment after typing stops.
    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { results = []; return }
        searching = true
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let found = (try? await OpenMeteo.search(text)) ?? []
        guard !Task.isCancelled else { return }
        results = found
        searching = false
    }
}

/// One city in the list: name, local time and condition on the left; both temperatures and today's
/// range on the right; its own sky behind.
struct CityCard: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.metrics) private var ui
    let city: City

    var body: some View {
        let forecast = store.forecasts[city.id]
        let unit = store.unit, other = unit.other
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: ui.pt(2)) {
                Text(city.name).font(ui.font(22, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(forecast.map { Forecast.format($0.now.time, "jmm") } ?? city.region)
                    .font(ui.font(14, .medium)).opacity(0.85).lineLimit(1)
                Spacer(minLength: ui.pt(8))
                Text(forecast.map { Condition.name($0.now.code) } ?? (store.failed.contains(city.id) ? "Offline" : "Loading…"))
                    .font(ui.font(14, .medium)).opacity(0.85)
            }
            Spacer(minLength: ui.pt(8))
            VStack(alignment: .trailing, spacing: 0) {
                if let forecast {
                    let now = forecast.now
                    HStack(alignment: .top, spacing: ui.pt(4)) {
                        Text("\(unit.value(now.temperature))°").font(.system(size: ui.pt(46), weight: .light))
                    }
                    Text("\(other.value(now.temperature))\(other.symbol)").font(ui.font(15, .medium)).opacity(0.8)
                    Spacer(minLength: ui.pt(4))
                    if let today = forecast.days.first?.including(now.temperature) {
                        Text("H:\(unit.value(today.high))°  L:\(unit.value(today.low))°").font(ui.font(14, .medium)).opacity(0.9)
                    }
                } else {
                    Text("––°").font(.system(size: ui.pt(46), weight: .light)).opacity(0.5)
                    Spacer()
                }
            }
            .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(ui.pt(14))
        .frame(height: ui.pt(124))
        .background {
            if let forecast {
                SkyBackground(code: forecast.now.code, isDay: forecast.now.isDay)
            } else {
                Color(white: 0.15)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ui.pt(16), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ui.pt(16), style: .continuous)
                .strokeBorder(store.activeID == city.id ? Color.white.opacity(0.5) : .clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: ui.pt(16), style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
