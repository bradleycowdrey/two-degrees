package com.bradcowdrey.twodegrees

import android.content.Context
import com.bradcowdrey.twodegrees.widget.WidgetData
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File

/**
 * Runs in the emulator in CI (`--ez selftest true`) with live data: forecasts (and 0.5's air quality,
 * normals, alerts, 15-minute rain and newer tiles), units, city search
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

        // 1b. 0.5's additions, live: the newer tiles' data, 15-minute rain, air quality, normals, alerts, the moon.
        active?.let { f ->
            val today = f.days.firstOrNull()
            check(f.now.visibility != null && f.now.cloudCover != null && today?.precipitationSum != null,
                "new tiles' data: visibility ${f.now.visibility?.let { Units(TempUnit.CELSIUS).visibility(it) }}, " +
                    "cloud cover ${f.now.cloudCover?.roundHalfUp()}%, today's precipitation ${today?.precipitationSum?.let { RainUnit.MM.text(it) }}")
            check(f.steps.size == 8, "15-minute precipitation decoded (${f.steps.size} steps from ${f.steps.firstOrNull()?.time?.toLocalTime()})")
        }
        val ny = store.current.cities.firstOrNull { it.name == "New York" } ?: WeatherStore.STARTER_CITIES[0]
        val air = store.current.air[ny.id] ?: withContext(Dispatchers.IO) { Extras.air(ny) }
        val aqi = air?.let { Air.value(it, Air.scale(ny)) }
        check(Air.scale(ny) == Air.Scale.US && aqi != null,
            "air quality for New York: ${aqi?.let { "US AQI ${it.roundHalfUp()}, ${Air.category(it, Air.Scale.US)}" } ?: "none"}" + (air?.let { Air.note(it, Air.Scale.US)?.let { n -> " ($n)" } } ?: ""))
        var normalsError: String? = null
        // Open-Meteo's free archive answers "429 too many requests" when CI runners share its limit; try
        // again, and if it still refuses or times out, note it rather than fail (it's the service's limit, not the app).
        var normals = store.current.normals(ny)
        for (attempt in 0 until 3) {
            if (normals != null) break
            if (attempt > 0) delay(20_000)
            normals = withContext(Dispatchers.IO) {
                runCatching { Normals.fetch(ny) }.onFailure { normalsError = it.message }.getOrNull()
            }
        }
        val nyToday = store.current.forecasts[ny.id]?.now?.time?.toLocalDate() ?: java.time.LocalDate.now()
        val entry = normals?.of(nyToday)
        val rateLimited = normals == null && normalsError.let { it != null && ("429" in it || "timed out" in it.lowercase()) }
        check(entry?.normalHigh != null || rateLimited,
            "normals and records for New York: " + (entry?.let { e ->
                "${Normals.normalLine(e, TempUnit.FAHRENHEIT)}; ${Normals.recordsLine(e, TempUnit.FAHRENHEIT)}".replace(' ', ' ')
            } ?: if (rateLimited) "skipped: the archive service is limiting or not answering this runner ($normalsError)" else "none (${normalsError ?: "no table"})"))
        val alerts = withContext(Dispatchers.IO) { runCatching { Alerts.fetch(ny) } }
        check(alerts.isSuccess, "NWS alerts for New York: " +
            (alerts.getOrNull()?.let { list -> "${list.size} active" + (list.firstOrNull()?.let { " (${it.event})" } ?: "") } ?: "failed (${alerts.exceptionOrNull()?.message})"))
        val moon = Moon.phase(java.time.Instant.now())
        check(moon.name in Moon.NAMES, "moon tonight: ${moon.text}")

        // 2. Units, both ways.
        val unit = state.unit
        store.toggleUnit()
        check(store.current.unit == unit.other, "switch to ${unit.other.label}")
        store.toggleUnit()
        check(store.current.unit == unit, "switch back to ${unit.label}")
        val wind = store.current.windUnit
        store.setWindUnit(WindUnit.MPH)
        val mph = store.current.units.wind(50.0).first
        store.setWindUnit(WindUnit.KMH)
        val kmh = store.current.units.wind(50.0).first
        store.setWindUnit(wind)
        check(mph == "31 mph" && kmh == "50 km/h", "wind units switch: $mph ↔ $kmh")

        // The city limit: twenty of your own; where you are doesn't count.
        val many = (1..WeatherStore.MAX_CITIES).map { City("City $it", "", it.toDouble(), it.toDouble()) }
        val full = store.current.copy(cities = many + City("Here", "", 0.5, 0.5, isCurrent = true))
        check(WeatherStore.MAX_CITIES == 20 && !full.canAdd && full.copy(cities = many.drop(1)).canAdd, "the city limit is ${WeatherStore.MAX_CITIES}")

        // Use My Location: where the emulator says you are (CI grants the permission and sets the place),
        // first in the list and shown; gone when turned off; back when turned on.
        if (locate) {
            check(!store.current.locationAsked, "a first launch asks whether to use your location")
            store.answerLocationPrompt(true)
            // The page appears a moment before the status reads FOUND: wait for both.
            repeat(80) { if (store.current.locationStatus != LocationStatus.FOUND) delay(250) }
            val here = store.current.cities.firstOrNull()
            check(store.current.locationStatus == LocationStatus.FOUND && here?.isCurrent == true && store.current.activeID == here.id,
                "Use My Location finds ${if (here?.isCurrent == true) "${here.name}, ${here.region}" else "nothing (${store.current.locationStatus})"} and shows it first")
            repeat(40) { if (City.CURRENT_ID !in store.current.forecasts) delay(500) }
            check(City.CURRENT_ID in store.current.forecasts, "where you are: its forecast loads")
            // Its extras follow the forecast: air quality soon, the normals table (a big request) a little later.
            val waitStart = System.currentTimeMillis()
            var airAfter = -1L
            repeat(60) {
                if (airAfter < 0 && City.CURRENT_ID in store.current.air) airAfter = System.currentTimeMillis() - waitStart
                if (City.CURRENT_ID !in store.current.air || store.current.cities.firstOrNull()?.let { store.current.normals(it) } == null) delay(500)
            }
            val hereAir = store.current.air[City.CURRENT_ID]
            check(hereAir != null, "where you are: air quality loads (${hereAir?.usAqi?.roundHalfUp()?.let { "US AQI $it" } ?: "none"}, after ${airAfter} ms)")
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
            // The emulator is in Denver: with Use My Location on, Denver becomes My Location instead of a second card.
            val merged = store.current.hereID == denver.id
            check((store.current.cities.size == before + 1 || merged) && store.current.activeID == denver.id, "add Denver and select it")
            if (locate) check(merged && store.current.cities.none { it.isCurrent },
                "adding the city you're in makes it My Location, with no second card")
            repeat(40) { if (denver.id !in store.current.forecasts) delay(500) }
            check(denver.id in store.current.forecasts, "Denver's forecast loads")
            delay(3000)   // a moment on screen for the screenshot
            store.remove(denver)
            check(store.current.cities.size == before && store.current.cities.none { it.id == denver.id }, "remove Denver")
            if (locate) check(store.current.cities.firstOrNull()?.isCurrent == true, "removing it brings back My Location as its own card")
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
