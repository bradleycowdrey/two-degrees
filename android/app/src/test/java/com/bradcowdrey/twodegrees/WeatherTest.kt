package com.bradcowdrey.twodegrees

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime

/** The 0.5 weather features' pure logic: the same rules as the Mac, iPhone and web apps. */
class WeatherTest {
    private val newYork = City("New York", "New York, United States", 40.7128, -74.006)
    private val london = City("London", "England, United Kingdom", 51.5072, -0.1276)

    @Test fun airQualityCategoriesOnBothScales() {
        val us = Air.Scale.US
        assertEquals("Good", Air.category(0.0, us))
        assertEquals("Good", Air.category(50.0, us))
        assertEquals("Moderate", Air.category(51.0, us))
        assertEquals("Unhealthy for Sensitive Groups", Air.category(150.0, us))
        assertEquals("Unhealthy", Air.category(151.0, us))
        assertEquals("Very Unhealthy", Air.category(300.0, us))
        assertEquals("Hazardous", Air.category(301.0, us))
        assertEquals("Hazardous", Air.category(900.0, us))
        val eu = Air.Scale.EUROPEAN
        assertEquals("Good", Air.category(20.0, eu))
        assertEquals("Fair", Air.category(21.0, eu))
        assertEquals("Moderate", Air.category(55.0, eu))
        assertEquals("Poor", Air.category(80.0, eu))
        assertEquals("Very Poor", Air.category(100.0, eu))
        assertEquals("Extremely Poor", Air.category(101.0, eu))
        assertEquals(Air.Scale.US, Air.scale(newYork))
        assertEquals(Air.Scale.EUROPEAN, Air.scale(london))
        assertEquals(0.0, Air.position(0.0, us), 1e-9)
        assertEquals(1.0 / 6, Air.position(50.0, us), 1e-9)
        assertEquals(1.0, Air.position(900.0, us), 1e-9)
    }

    @Test fun airQualityNotes() {
        fun air(now: Double?, before: Double?) = AirQuality(now, null, 30.0, 10.0, 20.0, 5.0, emptyMap(), before, null)
        assertEquals("Better than yesterday", Air.note(air(40.0, 60.0), Air.Scale.US))
        assertEquals("Worse than yesterday", Air.note(air(60.0, 40.0), Air.Scale.US))
        assertEquals("About the same as yesterday", Air.note(air(45.0, 40.0), Air.Scale.US))
        assertEquals("Mostly PM2.5", Air.note(air(45.0, null), Air.Scale.US))
    }

    @Test fun decodesAirQualityWithYesterdaysHour() {
        val body = """
            {"current":{"time":"2026-11-01T14:00","us_aqi":42,"european_aqi":31,"pm2_5":8.1,"pm10":12.0,"ozone":60,"nitrogen_dioxide":18,
                        "alder_pollen":null,"birch_pollen":null,"grass_pollen":null,"mugwort_pollen":null,"olive_pollen":null,"ragweed_pollen":null},
             "hourly":{"time":["2026-10-31T13:00","2026-10-31T14:00","2026-10-31T15:00"],"us_aqi":[50,55,58],"european_aqi":[30,33,34]}}
        """.trimIndent()
        val air = Air.decode(body)
        assertEquals(42.0, air.usAqi!!, 0.0)
        assertEquals(55.0, air.yesterdayUs!!, 0.0)
        assertEquals("Better than yesterday", Air.note(air, Air.Scale.US))
        assertNull("no pollen outside Europe", Pollen.summary(air))
    }

    @Test fun pollenLevels() {
        assertEquals("Low", Pollen.level(9.9))
        assertEquals("Moderate", Pollen.level(10.0))
        assertEquals("High", Pollen.level(50.0))
        assertEquals("Very High", Pollen.level(200.0))
        val air = AirQuality(null, 30.0, null, null, null, null,
            mapOf("Alder" to 2.0, "Birch" to 75.0, "Grass" to 12.0, "Mugwort" to 0.0, "Olive" to null, "Ragweed" to null), null, null)
        val s = Pollen.summary(air)!!
        assertEquals("Birch", s.type)
        assertEquals("High", s.level)
        assertEquals("Also Grass (moderate).", s.note)
    }

