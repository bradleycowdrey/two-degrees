package com.bradcowdrey.twodegrees

import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor

/** The moon tonight, worked out on the phone: no service needed. */
object Moon {
    const val SYNODIC_MONTH = 29.530588853
    /** A new moon: 2000-01-06 18:14 UTC. */
    private val NEW_MOON: Instant = Instant.parse("2000-01-06T18:14:00Z")

    val NAMES = listOf(
        "New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
        "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent",
    )

    data class Phase(val name: String, /** 0–100. */ val illumination: Int, /** 0 new, 0.5 full. */ val fraction: Double) {
        /** "Waxing Gibbous · 78%". */
        val text: String get() = "$name · $illumination%"
    }

    fun phase(at: Instant): Phase {
        val days = Duration.between(NEW_MOON, at).seconds / 86400.0
        val f = ((days / SYNODIC_MONTH) % 1 + 1) % 1
        val name = NAMES[floor(f * 8 + 0.5).toInt() % 8]
        val lit = (1 - cos(2 * PI * f)) / 2
        return Phase(name, (lit * 100).roundHalfUp(), f)
    }

    /** The next full or new moon, whichever comes first: "Full moon in 5 days", "New moon tomorrow". */
    fun next(at: Instant): String {
        val f = phase(at).fraction
        val toFull = ((0.5 - f + 1) % 1) * SYNODIC_MONTH
        val toNew = ((1 - f) % 1) * SYNODIC_MONTH
        val (name, days) = if (toFull <= toNew) "Full moon" to toFull else "New moon" to toNew
        return when (val n = days.roundHalfUp()) { 0 -> "$name today."; 1 -> "$name tomorrow."; else -> "$name in $n days." }
    }
}

/** The words for the newer detail tiles, as on the Mac, iPhone and web. */
/**
 * How colourful a sunrise or sunset is likely to be, from the clouds forecast for that hour. Colour
 * comes from high and mid-level cloud catching the low sun; thick low cloud near the horizon blocks
 * it, rain and fog hide it, and a clear sky gives a clean but plain glow. The same rule as the Mac,
 * iPhone and web (design/weather-features.md, "Sky colour").
 */
object SkyColour {
    enum class Rating(val word: String, val line: String) {
        POOR("Poor", "Little colour expected"), FAIR("Fair", "Some colour possible"),
        GOOD("Good", "Good colour likely"), GREAT("Great", "Great colour likely"),
    }
    data class Outlook(val rating: Rating, val reason: String)

    fun outlook(low: Double, mid: Double, high: Double, precipitation: Double, code: Int, visibility: Double?): Outlook {
        val fog = code == 45 || code == 48
        if (precipitation >= 0.2 || fog || code >= 51) {
            return Outlook(Rating.POOR, if (fog) "Fog will likely hide it." else "Rain or snow will likely hide it.")
        }
        if (low >= 70) return Outlook(Rating.POOR, "Low cloud will likely block it.")
        val canvas = maxOf(mid, high)
        var score = 30.0
        var reason = when {
            canvas < 5 -> { score += 15; "Clear sky: a clean, simple glow." }
            canvas < 20 -> { score += 22; "A few high clouds may catch some colour." }
            canvas <= 80 -> { score += 42; "High and mid-level clouds to catch the colour." }
            else -> { score += 12; "A thick cloud layer may mute it." }
        }
        score -= low * 0.5
        if (low >= 40) reason = "Low cloud may block some of it."
        if (visibility != null && visibility < 5000) { score -= 15; reason = "Haze may dull it." }
        val rating = when {
            score >= 65 -> Rating.GREAT
            score >= 50 -> Rating.GOOD
            score >= 35 -> Rating.FAIR
            else -> Rating.POOR
        }
        return Outlook(rating, reason)
    }

    /** The outlook for a sunrise or sunset, from the forecast hour nearest it (within 90 minutes). */
    fun outlook(forecast: Forecast, time: java.time.LocalDateTime): Outlook? {
        val hour = forecast.hours.minByOrNull { kotlin.math.abs(java.time.Duration.between(it.time, time).toMinutes()) } ?: return null
        if (kotlin.math.abs(java.time.Duration.between(hour.time, time).toMinutes()) > 90) return null
        val low = hour.cloudLow ?: return null
        val mid = hour.cloudMid ?: return null
        val high = hour.cloudHigh ?: return null
        return outlook(low, mid, high, hour.precipitation ?: 0.0, hour.code, hour.visibility)
    }

    /** The next sunrise or sunset after now: (is it sunset, its time). */
    fun next(forecast: Forecast): Pair<Boolean, java.time.LocalDateTime>? {
        val now = forecast.now.time
        for (day in forecast.days) {
            day.sunrise?.let { if (it > now) return false to it }
            day.sunset?.let { if (it > now) return true to it }
        }
        return null
    }
}

object Detail {
    /** Which clouds there are now, from the hour's layers: "Mostly high, thin cloud." */
    fun cloudLayers(forecast: Forecast): String? {
        val (low, mid, high) = cloudLayerValues(forecast) ?: return null
        return cloudWords(low, mid, high)
    }

    /** The hour nearest now's cloud by height, (low, mid, high) in %, or null if any is missing. */
    fun cloudLayerValues(forecast: Forecast): Triple<Double, Double, Double>? {
        val now = forecast.now.time
        val hour = forecast.hours.minByOrNull { kotlin.math.abs(java.time.Duration.between(it.time, now).toMinutes()) } ?: return null
        return Triple(hour.cloudLow ?: return null, hour.cloudMid ?: return null, hour.cloudHigh ?: return null)
    }

