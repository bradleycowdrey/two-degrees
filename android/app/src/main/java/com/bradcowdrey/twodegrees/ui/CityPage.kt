package com.bradcowdrey.twodegrees.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.NearMe
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bradcowdrey.twodegrees.Brand
import com.bradcowdrey.twodegrees.City
import com.bradcowdrey.twodegrees.Condition
import com.bradcowdrey.twodegrees.Forecast
import com.bradcowdrey.twodegrees.Meteo
import com.bradcowdrey.twodegrees.Air
import com.bradcowdrey.twodegrees.Detail
import com.bradcowdrey.twodegrees.Moon
import com.bradcowdrey.twodegrees.NextHours
import com.bradcowdrey.twodegrees.Normals
import com.bradcowdrey.twodegrees.Pollen
import com.bradcowdrey.twodegrees.Units
import com.bradcowdrey.twodegrees.Speech
import com.bradcowdrey.twodegrees.SkyColour
import com.bradcowdrey.twodegrees.Summary
import com.bradcowdrey.twodegrees.TempUnit
import com.bradcowdrey.twodegrees.WeatherStore
import com.bradcowdrey.twodegrees.roundHalfUp
import kotlinx.coroutines.delay

/**
 * One city, after the iPhone app: a large centred reading (pinned as one line once scrolled), then
 * cards for the next 24 hours and 10 days, then detail tiles. Every temperature in both units.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CityPage(city: City, state: WeatherStore.State, store: WeatherStore, scrollTo: String?, bottomInset: Dp, onOpen: (Overlay) -> Unit = {}) {
    val ui = LocalMetrics.current
    val forecast = state.forecasts[city.id]
    val alerts = state.alerts[city.id].orEmpty()
    val nextHours = forecast != null && NextHours.shows(forecast)
    val list = rememberLazyListState()
    val collapsed by remember { derivedStateOf { list.firstVisibleItemIndex > 0 || list.firstVisibleItemScrollOffset > 420 } }

    LaunchedEffect(scrollTo, forecast != null) {
        if (scrollTo != null && forecast != null && city.id == state.activeID) {
            delay(2500)
            // Header, alerts, next 2 hours, 24 hours, days, map, tiles, more tiles.
            val days = 2 + (if (alerts.isNotEmpty()) 1 else 0) + (if (nextHours) 1 else 0)
            list.animateScrollToItem(when (scrollTo) { "days" -> days; "more" -> days + 3; else -> days + 2 })
        }
    }

    // Swiping to another city puts this one back at the top, so it starts there when you return.
    val showing = city.id == state.activeID
    LaunchedEffect(showing) {
        if (!showing && (list.firstVisibleItemIndex > 0 || list.firstVisibleItemScrollOffset > 0)) list.scrollToItem(0)
    }

    // The spinner shows only for a pull, not for the app's own refreshes.
    var pulled by remember { mutableStateOf(false) }
    LaunchedEffect(state.loading) { if (!state.loading) pulled = false }
    PullToRefreshBox(isRefreshing = pulled && state.loading, onRefresh = { pulled = true; store.refresh() }, modifier = Modifier.fillMaxSize()) {
        BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            LazyColumn(
                state = list,
                modifier = Modifier.widthIn(max = ui.dp(600f)).fillMaxSize(),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = bottomInset + 24.dp),
                verticalArrangement = Arrangement.spacedBy(ui.dp(10f)),
            ) {
                item { Header(city, state.isHere(city), forecast, state.unit, store, Modifier.statusBarsPadding().padding(top = ui.dp(36f), bottom = ui.dp(26f))) }
                if (forecast != null) {
                    if (alerts.isNotEmpty()) item { AlertCards(city, alerts, forecast, onOpen) }
                    if (nextHours) item { NextHoursCard(forecast, state.units) }
                    item { HourlyCard(forecast, state.unit) }
                    item { DailyCard(forecast, state.unit) { i -> onOpen(Overlay.Day(city.id, i)) } }
                    item { MapCard(city, onOpen) }
                    item { DetailTiles(forecast, state.units) }
                    item { MoreTiles(city, forecast, state) }
                    item { Footer(city, forecast, offline = city.id in state.failed) }
                } else {
                    item {
                        Card("Forecast", Icons.Filled.Schedule) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                if (city.id in state.failed) {
                                    Icon(Icons.Filled.WifiOff, null, tint = Color.White)
                                    Text("Couldn’t reach Open-Meteo. Pull down to try again.", style = ui.text(15f))
                                } else {
                                    CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
                                    Text("Loading the forecast for ${city.name}…", style = ui.text(15f))
                                }
                            }
                        }
                    }
                }
            }
            AnimatedVisibility(collapsed && forecast != null, enter = fadeIn(), exit = fadeOut()) {
                if (forecast != null) CompactHeader(city, forecast, state.unit)
            }
        }
    }
}

/** The big number with its unit smaller and raised, as in the widgets. */
fun reading(value: Int, unit: TempUnit) = buildAnnotatedString {
    append("$value")
    withStyle(SpanStyle(fontSize = 0.42f.em(), baselineShift = BaselineShift(0.5f), fontWeight = FontWeight.Light)) { append(unit.symbol) }
}