    @Test fun moonPhaseOnTheFirstOfNovember2026() {
        // Full moon 26 Oct 2026, last quarter 1 Nov 2026 (20:28 UTC), new moon 9 Nov: midday on the 1st
        // is just before last quarter, about 60% lit.
        val p = Moon.phase(Instant.parse("2026-11-01T12:00:00Z"))
        assertEquals("Last Quarter", p.name)
        assertTrue("about 60% lit (${p.illumination})", p.illumination in 55..66)
        assertEquals("Full Moon", Moon.phase(Instant.parse("2026-10-26T04:12:00Z")).name)
        assertEquals("New Moon", Moon.phase(Instant.parse("2000-01-06T18:14:00Z")).name)
        assertEquals(0, Moon.phase(Instant.parse("2000-01-06T18:14:00Z")).illumination)
        assertEquals("Waxing Crescent", Moon.phase(Instant.parse("2026-11-12T12:00:00Z")).name)
        assertTrue(Moon.NAMES.size == 8)
    }

    private fun forecast(
        pressures: List<Double?> = emptyList(),
        steps: List<Double> = emptyList(),
        nowPrecipitation: Double? = null,
        code: Int = 3,
    ): Forecast {
        val start = LocalDateTime.of(2026, 11, 1, 0, 0)
        val now = LocalDateTime.of(2026, 11, 1, 14, 0)
        val hours = (0 until 48).map { h ->
            Forecast.Hour(start.plusHours(h.toLong()), 10.0, code, 0, true, precipitation = 0.0, pressure = pressures.getOrNull(h))
        }
        return Forecast(
            Forecast.Now(now, 10.0, 9.0, 70.0, 10.0, code, true, 200.0, precipitation = nowPrecipitation),
            hours, emptyList(), "America/New_York", 0L,
            steps.mapIndexed { i, mm -> Forecast.Step(now.plusMinutes(15L * i), mm) },
        )
    }

    @Test fun cloudWordsAndNextMoon() {
        assertEquals("No cloud at any height.", Detail.cloudWords(0.0, 5.0, 3.0))
        assertEquals("Mostly low cloud.", Detail.cloudWords(80.0, 10.0, 0.0))
        assertEquals("Mostly high, thin cloud.", Detail.cloudWords(0.0, 10.0, 60.0))
        assertEquals("Cloud at several heights.", Detail.cloudWords(60.0, 70.0, 0.0))
        assertEquals("Full moon tomorrow.", Moon.next(Instant.parse("2000-01-20T04:40:00Z")))
        assertEquals("New moon today.", Moon.next(Instant.parse("2000-01-06T18:14:00Z")))
    }

