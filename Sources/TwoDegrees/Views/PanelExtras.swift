import AppKit
import SwiftUI

// The Mac panel's own ways into a day and the rain map. The cards and tiles themselves are shared with
// the iPhone (CityCards.swift, Tiles.swift, DayCharts.swift).

/// A day in full, in a popover from the day's row: the date, then the same charts and facts as the
/// iPhone's day sheet.
struct DayDetailPopover: View {
    @Environment(\.metrics) private var ui
    let city: City
    let forecast: Forecast
    let day: Forecast.Day
    let isToday: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(Forecast.format(day.date, "EEEEMMMd"))
                    .font(ui.font(17, .semibold))
                    .foregroundStyle(.white)
                DayDetailContent(forecast: forecast, day: day, isToday: isToday, city: city)
            }
            .padding(ui.l)
        }
        .frame(width: ui.pt(420))
        .frame(maxHeight: ui.pt(640))
        .background(Palette.bg)
    }
}

enum RainMap {
    /// Opens the shared rain map page at a city in the browser.
    static func open(_ city: City, unit: TempUnit) {
        let url = String(format: "https://bradleycowdrey.github.io/two-degrees/radar.html?lat=%.2f&lon=%.2f&z=7&units=%@", city.latitude, city.longitude, unit.rawValue)
        NSWorkspace.shared.open(URL(string: url)!)
    }
}
