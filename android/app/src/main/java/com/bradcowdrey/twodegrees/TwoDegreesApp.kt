package com.bradcowdrey.twodegrees

import android.app.Application
import com.bradcowdrey.twodegrees.widget.WidgetUpdates

class TwoDegreesApp : Application() {
    override fun onCreate() {
        super.onCreate()
        OfflineCities.source = { runCatching { assets.open("Cities.tsv").bufferedReader().use { it.readText() } }.getOrNull() }
        val store = WeatherStore.get(this)
        store.onCitiesChanged = { WidgetUpdates.redraw(this) }
        WidgetUpdates.schedule(this)
    }
}