    @Test fun tileGraphics() {
        // Cloud layers from the hour nearest now; none if a layer is missing.
        val now = LocalDateTime.of(2026, 11, 1, 14, 20)
        fun f(hours: List<Forecast.Hour>) = Forecast(Forecast.Now(now, 10.0, 9.0, 70.0, 10.0, 3, true, 200.0), hours, emptyList(), "UTC", 0L)
        val hours = listOf(
            Forecast.Hour(now.withMinute(0), 10.0, 3, 0, true, cloudLow = 10.0, cloudMid = 20.0, cloudHigh = 30.0),
            Forecast.Hour(now.withMinute(0).plusHours(1), 10.0, 3, 0, true, cloudLow = 90.0, cloudMid = 0.0, cloudHigh = 0.0),
        )
        assertEquals(Triple(10.0, 20.0, 30.0), Detail.cloudLayerValues(f(hours)))
        assertNull(Detail.cloudLayerValues(f(listOf(Forecast.Hour(now, 10.0, 3, 0, true, cloudLow = 10.0)))))

        // The sun path: 0 at sunrise and sunset, highest midway, below the horizon after dark.
        val date = LocalDate.of(2026, 11, 1)
        assertEquals(0.25, Detail.dayFraction(LocalDateTime.of(2026, 11, 1, 6, 0), date), 1e-9)
        assertEquals(1.0, Detail.dayFraction(LocalDateTime.of(2026, 11, 2, 3, 0), date), 1e-9)
        val rise = Detail.dayFraction(LocalDateTime.of(2026, 11, 1, 6, 30), date)
        val set = Detail.dayFraction(LocalDateTime.of(2026, 11, 1, 16, 50), date)
        assertEquals(0.0, Detail.sunHeight(rise, rise, set), 1e-9)
        assertEquals(0.0, Detail.sunHeight(set, rise, set), 1e-9)
        val noon = (rise + set) / 2
        assertEquals(1 - Detail.sunCurveShift(rise, set), Detail.sunHeight(noon, rise, set), 1e-9)
        assertTrue(Detail.sunHeight(noon + 0.5, rise, set) < 0)
        assertTrue(Detail.sunHeight(Detail.dayFraction(LocalDateTime.of(2026, 11, 1, 21, 0), date), rise, set) < 0)

        // The Averages scale just fits the normal and today's range (not the records), with a little room.
        val (low, high) = Detail.averagesScale(5.0, 15.0, Normals.Entry(17.8, 7.2, 27.2, 1999, -2.2, 1957))
        assertTrue(low < 5.0 && low > -2.2 && high > 17.8 && high < 27.2)
        val (low2, high2) = Detail.averagesScale(-10.0, 30.0, Normals.Entry(17.8, 7.2, null, null, null, null))
        assertTrue(low2 < -10.0 && high2 > 30.0)
    }

    @Test fun skyColour() {
        fun o(low: Double, mid: Double, high: Double) = SkyColour.outlook(low, mid, high, 0.0, 2, 24_000.0).rating
        assertEquals(SkyColour.Rating.GREAT, o(0.0, 20.0, 50.0))
        assertEquals(SkyColour.Rating.GOOD, o(20.0, 0.0, 50.0))
        assertEquals(SkyColour.Rating.FAIR, o(0.0, 0.0, 0.0))
        assertEquals(SkyColour.Rating.FAIR, o(0.0, 95.0, 95.0))
        assertEquals(SkyColour.Rating.POOR, o(80.0, 30.0, 30.0))
        assertEquals(SkyColour.Rating.POOR, SkyColour.outlook(0.0, 40.0, 40.0, 1.2, 61, null).rating)
        assertEquals("Fog will likely hide it.", SkyColour.outlook(0.0, 40.0, 40.0, 0.0, 45, 400.0).reason)
        assertEquals(SkyColour.Rating.GOOD, SkyColour.outlook(0.0, 40.0, 40.0, 0.0, 2, 3000.0).rating)
    }

    @Test fun nextTwoHoursSentence() {
        val clock = { t: LocalDateTime -> "%d:%02d".format(t.hour, t.minute) }
        assertEquals("", NextHours.sentence(forecast(steps = List(8) { 0.0 }), clock))
        assertTrue(!NextHours.shows(forecast(steps = List(8) { 0.05 })))
        assertEquals("Rain starting around 14:30", NextHours.sentence(forecast(steps = listOf(0.0, 0.0, 0.3, 0.5, 0.4, 0.2, 0.3, 0.1)), clock))
        assertEquals("Rain stopping around 14:45", NextHours.sentence(forecast(steps = listOf(0.4, 0.3, 0.2, 0.0, 0.0, 0.0, 0.0, 0.0)), clock))
        assertEquals("Rain for the next two hours", NextHours.sentence(forecast(steps = List(8) { 0.5 }), clock))
        assertEquals("Light rain on and off", NextHours.sentence(forecast(steps = listOf(0.2, 0.0, 0.2, 0.0, 0.0, 0.3, 0.0, 0.0)), clock))
        assertEquals("Snow for the next two hours", NextHours.sentence(forecast(steps = List(8) { 0.5 }, code = 73), clock))
        assertTrue(NextHours.shows(forecast(steps = listOf(0.0, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0))))
    }

