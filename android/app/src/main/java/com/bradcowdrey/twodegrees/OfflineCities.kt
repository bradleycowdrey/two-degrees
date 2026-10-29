package com.bradcowdrey.twodegrees

import java.text.Normalizer
import java.util.Locale

/**
 * The cities search falls back on when Open-Meteo can't be reached: every place with at least 15,000
 * people, from GeoNames (Resources/Cities.tsv, shared with the Mac and iPhone apps), most populous first.
 * So you can pick a city with the internet out; its weather loads once you're back online.
 */
object OfflineCities {
    class Entry(val name: String, val region: String, val latitude: Double, val longitude: Double, val keys: List<String>)

    /** Reads the bundled list; set by the app (from its assets). */
    @Volatile var source: () -> String? = { null }

    val all: List<Entry> by lazy { source()?.let { parse(it) } ?: emptyList() }

    /**
     * One city per line: name, ASCII name (empty when the same), state or province, country code,
     * latitude, longitude. The country's name is in the phone's own language.
     */
    fun parse(text: String, locale: Locale = Locale.getDefault()): List<Entry> {
        val countries = HashMap<String, String>()
        return text.lineSequence().mapNotNull { line ->
            val c = line.split('\t')
            if (c.size < 6) return@mapNotNull null
            val lat = c[4].toDoubleOrNull() ?: return@mapNotNull null
            val lon = c[5].toDoubleOrNull() ?: return@mapNotNull null
            val country = countries.getOrPut(c[3]) {
                Locale("", c[3]).getDisplayCountry(locale).ifEmpty { c[3] }
            }
            Entry(c[0], listOf(c[2], country).filter { it.isNotEmpty() }.joinToString(", "), lat, lon,
                listOf(c[0], c[1]).filter { it.isNotEmpty() }.map(::fold))
        }.toList()
    }

    /**
     * Cities whose name starts with the query, exact names first, then the most populous. Text after
     * a comma narrows by state or country ("Portland, Maine").
     */
    fun search(query: String, list: List<Entry> = all, limit: Int = 8): List<City> {
        val parts = query.split(',', limit = 2).map(::fold)
        val name = parts.firstOrNull()?.takeIf { it.isNotEmpty() } ?: return emptyList()
        val place = parts.getOrNull(1) ?: ""
        val exact = ArrayList<Entry>()
        val starts = ArrayList<Entry>()
        for (entry in list) {
            if (place.isNotEmpty() && place !in fold(entry.region)) continue
            if (name in entry.keys) exact += entry
            else if (starts.size < limit && entry.keys.any { it.startsWith(name) }) starts += entry
        }
        return (exact + starts).take(limit).map { City(it.name, it.region, it.latitude, it.longitude) }
    }

    private val marks = Regex("\\p{Mn}+")

    fun fold(text: String): String =
        marks.replace(Normalizer.normalize(text, Normalizer.Form.NFD), "").lowercase(Locale.ROOT).trim()
}
