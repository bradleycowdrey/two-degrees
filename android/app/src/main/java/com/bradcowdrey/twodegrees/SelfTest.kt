package com.bradcowdrey.twodegrees

import android.content.Context
import com.bradcowdrey.twodegrees.widget.WidgetData
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File

/**
 * Runs in the emulator in CI (`--ez selftest true`) with live data: forecasts, units, city search
 * online and offline, adding and removing a city, and the widgets' data path. Writes files/report.txt,
 * first line "ALL PASSED (n passed)" or "FAILED (…)", as the Mac and iPhone self-tests do.
 */
object SelfTest {
    suspend fun run(context: Context, store: WeatherStore, locate: Boolean = false) {
        val lines = mutableListOf<String>()
        var failures = 0
        fun check(ok: Boolean, what: String) {
            lines += (if (ok) "PASS " else "FAIL ") + what
            if (!ok) failures++
        }

        // 1. Forecasts for the saved cities.
        store.refreshNow()
        val state = store.current
        val active = state.activeForecast
        check(active != null, "forecast loads for ${state.active.name}" + (active?.let { ": ${Condition.name(it.now.code)}, ${TempUnit.FAHRENHEIT.spaced(it.now.temperature)} / ${TempUnit.CELSIUS.spaced(it.now.temperature)}" } ?: ""))
        check(state.cities.all { it.id in state.forecasts }, "every saved city has a forecast (${state.forecasts.size} of ${state.cities.size})")
        active?.let {
            check(it.upcomingHours.size == 24, "24 hours ahead (${it.upcomingHours.size})")
            check(it.days.size >= 10, "10 days ahead (${it.days.size})")
            check(Codec.forecast(JSONObject(Codec.forecast(it).toString())) == it, "a forecast saves and reads back unchanged")
        }

        // 2. Units, both ways.
        val unit = state.unit
        store.toggleUnit()
        check(store.current.unit == unit.other, "switch to ${unit.other.label}")
        store.toggleUnit()
        check(store.current.unit == unit, "switch back to ${unit.label}")

        // Use My Location: where the emulator says you are (CI grants the permission and sets the place),
        // first in the list and shown; gone when turned off; back when turned on.
        if (locate) {
            check(!store.current.locationAsked, "a first launch asks whether to use your location")
            store.answerLocationPrompt(true)
            repeat(40) { if (store.current.cities.none { it.isCurrent }) delay(250) }
            val here = store.current.cities.firstOrNull()
            check(store.current.locationStatus == LocationStatus.FOUND && here?.isCurrent == true && store.current.activeID == here.id,
                "Use My Location finds ${if (here?.isCurrent == true) "${here.name}, ${here.region}" else "nothing (${store.current.locationStatus})"} and shows it first")
            repeat(40) { if (City.CURRENT_ID !in store.current.forecasts) delay(500) }
            check(City.CURRENT_ID in store.current.forecasts, "where you are: its forecast loads")
            store.setUseLocation(false)
            repeat(20) { if (store.current.cities.any { it.isCurrent }) delay(100) }
            check(store.current.cities.none { it.isCurrent }, "turning Use My Location off removes it")
            store.setUseLocation(true)
            repeat(40) { if (store.current.cities.none { it.isCurrent }) delay(250) }
            check(store.current.cities.firstOrNull()?.isCurrent == true, "turning it back on brings it back")
        }

        // 3. City search, online and offline.
        val found = withContext(Dispatchers.IO) { runCatching { OpenMeteo.search("Denver") }.getOrDefault(emptyList()) }
        check(found.isNotEmpty(), "city search finds Denver (${found.firstOrNull()?.region ?: "nothing"})")
        val offline = withContext(Dispatchers.IO) { OfflineCities.search("Denver") }
        check(OfflineCities.all.size > 20000 && offline.firstOrNull()?.name == "Denver",
            "offline city search: ${OfflineCities.all.size} cities bundled, finds Denver (${offline.firstOrNull()?.region ?: "nothing"})")

        // 4. Add and remove a city.
        found.firstOrNull()?.let { denver ->
            val before = store.current.cities.size
            store.add(denver)
            check(store.current.cities.size == before + 1 && store.current.activeID == denver.id, "add Denver and select it")
            repeat(40) { if (denver.id !in store.current.forecasts) delay(500) }
            check(denver.id in store.current.forecasts, "Denver's forecast loads")
            delay(3000)   // a moment on screen for the screenshot
            store.remove(denver)
            check(store.current.cities.size == before && store.current.cities.none { it.id == denver.id }, "remove Denver")
            store.select(store.current.cities[0])
        }
        // Back to where you are, if it's on, for the screenshots.
        store.current.cities.firstOrNull { it.isCurrent }?.let { store.select(it) }

        // 5. The widgets' data path: following the app, and a city of its own.
        val following = WidgetData.entry(context, 9001)
        check(following.city.id == store.current.activeID && following.forecast != null, "widget following the app shows ${following.city.name}")
        val paris = City("Paris", "Île-de-France, France", 48.8534, 2.3488)
        WidgetData.choose(context, 9002, paris)
        val own = WidgetData.entry(context, 9002)
        check(own.city == paris && own.forecast != null && !own.offline, "widget with its own city shows Paris")
        WidgetData.forget(context, intArrayOf(9001, 9002))

        store.termsAccepted = true   // so the later screenshots (the city list) open without the terms
        val header = if (failures == 0) "ALL PASSED (${lines.size} passed)" else "FAILED ($failures of ${lines.size} failed)"
        File(context.filesDir, "report.txt").writeText((listOf(header) + lines).joinToString("\n") + "\n")
    }
}