    @Test fun rainStartingSoon() {
        val soon = NextHours.startingSoon(forecast(steps = listOf(0.0, 0.0, 0.3, 0.5, 0.0, 0.0, 0.0, 0.0)))
        assertEquals(LocalDateTime.of(2026, 11, 1, 14, 30), soon?.first)
        assertEquals(false, soon?.second)
        assertNull("already raining", NextHours.startingSoon(forecast(steps = listOf(0.3, 0.3, 0.3, 0.0, 0.0, 0.0, 0.0, 0.0))))
        assertNull("raining now", NextHours.startingSoon(forecast(steps = listOf(0.0, 0.3, 0.3, 0.0, 0.0, 0.0, 0.0, 0.0), nowPrecipitation = 0.4)))
        assertNull("too light", NextHours.startingSoon(forecast(steps = listOf(0.0, 0.1, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0))))
        assertNull("later than 30 minutes", NextHours.startingSoon(forecast(steps = listOf(0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0))))
        assertEquals(true, NextHours.startingSoon(forecast(steps = listOf(0.0, 0.4, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0), code = 71))?.second)
    }

    @Test fun normalsAndRecordsFromAnArchive() {
        // Every year 1940–2025 on Nov 1 ±4 days: high 15 + (year − 2000) / 10, low 5, except two records.
        val days = mutableListOf<Triple<LocalDate, Double?, Double?>>()
        for (year in 1940..2025) {
            for (d in -4..4) {
                val date = LocalDate.of(year, 11, 1).plusDays(d.toLong())
                var hi = 15.0 + (year - 2000) / 10.0
                var lo = 5.0
                if (year == 1999 && d == 0) hi = 27.0
                if (year == 1957 && d == 0) lo = -2.0
                if (year == 1960 && d == 0) lo = -2.0   // a tie: the first year keeps it
                days += Triple(date, hi, lo)
            }
        }
        days += Triple(LocalDate.of(2024, 2, 29), 12.0, null)
        val n = Normals.build(days, fetchedAt = 1L)
        assertEquals(366, n.entries.size)
        val nov1 = n.of(LocalDate.of(2026, 11, 1))!!
        // 1991–2020 within ±3 days: the mean of 15 + (y − 2000)/10 is 15.55, plus 1999's record day in the window.
        val expected = 15.55 + (27.0 - 14.9) / (30 * 7)
        assertEquals(expected, nov1.normalHigh!!, 1e-9)
        assertEquals(5.0, nov1.normalLow!!, 1e-9)
        assertEquals(27.0, nov1.recordHigh!!, 0.0)
        assertEquals(1999, nov1.recordHighYear)
        assertEquals(-2.0, nov1.recordLow!!, 0.0)
        assertEquals(1957, nov1.recordLowYear)
        assertEquals(12.0, n.of(LocalDate.of(2028, 2, 29))!!.recordHigh!!, 0.0)
        assertNull(n.of(LocalDate.of(2026, 6, 1)))
        val back = Normals.decode(Normals.encode(n))!!
        assertEquals(1957, back.of(LocalDate.of(2026, 11, 1))!!.recordLowYear)
        assertEquals(nov1.normalHigh!!, back.of(LocalDate.of(2026, 11, 1))!!.normalHigh!!, 0.05)

        assertEquals("4° above normal", Normals.versus(19.5, 17.0, TempUnit.FAHRENHEIT))   // 67 °F against 63 °F
        assertEquals("About normal", Normals.versus(17.4, 17.0, TempUnit.CELSIUS))
        assertEquals("3° below normal", Normals.versus(14.0, 17.0, TempUnit.CELSIUS))
        val e = Normals.Entry(17.8, 7.2, 27.2, 1999, -2.2, 1957)
        assertEquals("Normal high 64 ° F · 18 ° C, low 45 ° F · 7 ° C", Normals.normalLine(e, TempUnit.FAHRENHEIT)?.replace('\u200A', ' '))
        assertEquals("Record high 81 ° F · 27 ° C (1999) · Record low 28 ° F · -2 ° C (1957)", Normals.recordsLine(e, TempUnit.FAHRENHEIT)?.replace('\u200A', ' '))
    }

