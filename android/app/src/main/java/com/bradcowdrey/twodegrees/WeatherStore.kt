package com.bradcowdrey.twodegrees

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The five text sizes, as on the Mac and iPhone. */
enum class TextSize(val label: String, val scale: Float) {
    SMALLEST("Smallest", 0.85f), SMALL("Small", 0.92f), MEDIUM("Medium", 1f), LARGE("Large", 1.1f), LARGEST("Largest", 1.2f)
}

enum class AppFont(val label: String) { INTER("Inter"), SYSTEM("System") }

/**
 * Saved cities, settings and forecasts, for the app and its widgets (one per process). Saved in
 * preferences with the same keys and limits as the iPhone app.
 */
class WeatherStore private constructor(context: Context) {
    data class State(
        val cities: List<City>,
        val activeID: String,
        val unit: TempUnit,
        val textSize: TextSize,
        val font: AppFont,
        /** Use My Location: keep a page for where you are, first in the list. On unless turned off. */
        val useLocation: Boolean = true,
        /** Whether "Show the weather where you are?" has been asked (after the terms, once). */
        val locationAsked: Boolean = false,
        val locationStatus: LocationStatus = LocationStatus.IDLE,
        val forecasts: Map<String, Forecast> = emptyMap(),
        val failed: Set<String> = emptySet(),
        val loading: Boolean = false,
        /** The saved city that's where you are, standing in for a separate My Location card. */
        val hereID: String? = null,
        val windUnit: WindUnit = WindUnit.AUTO,
        val rainUnit: RainUnit = RainUnit.AUTO,
        /** Notifications, both off until turned on. */
        val notifySevere: Boolean = false,
        val notifyRain: Boolean = false,
        /** By city ID: air quality, and active alerts (US only); by place (normalsKey): normals and records. */
        val air: Map<String, AirQuality> = emptyMap(),
        val alerts: Map<String, List<Alert>> = emptyMap(),
        val normals: Map<String, Normals> = emptyMap(),
    ) {
        /** Where you are: the separate My Location card, or the saved city standing in for it. */
        fun isHere(city: City): Boolean = city.isCurrent || (hereID != null && city.id == hereID)

        val active: City get() = cities.firstOrNull { it.id == activeID } ?: cities[0]
        val activeForecast: Forecast? get() = forecasts[active.id]
        /** Up to twenty cities of your own; where you are doesn't count. */
        val canAdd: Boolean get() = cities.count { !it.isCurrent } < MAX_CITIES

        val units: Units get() = Units(unit, windUnit, rainUnit)

        fun normals(city: City): Normals? = normals[normalsKey(city)]

        /** Notifications are for where you are, or the first city when Use My Location is off. */
        val notifyCity: City get() = cities.firstOrNull { isHere(it) } ?: cities[0]
    }

    private val app = context.applicationContext
    private val prefs: SharedPreferences = app.getSharedPreferences("two-degrees", Context.MODE_PRIVATE)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val _state: MutableStateFlow<State>
    val state: StateFlow<State> get() = _state.asStateFlow()
    val current: State get() = _state.value

    /** Finds where you are. Set by the activity once the terms are agreed; never in unit tests. */
    @Volatile var locate: (suspend () -> LocationResult)? = null

    /** Called when the cities or the current city change, so the widgets redraw. */
    @Volatile var onCitiesChanged: () -> Unit = {}