private fun Float.em() = androidx.compose.ui.unit.TextUnit(this, androidx.compose.ui.unit.TextUnitType.Em)

@Composable
private fun Header(city: City, isHere: Boolean, forecast: Forecast?, unit: TempUnit, store: WeatherStore, modifier: Modifier) {
    val ui = LocalMetrics.current
    val other = unit.other
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(ui.dp(2f))) {
        if (isHere) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.alpha(0.8f)) {
                Icon(Icons.Filled.NearMe, null, tint = Color.White, modifier = Modifier.size(ui.dp(13f)))
                Text("MY LOCATION", style = ui.text(13f, FontWeight.SemiBold))
            }
        }
        Text(city.name, style = ui.text(34f, align = TextAlign.Center), maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (forecast != null) {
            val now = forecast.now
            // Tap the reading to swap which unit is large.
            Row(
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(ui.dp(8f)),
                modifier = Modifier
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { store.toggleUnit() }
                    .semantics { contentDescription = Speech.temperature(now.temperature) + ". Tap to show ${other.label} large." },
            ) {
                Text(reading(unit.value(now.temperature), unit), style = ui.text(96f, FontWeight.Light).copy(letterSpacing = (-2).sp), maxLines = 1)
                Text(other.spaced(now.temperature), style = ui.text(43f, FontWeight.Light), modifier = Modifier.alpha(0.7f).padding(bottom = ui.dp(14f)), maxLines = 1)
            }
            Text(Condition.name(now.code), style = ui.text(20f, FontWeight.Medium), modifier = Modifier.alpha(0.9f))
            forecast.days.firstOrNull()?.including(now.temperature)?.let { today ->
                Text("H:${unit.value(today.high)}${unit.symbol}  L:${unit.value(today.low)}${unit.symbol}", style = ui.text(20f, FontWeight.Medium))
                Text("H:${other.value(today.high)}${other.symbol}  L:${other.value(today.low)}${other.symbol}", style = ui.text(15f), modifier = Modifier.alpha(0.65f))
            }
        } else {
            Text("––°", style = ui.text(96f, FontWeight.Light), modifier = Modifier.alpha(0.5f))
        }
    }
}

/** The reading on one line, pinned at the top once the big header has scrolled away. */
@Composable
private fun CompactHeader(city: City, forecast: Forecast, unit: TempUnit) {
    val ui = LocalMetrics.current
    val (top, _) = Sky.colors(forecast.now.code, forecast.now.isDay)
    // Solid sky behind the pinned line, fading out just below it, so the page scrolls away underneath.
    Column(Modifier.fillMaxWidth().clearAndSetSemantics {}) {
    Column(
        Modifier.fillMaxWidth().background(top).statusBarsPadding().padding(top = 6.dp, bottom = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        val now = forecast.now
        Text(city.name, style = ui.text(28f), maxLines = 1)
        Text(
            "${unit.spaced(now.temperature)} · ${unit.other.spaced(now.temperature)}  |  ${Condition.name(now.code)}",
            style = ui.text(16f, FontWeight.Medium), modifier = Modifier.alpha(0.85f), maxLines = 1,
        )
    }
    Box(Modifier.fillMaxWidth().height(14.dp).background(Brush.verticalGradient(listOf(top, top.copy(alpha = 0f)))))
    }
}

/** A frosted card with a small uppercase title, as in Apple's Weather. */
@Composable
fun Card(title: String, icon: ImageVector, content: @Composable () -> Unit) {
    val ui = LocalMetrics.current
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(ui.dp(16f))).background(Palette.card)
            .border(1.dp, Palette.cardStroke, RoundedCornerShape(ui.dp(16f))).padding(ui.dp(14f)),
        verticalArrangement = Arrangement.spacedBy(ui.dp(10f)),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.alpha(0.6f)) {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(ui.dp(14f)))
            Text(title.uppercase(), style = ui.text(12f, FontWeight.SemiBold))
        }
        content()
    }
}