    @Test fun decodesAnArchiveResponse() {
        val body = """{"daily":{"time":["1995-03-01","1996-03-01","2001-03-01"],"temperature_2m_max":[10.0,12.0,null],"temperature_2m_min":[1.0,null,-4.0]}}"""
        val e = Normals.decodeArchive(body).of(LocalDate.of(2026, 3, 1))!!
        assertEquals(11.0, e.normalHigh!!, 1e-9)
        assertEquals(-1.5, e.normalLow!!, 1e-9)
        assertEquals(1996, e.recordHighYear)
        assertEquals(-4.0, e.recordLow!!, 0.0)
    }

    @Test fun parsesNWSAlerts() {
        val body = """
            {"type":"FeatureCollection","features":[
              {"id":"https://api.weather.gov/alerts/a","properties":{"id":"urn:a","event":"Wind Advisory","severity":"Moderate","urgency":"Expected",
                "headline":"Wind Advisory issued November 1","description":"Gusts to 50 mph.","instruction":null,
                "effective":"2026-11-01T09:00:00-05:00","expires":"2026-11-01T18:15:00-05:00","senderName":"NWS New York NY"}},
              {"id":"https://api.weather.gov/alerts/b","properties":{"id":"urn:b","event":"Tornado Warning","severity":"Extreme","urgency":"Immediate",
                "headline":"Tornado Warning","description":"Take cover.","instruction":"Go to a basement.",
                "effective":"2026-11-01T13:00:00-05:00","expires":"2026-11-01T14:30:00-05:00","senderName":"NWS New York NY"}},
              {"id":"https://api.weather.gov/alerts/c","properties":{"id":"urn:c","event":"Frost Advisory","severity":"Minor",
                "effective":"2026-10-31T01:00:00-05:00","expires":"2026-10-31T09:00:00-05:00","senderName":"NWS New York NY"}}
            ]}
        """.trimIndent()
        val alerts = Alerts.parse(body, now = Instant.parse("2026-11-01T18:00:00Z"))
        assertEquals(listOf("Tornado Warning", "Wind Advisory"), alerts.map { it.event })   // expired one dropped, most severe first
        assertEquals("Go to a basement.", alerts[0].instruction)
        assertNull(alerts[1].instruction)
        assertTrue(alerts.all(Alerts::notifies))
        val clock = { t: LocalDateTime -> "%d:%02d".format(t.hour, t.minute) }
        assertEquals("Until 18:15", Alerts.until(alerts[1], "America/New_York", LocalDate.of(2026, 11, 1), clock))
        assertEquals("Until 17:15", Alerts.until(alerts[1], "America/Chicago", LocalDate.of(2026, 11, 1), clock))
        assertTrue(Alerts.parse("""{"features":[]}""").isEmpty())
        assertEquals("https://api.weather.gov/alerts/active?point=40.71,-74.01", Alerts.url(newYork))
        assertNull("only in the US", Alerts.url(london))
        assertEquals(emptyList<Alert>(), Alerts.fetch(london))
    }

    @Test fun unitConversions() {
        val f = Units(TempUnit.FAHRENHEIT)
        val c = Units(TempUnit.CELSIUS)
        assertEquals("mph", f.wind.symbol)
        assertEquals("km/h", c.wind.symbol)
        assertEquals("31 mph" to "50 km/h", f.wind(50.0))
        assertEquals("50 km/h" to "31 mph", c.wind(50.0))
        assertEquals("14 m/s" to null, Units(TempUnit.FAHRENHEIT, windChoice = WindUnit.MS).wind(50.0))
        assertEquals("27 kn" to null, c.copy(windChoice = WindUnit.KN).wind(50.0))
        assertEquals("0.10 in" to "2.5 mm", f.rain(2.5))
        assertEquals("2.5 mm" to "0.10 in", c.rain(2.5))
        assertEquals("12 mm", c.rain.text(12.3))
        assertEquals("0 mm", c.rain.text(0.0))
        assertEquals("16 km", c.visibility(16_000.0))
        assertEquals("9.9 mi", f.visibility(16_000.0))
        assertEquals("1.5 km", c.visibility(1_500.0))
        assertEquals("9.9 mi", c.visibilityOther(16_000.0))
        assertEquals("8 mi", f.visibility(12_875.0))
        assertEquals("13 km", f.visibilityOther(12_875.0))
        assertEquals("1,600 ft", f.visibility(490.0))
        assertEquals("490 m", f.visibilityOther(490.0))
        assertEquals(WindUnit.KN, WindUnit.of("kn"))
        assertEquals(RainUnit.AUTO, RainUnit.of(null))
    }

