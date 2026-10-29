package com.bradcowdrey.twodegrees.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import androidx.compose.ui.graphics.Color
import com.bradcowdrey.twodegrees.City
import com.bradcowdrey.twodegrees.Condition
import com.bradcowdrey.twodegrees.Forecast
import com.bradcowdrey.twodegrees.MainActivity
import com.bradcowdrey.twodegrees.Speech
import com.bradcowdrey.twodegrees.TempUnit
import com.bradcowdrey.twodegrees.ui.Glyphs
import com.bradcowdrey.twodegrees.ui.Sky

/** What one widget shows: a city, its forecast (or the last good one, marked offline), and the unit. */
data class WidgetEntry(val city: City, val forecast: Forecast?, val unit: TempUnit, val offline: Boolean)

/**
 * The Home Screen widget, in three sizes after the iPhone's: small (the reading), medium (plus the next
 * hours) and large (plus six days). Each shows Two Degrees' current city, or a city of its own
 * (long-press › Settings).
 */
class TwoDegreesWidget : GlanceAppWidget() {
    companion object {
        val SMALL = DpSize(110.dp, 110.dp)
        val MEDIUM = DpSize(250.dp, 110.dp)
        val LARGE = DpSize(250.dp, 260.dp)
    }

    override val sizeMode = SizeMode.Responsive(setOf(SMALL, MEDIUM, LARGE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val appWidgetId = GlanceAppWidgetManager(context).getAppWidgetId(id)
        val entry = WidgetData.entry(context, appWidgetId)
        provideContent { WidgetContent(entry) }
    }
}

class TwoDegreesWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TwoDegreesWidget()

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        WidgetData.forget(context, appWidgetIds)
    }
}

private val white = ColorProvider(Color.White)
private fun faded(alpha: Float) = ColorProvider(Color.White.copy(alpha = alpha))
private fun style(size: TextUnit, weight: FontWeight = FontWeight.Normal, alpha: Float = 1f, align: TextAlign = TextAlign.Start) =
    TextStyle(color = if (alpha == 1f) white else faded(alpha), fontSize = size, fontWeight = weight, textAlign = align)

/** A sky gradient as a small bitmap, stretched behind the widget. */
private fun skyBitmap(code: Int, isDay: Boolean): Bitmap {
    val (top, bottom) = Sky.colors(code, isDay)
    val bitmap = Bitmap.createBitmap(8, 128, Bitmap.Config.ARGB_8888)
    android.graphics.Canvas(bitmap).drawRect(0f, 0f, 8f, 128f, Paint().apply {
        shader = LinearGradient(0f, 0f, 0f, 128f, top.toArgb(), bottom.toArgb(), Shader.TileMode.CLAMP)
    })
    return bitmap
}

@Composable
private fun Glyph(code: Int, isDay: Boolean, size: Int) {
    Image(ImageProvider(Glyphs.bitmap(Condition.glyph(code, isDay), size * 3)), Condition.name(code), GlanceModifier.size(size.dp))
}

@Composable
fun WidgetContent(entry: WidgetEntry) {
    val size = LocalSize.current
    val now = entry.forecast?.now
    Box(
        GlanceModifier.fillMaxSize().cornerRadius(22.dp)
            .background(ImageProvider(skyBitmap(now?.code ?: 3, now?.isDay ?: true)), ContentScale.FillBounds)
            .clickable(actionStartActivity<MainActivity>()),
    ) {
        Box(GlanceModifier.fillMaxSize().padding(14.dp)) {
            when {
                entry.forecast == null -> Unavailable(entry)
                size.height >= TwoDegreesWidget.LARGE.height -> Large(entry, entry.forecast)
                size.width >= TwoDegreesWidget.MEDIUM.width -> Medium(entry, entry.forecast)
                else -> Small(entry, entry.forecast)
            }
        }
    }
}

@Composable
private fun Unavailable(entry: WidgetEntry) {
    Column {
        Text(entry.city.name, style = style(15.sp, FontWeight.Medium), maxLines = 1)
        Text("––°", style = style(40.sp, alpha = 0.5f))
        Spacer(GlanceModifier.defaultWeight())
        Text(if (entry.offline) "Couldn’t load. Tap to open." else "Loading…", style = style(12.sp, alpha = 0.8f))
    }
}

