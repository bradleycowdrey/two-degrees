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
}

/** The words for the newer detail tiles, as on the Mac, iPhone and web. */
object Detail {
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

    /** "Rising", "Falling" or "Steady": the change over the last 3 hours, 1 hPa or more. Null without the readings. */
    fun pressureTrend(forecast: Forecast): String? {
        val i = forecast.nowIndex
        if (i < 3) return null
        val now = forecast.now.pressure ?: forecast.hours[i].pressure ?: return null
        val before = forecast.hours[i - 3].pressure ?: return null
        val change = now - before
        return when {
            change >= 1 -> "Rising"
            change <= -1 -> "Falling"
            else -> "Steady"
        }
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
