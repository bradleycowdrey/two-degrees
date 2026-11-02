package com.bradcowdrey.twodegrees.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Air
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.bradcowdrey.twodegrees.City
import com.bradcowdrey.twodegrees.Condition
import com.bradcowdrey.twodegrees.Forecast
import com.bradcowdrey.twodegrees.SkyColour
import com.bradcowdrey.twodegrees.Meteo
import com.bradcowdrey.twodegrees.Normals
import com.bradcowdrey.twodegrees.Units
import com.bradcowdrey.twodegrees.WeatherStore
import com.bradcowdrey.twodegrees.roundHalfUp
import kotlinx.coroutines.launch

/**
 * One day, full screen: its temperature, rain and wind through the day as charts, then sunrise,
 * sunset, UV, gusts and (once loaded) the normals and records. Swipe or use the arrows between days.
 */
@Composable
fun DayDetail(city: City, forecast: Forecast, state: WeatherStore.State, start: Int, onClose: () -> Unit) {
    val days = forecast.days.take(10)
    if (days.isEmpty()) return
    val pager = rememberPagerState(initialPage = start.coerceIn(0, days.lastIndex)) { days.size }
    val scope = rememberCoroutineScope()
    val page = pager.currentPage
    val shown = days[page]
    OverlayPage(
        if (page == 0) "Today · ${city.name}" else "${Forecast.weekday(shown.date)} · ${city.name}", onClose,
        Modifier.background(Sky.brush(shown.code, true)),
        actions = {
            IconButton(onClick = { scope.launch { pager.animateScrollToPage(page - 1) } }, enabled = page > 0) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Previous day", tint = Color.White.copy(alpha = if (page > 0) 1f else 0.3f))
            }
            IconButton(onClick = { scope.launch { pager.animateScrollToPage(page + 1) } }, enabled = page < days.lastIndex) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Next day", tint = Color.White.copy(alpha = if (page < days.lastIndex) 1f else 0.3f))
            }
        },
    ) {
        HorizontalPager(pager, Modifier.fillMaxSize()) { i ->
            val day = if (i == 0) days[0].including(forecast.now.temperature) else days[i]
            DayPage(city, forecast, day, i == 0, state)
        }
    }
}

@Composable
private fun DayPage(city: City, forecast: Forecast, day: Forecast.Day, isToday: Boolean, state: WeatherStore.State) {
    val ui = LocalMetrics.current
    val unit = state.unit
    val units = state.units
    val hours = forecast.hoursOf(day.date)
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier.widthIn(max = ui.dp(600f)).fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(ui.dp(10f)),
        ) {
            // 1. The day: date, condition, high and low in both units, rain chance.
            Column(Modifier.fillMaxWidth().padding(vertical = ui.dp(12f)), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(Forecast.longDate(day.date), style = ui.text(24f, FontWeight.Medium))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 6.dp)) {
                    WeatherGlyph(day.code, true, ui.dp(28f))
                    Text(Condition.name(day.code), style = ui.text(18f, FontWeight.Medium))
                }
                Text("H:${unit.value(day.high)}${unit.symbol}  L:${unit.value(day.low)}${unit.symbol}", style = ui.text(20f, FontWeight.Medium), modifier = Modifier.padding(top = 4.dp))
                Text("H:${unit.other.value(day.high)}${unit.other.symbol}  L:${unit.other.value(day.low)}${unit.other.symbol}", style = ui.text(15f), modifier = Modifier.alpha(0.65f))
                Text("${day.rainChance}% chance of rain", style = ui.text(15f).copy(color = Palette.rain), modifier = Modifier.padding(top = 2.dp))
            }

            // 2. Temperature: larger unit's axis on the left, the other's on the right; Now on today.
            if (hours.size >= 2) {
                Card("Temperature", Icons.Filled.Thermostat) {
                    TemperatureChart(hours, units, if (isToday) forecast.now.time.let { it.hour + it.minute / 60f } else null)
                }
            }

            // 3. Rain: hourly chance, and the day's total.
            if (hours.size >= 2) {
                Card("Rain", Icons.Filled.WaterDrop) {
                    RainChart(hours)
                    day.precipitationSum?.let { mm ->
                        val (main, other) = units.rain(mm)
                        Text("Total: $main" + (other?.let { " · $it" } ?: ""), style = ui.text(15f))
                    }
                }
            }

            // 4. Wind: speed and (lighter) gusts, in the wind unit; the main direction.
            if (hours.count { it.wind != null } >= 2) {
                Card("Wind", Icons.Filled.Air) {
                    WindChart(hours, units)
                    day.windDirection?.let { Text("Mostly from the ${Meteo.compassName(it)}", style = ui.text(15f)) }
                }
            }

            // 5. Facts.
            Card("Details", Icons.Filled.Info) {
                val rows = mutableListOf<Pair<String, String>>()
                fun sky(t: java.time.LocalDateTime) = Forecast.clock(t) + (SkyColour.outlook(forecast, t)?.let { " · ${it.rating.word} colour" } ?: "")
                day.sunrise?.let { rows += "Sunrise" to sky(it) }
                day.sunset?.let { rows += "Sunset" to sky(it) }
                day.uvIndex?.let { rows += "UV index" to "${it.roundHalfUp()} · ${Meteo.uvLevel(it)}" }
                day.gustMax?.let { rows += "Max gust" to units.wind(it).let { (a, b) -> a + (b?.let { o -> " · $o" } ?: "") } }
                state.normals(city)?.of(day.date)?.let { e ->
                    if (e.normalHigh != null && e.normalLow != null) {
                        rows += "Normal" to "H:${unit.spaced(e.normalHigh)} · ${unit.other.spaced(e.normalHigh)}  L:${unit.spaced(e.normalLow)} · ${unit.other.spaced(e.normalLow)}"
                    }
                }
                Column {
                    rows.forEachIndexed { i, (label, value) ->
                        if (i > 0) HorizontalDivider(color = Color.White.copy(alpha = 0.15f))
                        Row(Modifier.fillMaxWidth().padding(vertical = 8.dp).semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
                            Text(label, style = ui.text(15f), modifier = Modifier.alpha(0.7f).weight(1f))
                            Text(value, style = ui.text(15f, FontWeight.Medium))
                        }
                    }
                    state.normals(city)?.of(day.date)?.let { Normals.recordsLine(it, unit) }?.let {
                        if (rows.isNotEmpty()) HorizontalDivider(color = Color.White.copy(alpha = 0.15f))
                        Text(it, style = ui.text(14f), modifier = Modifier.padding(vertical = 8.dp))
                    }
                }
            }
        }
    }
}