    init {
        val cities = Codec.cities(prefs.getString("cities", null))?.takeIf { it.isNotEmpty() } ?: STARTER_CITIES
        val activeID = prefs.getString("activeID", null)?.takeIf { id -> cities.any { it.id == id } } ?: cities[0].id
        _state = MutableStateFlow(State(
            cities = cities,
            activeID = activeID,
            unit = prefs.getString("unit", null)?.let { runCatching { TempUnit.valueOf(it) }.getOrNull() } ?: TempUnit.localeDefault(),
            textSize = prefs.getString("textSize", null)?.let { runCatching { TextSize.valueOf(it) }.getOrNull() } ?: TextSize.MEDIUM,
            font = prefs.getString("font", null)?.let { runCatching { AppFont.valueOf(it) }.getOrNull() } ?: AppFont.INTER,
            useLocation = prefs.getBoolean("useLocation", true),
            hereID = prefs.getString("hereID", null)?.takeIf { id -> cities.any { it.id == id } },
            locationAsked = prefs.getBoolean("locationAsked", false),
            forecasts = Codec.forecasts(prefs.getString("forecasts", null)),
            windUnit = WindUnit.of(prefs.getString("windUnit", null)),
            rainUnit = RainUnit.of(prefs.getString("rainUnit", null)),
            notifySevere = prefs.getBoolean("notifySevere", false),
            notifyRain = prefs.getBoolean("notifyRain", false),
        ))
        // The normals tables (one per place, cached 30 days) load off the main thread.
        scope.launch {
            val saved = withContext(Dispatchers.IO) {
                normalsPrefs.all.mapNotNull { (k, v) -> Normals.decode(v as? String)?.let { k to it } }.toMap()
            }
            _state.update { it.copy(normals = saved + it.normals) }
        }
    }

    private val normalsPrefs: SharedPreferences get() = app.getSharedPreferences("two-degrees.normals", Context.MODE_PRIVATE)

    // Cities

    fun add(city: City) {
        val s = current
        val existing = s.cities.firstOrNull { it.id == city.id }
        when {
            existing != null -> { setActive(existing.id); if (s.forecasts[existing.id] == null) launchLoad(existing) }
            s.canAdd -> {
                saveCities(s.cities + city, city.id)
                launchLoad(city)
                // Added the place you're in: it becomes My Location, with no second card.
                val place = lastPlace
                if (current.useLocation && place != null && City.samePlace(city, place)) placeCurrent(place)
            }
        }
    }

    /** The last place Use My Location found, kept so a card for it can come back without a new fix. */
    private var lastPlace: City?
        get() = prefs.getString("herePlace", null)?.let { runCatching { Codec.city(org.json.JSONObject(it)) }.getOrNull() }
        set(value) { prefs.edit().putString("herePlace", value?.let { Codec.city(it).toString() }).apply() }

    private fun setHereID(id: String?) {
        _state.update { it.copy(hereID = id) }
        prefs.edit().putString("hereID", id).apply()
        onCitiesChanged()
    }

    fun remove(city: City) {
        // Removing where you are turns Use My Location off; otherwise it would come straight back.
        if (city.isCurrent) { setUseLocation(false); return }
        val s = current
        if (s.cities.size < 2) return
        val cities = s.cities.filter { it.id != city.id }
        _state.update { it.copy(forecasts = it.forecasts - city.id, failed = it.failed - city.id) }
        saveForecasts()
        saveCities(cities, if (s.activeID == city.id) cities[0].id else s.activeID)
        // It stood in for My Location: bring back the separate card for where you are.
        if (city.id == s.hereID) {
            setHereID(null)
            val place = lastPlace
            if (current.useLocation && place != null) placeCurrent(place)
        }
    }

    fun move(from: Int, to: Int) {
        val list = current.cities.toMutableList()
        if (from !in list.indices || to !in list.indices) return
        list.add(to, list.removeAt(from))
        saveCities(list, current.activeID)
    }

    fun select(city: City) {
        setActive(city.id)
        if (isStale(city)) launchLoad(city)
    }

    private fun setActive(id: String) = saveCities(current.cities, id)

    private fun saveCities(cities: List<City>, activeID: String) {
        val changed = cities != current.cities || activeID != current.activeID
        _state.update { it.copy(cities = cities, activeID = activeID) }
        prefs.edit().putString("cities", Codec.cities(cities)).putString("activeID", activeID).apply()
        if (changed) onCitiesChanged()
    }

