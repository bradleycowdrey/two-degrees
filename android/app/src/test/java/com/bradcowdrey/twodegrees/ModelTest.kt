package com.bradcowdrey.twodegrees

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class ModelTest {
    @Test fun unitsRoundLikeTheOtherApps() {
        assertEquals(72, TempUnit.FAHRENHEIT.value(22.2))
        assertEquals(23, TempUnit.CELSIUS.value(22.5))
        assertEquals(-3, TempUnit.CELSIUS.value(-2.5))
        assertEquals("18 ° C", TempUnit.CELSIUS.spaced(18.0))
        assertEquals("°F", TempUnit.FAHRENHEIT.label)
        assertEquals(TempUnit.FAHRENHEIT, TempUnit.localeDefault(Locale.US))
        assertEquals(TempUnit.CELSIUS, TempUnit.localeDefault(Locale.UK))
    }

    @Test fun cityIDsMatchTheIPhone() {
        assertEquals("39.74,-104.98", City("Denver", "Colorado, United States", 39.7392, -104.9847).id)
    }

    @Test fun weatherTerms() {
        assertEquals("NW", Meteo.compass(315.0))
        assertEquals("north", Meteo.compassName(359.0))
        assertEquals("Very high", Meteo.uvLevel(9.0))
        assertEquals(10.0, Meteo.dewPoint(20.0, 52.5), 0.3)
        assertEquals("Thunderstorms with Hail", Condition.name(99))
    }

    private val body = """
        {"timezone":"America/Denver",
         "current":{"time":"2026-10-28T14:00","temperature_2m":20.4,"apparent_temperature":19.0,"relative_humidity_2m":30,
                    "weather_code":2,"wind_speed_10m":11.2,"wind_direction_10m":200,"is_day":1},
         "hourly":{"time":["2026-10-28T13:00","2026-10-28T14:00","2026-10-28T15:00"],"temperature_2m":[19.0,20.4,null],
                   "weather_code":[1,2,3],"precipitation_probability":[0,10,60],"is_day":[1,1,1]},
         "daily":{"time":["2026-10-28","2026-10-29"],"weather_code":[2,61],"temperature_2m_max":[22.0,15.0],"temperature_2m_min":[5.0,3.0],
                  "precipitation_probability_max":[10,70],"sunrise":["2026-10-28T07:20","2026-10-29T07:21"],
                  "sunset":["2026-10-28T17:55",null],"uv_index_max":[3.4,null]}}
    """.trimIndent()

    @Test fun decodesOpenMeteoAndSkipsGaps() {
        val f = OpenMeteo.decodeForecast(body, fetchedAt = 1L)
        assertEquals(2, f.now.code)
        assertEquals(2, f.hours.size)   // the hour with no temperature is dropped
        assertEquals(1, f.upcomingHours.size)   // from the current hour on
        assertEquals(2, f.days.size)
        assertNull(f.days[1].sunset)
        assertNull(f.days[1].uvIndex)
        assertEquals(f, Codec.forecast(JSONObject(Codec.forecast(f).toString())))
    }

    @Test fun refusesAnUnreadableNow() {
        val broken = body.replace("2026-10-28T14:00\",\"temperature", "soon\",\"temperature")
        assertTrue(runCatching { OpenMeteo.decodeForecast(broken) }.isFailure)
    }

    @Test fun savedCitiesReadBack() {
        val cities = WeatherStore.STARTER_CITIES
        assertEquals(cities, Codec.cities(Codec.cities(cities)))
        assertNull(Codec.cities("not json"))
    }
}

class OfflineCitiesTest {
    private val list = OfflineCities.parse(
        listOf(
            "Portland\t\tOregon\tUS\t45.5234\t-122.6762",
            "Zürich\tZurich\tZurich\tCH\t47.3667\t8.5500",
            "Portland\t\tMaine\tUS\t43.6615\t-70.2553",
            "Portsmouth\t\tEngland\tGB\t50.7987\t-1.0911",
            "Port Louis\t\tPort Louis\tMU\t-20.1619\t57.4989",
        ).joinToString("\n"),
        Locale.US,
    )

    @Test fun exactNamesFirstThenMostPopulous() {
        assertEquals(listOf("Portland", "Portland", "Portsmouth", "Port Louis"), OfflineCities.search("port", list).map { it.name })
        assertEquals("England, United Kingdom", OfflineCities.search("Portsmouth", list).first().region)
        assertEquals(2, OfflineCities.search("portland", list).size)
    }

    @Test fun ignoresAccentsAndNarrowsAfterAComma() {
        assertEquals("Zürich", OfflineCities.search("zur", list).first().name)
        assertEquals("Zurich, Switzerland", OfflineCities.search("Zurich", list).first().region)
        assertEquals(listOf("Maine, United States"), OfflineCities.search("Portland, maine", list).map { it.region })
        assertTrue(OfflineCities.search("  ", list).isEmpty())
        assertTrue(OfflineCities.search("Atlantis", list).isEmpty())
    }

    @Test fun searchFallsBackOfflineWhenTheNetworkFails() {
        val saved = OpenMeteo.fetch
        OpenMeteo.fetch = { throw java.io.IOException("offline") }
        OfflineCities.source = { "Denver\t\tColorado\tUS\t39.7392\t-104.9847" }
        try {
            assertEquals("Denver", OpenMeteo.search("Denv").first().name)
        } finally {
            OpenMeteo.fetch = saved
        }
    }
}