    @Test fun detailWords() {
        assertEquals("Clear", Detail.cloudWord(10.0))
        assertEquals("Mostly clear", Detail.cloudWord(30.0))
        assertEquals("Partly cloudy", Detail.cloudWord(31.0))
        assertEquals("Mostly cloudy", Detail.cloudWord(62.0))
        assertEquals("Overcast", Detail.cloudWord(91.0))
        assertEquals("Clear view", Detail.visibilityWord(24_000.0))
        assertEquals("Haze", Detail.visibilityWord(5_000.0))
        assertEquals("Fog", Detail.visibilityWord(800.0))
        val now = Forecast.Now(LocalDateTime.of(2026, 11, 1, 14, 0), 10.0, 9.0, 70.0, 20.0, 3, true, 200.0, gusts = 56.0)
        assertEquals("Gusts to 35 mph", Detail.gustNote(now, Units(TempUnit.FAHRENHEIT)))
        assertNull(Detail.gustNote(now.copy(gusts = 29.0), Units(TempUnit.FAHRENHEIT)))
    }

    @Test fun newFieldsDecodeAndOldSavedForecastsStillLoad() {
        val body = """
            {"timezone":"America/Denver",
             "current":{"time":"2026-10-28T14:00","temperature_2m":20.4,"apparent_temperature":19.0,"relative_humidity_2m":30,
                        "weather_code":2,"wind_speed_10m":11.2,"wind_direction_10m":200,"is_day":1,"pressure_msl":1016.2,"cloud_cover":62,
                        "wind_gusts_10m":30.1,"visibility":24140,"precipitation":0.0},
             "minutely_15":{"time":["2026-10-28T14:00","2026-10-28T14:15"],"precipitation":[0.0,0.3]},
             "hourly":{"time":["2026-10-28T13:00","2026-10-28T14:00"],"temperature_2m":[19.0,20.4],"weather_code":[1,2],
                       "precipitation_probability":[0,10],"is_day":[1,1],"precipitation":[0.0,null],"wind_speed_10m":[10,11],
                       "wind_gusts_10m":[20,22],"pressure_msl":[1015,1016.2],"visibility":[24000,24140]},
             "daily":{"time":["2026-10-28"],"weather_code":[2],"temperature_2m_max":[22.0],"temperature_2m_min":[5.0],
                      "precipitation_probability_max":[10],"sunrise":["2026-10-28T07:20"],"sunset":["2026-10-28T17:55"],"uv_index_max":[3.4],
                      "precipitation_sum":[1.2],"rain_sum":[1.2],"snowfall_sum":[0],"wind_speed_10m_max":[25],"wind_gusts_10m_max":[48],
                      "wind_direction_10m_dominant":[310]}}
        """.trimIndent()
        val f = OpenMeteo.decodeForecast(body, fetchedAt = 1L)
        assertEquals(1016.2, f.now.pressure!!, 0.0)
        assertEquals(62.0, f.now.cloudCover!!, 0.0)
        assertEquals(2, f.steps.size)
        assertNull(f.hours[1].precipitation)
        assertEquals(48.0, f.days[0].gustMax!!, 0.0)
        assertEquals(f, Codec.forecast(JSONObject(Codec.forecast(f).toString())))
        // A forecast saved by 0.4 (no new fields) still loads, with them missing.
        val old = JSONObject(Codec.forecast(f).toString())
        old.remove("steps")
        old.getJSONObject("now").remove("pressure")
        old.getJSONArray("days").getJSONObject(0).remove("gustMax")
        val back = Codec.forecast(old)
        assertNotNull(back)
        assertTrue(back!!.steps.isEmpty())
        assertNull(back.now.pressure)
        assertNull(back.days[0].gustMax)
        // Without the new fields at all, decoding still works.
        val bare = OpenMeteo.decodeForecast(body.replace("\"pressure_msl\":1016.2,", "").replace(Regex("\"minutely_15\":\\{[^}]*\\},"), ""))
        assertNull(bare.now.pressure)
        assertTrue(bare.steps.isEmpty())
    }

