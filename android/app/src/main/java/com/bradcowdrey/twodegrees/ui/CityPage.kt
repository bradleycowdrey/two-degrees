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
import com.bradcowdrey.twodegrees.Speech
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
fun CityPage(city: City, state: WeatherStore.State, store: WeatherStore, scrollTo: String?, bottomInset: Dp) {
    val ui = LocalMetrics.current
    val forecast = state.forecasts[city.id]
    val list = rememberLazyListState()
    val collapsed by remember { derivedStateOf { list.firstVisibleItemIndex > 0 || list.firstVisibleItemScrollOffset > 420 } }

    LaunchedEffect(scrollTo, forecast != null) {
        if (scrollTo != null && forecast != null && city.id == state.activeID) {
            delay(2500)
            list.animateScrollToItem(if (scrollTo == "days") 2 else 3)
        }
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
                item { Header(city, forecast, state.unit, store, Modifier.statusBarsPadding().padding(top = ui.dp(36f), bottom = ui.dp(26f))) }
                if (forecast != null) {
                    item { HourlyCard(forecast, state.unit) }
                    item { DailyCard(forecast, state.unit) }
                    item { DetailTiles(forecast, state.unit) }
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
private fun Header(city: City, forecast: Forecast?, unit: TempUnit, store: WeatherStore, modifier: Modifier) {
    val ui = LocalMetrics.current
    val other = unit.other
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(ui.dp(2f))) {
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
private fun DailyCard(forecast: Forecast, unit: TempUnit) {
    val days = forecast.days.take(10)
    val now = forecast.now.temperature
    val low = minOf(now, days.minOfOrNull { it.low } ?: now)
    val high = maxOf(now, days.maxOfOrNull { it.high } ?: now)
    Card("${days.size}-day forecast", Icons.Filled.CalendarMonth) {
        Column {
            days.forEachIndexed { i, day ->
                HorizontalDivider(color = Color.White.copy(alpha = 0.2f))
                DailyRow(if (i == 0) day.including(now) else day, i == 0, low, high, if (i == 0) now else null, unit)
            }
        }
    }
}

@Composable
private fun DailyRow(day: Forecast.Day, isToday: Boolean, scaleLow: Double, scaleHigh: Double, now: Double?, unit: TempUnit) {
    val ui = LocalMetrics.current
    val name = if (isToday) "Today" else Forecast.weekday(day.date)
    Row(
        Modifier.fillMaxWidth().heightIn(min = ui.dp(48f)).semantics(mergeDescendants = true) {
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
private fun DetailTiles(forecast: Forecast, unit: TempUnit) {
    val ui = LocalMetrics.current
    val now = forecast.now
    val other = unit.other
    val today = forecast.days.firstOrNull()?.including(now.temperature)
    val dew = Meteo.dewPoint(now.temperature, now.humidity)
    val kmh = now.wind.roundHalfUp()
    val tiles = listOf<@Composable (Modifier) -> Unit>(
        { DetailTile("Feels like", unit.spaced(now.feelsLike), other.spaced(now.feelsLike), feelsNote(forecast), it) },
        { DetailTile("Humidity", "${now.humidity.roundHalfUp()}%", null, "The dew point is ${unit.spaced(dew)} · ${other.spaced(dew)} right now.", it) },
        {
            DetailTile(
                "Wind",
                if (unit == TempUnit.FAHRENHEIT) "${Meteo.mph(now.wind)} mph" else "$kmh km/h",
                if (unit == TempUnit.FAHRENHEIT) "$kmh km/h" else "${Meteo.mph(now.wind)} mph",
                windNote(forecast), it,
            )
        },
        { DetailTile("Rain", "${today?.rainChance ?: 0}%", "chance today", Summary.rainNote(forecast), it) },
        { mod ->
            val sunset = today?.sunset
            if (sunset != null && now.time < sunset) {
                DetailTile("Sunset", Forecast.clock(sunset), null, "Sunrise: ${today?.sunrise?.let(Forecast::clock) ?: "–"}", mod)
            } else {
                val tomorrow = forecast.days.getOrNull(1)
                DetailTile("Sunrise", tomorrow?.sunrise?.let(Forecast::clock) ?: "–", null, "Sunset: ${tomorrow?.sunset?.let(Forecast::clock) ?: "–"}", mod)
            }
        },
        { mod ->
            val uv = today?.uvIndex
            if (uv != null) DetailTile("UV index", "${uv.roundHalfUp()}", Meteo.uvLevel(uv),
                if (uv >= 3) "Use sun protection around midday." else "Low for the rest of the day.", mod)
            else DetailTile("UV index", "–", null, "Pull down to refresh.", mod)
        },
    )
    Column(verticalArrangement = Arrangement.spacedBy(ui.dp(10f))) {
        tiles.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(ui.dp(10f))) {
                row.forEach { tile -> tile(Modifier.weight(1f)) }
            }
        }
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
private fun DetailTile(title: String, value: String, sub: String?, note: String, modifier: Modifier) {
    val ui = LocalMetrics.current
    Column(
        modifier.heightIn(min = ui.dp(160f)).clip(RoundedCornerShape(ui.dp(16f))).background(Palette.card)
            .border(1.dp, Palette.cardStroke, RoundedCornerShape(ui.dp(16f))).padding(ui.dp(14f))
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(ui.dp(4f)),
    ) {
        Text(title.uppercase(), style = ui.text(12f, FontWeight.SemiBold), modifier = Modifier.alpha(0.6f))
        Text(value, style = ui.text(30f, FontWeight.Medium), maxLines = 1, modifier = Modifier.padding(top = ui.dp(4f)))
        if (sub != null) Text(sub, style = ui.text(15f), modifier = Modifier.alpha(0.7f), maxLines = 1)
        Spacer(Modifier.weight(1f, fill = false).height(ui.dp(4f)))
        Text(note, style = ui.text(13f), modifier = Modifier.alpha(0.85f))
    }
}

@Composable
private fun Footer(city: City, forecast: Forecast, offline: Boolean) {
    val ui = LocalMetrics.current
    val uri = LocalUriHandler.current
    val time = java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT).format(java.util.Date(forecast.fetchedAt))
    Column(Modifier.fillMaxWidth().padding(top = 8.dp).alpha(0.6f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row {
            Text("Weather for ${city.name} · ", style = ui.text(13f))
            Text("Open-Meteo", style = ui.text(13f).copy(textDecoration = TextDecoration.Underline), modifier = Modifier.clickable { uri.openUri(Brand.DATA_CREDIT) })
        }
        Text(if (offline) "Offline · from $time" else "Updated $time", style = ui.text(13f))
        Text("Made by ${Brand.AUTHOR}. Free. Forever.", style = ui.text(13f), modifier = Modifier.clickable { uri.openUri(Brand.WEBSITE) })
    }
}
