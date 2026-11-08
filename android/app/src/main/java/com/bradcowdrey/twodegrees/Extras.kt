package com.bradcowdrey.twodegrees

import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.util.Locale

/** Whether a city is in the United States: the country in its region, else (no region) its coordinates. */
object Region {
    private val names: Set<String> by lazy {
        setOf(
            "United States", "United States of America", "USA", "US", "Puerto Rico", "Guam", "U.S. Virgin Islands",
            "American Samoa", "Northern Mariana Islands",
            Locale("", "US").getDisplayCountry(Locale.getDefault()), Locale("", "US").getDisplayCountry(Locale.ENGLISH),
            Locale("", "PR").getDisplayCountry(Locale.getDefault()),
        )
    }

    fun isUS(city: City): Boolean {
        val country = city.region.substringAfterLast(",").trim()
        if (country.isNotEmpty()) return country in names
        val (lat, lon) = city.latitude to city.longitude
        return (lat in 24.4..49.4 && lon in -125.0..-66.9) || (lat in 51.0..71.5 && lon in -170.0..-129.9) ||
            (lat in 18.9..22.3 && lon in -160.3..-154.8) || (lat in 17.8..18.6 && lon in -67.3..-65.2)
    }
}

// Air quality and pollen

/** Open-Meteo's air quality right now, and the same hour yesterday. */
data class AirQuality(
    val usAqi: Double?,
    val europeanAqi: Double?,
    val pm25: Double?,
    val pm10: Double?,
    val ozone: Double?,
    val nitrogenDioxide: Double?,
    /** Grains/m³ by type (Alder, Birch, Grass, Mugwort, Olive, Ragweed); null outside Europe. */
    val pollen: Map<String, Double?>,
    val yesterdayUs: Double?,
    val yesterdayEuropean: Double?,
)

object Air {
    /** The local scale: US AQI in the United States, European AQI elsewhere. */
    enum class Scale(val title: String, val bands: List<Band>) {
        US("US AQI", listOf(
            Band(50.0, "Good", 0xFF4CC36B), Band(100.0, "Moderate", 0xFFE9D05A), Band(150.0, "Unhealthy for Sensitive Groups", 0xFFF2A65A),
            Band(200.0, "Unhealthy", 0xFFE5484D), Band(300.0, "Very Unhealthy", 0xFF9B5DE5), Band(500.0, "Hazardous", 0xFF8E2D45),
        )),
        EUROPEAN("European AQI", listOf(
            Band(20.0, "Good", 0xFF50D7C8), Band(40.0, "Fair", 0xFF4CC36B), Band(60.0, "Moderate", 0xFFE9D05A),
            Band(80.0, "Poor", 0xFFE5484D), Band(100.0, "Very Poor", 0xFF9B3050), Band(150.0, "Extremely Poor", 0xFF7D2181),
        )),
    }

    /** One category: up to and including this value. */
    data class Band(val upTo: Double, val name: String, val color: Long)

    fun scale(city: City) = if (Region.isUS(city)) Scale.US else Scale.EUROPEAN

    fun value(air: AirQuality, scale: Scale): Double? = if (scale == Scale.US) air.usAqi else air.europeanAqi

    fun band(value: Double, scale: Scale): Band {
        val v = value.roundHalfUp()
        return scale.bands.firstOrNull { v <= it.upTo } ?: scale.bands.last()
    }

    fun category(value: Double, scale: Scale): String = band(value, scale).name

    /** Where the value sits on the bar, 0 to 1: the bands are equal widths. */
    fun position(value: Double, scale: Scale): Double {
        val bands = scale.bands
        val i = bands.indexOf(band(value, scale))
        val from = if (i == 0) 0.0 else bands[i - 1].upTo
        val k = ((value - from) / (bands[i].upTo - from)).coerceIn(0.0, 1.0)
        return (i + k) / bands.size
    }