    @Test fun usPlaces() {
        assertTrue(Region.isUS(newYork))
        assertTrue(Region.isUS(City("Denver", "Colorado, United States", 39.74, -104.98)))
        assertTrue(!Region.isUS(City("Toronto", "Ontario, Canada", 43.65, -79.38)))
        assertTrue(Region.isUS(City("My Location", "", 39.74, -104.98)))
    }

    @Test fun widgetTapCityRoundTrips() {
        val odd = City("Saint-Étienne & \"Co\" ?=/", "Auvergne-Rhône-Alpes, France", 45.4339, 4.39, isCurrent = false)
        assertEquals(odd, WidgetTap.decode(WidgetTap.encode(odd)))
        val here = City("Denver", "Colorado, United States", 39.74, -104.98, isCurrent = true)
        assertEquals(here, WidgetTap.decode(WidgetTap.encode(here)))
        // Anything missing or malformed is ignored.
        assertNull(WidgetTap.decode(null))
        assertNull(WidgetTap.decode(""))
        assertNull(WidgetTap.decode("not json"))
        assertNull(WidgetTap.decode("{\"name\":\"X\"}"))
        assertNull(WidgetTap.decode("{\"name\":\"\",\"latitude\":1,\"longitude\":2}"))
        assertNull(WidgetTap.decode("{\"name\":\"X\",\"latitude\":91,\"longitude\":2}"))
        assertNull(WidgetTap.decode("{\"name\":\"X\",\"latitude\":1,\"longitude\":\"east\"}"))
    }

    @Test fun widgetTapOpensItsCity() {
        val tokyo = City("Tokyo", "Japan", 35.6762, 139.6503)
        val here = City("Boulder", "Colorado, United States", 40.015, -105.27, isCurrent = true)
        val cities = listOf(here, newYork, london)
        fun target(city: City, list: List<City> = cities, hereID: String? = null, canAdd: Boolean = true) =
            WidgetTap.target(city, list, hereID, canAdd)

        // My Location: its card; else the saved city standing in for it; else (Use My Location off) the first city.
        assertEquals(WidgetTap.Target.Select("here"), target(here.copy(name = "Elsewhere", latitude = 1.0)))
        assertEquals(WidgetTap.Target.Select(london.id), target(here, listOf(newYork, london), hereID = london.id))
        assertEquals(WidgetTap.Target.Select(newYork.id), target(here, listOf(newYork, london)))
        // A saved city: by ID (coordinates to 2 decimals), or the same place.
        assertEquals(WidgetTap.Target.Select(london.id), target(london.copy(name = "Londres", latitude = 51.5049)))
        assertEquals(WidgetTap.Target.Select(newYork.id), target(City("New York", "NY", 40.75, -73.99)))
        // A saved city isn't matched to the My Location card, even nearby.
        assertEquals(WidgetTap.Target.Add(City("Boulder", "CO", 40.02, -105.27)), target(City("Boulder", "CO", 40.02, -105.27)))
        // A new city: added if there's room, else nothing changes.
        assertEquals(WidgetTap.Target.Add(tokyo), target(tokyo))
        assertEquals(WidgetTap.Target.Stay, target(tokyo, canAdd = false))
        assertEquals(WidgetTap.Target.Select(london.id), target(london, canAdd = false))
    }
}