    // Settings

    fun setUnit(unit: TempUnit) {
        _state.update { it.copy(unit = unit) }
        prefs.edit().putString("unit", unit.name).apply()
        onCitiesChanged()
    }

    fun toggleUnit() = setUnit(current.unit.other)

    fun setWindUnit(unit: WindUnit) {
        _state.update { it.copy(windUnit = unit) }
        prefs.edit().putString("windUnit", unit.key).apply()
    }

    fun setRainUnit(unit: RainUnit) {
        _state.update { it.copy(rainUnit = unit) }
        prefs.edit().putString("rainUnit", unit.key).apply()
    }

    fun setNotifySevere(on: Boolean) {
        _state.update { it.copy(notifySevere = on) }
        prefs.edit().putBoolean("notifySevere", on).apply()
    }

    fun setNotifyRain(on: Boolean) {
        _state.update { it.copy(notifyRain = on) }
        prefs.edit().putBoolean("notifyRain", on).apply()
    }

    fun setTextSize(size: TextSize) {
        _state.update { it.copy(textSize = size) }
        prefs.edit().putString("textSize", size.name).apply()
    }

    fun setFont(font: AppFont) {
        _state.update { it.copy(font = font) }
        prefs.edit().putString("font", font.name).apply()
    }

    // Use My Location

    /**
     * The answer to "Show the weather where you are?": Use My Location (recommended) turns it on, Not
     * Now turns it off. Either way it's never asked again; the setting stays in the ⋮ menu.
     */
    fun answerLocationPrompt(yes: Boolean) = setUseLocation(yes)

    fun setUseLocation(on: Boolean) {
        // Choosing it in the menu answers the question too.
        _state.update { it.copy(useLocation = on, locationAsked = true) }
        prefs.edit().putBoolean("useLocation", on).putBoolean("locationAsked", true).apply()
        scope.launch { updateLocation() }
    }

    /**
     * Finds where you are and keeps its page up to date (first in the list), or removes it when Use My
     * Location is off. The first time, it also shows that page.
     */
    suspend fun updateLocation() {
        if (!current.useLocation) {
            removeCurrent()
            _state.update { it.copy(locationStatus = LocationStatus.OFF) }
            return
        }
        if (!current.locationAsked) return   // not before the question
        val locate = locate ?: return
        if (current.locationStatus == LocationStatus.LOCATING) return
        _state.update { it.copy(locationStatus = LocationStatus.LOCATING) }
        val result = locate()
        if (!current.useLocation) { _state.update { it.copy(locationStatus = LocationStatus.OFF) }; return }
        val status = when (result) {
            is LocationResult.Found -> { placeCurrent(result.city); LocationStatus.FOUND }
            LocationResult.Denied -> LocationStatus.DENIED
            LocationResult.Unavailable -> LocationStatus.UNAVAILABLE
        }
        _state.update { it.copy(locationStatus = status) }
    }

    fun locateNow() { scope.launch { updateLocation() } }

    /** Puts where you are first in the list (or updates it in place), and loads its weather. */
    fun placeCurrent(place: City) {
        val here = place.copy(isCurrent = true)
        lastPlace = here
        val s = current
        // A saved city is the same place: it becomes My Location, and there's no second card.
        val match = s.cities.firstOrNull { !it.isCurrent && City.samePlace(it, here) }
        if (match != null) {
            val firstTime = s.hereID == null && s.cities.none { it.isCurrent }
            val showing = s.activeID == City.CURRENT_ID
            if (s.cities.any { it.isCurrent }) {
                _state.update { it.copy(forecasts = it.forecasts - City.CURRENT_ID, failed = it.failed - City.CURRENT_ID) }
                saveCities(s.cities.filter { !it.isCurrent }, if (firstTime || showing) match.id else s.activeID)
            } else if (firstTime) {
                setActive(match.id)
            }
            setHereID(match.id)
            return
        }
        if (s.hereID != null) setHereID(null)
        val i = s.cities.indexOfFirst { it.isCurrent }
        if (i >= 0) {
            val old = s.cities[i]
            if (old == here) return
            if (old.latitude != here.latitude || old.longitude != here.longitude) {
                _state.update { it.copy(forecasts = it.forecasts - here.id, failed = it.failed - here.id) }
            }
            saveCities(s.cities.toMutableList().also { it[i] = here }, s.activeID)
        } else {
            saveCities(listOf(here) + s.cities, here.id)
        }
        if (here.id !in current.forecasts) launchLoad(here)
    }

