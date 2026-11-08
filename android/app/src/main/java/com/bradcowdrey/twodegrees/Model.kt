package com.bradcowdrey.twodegrees

import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.ln
import kotlin.math.roundToInt

/**
 * A saved place. Coordinates are what Open-Meteo needs; the name is what people see. `isCurrent` marks
 * where you are (Use My Location), kept up to date by the app.
 */
data class City(
    val name: String,
    val region: String,
    val latitude: Double,
    val longitude: Double,
    val isCurrent: Boolean = false,
) {
    /** Where you are has one ID wherever you go, so its page, forecast and widgets stay put. */
    val id: String get() = if (isCurrent) CURRENT_ID else String.format(Locale.US, "%.2f,%.2f", latitude, longitude)

    companion object {
        const val CURRENT_ID = "here"

        /**
         * Whether two cities are the same place: the same name within 25 km, or anything within 2 km.
         * Where you are and a saved city that's the same place share one card.
         */
        fun samePlace(a: City, b: City): Boolean {
            val k = Math.cos(Math.toRadians(a.latitude))
            var dx = Math.abs(a.longitude - b.longitude)
            if (dx > 180) dx = 360 - dx
            val dy = a.latitude - b.latitude
            val km = Math.sqrt(dy * dy + (dx * k) * (dx * k)) * 111
            return km <= 2 || (km <= 25 && OfflineCities.fold(a.name) == OfflineCities.fold(b.name))
        }
    }
}

/**
 * Tapping a widget opens the app on that widget's city. The city rides in the launch intent as JSON
 * (extra [KEY]); which page it opens follows the same rule as on the Mac and iPhone.
 */
object WidgetTap {
    const val KEY = "widgetCity"

    fun encode(city: City): String = Codec.city(city).toString()

    /** The city, or null for anything missing or malformed. */
    fun decode(text: String?): City? {
        val city = text?.let { runCatching { Codec.city(org.json.JSONObject(it)) }.getOrNull() } ?: return null
        val ok = city.name.isNotBlank() && city.latitude in -90.0..90.0 && city.longitude in -180.0..180.0
        return city.takeIf { ok }
    }

    sealed interface Target {
        data class Select(val id: String) : Target
        data class Add(val city: City) : Target
        /** The list is full: nothing changes. */
        data object Stay : Target
    }

    /**
     * Where a tap goes: My Location's card (or the saved city standing in for it; the first city when
     * Use My Location is off); else the saved city that's the same place; else the city, added if
     * there's room; else nowhere new.
     */
    fun target(city: City, cities: List<City>, hereID: String?, canAdd: Boolean): Target {
        if (city.isCurrent) {
            val here = cities.firstOrNull { it.isCurrent } ?: cities.firstOrNull { it.id == hereID } ?: cities.firstOrNull()
            return here?.let { Target.Select(it.id) } ?: Target.Stay
        }
        val saved = cities.firstOrNull { !it.isCurrent && (it.id == city.id || City.samePlace(it, city)) }
        return when {
            saved != null -> Target.Select(saved.id)
            canAdd -> Target.Add(city)
            else -> Target.Stay
        }
    }
}

enum class TempUnit(val letter: String) {
    FAHRENHEIT("F"), CELSIUS("C");

    /** A reading's unit: hair spaces either side of the degree sign, as on the Mac and iPhone. */
    val symbol: String get() = " ° $letter"

    /** "°F" with no spacing: for controls, menus and copied text. */
    val label: String get() = "°$letter"

    val other: TempUnit get() = if (this == FAHRENHEIT) CELSIUS else FAHRENHEIT

    /** Whole degrees in this unit, from Celsius. */
    fun value(celsius: Double): Int =
        (if (this == FAHRENHEIT) celsius * 9 / 5 + 32 else celsius).roundHalfUp()

    /** A reading with its unit ("18 °C"). */
    fun spaced(celsius: Double): String = "${value(celsius)}$symbol"

    companion object {
        /** °F where people measure in Fahrenheit (the US and a few others), otherwise °C. */
        fun localeDefault(locale: Locale = Locale.getDefault()): TempUnit =
            if (locale.country in setOf("US", "LR", "MM", "BS", "BZ", "KY", "PW", "FM", "MH")) FAHRENHEIT else CELSIUS
    }
}

/** Rounds .5 away from zero, as Swift's `rounded()` does, so every app shows the same number. */
fun Double.roundHalfUp(): Int = if (this >= 0) (this + 0.5).toInt() else -((-this + 0.5).toInt())

/**
 * One city's forecast, in Celsius, km/h, mm, hPa and metres, with times as the city's own wall-clock.
 * Everything added in 0.5 is optional: a missing value hides its tile, never the forecast.
 */
