package com.bradcowdrey.twodegrees

import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.LocalDate
import java.time.LocalDateTime
import java.util.Locale

/** Open-Meteo: free, open source, no key. https://open-meteo.com */
object OpenMeteo {
    /** Swapped in unit tests. Returns the response body, or throws IOException. */
    @Volatile var fetch: (String) -> String = ::httpGet

    fun forecast(city: City): Forecast {
        val url = "https://api.open-meteo.com/v1/forecast" +
            "?latitude=${"%.4f".format(Locale.US, city.latitude)}&longitude=${"%.4f".format(Locale.US, city.longitude)}" +
            "&timezone=auto&forecast_days=11" +
            "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day" +
            "&hourly=temperature_2m,weather_code,precipitation_probability,is_day" +
            "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max"
        return decodeForecast(fetch(url))
    }

    /** Open-Meteo's geocoder; with the internet out, the bundled city list (OfflineCities). */
    fun search(query: String): List<City> = try {
        searchOnline(query)
    } catch (e: IOException) {
        OfflineCities.search(query).ifEmpty { throw e }
    }

    private fun searchOnline(query: String): List<City> {
        val language = Locale.getDefault().language.ifEmpty { "en" }
        val body = fetch("https://geocoding-api.open-meteo.com/v1/search?name=${URLEncoder.encode(query, "UTF-8")}&count=8&language=$language")
        val results = JSONObject(body).optJSONArray("results") ?: return emptyList()
        return (0 until results.length()).map { i ->
            val p = results.getJSONObject(i)
            City(
                name = p.getString("name"),
                region = listOfNotNull(p.optStringOrNull("admin1"), p.optStringOrNull("country")).joinToString(", "),
                latitude = p.getDouble("latitude"),
                longitude = p.getDouble("longitude"),
            )
        }
    }

    /** Open-Meteo's forecast JSON → Forecast. Without a readable "now", every time shown would be wrong: refuse it. */
    fun decodeForecast(body: String, fetchedAt: Long = System.currentTimeMillis()): Forecast {
        val raw = JSONObject(body)
        val current = raw.getJSONObject("current")
        val now = Forecast.Now(
            time = dateTime(current.getString("time")) ?: throw IOException("Unreadable time"),
            temperature = current.getDouble("temperature_2m"),
            feelsLike = current.getDouble("apparent_temperature"),
            humidity = current.getDouble("relative_humidity_2m"),
            wind = current.getDouble("wind_speed_10m"),
            code = current.getInt("weather_code"),
            isDay = current.getInt("is_day") == 1,
            windDirection = current.optDoubleOrNull("wind_direction_10m"),
        )
        val hourly = raw.getJSONObject("hourly")
        val hourTimes = hourly.getJSONArray("time")
        val hours = (0 until hourTimes.length()).mapNotNull { i ->
            val time = dateTime(hourTimes.getString(i)) ?: return@mapNotNull null
            val t = hourly.getJSONArray("temperature_2m").doubleOrNull(i) ?: return@mapNotNull null
            Forecast.Hour(
                time = time, temperature = t,
                code = hourly.getJSONArray("weather_code").intOrNull(i) ?: 3,
                rainChance = hourly.getJSONArray("precipitation_probability").intOrNull(i) ?: 0,
                isDay = (hourly.getJSONArray("is_day").intOrNull(i) ?: 1) == 1,
            )
        }
        val daily = raw.getJSONObject("daily")
        val dayTimes = daily.getJSONArray("time")
        val days = (0 until dayTimes.length()).mapNotNull { i ->
            val date = runCatching { LocalDate.parse(dayTimes.getString(i)) }.getOrNull() ?: return@mapNotNull null
            val hi = daily.getJSONArray("temperature_2m_max").doubleOrNull(i) ?: return@mapNotNull null
            val lo = daily.getJSONArray("temperature_2m_min").doubleOrNull(i) ?: return@mapNotNull null
            Forecast.Day(
                date = date, code = daily.getJSONArray("weather_code").intOrNull(i) ?: 3, high = hi, low = lo,
                rainChance = daily.getJSONArray("precipitation_probability_max").intOrNull(i) ?: 0,
                sunrise = daily.optJSONArray("sunrise")?.stringOrNull(i)?.let(::dateTime),
                sunset = daily.optJSONArray("sunset")?.stringOrNull(i)?.let(::dateTime),
                uvIndex = daily.optJSONArray("uv_index_max")?.doubleOrNull(i),
            )
        }
        return Forecast(now, hours, days, raw.optString("timezone", "GMT"), fetchedAt)
    }

    /** "2026-10-17T14:00", the city's own wall-clock. */
    fun dateTime(text: String): LocalDateTime? = runCatching { LocalDateTime.parse(text) }.getOrNull()