@Composable
private fun HourlyCard(forecast: Forecast, unit: TempUnit) {
    val ui = LocalMetrics.current
    val other = unit.other
    Card("Next 24 hours", Icons.Filled.Schedule) {
        val summary = Summary.line(forecast, unit)
        if (summary.isNotEmpty()) {
            Text(summary, style = ui.text(15f))
            HorizontalDivider(color = Color.White.copy(alpha = 0.2f))
        }
        LazyRow {
            itemsIndexed(forecast.upcomingHours) { index, hour ->
                val t = if (index == 0) forecast.now.temperature else hour.temperature
                val label = if (index == 0) "Now" else Forecast.hour(hour.time)
                Column(
                    Modifier.width(ui.dp(62f)).semantics(mergeDescendants = true) {
                        contentDescription = "$label: ${Condition.name(hour.code)}, ${Speech.temperature(t)}"
                    },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(ui.dp(6f)),
                ) {
                    Text(label, style = ui.text(15f, FontWeight.SemiBold), maxLines = 1)
                    WeatherGlyph(if (index == 0) forecast.now.code else hour.code, hour.isDay, ui.dp(26f))
                    Text(if (hour.rainChance >= 20) "${hour.rainChance}%" else " ", style = ui.text(11f, FontWeight.SemiBold).copy(color = Palette.rain))
                    Text("${unit.value(t)}°", style = ui.text(18f, FontWeight.Medium), maxLines = 1)
                    Text(other.spaced(t), style = ui.text(13f), modifier = Modifier.alpha(0.6f), maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun DailyCard(forecast: Forecast, unit: TempUnit, onDay: (Int) -> Unit) {
    val days = forecast.days.take(10)
    val now = forecast.now.temperature
    val low = minOf(now, days.minOfOrNull { it.low } ?: now)
    val high = maxOf(now, days.maxOfOrNull { it.high } ?: now)
    Card("${days.size}-day forecast", Icons.Filled.CalendarMonth) {
        Column {
            days.forEachIndexed { i, day ->
                HorizontalDivider(color = Color.White.copy(alpha = 0.2f))
                DailyRow(if (i == 0) day.including(now) else day, i == 0, low, high, if (i == 0) now else null, unit, Modifier.clickable { onDay(i) })
            }
        }
    }
}

@Composable
private fun DailyRow(day: Forecast.Day, isToday: Boolean, scaleLow: Double, scaleHigh: Double, now: Double?, unit: TempUnit, modifier: Modifier) {
    val ui = LocalMetrics.current
    val name = if (isToday) "Today" else Forecast.weekday(day.date)
    Row(
        modifier.fillMaxWidth().heightIn(min = ui.dp(48f)).semantics(mergeDescendants = true) {
            contentDescription = "$name: ${Condition.name(day.code)}. Low ${Speech.temperature(day.low)}. High ${Speech.temperature(day.high)}." +
                if (day.rainChance >= 20) " ${day.rainChance} percent chance of rain." else ""
        },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(ui.dp(10f)),
    ) {
        Text(name, style = ui.text(18f, FontWeight.Medium), maxLines = 1, modifier = Modifier.width(ui.dp(56f)))
        Column(Modifier.width(ui.dp(36f)), horizontalAlignment = Alignment.CenterHorizontally) {
            WeatherGlyph(day.code, true, ui.dp(22f))
            if (day.rainChance >= 20) Text("${day.rainChance}%", style = ui.text(11f, FontWeight.SemiBold).copy(color = Palette.rain), maxLines = 1)
        }
        Temperature(day.low, unit, Alignment.End, Modifier.alpha(0.65f))
        DayBar(day, scaleLow, scaleHigh, now, Modifier.weight(1f))
        Temperature(day.high, unit, Alignment.Start, Modifier)
    }
}

@Composable
private fun Temperature(celsius: Double, unit: TempUnit, alignment: Alignment.Horizontal, modifier: Modifier) {
    val ui = LocalMetrics.current
    Column(modifier.width(ui.dp(50f)), horizontalAlignment = alignment) {
        Text("${unit.value(celsius)}°", style = ui.text(17f, FontWeight.Medium), maxLines = 1)
        Text(unit.other.spaced(celsius), style = ui.text(11f), modifier = Modifier.alpha(0.6f), maxLines = 1)
    }
}

/** This day's low to high on the ten days' shared scale, with a dot for right now on today. */
@Composable
private fun DayBar(day: Forecast.Day, scaleLow: Double, scaleHigh: Double, now: Double?, modifier: Modifier) {
    val ui = LocalMetrics.current
    BoxWithConstraints(modifier.height(ui.dp(20f)), contentAlignment = Alignment.CenterStart) {
        val span = maxOf(scaleHigh - scaleLow, 1.0)
        val h = ui.dp(5f)
        fun x(t: Double): Dp = maxWidth * ((t - scaleLow) / span).toFloat()
        Box(Modifier.fillMaxWidth().height(h).clip(CircleShape).background(Color.White.copy(alpha = 0.15f)))
        Box(
            Modifier.offset(x = x(day.low)).width(maxOf(x(day.high) - x(day.low), h)).height(h).clip(CircleShape)
                .background(Brush.horizontalGradient(listOf(Palette.temperature(day.low), Palette.temperature(day.high)))),
        )
        if (now != null) {
            val d = h + 3.dp
            Box(
                Modifier.offset(x = (x(now) - d / 2).coerceIn(0.dp, maxWidth - d)).size(d).clip(CircleShape)
                    .background(Color.White).border(1.5.dp, Color.Black.copy(alpha = 0.35f), CircleShape),
            )
        }
    }
}

@Composable
private fun DetailTiles(forecast: Forecast, units: Units) {
    val now = forecast.now
    val unit = units.temperature
    val other = unit.other
    val today = forecast.days.firstOrNull()?.including(now.temperature)
    val dew = Meteo.dewPoint(now.temperature, now.humidity)
    val (wind, windOther) = units.wind(now.wind)
    val tiles = listOf<@Composable (Modifier) -> Unit>(
        { DetailTile("Feels like", unit.spaced(now.feelsLike), other.spaced(now.feelsLike), feelsNote(forecast), it, accent = TileAccent.temperature(now.feelsLike)) },
        { DetailTile("Humidity", "${now.humidity.roundHalfUp()}%", null, "The dew point is ${unit.spaced(dew)} · ${other.spaced(dew)} right now.", it, accent = TileAccent.HUMIDITY) },
        { DetailTile("Wind", wind, windOther, listOfNotNull(windNote(forecast), Detail.gustNote(now, units)?.let { "$it." }).joinToString(" "), it, accent = TileAccent.WIND) { WindCompass(now.windDirection) } },
        { DetailTile("Rain", "${today?.rainChance ?: 0}%", "chance today", Summary.rainNote(forecast), it, accent = TileAccent.RAIN) },
        { mod ->
            // The next sunrise or sunset, how colourful it's likely to be, and the other one's time.
            val next = SkyColour.next(forecast)
            // Today's sun path, whichever one the tile shows.
            val day = forecast.days.firstOrNull()
            val rise = day?.sunrise
            val set = day?.sunset
            val path: @Composable (Long) -> Unit = { accent -> if (day != null && rise != null && set != null) SunPathCurve(day.date, rise, set, now.time, accent) }
            if (next != null) {
                val (isSunset, time) = next
                val outlook = SkyColour.outlook(forecast, time)
                val other = if (isSunset) forecast.days.mapNotNull { it.sunrise }.firstOrNull { it > time }
                            else forecast.days.firstOrNull { it.date == time.toLocalDate() }?.sunset
                DetailTile(if (isSunset) "Sunset" else "Sunrise", Forecast.clock(time), outlook?.rating?.line,
                    listOfNotNull(outlook?.reason, "${if (isSunset) "Sunrise" else "Sunset"} ${other?.let(Forecast::clock) ?: "–"}.").joinToString(" "), mod, accent = if (isSunset) TileAccent.SUNSET else TileAccent.SUNRISE) {
                    path(if (isSunset) TileAccent.SUNSET else TileAccent.SUNRISE)
                }
            } else {
                DetailTile("Sunset", today?.sunset?.let(Forecast::clock) ?: "–", null, "Sunrise ${today?.sunrise?.let(Forecast::clock) ?: "–"}.", mod, accent = TileAccent.SUNSET) { path(TileAccent.SUNSET) }
            }
        },
        { mod ->
            val uv = today?.uvIndex
            if (uv != null) DetailTile("UV index", "${uv.roundHalfUp()}", Meteo.uvLevel(uv),
                if (uv >= 3) "Use sun protection around midday." else "Low for the rest of the day.", mod, accent = TileAccent.uv(uv)) { UvBar(uv) }
            else DetailTile("UV index", "–", null, "Pull down to refresh.", mod, accent = TileAccent.NEUTRAL)
        },
    )
    TileGrid(tiles)
}

/** Two across, each row as tall as its taller tile; an odd one out keeps its half width. */
@Composable
private fun TileGrid(tiles: List<@Composable (Modifier) -> Unit>) {
    val ui = LocalMetrics.current
    Column(verticalArrangement = Arrangement.spacedBy(ui.dp(10f))) {
        tiles.chunked(2).forEach { row ->
            Row(Modifier.height(IntrinsicSize.Max), horizontalArrangement = Arrangement.spacedBy(ui.dp(10f))) {
                row.forEach { tile -> tile(Modifier.weight(1f).fillMaxHeight()) }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

/**
 * The tiles after the first six: air quality (with pollen where it's measured), averages, visibility,
 * precipitation, cloud cover and the moon. Every city shows all six, so every city has the same twelve
 * tiles; one whose data isn't there yet shows a dash instead of disappearing.
 */
@Composable
private fun MoreTiles(city: City, forecast: Forecast, state: WeatherStore.State) {
    val units = state.units
    val unit = units.temperature
    val now = forecast.now
    val today = forecast.days.firstOrNull()
    val missing = "Not available right now."
    val tiles = mutableListOf<@Composable (Modifier) -> Unit>()

    val air = state.air[city.id]
    val scale = Air.scale(city)
    val aqi = air?.let { Air.value(it, scale) }
    if (air != null && aqi != null) {
        val pollen = Pollen.summary(air)?.let { " Pollen: ${it.type.lowercase()} ${it.level.lowercase()}." } ?: ""
        tiles.add {
            DetailTile("Air quality", "${aqi.roundHalfUp()}", Air.category(aqi, scale), listOfNotNull(Air.note(air, scale)?.let { n -> "$n." }, pollen.trim().ifEmpty { null }).joinToString(" "), it, accent = TileAccent.air(Air.position(aqi, scale))) {
                AirScaleBar(aqi, scale)
                Text(scale.title, style = LocalMetrics.current.text(11f), modifier = Modifier.alpha(0.6f))
            }
        }
    } else {
        tiles.add { DetailTile("Air quality", "–", null, missing, it, accent = TileAccent.NEUTRAL) }
    }
    val normal = today?.let { state.normals(city)?.of(it.date) }
    if (today != null && normal?.normalHigh != null) {
        val accent = TileAccent.versusNormal(today.high - normal.normalHigh)
        tiles.add { DetailTile("Averages", Normals.versus(today.high, normal.normalHigh, unit), null, Normals.normalLine(normal, unit), it, accent = accent) { AveragesBar(today.low, today.high, normal, accent) } }
    } else {
        tiles.add { DetailTile("Averages", "–", null, missing, it, accent = TileAccent.NEUTRAL) }
    }
    val m = now.visibility
    tiles.add { if (m != null) DetailTile("Visibility", units.visibility(m), units.visibilityOther(m), Detail.visibilityWord(m), it, accent = TileAccent.VISIBILITY) else DetailTile("Visibility", "–", null, missing, it, accent = TileAccent.VISIBILITY) }
    val mm = today?.precipitationSum
    if (mm != null) {
        val (main, other) = units.rain(mm)
        val next = Detail.next24Hours(forecast)
        val note = when {
            next == null -> null
            next >= 0.05 -> "Expected in the next 24 hours: ${units.rain.text(next)}"
            else -> "None expected"
        }
        tiles.add { DetailTile("Precipitation", main, other?.let { "$it today" } ?: "today", note, it, accent = TileAccent.RAIN) }
    } else {
        tiles.add { DetailTile("Precipitation", "–", null, missing, it, accent = TileAccent.RAIN) }
    }
    val pct = now.cloudCover
    val layers = Detail.cloudLayerValues(forecast)
    tiles.add { if (pct != null) DetailTile("Cloud cover", "${pct.roundHalfUp()}%", Detail.cloudWord(pct), Detail.cloudLayers(forecast), it, accent = TileAccent.CLOUD) { if (layers != null) CloudLayerBars(layers) } else DetailTile("Cloud cover", "–", null, missing, it, accent = TileAccent.CLOUD) }
    val moon = Moon.phase(java.time.Instant.ofEpochMilli(System.currentTimeMillis()))
    val nextMoon = Moon.next(java.time.Instant.now())
    tiles.add { DetailTile("Moon", moon.name, "${moon.illumination}% lit", nextMoon, it, accent = TileAccent.MOON) { MoonDisc(moon.fraction) } }
    TileGrid(tiles)
}

/** A thin bar in the scale's colours, with a dot at the value. */
@Composable
private fun AirScaleBar(value: Double, scale: Air.Scale) {
    val ui = LocalMetrics.current
    androidx.compose.foundation.Canvas(Modifier.fillMaxWidth().height(ui.dp(10f))) {
        val h = 4.dp.toPx()
        val y = size.height / 2
        val w = size.width / scale.bands.size
        scale.bands.forEachIndexed { i, band ->
            drawRect(Color(band.color), androidx.compose.ui.geometry.Offset(i * w, y - h / 2), androidx.compose.ui.geometry.Size(w, h))
        }
        val x = (size.width * Air.position(value, scale).toFloat()).coerceIn(size.height / 2, size.width - size.height / 2)
        drawCircle(Color.White, size.height / 2, androidx.compose.ui.geometry.Offset(x, y))
        drawCircle(Color.Black.copy(alpha = 0.4f), size.height / 2, androidx.compose.ui.geometry.Offset(x, y), style = androidx.compose.ui.graphics.drawscope.Stroke(1.dp.toPx()))
    }
}

/** UV on its scale (0 to 11+), green to violet, with a dot at today's peak. */
@Composable
private fun UvBar(uv: Double) {
    val ui = LocalMetrics.current
    val colors = listOf(0xFF3EA72D, 0xFFFFF300, 0xFFF18B00, 0xFFE53210, 0xFFB567A4).map { Color(it) }
    androidx.compose.foundation.Canvas(Modifier.fillMaxWidth().padding(top = ui.dp(4f)).height(ui.dp(10f))) {
        val h = 4.dp.toPx()
        val y = size.height / 2
        drawRoundRect(androidx.compose.ui.graphics.Brush.horizontalGradient(colors), androidx.compose.ui.geometry.Offset(0f, y - h / 2),
            androidx.compose.ui.geometry.Size(size.width, h), androidx.compose.ui.geometry.CornerRadius(h / 2))
        val x = (size.width * (uv / 11).coerceIn(0.0, 1.0).toFloat()).coerceIn(size.height / 2, size.width - size.height / 2)
        drawCircle(Color.White, size.height / 2, androidx.compose.ui.geometry.Offset(x, y))
        drawCircle(Color.Black.copy(alpha = 0.4f), size.height / 2, androidx.compose.ui.geometry.Offset(x, y), style = androidx.compose.ui.graphics.drawscope.Stroke(1.dp.toPx()))
    }
}

/** A small compass with an arrow the way the wind is blowing, its tail on the side it comes from. No arrow without a direction. */
@Composable
private fun WindCompass(direction: Double?) {
    val ui = LocalMetrics.current
    val letter = ui.text(9f, FontWeight.Medium)
    Box(Modifier.fillMaxWidth().padding(top = ui.dp(4f)).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        Box(Modifier.size(ui.dp(56f))) {
            androidx.compose.foundation.Canvas(Modifier.fillMaxSize()) {
                val stroke = 1.dp.toPx()
                val r = size.minDimension / 2 - stroke
                val c = center
                drawCircle(Color.White.copy(alpha = 0.25f), r, c, style = androidx.compose.ui.graphics.drawscope.Stroke(stroke))
                // Ticks every 30°, leaving room for the letters at N, E, S and W.
                for (deg in 0 until 360 step 30) {
                    if (deg % 90 == 0) continue
                    val a = Math.toRadians(deg.toDouble())
                    val dx = kotlin.math.sin(a).toFloat()
                    val dy = -kotlin.math.cos(a).toFloat()
                    val inner = r - 4.dp.toPx()
                    drawLine(Color.White.copy(alpha = 0.35f), androidx.compose.ui.geometry.Offset(c.x + dx * inner, c.y + dy * inner),
                        androidx.compose.ui.geometry.Offset(c.x + dx * r, c.y + dy * r), stroke, androidx.compose.ui.graphics.StrokeCap.Round)
                }
                if (direction != null) {
                    // Wind direction is where it comes from; the arrow points where it's going.
                    val a = Math.toRadians(direction + 180)
                    val dx = kotlin.math.sin(a).toFloat()
                    val dy = -kotlin.math.cos(a).toFloat()
                    val len = r * 0.62f
                    val head = 6.dp.toPx()
                    val tip = androidx.compose.ui.geometry.Offset(c.x + dx * len, c.y + dy * len)
                    val tail = androidx.compose.ui.geometry.Offset(c.x - dx * len, c.y - dy * len)
                    val neck = androidx.compose.ui.geometry.Offset(tip.x - dx * head, tip.y - dy * head)
                    val accent = Color(TileAccent.WIND)
                    drawLine(accent, tail, neck, 1.5.dp.toPx(), androidx.compose.ui.graphics.StrokeCap.Round)
                    drawCircle(accent, 2.dp.toPx(), tail)
                    val half = head * 0.55f
                    drawPath(androidx.compose.ui.graphics.Path().apply {
                        moveTo(tip.x, tip.y)
                        lineTo(neck.x - dy * half, neck.y + dx * half)
                        lineTo(neck.x + dy * half, neck.y - dx * half)
                        close()
                    }, accent)
                }
            }
            val inset = Modifier.padding(ui.dp(3f)).alpha(0.55f)
            Text("N", style = letter, modifier = Modifier.align(Alignment.TopCenter).then(inset))
            Text("E", style = letter, modifier = Modifier.align(Alignment.CenterEnd).then(inset))
            Text("S", style = letter, modifier = Modifier.align(Alignment.BottomCenter).then(inset))
            Text("W", style = letter, modifier = Modifier.align(Alignment.CenterStart).then(inset))
        }
    }
}

/**
 * Today's sun path across the day, midnight to midnight: above a thin horizon between sunrise and
 * sunset, faintly below it otherwise, with a dot for the sun now.
 */
@Composable
private fun SunPathCurve(date: java.time.LocalDate, sunrise: java.time.LocalDateTime, sunset: java.time.LocalDateTime, now: java.time.LocalDateTime, accent: Long) {
    val ui = LocalMetrics.current
    val rise = Detail.dayFraction(sunrise, date)
    val set = Detail.dayFraction(sunset, date)
    val sun = Detail.dayFraction(now, date)
    androidx.compose.foundation.Canvas(Modifier.fillMaxWidth().padding(top = ui.dp(4f)).height(ui.dp(34f)).clearAndSetSemantics {}) {
        val dot = 3.5.dp.toPx()
        val pad = dot + 2.dp.toPx()
        val k = Detail.sunCurveShift(rise, set)
        // Heights run from 1 - k at the top to -1 - k at the bottom.
        fun y(h: Double) = (pad + (1 - k - h) / 2 * (size.height - 2 * pad)).toFloat()
        val horizon = y(0.0)
        val steps = 96
        val curve = androidx.compose.ui.graphics.Path()
        val fill = androidx.compose.ui.graphics.Path().apply { moveTo(0f, horizon) }
        for (s in 0..steps) {
            val x = s.toDouble() / steps
            val px = (x * size.width).toFloat()
            val py = y(Detail.sunHeight(x, rise, set))
            if (s == 0) curve.moveTo(px, py) else curve.lineTo(px, py)
            fill.lineTo(px, py)
        }
        fill.lineTo(size.width, horizon)
        fill.close()
        val line = androidx.compose.ui.graphics.drawscope.Stroke(1.5.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round)
        val color = Color(accent)
        // Below the horizon: faint white.
        clipRect(top = horizon) { drawPath(curve, Color.White.copy(alpha = 0.2f), style = line) }
        // Above it: the accent, with a soft fill down to the horizon.
        clipRect(bottom = horizon) {
            drawPath(fill, color.copy(alpha = 0.12f))
            drawPath(curve, color.copy(alpha = 0.6f), style = line)
        }
        drawLine(Color.White.copy(alpha = 0.3f), androidx.compose.ui.geometry.Offset(0f, horizon), androidx.compose.ui.geometry.Offset(size.width, horizon), 1.dp.toPx())
        val at = androidx.compose.ui.geometry.Offset((sun * size.width).toFloat().coerceIn(dot, size.width - dot), y(Detail.sunHeight(sun, rise, set)))
        if (sun in rise..set) {
            drawCircle(color.copy(alpha = 0.25f), dot * 2, at)
            drawCircle(color, dot, at)
        } else {
            drawCircle(Color.White.copy(alpha = 0.35f), dot, at)
        }
    }
}

/** Today's low to high (accent) over the normal low to high (muted), on one scale out to the records. */
@Composable
private fun AveragesBar(todayLow: Double, todayHigh: Double, normal: Normals.Entry, accent: Long) {
    val ui = LocalMetrics.current
    val (low, high) = Detail.averagesScale(todayLow, todayHigh, normal)
    androidx.compose.foundation.Canvas(Modifier.fillMaxWidth().padding(top = ui.dp(6f)).height(ui.dp(10f)).clearAndSetSemantics {}) {
        val y = size.height / 2
        fun x(c: Double) = (size.width * ((c - low) / (high - low))).toFloat()
        fun band(from: Double, to: Double, h: Float, color: Color) {
            val start = x(from)
            drawRoundRect(color, androidx.compose.ui.geometry.Offset(start, y - h / 2),
                androidx.compose.ui.geometry.Size(maxOf(x(to) - start, h), h), androidx.compose.ui.geometry.CornerRadius(h / 2))
        }
        band(low, high, 3.dp.toPx(), Color.White.copy(alpha = 0.08f))
        val nLow = normal.normalLow
        val nHigh = normal.normalHigh
        if (nLow != null && nHigh != null) band(nLow, nHigh, 7.dp.toPx(), Color.White.copy(alpha = 0.22f))
        band(todayLow, todayHigh, 5.dp.toPx(), Color(accent))
    }
}

/** High, mid and low cloud, top to bottom, each filled to its %. */
@Composable
private fun CloudLayerBars(layers: Triple<Double, Double, Double>) {
    val ui = LocalMetrics.current
    val (low, mid, high) = layers
    Column(Modifier.fillMaxWidth().padding(top = ui.dp(4f)).clearAndSetSemantics {}, verticalArrangement = Arrangement.spacedBy(ui.dp(2f))) {
        listOf("High" to high, "Mid" to mid, "Low" to low).forEach { (label, pct) ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(label, style = ui.text(10f), maxLines = 1, softWrap = false, modifier = Modifier.widthIn(min = ui.dp(30f)).alpha(0.7f))
                androidx.compose.foundation.Canvas(Modifier.weight(1f).height(ui.dp(4f))) {
                    val h = size.height
                    val corner = androidx.compose.ui.geometry.CornerRadius(h / 2)
                    drawRoundRect(Color.White.copy(alpha = 0.12f), size = size, cornerRadius = corner)
                    val w = (size.width * (pct / 100).coerceIn(0.0, 1.0)).toFloat()
                    if (w > 0f) drawRoundRect(Color(TileAccent.CLOUD), size = androidx.compose.ui.geometry.Size(maxOf(w, h), h), cornerRadius = corner)
                }
            }
        }
    }
}

/** The moon's lit part: 0 new, 0.5 full; waxing lit on the right, as seen from the north. */
@Composable
private fun MoonDisc(fraction: Double) {
    val ui = LocalMetrics.current
    androidx.compose.foundation.Canvas(Modifier.padding(top = ui.dp(4f)).size(ui.dp(30f))) {
        val r = size.minDimension / 2
        val c = center
        drawCircle(Color.White.copy(alpha = 0.15f), r, c)
        // The terminator is an ellipse whose width follows the phase.
        val k = kotlin.math.cos(2 * Math.PI * fraction).toFloat()   // 1 new, -1 full
        val waxing = fraction < 0.5
        val path = androidx.compose.ui.graphics.Path().apply {
            val steps = 48
            for (s in 0..steps) {
                val a = Math.PI * s / steps - Math.PI / 2   // top to bottom
                val y = c.y + r * kotlin.math.sin(a).toFloat()
                val edge = r * kotlin.math.cos(a).toFloat()
                val x = if (waxing) c.x + edge else c.x - edge
                if (s == 0) moveTo(x, y) else lineTo(x, y)
            }
            for (s in steps downTo 0) {
                val a = Math.PI * s / steps - Math.PI / 2
                val y = c.y + r * kotlin.math.sin(a).toFloat()
                val edge = r * kotlin.math.cos(a).toFloat() * k
                val x = if (waxing) c.x + edge else c.x - edge
                lineTo(x, y)
            }
            close()
        }
        drawPath(path, Color(0xFFF3EEDF))
    }
}

private fun feelsNote(forecast: Forecast): String {
    val now = forecast.now
    val difference = now.feelsLike - now.temperature
    return when {
        difference <= -1.5 -> if (now.wind >= 15) "Wind is making it feel cooler." else "It feels cooler than it is."
        difference >= 1.5 -> "Humidity is making it feel warmer."
        else -> "Similar to the actual temperature."
    }
}

private fun windNote(forecast: Forecast): String {
    val now = forecast.now
    val strength = when {
        now.wind < 2 -> return "Calm."
        now.wind < 12 -> "A light breeze"
        now.wind < 29 -> "A moderate breeze"
        now.wind < 50 -> "A strong breeze"
        else -> "Gale-force wind"
    }
    return now.windDirection?.let { "$strength from the ${Meteo.compassName(it)}." } ?: "$strength."
}

@Composable
private fun DetailTile(title: String, value: String, sub: String?, note: String?, modifier: Modifier, accent: Long = TileAccent.NEUTRAL, extra: @Composable () -> Unit = {}) {
    val ui = LocalMetrics.current
    // A reading in words ("Waxing Gibbous · 78%", "4° above normal") is set smaller, on up to two lines.
    val words = value.length > 7
    Column(
        modifier.heightIn(min = ui.dp(160f)).clip(RoundedCornerShape(ui.dp(16f))).background(Palette.card)
            // The tile's own colour (TileAccent), as a faint glow at the top.
            .background(androidx.compose.ui.graphics.Brush.verticalGradient(0f to Color(accent).copy(alpha = 0.16f), 0.5f to Color(accent).copy(alpha = 0f)))
            .border(1.dp, Palette.cardStroke, RoundedCornerShape(ui.dp(16f))).padding(ui.dp(14f))
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(ui.dp(4f)),
    ) {
        Text(title.uppercase(), style = ui.text(12f, FontWeight.SemiBold).copy(color = Color(accent)), modifier = Modifier.alpha(0.9f))
        Text(value, style = ui.text(if (words) 21f else 30f, FontWeight.Medium), maxLines = if (words) 2 else 1, modifier = Modifier.padding(top = ui.dp(4f)))
        if (sub != null) Text(sub, style = ui.text(15f), modifier = Modifier.alpha(0.7f), maxLines = 2)
        extra()
        Spacer(Modifier.weight(1f, fill = false).height(ui.dp(4f)))
        if (!note.isNullOrEmpty()) Text(note, style = ui.text(13f), modifier = Modifier.alpha(0.85f))
    }
}

@Composable
private fun Footer(city: City, forecast: Forecast, offline: Boolean) = AppFooter("Weather for ${city.name}", forecast.fetchedAt, offline)

/**
 * The footer every screen ends with, in one style: where the weather comes from (linked), when it was
 * updated (or that it's offline), and the sign-off. [lead] is null on the city list, which credits the
 * city search too.
 */
@Composable
fun AppFooter(lead: String?, fetchedAt: Long?, offline: Boolean) {
    val ui = LocalMetrics.current
    val uri = LocalUriHandler.current
    val link = ui.text(13f).copy(textDecoration = TextDecoration.Underline)
    Column(Modifier.fillMaxWidth().padding(top = 8.dp).alpha(0.6f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row {
            if (lead != null) {
                Text("$lead · ", style = ui.text(13f))
                Text("Open-Meteo", style = link, modifier = Modifier.clickable { uri.openUri(Brand.DATA_CREDIT) })
            } else {
                Text("Weather by ", style = ui.text(13f))
                Text("Open-Meteo", style = link, modifier = Modifier.clickable { uri.openUri(Brand.DATA_CREDIT) })
                Text(" · Places by ", style = ui.text(13f))
                Text("GeoNames", style = link, modifier = Modifier.clickable { uri.openUri("https://www.geonames.org") })
            }
        }
        if (fetchedAt != null) {
            val time = java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT).format(java.util.Date(fetchedAt))
            Text(if (offline) "Offline · from $time" else "Updated $time", style = ui.text(13f))
        }
        Text("Made by ${Brand.AUTHOR}. Free. Forever.", style = ui.text(13f), modifier = Modifier.clickable { uri.openUri(Brand.WEBSITE) })
    }
}

/**
 * One quiet accent colour per detail tile, on its title and as a faint glow at the top. Some follow
 * the reading (how warm it feels, the UV level, the air quality, today against normal); the rest are
 * fixed. The same colours as the iPhone (TileAccent in Palette.swift) and the web.
 */
object TileAccent {
    const val HUMIDITY = 0xFF6FC8D6; const val WIND = 0xFF9EDCC2; const val RAIN = 0xFF8DB4E2
    const val SUNRISE = 0xFFF2C66D; const val SUNSET = 0xFFF39A72; const val VISIBILITY = 0xFFB4D2F0
    const val CLOUD = 0xFFB9C3CF; const val MOON = 0xFFEFE3CC; const val NEUTRAL = 0xFFC9C2B8

    /** Blue when cold, green when mild, gold when warm, coral when hot (°C). */
    fun temperature(c: Double): Long = if (c < 5) 0xFF8CC0F5 else if (c < 18) 0xFF9AD3A8 else if (c < 27) 0xFFF2C66D else 0xFFF28B62
    fun uv(uv: Double): Long = if (uv < 3) 0xFF6CC24A else if (uv < 6) 0xFFE8D44D else if (uv < 8) 0xFFF0A04B else if (uv < 11) 0xFFE5604A else 0xFFB57BD0
    fun air(position: Double): Long = if (position < 0.17) 0xFF6CC24A else if (position < 0.34) 0xFFE8D44D else if (position < 0.5) 0xFFF0A04B else if (position < 0.67) 0xFFE5604A else 0xFFB57BD0
    fun versusNormal(difference: Double): Long = if (difference >= 1.5) 0xFFF2A65A else if (difference <= -1.5) 0xFF8CC0F5 else NEUTRAL
}