    private fun removeCurrent() {
        if (current.hereID != null) setHereID(null)
        lastPlace = null
        val s = current
        val i = s.cities.indexOfFirst { it.isCurrent }
        if (i < 0) return
        if (s.cities.size == 1) {
            // Never leave the list empty: keep it as an ordinary city.
            val city = s.cities[0].copy(isCurrent = false)
            saveCities(listOf(city), city.id)
            return
        }
        val cities = s.cities.filterIndexed { j, _ -> j != i }
        _state.update { it.copy(forecasts = it.forecasts - City.CURRENT_ID, failed = it.failed - City.CURRENT_ID) }
        saveForecasts()
        saveCities(cities, if (s.activeID == City.CURRENT_ID) cities[0].id else s.activeID)
    }

    // Forecasts

    fun refresh() { scope.launch { refreshNow() } }

    suspend fun refreshNow() {
        _state.update { it.copy(loading = true) }
        current.cities.map { city -> scope.async { load(city)?.let { loadExtras(city) } } }.awaitAll()
        _state.update { it.copy(loading = false) }
    }

    fun refreshIfDue() {
        if (current.cities.any(::isStale)) { refresh(); return }
        // Air quality and alerts aren't saved: a fresh start with saved forecasts still fetches them, once.
        current.cities.filter { it.id !in extrasLoaded }.forEach { city -> scope.launch { loadExtras(city) } }
    }

    private fun isStale(city: City): Boolean {
        val f = current.forecasts[city.id] ?: return true
        return System.currentTimeMillis() - f.fetchedAt > REFRESH_INTERVAL_MS
    }

    private fun launchLoad(city: City) { scope.launch { load(city)?.let { loadExtras(city) } } }

    /** Cities whose extras this process has asked for. */
    private val extrasLoaded: MutableSet<String> = java.util.Collections.synchronizedSet(mutableSetOf())

    /** One big archive request at a time. */
    private val normalsLock = Mutex()

    /**
     * With the forecast: air quality and (in the US) alerts, and the normals table when it's missing or
     * a month old. A failure hides air quality, keeps the last alerts that haven't expired, and never
     * touches the forecast.
     */
    suspend fun loadExtras(city: City) = coroutineScope {
        extrasLoaded += city.id
        fun kept() = current.cities.any { it.id == city.id }
        // Each one shows as soon as it arrives: the NWS can be slow, and shouldn't hold up air quality.
        launch {
            val a = withContext(Dispatchers.IO) { Extras.air(city) }
            if (kept()) _state.update { s -> s.copy(air = if (a != null) s.air + (city.id to a) else s.air - city.id) }
        }
        val alerts = async(Dispatchers.IO) { Extras.alerts(city) }
        val key = normalsKey(city)
        val normals = async {
            normalsLock.withLock {
                if (current.normals[key]?.isStale == false) return@withLock null
                withContext(Dispatchers.IO) { Extras.normals(city) }
            }
        }
        val list = alerts.await()
        if (kept()) {
            val now = java.time.Instant.now()
            _state.update { s ->
                s.copy(alerts = s.alerts + (city.id to (list ?: s.alerts[city.id].orEmpty()).filter { it.expires == null || it.expires.toInstant().isAfter(now) }))
            }
        }
        normals.await()?.let { n ->
            _state.update { it.copy(normals = it.normals + (key to n)) }
            withContext(Dispatchers.IO) { normalsPrefs.edit().putString(key, Normals.encode(n)).commit() }
        }
        list != null
    }