    /** "Better than yesterday" / "Worse than yesterday" / "About the same as yesterday" (±5); else the main pollutant. */
    fun note(air: AirQuality, scale: Scale): String? {
        val now = value(air, scale)
        val before = if (scale == Scale.US) air.yesterdayUs else air.yesterdayEuropean
        if (now != null && before != null) {
            val change = now - before
            return when {
                change < -5 -> "Better than yesterday"
                change > 5 -> "Worse than yesterday"
                else -> "About the same as yesterday"
            }
        }
        return mainPollutant(air)?.let { "Mostly $it" }
    }

    /** The pollutant furthest above its guideline level (WHO's 24-hour and 8-hour values). */
    fun mainPollutant(air: AirQuality): String? = listOfNotNull(
        air.pm25?.let { "PM2.5" to it / 15 }, air.pm10?.let { "PM10" to it / 45 },
        air.ozone?.let { "ozone" to it / 100 }, air.nitrogenDioxide?.let { "nitrogen dioxide" to it / 25 },
    ).maxByOrNull { it.second }?.first

    fun url(city: City) = "https://air-quality-api.open-meteo.com/v1/air-quality?${OpenMeteo.coordinates(city)}" +
        "&timezone=auto&forecast_days=1&past_days=1" +
        "&current=us_aqi,european_aqi,pm2_5,pm10,ozone,nitrogen_dioxide,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen" +
        "&hourly=us_aqi,european_aqi"

    fun fetch(city: City): AirQuality = decode(OpenMeteo.fetch(url(city)))

    val POLLEN = listOf("alder" to "Alder", "birch" to "Birch", "grass" to "Grass", "mugwort" to "Mugwort", "olive" to "Olive", "ragweed" to "Ragweed")

    fun decode(body: String): AirQuality {
        val raw = JSONObject(body)
        val current = raw.getJSONObject("current")
        // Yesterday's same hour, from the hourly series (it starts at yesterday's midnight).
        val yesterday = current.optStringOrNull("time")?.let(OpenMeteo::dateTime)?.withMinute(0)?.minusDays(1)?.toString()
        val hourly = raw.optJSONObject("hourly")
        val i = hourly?.optJSONArray("time")?.let { t -> (0 until t.length()).firstOrNull { t.stringOrNull(it) == yesterday } }
        return AirQuality(
            usAqi = current.optDoubleOrNull("us_aqi"),
            europeanAqi = current.optDoubleOrNull("european_aqi"),
            pm25 = current.optDoubleOrNull("pm2_5"),
            pm10 = current.optDoubleOrNull("pm10"),
            ozone = current.optDoubleOrNull("ozone"),
            nitrogenDioxide = current.optDoubleOrNull("nitrogen_dioxide"),
            pollen = POLLEN.associate { (key, name) -> name to current.optDoubleOrNull("${key}_pollen") },
            yesterdayUs = i?.let { hourly.optJSONArray("us_aqi")?.doubleOrNull(it) },
            yesterdayEuropean = i?.let { hourly.optJSONArray("european_aqi")?.doubleOrNull(it) },
        )
    }
}

object Pollen {
    /** Grains/m³: under 10 Low, under 50 Moderate, under 200 High, else Very High. */
    fun level(grains: Double) = when {
        grains < 10 -> "Low"
        grains < 50 -> "Moderate"
        grains < 200 -> "High"
        else -> "Very High"
    }

    data class Summary(val type: String, val level: String, /** Other types above Low, highest first. */ val others: List<String>) {
        val note: String get() = if (others.isEmpty()) "Other pollen is low." else "Also ${others.joinToString(", ")}."
    }

    /** The highest type and its level; null when there's no pollen data (outside Europe). */
    fun summary(air: AirQuality): Summary? {
        val known = air.pollen.mapNotNull { (k, v) -> v?.let { k to it } }.sortedByDescending { it.second }
        val top = known.firstOrNull() ?: return null
        val others = known.drop(1).filter { level(it.second) != "Low" }.map { "${it.first} (${level(it.second).lowercase()})" }
        return Summary(top.first, level(top.second), others)
    }
}