/** The big number with its unit smaller and raised; the other unit beneath. */
@Composable
private fun BigReading(celsius: Double, unit: TempUnit, numberSize: Int) {
    Row(GlanceModifier.semantics { contentDescription = Speech.temperature(celsius) }) {
        Text("${unit.value(celsius)}", style = style(numberSize.sp, FontWeight.Normal))
        Text("°${unit.letter}", style = style((numberSize * 0.42f).sp), modifier = GlanceModifier.padding(top = (numberSize * 0.18f).dp))
    }
}

@Composable
private fun Small(entry: WidgetEntry, forecast: Forecast) {
    val unit = entry.unit
    val now = forecast.now
    Column(GlanceModifier.fillMaxSize()) {
        Text(entry.city.name, style = style(15.sp, FontWeight.Medium), maxLines = 1)
        BigReading(now.temperature, unit, 40)
        Text(unit.other.spaced(now.temperature), style = style(14.sp, alpha = 0.75f))
        Spacer(GlanceModifier.defaultWeight())
        Glyph(now.code, now.isDay, 18)
        val today = forecast.days.firstOrNull()?.including(now.temperature)
        Text(
            if (entry.offline) "Offline" else today?.let { "H:${unit.value(it.high)}° L:${unit.value(it.low)}°" } ?: Condition.name(now.code),
            style = style(12.sp, FontWeight.Medium), maxLines = 1,
        )
    }
}

@Composable
private fun Medium(entry: WidgetEntry, forecast: Forecast) {
    val unit = entry.unit
    Row(GlanceModifier.fillMaxSize()) {
        Box(GlanceModifier.width(120.dp)) { Small(entry, forecast) }
        Spacer(GlanceModifier.width(8.dp))
        Row(GlanceModifier.defaultWeight(), verticalAlignment = Alignment.CenterVertically) {
            forecast.upcomingHours.drop(1).filterIndexed { i, _ -> i % 2 == 0 }.take(4).forEach { hour ->
                Column(GlanceModifier.defaultWeight(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(Forecast.hour(hour.time), style = style(12.sp, FontWeight.Medium, 0.85f, TextAlign.Center), maxLines = 1)
                    Spacer(GlanceModifier.height(6.dp))
                    Glyph(hour.code, hour.isDay, 22)
                    Spacer(GlanceModifier.height(6.dp))
                    Text("${unit.value(hour.temperature)}°", style = style(16.sp, FontWeight.Medium, align = TextAlign.Center))
                    Text(unit.other.spaced(hour.temperature), style = style(11.sp, alpha = 0.65f, align = TextAlign.Center), maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun Large(entry: WidgetEntry, forecast: Forecast) {
    val unit = entry.unit
    val other = unit.other
    val now = forecast.now
    Column(GlanceModifier.fillMaxSize()) {
        Row(GlanceModifier.fillMaxWidth()) {
            Column(GlanceModifier.defaultWeight()) {
                Text(entry.city.name, style = style(16.sp, FontWeight.Medium), maxLines = 1)
                BigReading(now.temperature, unit, 44)
                Text(other.spaced(now.temperature), style = style(14.sp, alpha = 0.75f))
            }
            Column(horizontalAlignment = Alignment.End) {
                Glyph(now.code, now.isDay, 40)
                Text(if (entry.offline) "Offline" else Condition.name(now.code), style = style(13.sp, FontWeight.Medium, align = TextAlign.End), maxLines = 1)
            }
        }
        Spacer(GlanceModifier.height(8.dp))
        forecast.days.take(6).forEachIndexed { i, d ->
            val day = if (i == 0) d.including(now.temperature) else d
            Row(GlanceModifier.fillMaxWidth().defaultWeight(), verticalAlignment = Alignment.CenterVertically) {
                Text(if (i == 0) "Today" else Forecast.weekday(day.date), style = style(14.sp, FontWeight.Medium), modifier = GlanceModifier.width(54.dp), maxLines = 1)
                Glyph(day.code, true, 20)
                Spacer(GlanceModifier.defaultWeight())
                Text("${unit.value(day.low)}° · ${unit.value(day.high)}°", style = style(14.sp, FontWeight.Medium, align = TextAlign.End))
                Text("  ${other.value(day.low)}–${other.value(day.high)}${other.label}", style = style(12.sp, alpha = 0.65f, align = TextAlign.End), maxLines = 1)
            }
        }
    }
}