    /** Fetches one city's forecast; on failure, keeps the last one and marks the city offline. */
    suspend fun load(city: City): Forecast? {
        val result = withContext(Dispatchers.IO) { runCatching { OpenMeteo.forecast(city) } }
        val forecast = result.getOrNull()
        // The city may have been removed while its forecast loaded: don't keep (or save) it.
        if (current.cities.none { it.id == city.id }) return forecast
        if (forecast != null) {
            _state.update { it.copy(forecasts = it.forecasts + (city.id to forecast), failed = it.failed - city.id) }
            saveForecasts()
        } else {
            _state.update { it.copy(failed = it.failed + city.id) }
        }
        if (city.id == current.activeID) onCitiesChanged()
        return forecast
    }

    private fun saveForecasts() {
        prefs.edit().putString("forecasts", Codec.forecasts(current.forecasts)).apply()
    }

    // Terms

    /** True when there's no need to ask (agreed to these terms, or to earlier ones within the month). */
    var termsAccepted: Boolean
        get() = !TermsSchedule.shouldAsk(prefs.getString(TERMS_KEY, null), prefs.getLong("terms.acceptedAt", 0), Brand.TERMS_VERSION)
        set(value) {
            if (value) prefs.edit().putString(TERMS_KEY, Brand.TERMS_VERSION).putLong("terms.acceptedAt", System.currentTimeMillis()).apply()
            else prefs.edit().remove(TERMS_KEY).remove("terms.acceptedAt").apply()
        }

    /** A one-line reading for the current city, both units, to share. */
    fun readingText(): String? {
        val s = current
        val f = s.activeForecast ?: return null
        val t = f.now.temperature
        return "${s.active.name}: ${TempUnit.FAHRENHEIT.value(t)}°F / ${TempUnit.CELSIUS.value(t)}°C, " +
            "${Condition.name(f.now.code).lowercase()}. Via Two Degrees."
    }

    companion object {
        const val MAX_CITIES = 20
        const val REFRESH_INTERVAL_MS = 15 * 60 * 1000L
        private const val TERMS_KEY = "terms.accepted"

        val STARTER_CITIES = listOf(
            City("New York", "New York, United States", 40.7128, -74.006),
            City("London", "England, United Kingdom", 51.5072, -0.1276),
            City("Tokyo", "Japan", 35.6762, 139.6503),
        )

        @Volatile private var instance: WeatherStore? = null

        fun get(context: Context): WeatherStore = instance ?: synchronized(this) {
            instance ?: WeatherStore(context).also { instance = it }
        }
    }
}

/** Single source of truth for branding, as on the Mac and iPhone. */
object Brand {
    const val APP_NAME = "Two Degrees"
    const val AUTHOR = "Bradley Cowdrey"
    const val WEBSITE = "https://bradcowdrey.com"
    const val LEGAL = "https://bradcowdrey.com/legal"
    const val TERMS_VERSION = "2026-11-01"
    const val PRODUCT_PAGE = "https://bradcowdrey.com/two-degrees"
    const val ISSUES = "https://github.com/bradleycowdrey/two-degrees/issues"
    const val DATA_CREDIT = "https://open-meteo.com/"
    const val SHARE_MESSAGE = "Two Degrees: the weather in °F and °C at once, on your Android phone and its Home Screen. Free and open source, by Bradley Cowdrey."
    const val TERMS_SUMMARY = "Two Degrees is free and provided as is, without warranty. It is not a safety tool: for severe weather, follow official warnings. Your cities stay on your phone; only their locations go to Open-Meteo to get the weather. If you allow it, your location is used only to show the weather where you are."
}