// Normals and records

/**
 * Each month-day's normal high and low (1991–2020, a ±3-day window) and its record high and low with
 * their years, from Open-Meteo's historical weather. 366 entries, Feb 29 included.
 */
data class Normals(val fetchedAt: Long, val entries: List<Entry?>) {
    data class Entry(
        val normalHigh: Double?,
        val normalLow: Double?,
        val recordHigh: Double?,
        val recordHighYear: Int?,
        val recordLow: Double?,
        val recordLowYear: Int?,
    )

    fun of(date: LocalDate): Entry? = entries.getOrNull(position(date))

    val isStale: Boolean get() = System.currentTimeMillis() - fetchedAt > CACHE_MS

    companion object {
        const val CACHE_MS = 30L * 24 * 60 * 60 * 1000

        /** Jan 1 is 0, Feb 29 is 59, Dec 31 is 365. */
        fun position(date: LocalDate): Int = LocalDate.of(2000, date.monthValue, date.dayOfMonth).dayOfYear - 1

        fun url(city: City, today: LocalDate) = "https://archive-api.open-meteo.com/v1/archive?${OpenMeteo.coordinates(city)}" +
            "&start_date=1940-01-01&end_date=${today.minusDays(7)}&daily=temperature_2m_max,temperature_2m_min&timezone=auto"

        fun fetch(city: City, today: LocalDate = LocalDate.now()): Normals = decodeArchive(OpenMeteo.fetch(url(city, today)))

        fun decodeArchive(body: String, fetchedAt: Long = System.currentTimeMillis()): Normals {
            val daily = JSONObject(body).getJSONObject("daily")
            val times = daily.getJSONArray("time")
            val max = daily.getJSONArray("temperature_2m_max")
            val min = daily.getJSONArray("temperature_2m_min")
            val days = (0 until times.length()).mapNotNull { i ->
                runCatching { LocalDate.parse(times.getString(i)) }.getOrNull()?.let { Triple(it, max.doubleOrNull(i), min.doubleOrNull(i)) }
            }
            return build(days, fetchedAt)
        }

        /** Each day: date, max, min (°C). */
        fun build(days: List<Triple<LocalDate, Double?, Double?>>, fetchedAt: Long = System.currentTimeMillis()): Normals {
            val hiSum = DoubleArray(366); val hiCount = IntArray(366)
            val loSum = DoubleArray(366); val loCount = IntArray(366)
            val recHigh = arrayOfNulls<Pair<Double, Int>>(366)
            val recLow = arrayOfNulls<Pair<Double, Int>>(366)
            for ((date, hi, lo) in days) {
                val p = position(date)
                if (date.year in 1991..2020) {
                    if (hi != null) { hiSum[p] += hi; hiCount[p]++ }
                    if (lo != null) { loSum[p] += lo; loCount[p]++ }
                }
                // The first year to reach it keeps the record.
                if (hi != null && (recHigh[p] == null || hi > recHigh[p]!!.first)) recHigh[p] = hi to date.year
                if (lo != null && (recLow[p] == null || lo < recLow[p]!!.first)) recLow[p] = lo to date.year
            }
            fun window(sum: DoubleArray, count: IntArray, p: Int): Double? {
                var s = 0.0; var n = 0
                for (d in -3..3) { val q = (p + d + 366) % 366; s += sum[q]; n += count[q] }
                return if (n == 0) null else s / n
            }
            val entries = (0 until 366).map { p ->
                val e = Entry(window(hiSum, hiCount, p), window(loSum, loCount, p), recHigh[p]?.first, recHigh[p]?.second, recLow[p]?.first, recLow[p]?.second)
                e.takeIf { listOf(it.normalHigh, it.normalLow, it.recordHigh, it.recordLow).any { v -> v != null } }
            }
            return Normals(fetchedAt, entries)
        }

        // Saved as one small JSON object: six arrays of 366.
        fun encode(n: Normals): String = JSONObject()
            .put("fetchedAt", n.fetchedAt)
            .put("normalHigh", JSONArray(n.entries.map { it?.normalHigh?.let { v -> Math.round(v * 10) / 10.0 } ?: JSONObject.NULL }))
            .put("normalLow", JSONArray(n.entries.map { it?.normalLow?.let { v -> Math.round(v * 10) / 10.0 } ?: JSONObject.NULL }))
            .put("recordHigh", JSONArray(n.entries.map { it?.recordHigh ?: JSONObject.NULL }))
            .put("recordHighYear", JSONArray(n.entries.map { it?.recordHighYear ?: JSONObject.NULL }))
            .put("recordLow", JSONArray(n.entries.map { it?.recordLow ?: JSONObject.NULL }))
            .put("recordLowYear", JSONArray(n.entries.map { it?.recordLowYear ?: JSONObject.NULL }))
            .toString()

        fun decode(text: String?): Normals? = text?.let {
            runCatching {
                val o = JSONObject(it)
                val a = listOf("normalHigh", "normalLow", "recordHigh", "recordHighYear", "recordLow", "recordLowYear").map(o::getJSONArray)
                Normals(o.getLong("fetchedAt"), (0 until 366).map { i ->
                    Entry(a[0].doubleOrNull(i), a[1].doubleOrNull(i), a[2].doubleOrNull(i), a[3].intOrNull(i), a[4].doubleOrNull(i), a[5].intOrNull(i))
                        .takeIf { e -> listOf(e.normalHigh, e.normalLow, e.recordHigh, e.recordLow).any { v -> v != null } }
                })
            }.getOrNull()
        }

        /** "4° above normal" / "3° below normal" / "About normal" (within ±1°), in the larger unit. */
        fun versus(high: Double, normalHigh: Double, unit: TempUnit): String {
            val d = unit.value(high) - unit.value(normalHigh)
            return when {
                d > 1 -> "$d° above normal"
                d < -1 -> "${-d}° below normal"
                else -> "About normal"
            }
        }

        /** "Normal high 64 °F · 18 °C, low 45 °F · 7 °C". */
        fun normalLine(e: Entry, unit: TempUnit): String? {
            val hi = e.normalHigh ?: return null
            val lo = e.normalLow ?: return null
            return "Normal high ${unit.spaced(hi)} · ${unit.other.spaced(hi)}, low ${unit.spaced(lo)} · ${unit.other.spaced(lo)}"
        }

        /** "Record high 81 °F · 27 °C (1999) · Record low 28 °F · −2 °C (1957)". */
        fun recordsLine(e: Entry, unit: TempUnit): String? {
            val parts = listOfNotNull(
                e.recordHigh?.let { "Record high ${unit.spaced(it)} · ${unit.other.spaced(it)}${e.recordHighYear?.let { y -> " ($y)" } ?: ""}" },
                e.recordLow?.let { "Record low ${unit.spaced(it)} · ${unit.other.spaced(it)}${e.recordLowYear?.let { y -> " ($y)" } ?: ""}" },
            )
            return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
        }
    }
}

