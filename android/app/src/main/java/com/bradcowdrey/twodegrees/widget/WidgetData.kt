package com.bradcowdrey.twodegrees.widget

import android.content.Context
import androidx.core.content.edit
import com.bradcowdrey.twodegrees.City
import com.bradcowdrey.twodegrees.Codec
import com.bradcowdrey.twodegrees.Forecast
import com.bradcowdrey.twodegrees.OpenMeteo
import com.bradcowdrey.twodegrees.WeatherStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * Each widget's city: Two Degrees' current city (the default, like the iPhone's "Use Two Degrees'
 * Cities"), or one chosen for that widget. And what it shows: live numbers; else the last good ones,
 * marked offline; else a plain "couldn't load".
 */
object WidgetData {
    private fun prefs(context: Context) = context.getSharedPreferences("two-degrees.widgets", Context.MODE_PRIVATE)

    /** The widget's own city, or null to follow the app. */
    fun chosenCity(context: Context, appWidgetId: Int): City? =
        prefs(context).getString("city.$appWidgetId", null)?.let { runCatching { Codec.city(JSONObject(it)) }.getOrNull() }

    fun choose(context: Context, appWidgetId: Int, city: City?) = prefs(context).edit {
        if (city == null) remove("city.$appWidgetId") else putString("city.$appWidgetId", Codec.city(city).toString())
    }

    fun forget(context: Context, appWidgetIds: IntArray) = prefs(context).edit { appWidgetIds.forEach { remove("city.$it") } }

    suspend fun entry(context: Context, appWidgetId: Int): WidgetEntry {
        val store = WeatherStore.get(context)
        val state = store.current
        val city = chosenCity(context, appWidgetId) ?: state.active
        val saved = state.forecasts[city.id] ?: cached(context, city)
        if (saved != null && System.currentTimeMillis() - saved.fetchedAt < WeatherStore.REFRESH_INTERVAL_MS) {
            return WidgetEntry(city, saved, state.unit, offline = false)
        }
        val fresh = if (state.cities.any { it.id == city.id }) store.load(city)
        else withContext(Dispatchers.IO) { runCatching { OpenMeteo.forecast(city) }.getOrNull() }?.also { cache(context, city, it) }
        return WidgetEntry(city, fresh ?: saved, state.unit, offline = fresh == null)
    }

    private fun cached(context: Context, city: City): Forecast? =
        prefs(context).getString("forecast.${city.id}", null)?.let { runCatching { Codec.forecast(JSONObject(it)) }.getOrNull() }

    private fun cache(context: Context, city: City, forecast: Forecast) =
        prefs(context).edit { putString("forecast.${city.id}", Codec.forecast(forecast).toString()) }
}