data class Forecast(
    val now: Now,
    val hours: List<Hour>,
    val days: List<Day>,
    val timeZone: String,
    val fetchedAt: Long,
    /** The next two hours' precipitation, in 15-minute steps from the current one. */
    val steps: List<Step> = emptyList(),
) {
    data class Now(
        val time: LocalDateTime,
        val temperature: Double,
        val feelsLike: Double,
        val humidity: Double,
        val wind: Double,
        val code: Int,
        val isDay: Boolean,
        /** Degrees the wind comes from (0 = north). */
        val windDirection: Double?,
        val pressure: Double? = null,
        val cloudCover: Double? = null,
        val gusts: Double? = null,
        val visibility: Double? = null,
        val precipitation: Double? = null,
    )

    data class Hour(
        val time: LocalDateTime,
        val temperature: Double,
        val code: Int,
        val rainChance: Int,
        val isDay: Boolean,
        val precipitation: Double? = null,
        val wind: Double? = null,
        val gusts: Double? = null,
        val pressure: Double? = null,
        val visibility: Double? = null,
        /** Low (up to ~2 km), mid (~2–6 km) and high (above ~6 km) cloud, % of the sky. */
        val cloudLow: Double? = null,
        val cloudMid: Double? = null,
        val cloudHigh: Double? = null,
    )

    /** One 15-minute step: its start and the precipitation in it (mm). */
    data class Step(val time: LocalDateTime, val precipitation: Double)

    data class Day(
        val date: LocalDate,
        val code: Int,
        val high: Double,
        val low: Double,
        val rainChance: Int,
        val sunrise: LocalDateTime?,
        val sunset: LocalDateTime?,
        val uvIndex: Double?,
        val precipitationSum: Double? = null,
        val rainSum: Double? = null,
        val snowfallSum: Double? = null,
        val windMax: Double? = null,
        val gustMax: Double? = null,
        val windDirection: Double? = null,
    ) {
        /** This day with its range widened to include a reading, so today never contradicts "now". */
        fun including(celsius: Double) = copy(low = minOf(low, celsius), high = maxOf(high, celsius))
    }

    /** The next 24 hours, starting with the current one. */
    val upcomingHours: List<Hour>
        get() {
            val hourStart = now.time.withMinute(0).withSecond(0).withNano(0)
            return hours.dropWhile { it.time < hourStart }.take(24)
        }

    /** One day's hours, midnight to midnight. */
    fun hoursOf(date: LocalDate): List<Hour> = hours.filter { it.time.toLocalDate() == date }

    /** The hourly entry for the current hour, if the forecast has it. */
    val nowIndex: Int
        get() {
            val hourStart = now.time.withMinute(0).withSecond(0).withNano(0)
            return hours.indexOfFirst { it.time == hourStart }
        }

    companion object {
        fun hour(time: LocalDateTime): String =
            time.format(DateTimeFormatter.ofPattern(if (is24Hour()) "HH" else "h a", Locale.getDefault()))

        fun clock(time: LocalDateTime): String =
            time.format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.getDefault()))

        fun weekday(date: LocalDate): String = date.format(DateTimeFormatter.ofPattern("EEE", Locale.getDefault()))

        /** "Tuesday, Nov 4". */
        fun longDate(date: LocalDate): String = date.format(DateTimeFormatter.ofPattern("EEEE, MMM d", Locale.getDefault()))

        /** Set by the app from the phone's 12/24-hour setting. */
        @Volatile var uses24Hour: Boolean? = null
        private fun is24Hour(): Boolean = uses24Hour ?: (Locale.getDefault().country !in setOf("US", "CA", "AU", "IN", "PH"))
    }
}

/** WMO weather codes as names, in title case as the iPhone shows them ("Partly Cloudy"). */
object Condition {
    fun name(code: Int): String = when (code) {
        0 -> "Clear"
        1 -> "Mostly Clear"
        2 -> "Partly Cloudy"
        3 -> "Overcast"
        45 -> "Fog"
        48 -> "Freezing Fog"
        51 -> "Light Drizzle"
        53 -> "Drizzle"
        55 -> "Heavy Drizzle"
        56, 57 -> "Freezing Drizzle"
        61 -> "Light Rain"
        63 -> "Rain"
        65 -> "Heavy Rain"
        66, 67 -> "Freezing Rain"
        71 -> "Light Snow"
        73 -> "Snow"
        75 -> "Heavy Snow"
        77 -> "Snow Grains"
        80, 81 -> "Showers"
        82 -> "Heavy Showers"
        85, 86 -> "Snow Showers"
        95 -> "Thunderstorms"
        96, 99 -> "Thunderstorms with Hail"
        else -> "Cloudy"
    }

    fun isSnow(code: Int) = code in setOf(71, 73, 75, 77, 85, 86)
    fun isStorm(code: Int) = code in setOf(95, 96, 99)

    /** Which drawn symbol a code gets. */
    enum class Glyph { SUN, MOON, PARTLY_SUN, PARTLY_MOON, CLOUD, FOG, DRIZZLE, RAIN, HEAVY_RAIN, SLEET, SNOW, STORM }