// Severe weather alerts

/** One active alert from the US National Weather Service. */
data class Alert(
    val id: String,
    val event: String,
    val severity: String,
    val urgency: String?,
    val headline: String?,
    val description: String?,
    val instruction: String?,
    val effective: OffsetDateTime?,
    val expires: OffsetDateTime?,
    val senderName: String?,
)

object Alerts {
    /** Required by the NWS. */
    const val USER_AGENT = "TwoDegrees (bradcowdrey.com, legal@bradcowdrey.com)"
    const val NOTE = "From the US National Weather Service. Alerts can be late or missing: follow official warnings."
    const val SETTINGS_NOTE = "Severe weather alerts: United States only, from the National Weather Service."

    /** Swapped in unit tests. */
    @Volatile var get: (String) -> String = { OpenMeteo.request(it, mapOf("User-Agent" to USER_AGENT, "Accept" to "application/geo+json")) }

    private val ORDER = listOf("Extreme", "Severe", "Moderate", "Minor", "Unknown")
    fun rank(severity: String) = ORDER.indexOf(severity).let { if (it < 0) ORDER.size else it }

    /** Extreme, Severe and Moderate alerts get a notification. */
    fun notifies(alert: Alert) = alert.severity in setOf("Extreme", "Severe", "Moderate")

