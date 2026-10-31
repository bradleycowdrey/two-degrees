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

/** One city's forecast, in Celsius and km/h, with times as the city's own wall-clock. */
data class Forecast(
    val now: Now,
    val hours: List<Hour>,
    val days: List<Day>,
    val timeZone: String,
    val fetchedAt: Long,
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
    )

    data class Hour(val time: LocalDateTime, val temperature: Double, val code: Int, val rainChance: Int, val isDay: Boolean)

    data class Day(
        val date: LocalDate,
        val code: Int,
        val high: Double,
        val low: Double,
        val rainChance: Int,
        val sunrise: LocalDateTime?,
        val sunset: LocalDateTime?,
        val uvIndex: Double?,
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

    companion object {
        fun hour(time: LocalDateTime): String =
            time.format(DateTimeFormatter.ofPattern(if (is24Hour()) "HH" else "h a", Locale.getDefault()))

        fun clock(time: LocalDateTime): String =
            time.format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.getDefault()))

        fun weekday(date: LocalDate): String = date.format(DateTimeFormatter.ofPattern("EEE", Locale.getDefault()))

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