// Charts: drawn with Canvas, labels by a TextMeasurer, the same colours as the day bars.

private val CHART_LEFT = 40.dp
private val CHART_RIGHT = 40.dp
private val CHART_BOTTOM = 22.dp

/**
 * A chart's frame: grid lines and labels at fractions of the height (0 at the bottom), hour labels
 * along the bottom (by hour of the day, 0–24), then the plot itself drawn in its rectangle.
 */
@Composable
private fun Chart(
    left: List<Pair<Float, String>>,
    right: List<Pair<Float, String>>,
    description: String,
    hours: List<Forecast.Hour>,
    plot: DrawScope.(Rect) -> Unit,
) {
    val ui = LocalMetrics.current
    val measurer = rememberTextMeasurer()
    val style = TextStyle(fontFamily = ui.family, fontSize = ui.sp(11f), color = Color.White.copy(alpha = 0.7f), fontWeight = FontWeight.Medium)
    val ticks = listOf(0, 6, 12, 18).mapNotNull { h -> hours.firstOrNull { it.time.hour == h }?.let { h to Forecast.hour(it.time) } }
    Canvas(Modifier.fillMaxWidth().height(ui.dp(150f)).semantics { contentDescription = description }) {
        val rect = Rect(CHART_LEFT.toPx(), 6.dp.toPx(), size.width - CHART_RIGHT.toPx(), size.height - CHART_BOTTOM.toPx())
        for ((f, text) in left) {
            val y = rect.bottom - rect.height * f
            drawLine(Color.White.copy(alpha = 0.12f), Offset(rect.left, y), Offset(rect.right, y), 1.dp.toPx())
            val m = measurer.measure(text, style)
            drawText(m, topLeft = Offset(rect.left - m.size.width - 6.dp.toPx(), y - m.size.height / 2))
        }
        for ((f, text) in right) {
            val y = rect.bottom - rect.height * f
            val m = measurer.measure(text, style)
            drawText(m, topLeft = Offset(rect.right + 6.dp.toPx(), y - m.size.height / 2))
        }
        for ((h, text) in ticks) {
            val x = rect.left + rect.width * h / 23f
            val m = measurer.measure(text, style)
            drawText(m, topLeft = Offset((x - m.size.width / 2).coerceIn(rect.left - 4.dp.toPx(), size.width - m.size.width.toFloat()), rect.bottom + 4.dp.toPx()))
        }
        plot(rect)
    }
}

/** x for an hour of the day (0–23) in the plot. */
private fun Rect.x(hour: Float) = left + width * hour / 23f

private fun line(points: List<Offset>): Path = Path().apply {
    points.forEachIndexed { i, p -> if (i == 0) moveTo(p.x, p.y) else lineTo(p.x, p.y) }
}