    /** How far through the day a time is, 0 at midnight to 1 at the next midnight. */
    fun dayFraction(time: java.time.LocalDateTime, date: java.time.LocalDate): Double =
        (java.time.Duration.between(date.atStartOfDay(), time).toMinutes() / 1440.0).coerceIn(0.0, 1.0)

    /**
     * The sun's height on the sunrise/sunset curve at a point in the day (all day fractions): a cosine
     * over 24 hours, highest midway between sunrise and sunset and 0 at both. Runs from -1 - k to 1 - k,
     * where k is [sunCurveShift].
     */
    fun sunHeight(x: Double, sunrise: Double, sunset: Double): Double =
        kotlin.math.cos(2 * Math.PI * (x - (sunrise + sunset) / 2)) - sunCurveShift(sunrise, sunset)

    /** How far the curve sits below centre: the cosine's value at sunrise. */
    fun sunCurveShift(sunrise: Double, sunset: Double): Double = kotlin.math.cos(Math.PI * (sunset - sunrise))

    /**
     * The Averages tile's scale: from the lowest to the highest of the record (or normal) low and high
     * and today's low and high, with a little room at each end.
     */
    fun averagesScale(todayLow: Double, todayHigh: Double, entry: Normals.Entry): Pair<Double, Double> {
        val low = minOf(entry.recordLow ?: entry.normalLow ?: todayLow, todayLow)
        val high = maxOf(entry.recordHigh ?: entry.normalHigh ?: todayHigh, todayHigh)
        val pad = maxOf((high - low) * 0.05, 0.5)
        return (low - pad) to (high + pad)
    }

    fun cloudWords(low: Double, mid: Double, high: Double): String = when {
        maxOf(low, mid, high) < 10 -> "No cloud at any height."
        listOf(low, mid, high).count { it >= 50 } >= 2 -> "Cloud at several heights."
        low >= mid && low >= high -> "Mostly low cloud."
        mid >= high -> "Mostly mid-level cloud."
        else -> "Mostly high, thin cloud."
    }

    /** 0–10 Clear, to 30 Mostly clear, to 60 Partly cloudy, to 90 Mostly cloudy, else Overcast. */
    fun cloudWord(percent: Double) = when {
        percent <= 10 -> "Clear"
        percent <= 30 -> "Mostly clear"
        percent <= 60 -> "Partly cloudy"
        percent <= 90 -> "Mostly cloudy"
        else -> "Overcast"
    }

    /** From metres: 10 km or more Clear view, 2–10 km Haze, under 2 km Fog. */
    fun visibilityWord(metres: Double) = when {
        metres >= 10_000 -> "Clear view"
        metres >= 2_000 -> "Haze"
        else -> "Fog"
    }


    /** "Gusts to 35 mph", when gusts are 10 km/h or more above the wind. */
    fun gustNote(now: Forecast.Now, units: Units): String? {
        val gusts = now.gusts ?: return null
        return if (gusts - now.wind >= 10) "Gusts to ${units.wind.text(gusts)}" else null
    }

    /** Precipitation over the next 24 hours, in mm, or null without hourly amounts. */
    fun next24Hours(forecast: Forecast): Double? {
        val amounts = forecast.upcomingHours.mapNotNull { it.precipitation }
        return if (amounts.isEmpty()) null else amounts.sum()
    }
}

/** The Next 2 hours card: 15-minute rain (or snow), and its one line. */
object NextHours {
    const val WET = 0.1

    /** Shown only with 0.1 mm or more in any step. */
    fun shows(forecast: Forecast): Boolean = forecast.steps.any { it.precipitation >= WET }

    fun snowy(forecast: Forecast): Boolean =
        Condition.isSnow(forecast.now.code) || forecast.upcomingHours.take(3).any { Condition.isSnow(it.code) }

    /** "Rain starting around 3:15 PM" / "Rain stopping around 3:45 PM" / "Rain for the next two hours" / "Light rain on and off". */
    fun sentence(forecast: Forecast, clock: (LocalDateTime) -> String = Forecast::clock): String {
        val steps = forecast.steps
        val word = if (snowy(forecast)) "Snow" else "Rain"
        val wet = steps.map { it.precipitation >= WET }
        if (wet.isEmpty() || wet.none { it }) return ""
        if (wet.all { it }) return "$word for the next two hours"
        if (!wet[0]) return "$word starting around ${clock(steps[wet.indexOf(true)].time)}"
        val dry = wet.indexOf(false)
        if (wet.drop(dry).none { it }) return "$word stopping around ${clock(steps[dry].time)}"
        return "Light ${word.lowercase()} on and off"
    }

    /**
     * Rain Starting Soon: not raining now, and 0.2 mm or more in one of the next two steps (about 30
     * minutes). The step's time, and whether it's snow; null when there's nothing to say.
     */
    fun startingSoon(forecast: Forecast): Pair<LocalDateTime, Boolean>? {
        val steps = forecast.steps
        if (steps.size < 3) return null
        if ((forecast.now.precipitation ?: 0.0) >= WET || steps[0].precipitation >= WET) return null
        val step = steps.subList(1, 3).firstOrNull { it.precipitation >= 0.2 } ?: return null
        return step.time to snowy(forecast)
    }
}