    private fun httpGet(url: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 20_000
        connection.setRequestProperty("User-Agent", "TwoDegrees")
        try {
            if (connection.responseCode != 200) throw IOException("HTTP ${connection.responseCode}")
            return connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }
}

// JSON helpers

internal fun JSONObject.optStringOrNull(key: String): String? =
    if (has(key) && !isNull(key)) getString(key).takeIf { it.isNotEmpty() } else null

internal fun JSONObject.optDoubleOrNull(key: String): Double? = if (has(key) && !isNull(key)) getDouble(key) else null

internal fun JSONArray.doubleOrNull(i: Int): Double? = if (i < length() && !isNull(i)) getDouble(i) else null
internal fun JSONArray.intOrNull(i: Int): Int? = if (i < length() && !isNull(i)) getInt(i) else null
internal fun JSONArray.stringOrNull(i: Int): String? = if (i < length() && !isNull(i)) getString(i) else null

/** Saved cities and forecasts, as JSON, for the app's preferences and the widgets. */
object Codec {
    fun city(c: City): JSONObject = JSONObject()
        .put("name", c.name).put("region", c.region).put("latitude", c.latitude).put("longitude", c.longitude)

    fun city(o: JSONObject): City = City(o.getString("name"), o.optString("region"), o.getDouble("latitude"), o.getDouble("longitude"))

    fun cities(list: List<City>): String = JSONArray(list.map(::city)).toString()

    fun cities(text: String?): List<City>? = text?.let {
        runCatching { JSONArray(it).let { a -> (0 until a.length()).map { i -> city(a.getJSONObject(i)) } } }.getOrNull()
    }

    fun forecast(f: Forecast): JSONObject = JSONObject()
        .put("now", JSONObject()
            .put("time", f.now.time.toString()).put("temperature", f.now.temperature).put("feelsLike", f.now.feelsLike)
            .put("humidity", f.now.humidity).put("wind", f.now.wind).put("code", f.now.code).put("isDay", f.now.isDay)
            .put("windDirection", f.now.windDirection ?: JSONObject.NULL))
        .put("hours", JSONArray(f.hours.map {
            JSONObject().put("time", it.time.toString()).put("temperature", it.temperature).put("code", it.code)
                .put("rainChance", it.rainChance).put("isDay", it.isDay)
        }))
        .put("days", JSONArray(f.days.map {
            JSONObject().put("date", it.date.toString()).put("code", it.code).put("high", it.high).put("low", it.low)
                .put("rainChance", it.rainChance).put("sunrise", it.sunrise?.toString() ?: JSONObject.NULL)
                .put("sunset", it.sunset?.toString() ?: JSONObject.NULL).put("uvIndex", it.uvIndex ?: JSONObject.NULL)
        }))
        .put("timeZone", f.timeZone).put("fetchedAt", f.fetchedAt)

    fun forecast(o: JSONObject): Forecast? = runCatching {
        val n = o.getJSONObject("now")
        val hours = o.getJSONArray("hours")
        val days = o.getJSONArray("days")
        Forecast(
            now = Forecast.Now(
                LocalDateTime.parse(n.getString("time")), n.getDouble("temperature"), n.getDouble("feelsLike"),
                n.getDouble("humidity"), n.getDouble("wind"), n.getInt("code"), n.getBoolean("isDay"), n.optDoubleOrNull("windDirection"),
            ),
            hours = (0 until hours.length()).map { i ->
                val h = hours.getJSONObject(i)
                Forecast.Hour(LocalDateTime.parse(h.getString("time")), h.getDouble("temperature"), h.getInt("code"), h.getInt("rainChance"), h.getBoolean("isDay"))
            },
            days = (0 until days.length()).map { i ->
                val d = days.getJSONObject(i)
                Forecast.Day(
                    LocalDate.parse(d.getString("date")), d.getInt("code"), d.getDouble("high"), d.getDouble("low"), d.getInt("rainChance"),
                    d.optStringOrNull("sunrise")?.let(LocalDateTime::parse), d.optStringOrNull("sunset")?.let(LocalDateTime::parse),
                    d.optDoubleOrNull("uvIndex"),
                )
            },
            timeZone = o.optString("timeZone", "GMT"),
            fetchedAt = o.getLong("fetchedAt"),
        )
    }.getOrNull()

    fun forecasts(map: Map<String, Forecast>): String = JSONObject().apply { map.forEach { (k, v) -> put(k, forecast(v)) } }.toString()

    fun forecasts(text: String?): Map<String, Forecast> = text?.let {
        runCatching {
            val o = JSONObject(it)
            o.keys().asSequence().mapNotNull { k -> forecast(o.getJSONObject(k))?.let { f -> k to f } }.toMap()
        }.getOrNull()
    } ?: emptyMap()
}