@Composable
private fun TemperatureChart(hours: List<Forecast.Hour>, units: Units, now: Float?) {
    val unit = units.temperature
    val lo = hours.minOf { it.temperature }
    val hi = hours.maxOf { it.temperature }
    // A little room above and below, at least 4 °C of range so a flat day doesn't look wild.
    val pad = maxOf(1.0, (4 - (hi - lo)) / 2)
    val bottom = lo - pad
    val top = hi + pad
    fun f(c: Double) = ((c - bottom) / (top - bottom)).toFloat()
    val marks = listOf(lo, (lo + hi) / 2, hi)
    val description = "Temperature from ${unit.spaced(lo)} to ${unit.spaced(hi)}, ${unit.other.spaced(lo)} to ${unit.other.spaced(hi)}"
    Chart(
        left = marks.map { f(it) to "${unit.value(it)}°" },
        right = marks.map { f(it) to "${unit.other.value(it)}°" },
        description = description,
        hours = hours,
    ) { rect ->
        val points = hours.map { h -> Offset(rect.x(h.time.hour.toFloat()), rect.bottom - rect.height * f(h.temperature)) }
        val brush = Brush.verticalGradient(
            listOf(Palette.temperature(top), Palette.temperature(bottom)), startY = rect.top, endY = rect.bottom,
        )
        drawPath(line(points), brush, style = Stroke(3.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
        if (now != null) {
            val x = rect.x(now.coerceIn(0f, 23f))
            drawLine(Color.White.copy(alpha = 0.6f), Offset(x, rect.top), Offset(x, rect.bottom), 1.dp.toPx(),
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx())))
            // The dot sits on the line, between the hours either side.
            val i = now.toInt().coerceIn(0, hours.lastIndex)
            val j = (i + 1).coerceAtMost(hours.lastIndex)
            val k = now - i
            val y = points[i].y + (points[j].y - points[i].y) * k
            drawCircle(Color.White, 5.dp.toPx(), Offset(x, y))
            drawCircle(Color.Black.copy(alpha = 0.35f), 5.dp.toPx(), Offset(x, y), style = Stroke(1.5.dp.toPx()))
        }
    }
    if (now != null) NowLabel()
}

@Composable
private fun NowLabel() {
    val ui = LocalMetrics.current
    Text("Dashed line: now", style = ui.text(12f), modifier = Modifier.alpha(0.6f))
}

@Composable
private fun RainChart(hours: List<Forecast.Hour>) {
    Chart(
        left = listOf(0f to "0%", 0.5f to "50%", 1f to "100%"),
        right = emptyList(),
        description = "Chance of rain by hour, up to ${hours.maxOf { it.rainChance }}%",
        hours = hours,
    ) { rect ->
        val w = rect.width / 24f * 0.7f
        for (h in hours) {
            val x = rect.x(h.time.hour.toFloat())
            val height = rect.height * h.rainChance / 100f
            if (height > 0) drawRect(Palette.rain, Offset(x - w / 2, rect.bottom - height), androidx.compose.ui.geometry.Size(w, height))
        }
    }
}

@Composable
private fun WindChart(hours: List<Forecast.Hour>, units: Units) {
    val unit = units.wind
    // Round steps in the wind unit (0, 10, 20, 30…), as on the iPhone, with the top a whole step.
    val perKmh = unit.value(1.0)
    val peak = maxOf(hours.maxOf { maxOf(it.wind ?: 0.0, it.gusts ?: 0.0) } * perKmh, 4.0)
    val step = listOf(1.0, 2.0, 5.0, 10.0, 20.0, 25.0, 50.0, 100.0).first { peak / it <= 4 }
    val topValue = kotlin.math.ceil(peak / step) * step
    fun f(kmh: Double) = (kmh * perKmh / topValue).toFloat()
    val marks = generateSequence(0.0) { it + step }.takeWhile { it <= topValue + 1e-9 }.toList()
    Chart(
        left = marks.map { (it / topValue).toFloat() to "${it.roundHalfUp()}" },
        right = listOf(1f to unit.symbol),
        description = "Wind up to ${unit.text(hours.maxOf { it.wind ?: 0.0 })}, gusts up to ${unit.text(hours.maxOf { it.gusts ?: 0.0 })}",
        hours = hours,
    ) { rect ->
        fun points(value: (Forecast.Hour) -> Double?) = hours.mapNotNull { h ->
            value(h)?.let { Offset(rect.x(h.time.hour.toFloat()), rect.bottom - rect.height * f(it)) }
        }
        drawPath(line(points { it.gusts }), Color.White.copy(alpha = 0.35f), style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
        drawPath(line(points { it.wind }), Color.White, style = Stroke(3.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
    val ui = LocalMetrics.current
    Text("Bright line: wind · faint line: gusts", style = ui.text(12f), modifier = Modifier.alpha(0.6f))
}