    fun glyph(code: Int, isDay: Boolean): Glyph = when (code) {
        0 -> if (isDay) Glyph.SUN else Glyph.MOON
        1, 2 -> if (isDay) Glyph.PARTLY_SUN else Glyph.PARTLY_MOON
        45, 48 -> Glyph.FOG
        51, 53, 55, 56, 57 -> Glyph.DRIZZLE
        61, 63, 80, 81 -> Glyph.RAIN
        65, 82 -> Glyph.HEAVY_RAIN
        66, 67 -> Glyph.SLEET
        71, 73, 75, 77, 85, 86 -> Glyph.SNOW
        95, 96, 99 -> Glyph.STORM
        else -> Glyph.CLOUD
    }
}

/** Both units, as TalkBack says them. */
object Speech {
    fun temperature(celsius: Double) =
        "${TempUnit.FAHRENHEIT.value(celsius)} degrees Fahrenheit, ${TempUnit.CELSIUS.value(celsius)} degrees Celsius"
}

/** Weather terms shared with the Mac and iPhone apps: dew point, UV levels and compass points. */
object Meteo {
    /** Dew point in °C from temperature (°C) and relative humidity (%), by the Magnus formula. */
    fun dewPoint(t: Double, humidity: Double): Double {
        val a = 17.62
        val b = 243.12
        val gamma = ln(maxOf(humidity, 1.0) / 100) + a * t / (b + t)
        return b * gamma / (a - gamma)
    }

    fun uvLevel(index: Double) = when {
        index < 3 -> "Low"
        index < 6 -> "Moderate"
        index < 8 -> "High"
        index < 11 -> "Very high"
        else -> "Extreme"
    }

    fun compass(degrees: Double): String {
        val points = listOf("N", "NE", "E", "SE", "S", "SW", "W", "NW")
        val d = ((degrees % 360) + 360) % 360
        return points[((d + 22.5) / 45).toInt() % 8]
    }

    fun compassName(degrees: Double): String = mapOf(
        "N" to "north", "NE" to "northeast", "E" to "east", "SE" to "southeast",
        "S" to "south", "SW" to "southwest", "W" to "west", "NW" to "northwest",
    )[compass(degrees)] ?: compass(degrees)

    fun mph(kmh: Double) = (kmh * 0.621371).roundToInt()
}

/** The one-line summary above the hourly forecast, with the same rules as the Mac and iPhone. */
object Summary {
    fun line(forecast: Forecast, unit: TempUnit): String {
        val hours = forecast.upcomingHours
        fun dual(c: Double) = "${unit.spaced(c)} / ${unit.other.spaced(c)}"
        hours.drop(1).take(12).firstOrNull { it.rainChance >= 50 }?.let { wet ->
            return "${wetWord(wet.code)} likely around ${Forecast.hour(wet.time)} (${wet.rainChance}%)."
        }
        val next = hours.take(16)
        val first = next.firstOrNull() ?: return ""
        next.maxByOrNull { it.temperature }?.let { peak ->
            if (peak.time != first.time && peak.temperature - forecast.now.temperature > 1.5)
                return "Warming to ${dual(peak.temperature)} by ${Forecast.hour(peak.time)}."
        }
        next.minByOrNull { it.temperature }?.let { dip ->
            if (dip.time != first.time && forecast.now.temperature - dip.temperature > 1.5)
                return "Cooling to ${dual(dip.temperature)} by ${Forecast.hour(dip.time)}."
        }
        val today = forecast.days.firstOrNull() ?: return ""
        return "Today ${dual(today.low)} to ${dual(today.high)}."
    }

    fun rainNote(forecast: Forecast): String {
        val wet = forecast.upcomingHours.drop(1).take(12).firstOrNull { it.rainChance >= 50 }
            ?: return "None expected in the next 12 hours."
        return "${wetWord(wet.code)} likely around ${Forecast.hour(wet.time)}."
    }

    private fun wetWord(code: Int) = when {
        Condition.isSnow(code) -> "Snow"
        Condition.isStorm(code) -> "Storms"
        else -> "Rain"
    }
}

/**
 * When to ask for the Terms of Use and Privacy, as on the Mac and iPhone: always the first time; again
 * when they change, but no more than once a month.
 */
object TermsSchedule {
    const val INTERVAL_MS = 30L * 24 * 60 * 60 * 1000

    fun shouldAsk(acceptedVersion: String?, acceptedAt: Long?, current: String, now: Long = System.currentTimeMillis()): Boolean {
        if (acceptedVersion.isNullOrEmpty()) return true   // never agreed
        if (acceptedVersion == current) return false
        if (acceptedAt == null || acceptedAt <= 0) return true   // agreed before the date was kept
        return now - acceptedAt >= INTERVAL_MS
    }
}