    /** Coordinates rounded to 2 decimals, without trailing zeros (as the NWS prefers). */
    private fun round(v: Double) = BigDecimal(v).setScale(2, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()

    /** Only for places in the United States; null elsewhere. */
    fun url(city: City): String? = if (Region.isUS(city)) "https://api.weather.gov/alerts/active?point=${round(city.latitude)},${round(city.longitude)}" else null

    /** A US city's active alerts, most severe first; none outside the US. Throws IOException when the request fails. */
    fun fetch(city: City, now: Instant = Instant.now()): List<Alert> {
        val url = url(city) ?: return emptyList()
        return parse(get(url), now)
    }

    fun parse(body: String, now: Instant = Instant.now()): List<Alert> {
        val features = JSONObject(body).optJSONArray("features") ?: return emptyList()
        return (0 until features.length()).mapNotNull { i ->
            val p = features.optJSONObject(i)?.optJSONObject("properties") ?: return@mapNotNull null
            Alert(
                id = p.optStringOrNull("id") ?: return@mapNotNull null,
                event = p.optStringOrNull("event") ?: "Weather Alert",
                severity = p.optStringOrNull("severity") ?: "Unknown",
                urgency = p.optStringOrNull("urgency"),
                headline = p.optStringOrNull("headline"),
                description = p.optStringOrNull("description"),
                instruction = p.optStringOrNull("instruction"),
                effective = p.optStringOrNull("effective")?.let(::time),
                expires = p.optStringOrNull("expires")?.let(::time),
                senderName = p.optStringOrNull("senderName"),
            )
        }.filter { it.expires == null || it.expires.toInstant().isAfter(now) }
            .distinctBy { it.id }
            .sortedWith(compareBy({ rank(it.severity) }, { it.expires }))
    }

    private fun time(text: String): OffsetDateTime? = runCatching { OffsetDateTime.parse(text) }.getOrNull()

    /** "Until 6:15 PM" in the city's own time ("Until Tue 6:15 PM" on another day). */
    fun until(alert: Alert, timeZone: String, today: LocalDate?, clock: (LocalDateTime) -> String = Forecast::clock): String? {
        val expires = alert.expires ?: return null
        val zone = runCatching { ZoneId.of(timeZone) }.getOrDefault(ZoneId.of("UTC"))
        val local = expires.atZoneSameInstant(zone).toLocalDateTime()
        val day = if (today != null && local.toLocalDate() != today) "${Forecast.weekday(local.toLocalDate())} " else ""
        return "Until $day${clock(local)}"
    }

    /** weather.gov's page for the place: forecast and hazards. */
    fun moreURL(city: City) = "https://forecast.weather.gov/MapClick.php?lat=${round(city.latitude)}&lon=${round(city.longitude)}"
}

/** Every saved city's air quality, normals and alerts beside its forecast; failures just hide tiles. */
object Extras {
    fun air(city: City): AirQuality? = runCatching { Air.fetch(city) }.getOrNull()

    /** Null when the request failed (as opposed to no alerts). */
    fun alerts(city: City): List<Alert>? = runCatching { Alerts.fetch(city) }.getOrNull()

    fun normals(city: City): Normals? = runCatching { Normals.fetch(city) }.getOrNull()
}

/** Normals go by place, not page: where you are keeps its table until it moves about 10 km. */
fun normalsKey(city: City): String = String.format(Locale.US, "%.1f,%.1f", city.latitude, city.longitude)
