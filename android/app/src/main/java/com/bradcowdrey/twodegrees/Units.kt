package com.bradcowdrey.twodegrees

import java.util.Locale
import kotlin.math.abs

/**
 * Wind and rain units, as on the Mac, iPhone and web: Automatic follows the larger
 * temperature unit. Saved under `windUnit` and `rainUnit` with these keys.
 * A reading shows its other-system counterpart beside it only for mph↔km/h, mm↔in and hPa↔inHg.
 */
enum class WindUnit(val key: String, val label: String, val symbol: String) {
    AUTO("auto", "Automatic", ""), KMH("kmh", "km/h", "km/h"), MPH("mph", "mph", "mph"), MS("ms", "m/s", "m/s"), KN("kn", "knots", "kn");

    /** mph when °F is larger, km/h when °C. */
    fun resolved(unit: TempUnit): WindUnit = if (this != AUTO) this else if (unit == TempUnit.FAHRENHEIT) MPH else KMH

    /** From km/h. */
    fun value(kmh: Double): Double = when (this) {
        MPH -> kmh * 0.621371
        MS -> kmh / 3.6
        KN -> kmh / 1.852
        else -> kmh
    }

    /** "12 mph" (a resolved unit). */
    fun text(kmh: Double): String = "${value(kmh).roundHalfUp()} $symbol"

    val counterpart: WindUnit? get() = when (this) { MPH -> KMH; KMH -> MPH; else -> null }

    /** Visibility follows the wind unit's system: miles with mph, kilometres otherwise. */
    val usesMiles: Boolean get() = this == MPH

    companion object {
        fun of(key: String?) = entries.firstOrNull { it.key == key } ?: AUTO
    }
}

enum class RainUnit(val key: String, val label: String) {
    AUTO("auto", "Automatic"), MM("mm", "mm"), IN("in", "in");

    /** in with °F, mm with °C. */
    fun resolved(unit: TempUnit): RainUnit = if (this != AUTO) this else if (unit == TempUnit.FAHRENHEIT) IN else MM

    /** "2.4 mm", "0.09 in" (a resolved unit), from mm. */
    fun text(mm: Double): String = when (this) {
        IN -> if (mm < 0.05) "0 in" else "${fixed(mm / 25.4, 2)} in"
        else -> if (mm < 0.05) "0 mm" else if (mm >= 10) "${mm.roundHalfUp()} mm" else "${fixed(mm, 1)} mm"
    }

    val counterpart: RainUnit get() = if (this == IN) MM else IN

    companion object {
        fun of(key: String?) = entries.firstOrNull { it.key == key } ?: AUTO
    }
}

/** The two choices together, with the temperature unit that Automatic follows. */
data class Units(val temperature: TempUnit, val windChoice: WindUnit = WindUnit.AUTO, val rainChoice: RainUnit = RainUnit.AUTO) {
    val wind: WindUnit get() = windChoice.resolved(temperature)
    val rain: RainUnit get() = rainChoice.resolved(temperature)

    /** A wind reading and its counterpart (or null): "12 mph" to "19 km/h". */
    fun wind(kmh: Double): Pair<String, String?> = wind.text(kmh) to wind.counterpart?.text(kmh)
    fun rain(mm: Double): Pair<String, String?> = rain.text(mm) to rain.counterpart.text(mm)

    /** "16 km" or "9.9 mi", from metres. */
    fun visibility(metres: Double): String {
        val v = if (wind.usesMiles) metres / 1609.344 else metres / 1000
        val text = if (v >= 10) "${v.roundHalfUp()}" else fixed(v, 1)
        return "$text ${if (wind.usesMiles) "mi" else "km"}"
    }
}

/** A number with this many decimals, always with a point. */
internal fun fixed(value: Double, decimals: Int): String {
    val s = String.format(Locale.US, "%.${decimals}f", abs(value) + 1e-9)
    return if (value < 0 && s.any { it in '1'..'9' }) "-$s" else s
}
