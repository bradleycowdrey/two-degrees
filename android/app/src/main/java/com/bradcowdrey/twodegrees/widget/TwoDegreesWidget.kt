package com.bradcowdrey.twodegrees.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.Build
import android.util.TypedValue
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
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
import com.bradcowdrey.twodegrees.City
import com.bradcowdrey.twodegrees.Condition
import com.bradcowdrey.twodegrees.Forecast
import com.bradcowdrey.twodegrees.MainActivity
import com.bradcowdrey.twodegrees.Speech
import com.bradcowdrey.twodegrees.TempUnit
import com.bradcowdrey.twodegrees.WidgetTap
import com.bradcowdrey.twodegrees.ui.Glyphs
import com.bradcowdrey.twodegrees.ui.Palette
import com.bradcowdrey.twodegrees.ui.Sky
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** What one widget shows: a city, its forecast (or the last good one, marked offline), and the unit. */
data class WidgetEntry(val city: City, val forecast: Forecast?, val unit: TempUnit, val offline: Boolean)

/**
 * The Home Screen widget, in the iPhone's three sizes: small (the reading), medium (plus the next
 * hours) and large (plus the hours and six days). Each shows Two Degrees' current city, or a city of
 * its own (long-press › Settings). Each size has a snug and a roomy layout, for the launchers' cells,
 * and the medium and large have one in between, so a common 4×2 still shows five hours and a
 * narrow 4×4 still shows six days.
 */
class TwoDegreesWidget : GlanceAppWidget() {
    companion object {
        val SMALL = DpSize(110.dp, 110.dp)
        val SMALL_ROOMY = DpSize(150.dp, 150.dp)
        val MEDIUM = DpSize(250.dp, 110.dp)
        val MEDIUM_WIDE = DpSize(300.dp, 110.dp)
        val MEDIUM_ROOMY = DpSize(340.dp, 150.dp)
        val LARGE = DpSize(250.dp, 300.dp)
        val LARGE_TALL = DpSize(250.dp, 345.dp)
        val LARGE_ROOMY = DpSize(300.dp, 350.dp)

        /** One of each size at its roomy layout, as the self-test photographs them. */
        val SHOWN = listOf(SMALL_ROOMY, MEDIUM_ROOMY, LARGE_ROOMY)
    }

    override val sizeMode = SizeMode.Responsive(setOf(
        SMALL, SMALL_ROOMY, MEDIUM, MEDIUM_WIDE, MEDIUM_ROOMY, LARGE, LARGE_TALL, LARGE_ROOMY,
    )))

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

// Text tones over the sky: white at the iPhone widget's opacities.
private const val SECONDARY = 0.78f
private const val MUTED = 0.6f
private const val DIVIDER = 0.18f

private fun white(alpha: Float = 1f) = ColorProvider(Color.White.copy(alpha = alpha))
private fun style(size: TextUnit, weight: FontWeight = FontWeight.Normal, alpha: Float = 1f, align: TextAlign = TextAlign.Start) =
    TextStyle(color = white(alpha), fontSize = size, fontWeight = weight, textAlign = align)

// The iPhone's semibold is Android's medium.
private val SEMIBOLD = FontWeight.Medium

/** A sky gradient as a small bitmap, stretched behind the widget. */
private fun skyBitmap(code: Int, isDay: Boolean): Bitmap {
    val (top, bottom) = Sky.colors(code, isDay)
    val bitmap = Bitmap.createBitmap(8, 128, Bitmap.Config.ARGB_8888)
    Canvas(bitmap).drawRect(0f, 0f, 8f, 128f, Paint().apply {
        shader = LinearGradient(0f, 0f, 0f, 128f, top.toArgb(), bottom.toArgb(), Shader.TileMode.CLAMP)
    })
    return bitmap
}

/** Pixels per dp and per sp, for the parts drawn as bitmaps. */
private class PxScale(context: Context) {
    private val metrics = context.resources.displayMetrics
    val dp = metrics.density
    fun sp(value: Float) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, value, metrics)
}

private fun typeface(weight: Int): Typeface =
    if (Build.VERSION.SDK_INT >= 28) Typeface.create(Typeface.DEFAULT, weight, false)
    else Typeface.create(if (weight >= 500) "sans-serif-medium" else "sans-serif", Typeface.NORMAL)

private fun textPaint(px: Float, weight: Int, alpha: Float = 1f) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    textSize = px
    typeface = typeface(weight)
    color = Color.White.copy(alpha = alpha).toArgb()
}

@Composable
private fun Glyph(code: Int, isDay: Boolean, size: Int) {
    val px = (size * PxScale(LocalContext.current).dp).roundToInt().coerceAtLeast(1)
    Image(ImageProvider(Glyphs.bitmap(Condition.glyph(code, isDay), px)), Condition.name(code), GlanceModifier.size(size.dp))
}

/** The iPhone's "icloud.slash": a cloud with a stroke through it, in the muted white. */
private fun offlineBitmap(px: Int): Bitmap {
    val bitmap = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    Glyphs.draw(canvas, Condition.Glyph.CLOUD, px.toFloat())
    val tone = Color.White.copy(alpha = MUTED).toArgb()
    canvas.drawRect(0f, 0f, px.toFloat(), px.toFloat(), Paint().apply { color = tone; xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN) })
    val unit = px / 24f
    canvas.drawLine(4 * unit, 4 * unit, 20 * unit, 21 * unit, Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = tone; strokeWidth = 1.8f * unit; strokeCap = Paint.Cap.ROUND
    })
    return bitmap
}

/**
 * The big reading as on the iPhone: the number, its unit smaller and raised to the top of the number
 * ("46°F"), and the other unit beside it on the same baseline ("8 °C"). Drawn as one bitmap, since
 * widget text can't share a baseline; it shrinks to 70% to fit, as the iPhone's does. The bitmap
 * holds only the shapes (the muted part fainter) and is tinted white, which keeps it a quarter of
 * the size, since the launcher is sent one for every layout.
 */
@Composable
private fun BigReading(celsius: Double, unit: TempUnit, size: Float, maxWidth: Dp) {
    val scale = PxScale(LocalContext.current)
    fun measure(k: Float): Triple<List<Paint>, List<String>, Float> {
        val big = scale.sp(size) * k
        val number = textPaint(big, 600).apply { letterSpacing = -0.03f }
        val symbol = textPaint(big * 0.42f, 500).apply { letterSpacing = -0.03f / 0.42f }
        val other = textPaint(big * 0.45f, 500, MUTED)
        val texts = listOf("${unit.value(celsius)}", unit.symbol, unit.other.spaced(celsius))
        val width = number.measureText(texts[0]) + symbol.measureText(texts[1]) + 6 * scale.dp * k + other.measureText(texts[2])
        return Triple(listOf(number, symbol, other), texts, width)
    }
    val room = maxWidth.value * scale.dp
    val natural = measure(1f).third
    val k = if (natural > room) max(0.7f, room / natural) else 1f
    val (paints, texts, width) = measure(k)
    val (number, symbol, other) = paints
    val metrics = number.fontMetrics
    val height = -metrics.ascent + metrics.descent
    val bitmap = Bitmap.createBitmap(min(width, room).roundToInt().coerceAtLeast(1), height.roundToInt().coerceAtLeast(1), Bitmap.Config.ALPHA_8)
    val canvas = Canvas(bitmap)
    val baseline = -metrics.ascent
    var x = 0f
    canvas.drawText(texts[0], x, baseline, number); x += number.measureText(texts[0])
    canvas.drawText(texts[1], x, baseline - number.textSize * 0.36f, symbol); x += symbol.measureText(texts[1]) + 6 * scale.dp * k
    canvas.drawText(texts[2], x, baseline, other)
    Image(
        ImageProvider(bitmap), Speech.temperature(celsius),
        GlanceModifier.width((bitmap.width / scale.dp).dp).height((bitmap.height / scale.dp).dp),
        contentScale = ContentScale.Fit,
        colorFilter = ColorFilter.tint(white()),
    )
}

/**
 * One day's range on the scale shared by all the days shown: a bar from the low to the high in the
 * temperature colors, the low and high riding its ends, and for today a dot at the current reading.
 */
private fun dayBar(scale: PxScale, widthDp: Float, low: Int, high: Int, lowC: Double, highC: Double, from: Double, to: Double, now: Double?): Bitmap {
    val d = scale.dp
    val labelLow = textPaint(scale.sp(12f), 600, SECONDARY)
    val labelHigh = textPaint(scale.sp(12f), 600)
    val w = (widthDp * d).roundToInt().coerceAtLeast(1)
    val h = max(16 * d, labelHigh.fontSpacing).roundToInt()
    val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val room = 32 * d
    val gap = 4 * d
    val track = max(w - 2 * room, 1f)
    val span = max(to - from, 1.0)
    fun x(t: Double) = room + ((t - from) / span).toFloat() * track
    val mid = h / 2f
    val start = x(lowC)
    val end = max(x(highC), start + 5 * d)
    canvas.drawRoundRect(RectF(start, mid - 2.5f * d, end, mid + 2.5f * d), 2.5f * d, 2.5f * d, Paint(Paint.ANTI_ALIAS_FLAG).apply {
        shader = LinearGradient(start, 0f, end, 0f, Palette.temperature(lowC).toArgb(), Palette.temperature(highC).toArgb(), Shader.TileMode.CLAMP)
    })
    if (now != null) {
        val cx = x(now)
        canvas.drawCircle(cx, mid, 4 * d, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE })
        canvas.drawCircle(cx, mid, 4 * d, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE; strokeWidth = 1.5f * d; color = Color.Black.copy(alpha = 0.35f).toArgb()
        })
    }
    val m = labelHigh.fontMetrics
    val baseline = mid - (m.ascent + m.descent) / 2
    val lowText = "$low°"
    canvas.drawText(lowText, start - gap - labelLow.measureText(lowText), baseline, labelLow)
    canvas.drawText("$high°", x(highC) + gap, baseline, labelHigh)
    return bitmap
}

private val widgetCity = ActionParameters.Key<String>(WidgetTap.KEY)

@Composable
fun WidgetContent(entry: WidgetEntry) {
    val size = LocalSize.current
    val now = entry.forecast?.now
    // The iPhone's margins: 16 around, a little less in the snug layouts.
    val pad = if (size.width < TwoDegreesWidget.SMALL_ROOMY.width || size.height < TwoDegreesWidget.SMALL_ROOMY.height) 12.dp else 16.dp
    val inner = DpSize(size.width - pad * 2, size.height - pad * 2)
    Box(
        GlanceModifier.fillMaxSize().cornerRadius(22.dp)
            .background(ImageProvider(skyBitmap(now?.code ?: 3, now?.isDay ?: false)), ContentScale.FillBounds)
            // A tap opens the app on this widget's city.
            .clickable(actionStartActivity<MainActivity>(actionParametersOf(widgetCity to WidgetTap.encode(entry.city)))),
    ) {
        Box(GlanceModifier.fillMaxSize().padding(pad)) {
            when {
                entry.forecast == null -> Unavailable(entry)
                size.height >= TwoDegreesWidget.LARGE.height -> Large(entry, entry.forecast, inner)
                size.width >= TwoDegreesWidget.MEDIUM.width -> Medium(entry, entry.forecast, inner)
                else -> NowBlock(entry, entry.forecast, inner)
            }
        }
    }
}

/** Offline with nothing saved yet: the city, and a plain message that it will try again. */
@Composable
private fun Unavailable(entry: WidgetEntry) {
    val px = (20 * PxScale(LocalContext.current).dp).roundToInt()
    Column(GlanceModifier.fillMaxSize()) {
        Text(entry.city.name, style = style(13.sp, SEMIBOLD), maxLines = 1)
        Spacer(GlanceModifier.defaultWeight())
        Image(ImageProvider(offlineBitmap(px)), null, GlanceModifier.size(20.dp))
        Spacer(GlanceModifier.height(4.dp))
        Text("Couldn’t load the weather", style = style(12.sp, SEMIBOLD, SECONDARY))
        Spacer(GlanceModifier.height(4.dp))
        Text("Trying again in a few minutes", style = style(11.sp, FontWeight.Medium, MUTED))
    }
}

private fun offlineLine(forecast: Forecast): String {
    val fetched = LocalDateTime.ofInstant(Instant.ofEpochMilli(forecast.fetchedAt), ZoneId.systemDefault())
    return "Offline · from ${Forecast.clock(fetched)}"
}

/**
 * The small widget, and the medium's left half: the city with the reading right under it, the sky and
 * today's range in both units at the foot (or when it's from, offline).
 */
@Composable
private fun NowBlock(entry: WidgetEntry, forecast: Forecast, room: DpSize) {
    val unit = entry.unit
    val other = unit.other
    val now = forecast.now
    // Too short for the sky's symbol: the name and range still fit.
    val snug = room.height < 110.dp
    Column(GlanceModifier.fillMaxSize()) {
        Text(entry.city.name, style = style(13.sp, SEMIBOLD), maxLines = 1)
        BigReading(now.temperature, unit, if (snug) 32f else 40f, room.width)
        Spacer(GlanceModifier.defaultWeight())
        if (!snug) {
            Glyph(now.code, now.isDay, 15)
            Spacer(GlanceModifier.height(3.dp))
        }
        Text(Condition.name(now.code), style = style(12.sp, SEMIBOLD, SECONDARY), maxLines = 1)
        val today = forecast.days.firstOrNull()?.including(now.temperature)
        when {
            entry.offline -> Text(offlineLine(forecast), style = style(11.sp, FontWeight.Medium, MUTED), maxLines = 1)
            today != null -> Text(
                "${unit.value(today.low)}–${unit.value(today.high)}${unit.symbol} · ${other.value(today.low)}–${other.value(today.high)}${other.symbol}",
                style = style(11.sp, FontWeight.Medium, MUTED), maxLines = 1,
            )
        }
    }
}

/** A thin rule, as between the iPhone widget's sections. */
@Composable
private fun Divider(vertical: Boolean) {
    val line = Color.White.copy(alpha = DIVIDER)
    Box(
        if (vertical) GlanceModifier.width(0.5.dp).fillMaxHeight().background(line)
        else GlanceModifier.fillMaxWidth().height(0.5.dp).background(line),
    ) {}
}

/** Now on the left, the next hours on the right (five where there's room, as on the iPhone). */
@Composable
private fun Medium(entry: WidgetEntry, forecast: Forecast, room: DpSize) {
    val left = if (room.width < 280.dp) 104.dp else 128.dp
    val spacing = if (room.width < 280.dp) 10.dp else 14.dp
    val count = ((room.width - left - spacing * 2).value / 30).toInt().coerceIn(2, 5)
    Row(GlanceModifier.fillMaxSize()) {
        Box(GlanceModifier.width(left).fillMaxHeight()) { NowBlock(entry, forecast, DpSize(left, room.height)) }
        Spacer(GlanceModifier.width(spacing))
        Divider(vertical = true)
        Spacer(GlanceModifier.width(spacing))
        Box(GlanceModifier.defaultWeight().fillMaxHeight(), contentAlignment = Alignment.CenterStart) {
            HoursRow(entry, forecast, count)
        }
    }
}

/** Each hour: its time ("Now" first), the sky, the reading, and the other unit beneath. */
@Composable
private fun HoursRow(entry: WidgetEntry, forecast: Forecast, count: Int) {
    val unit = entry.unit
    val other = unit.other
    Row(GlanceModifier.fillMaxWidth()) {
        forecast.upcomingHours.take(count).forEachIndexed { index, hour ->
            val label = if (index == 0) "Now" else Forecast.hour(hour.time)
            Column(
                GlanceModifier.defaultWeight().semantics {
                    contentDescription = "$label: ${Condition.name(hour.code)}, ${Speech.temperature(hour.temperature)}"
                },
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    label,
                    style = if (index == 0) style(10.sp, SEMIBOLD, align = TextAlign.Center) else style(10.sp, FontWeight.Medium, MUTED, TextAlign.Center),
                    maxLines = 1,
                )
                Spacer(GlanceModifier.height(3.dp))
                Box(GlanceModifier.height(18.dp), contentAlignment = Alignment.Center) { Glyph(hour.code, hour.isDay, 14) }
                Spacer(GlanceModifier.height(3.dp))
                Text("${unit.value(hour.temperature)}°", style = style(13.sp, SEMIBOLD, align = TextAlign.Center), maxLines = 1)
                Spacer(GlanceModifier.height(3.dp))
                Text("${other.value(hour.temperature)}${other.symbol}", style = style(10.sp, alpha = MUTED, align = TextAlign.Center), maxLines = 1)
            }
        }
    }
}

/** Now, the next six hours, and six days on one shared scale, as on the iPhone. */
@Composable
private fun Large(entry: WidgetEntry, forecast: Forecast, room: DpSize) {
    // The top is about 74 high and the hours about 72; each day takes 22 with its spacing.
    val days = ((room.height.value - 74 - 72 - 41 + 6) / 22).toInt().coerceIn(3, 6)
    val hours = (room.width.value / 30).toInt().coerceIn(4, 6)
    Column(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
        LargeNow(entry, forecast, room)
        Spacer(GlanceModifier.height(10.dp))
        Divider(vertical = false)
        Spacer(GlanceModifier.height(10.dp))
        HoursRow(entry, forecast, hours)
        Spacer(GlanceModifier.height(10.dp))
        Divider(vertical = false)
        Spacer(GlanceModifier.height(10.dp))
        DaysList(entry, forecast, days, room.width)
    }
}

/**
 * The large widget's top: the city and the reading on the left, the sky and its name on the right.
 * Today's range is in the first day row below, so it isn't repeated here.
 */
@Composable
private fun LargeNow(entry: WidgetEntry, forecast: Forecast, room: DpSize) {
    val now = forecast.now
    Row(GlanceModifier.fillMaxWidth()) {
        Column(GlanceModifier.defaultWeight()) {
            Text(entry.city.name, style = style(13.sp, SEMIBOLD), maxLines = 1)
            Spacer(GlanceModifier.height(2.dp))
            BigReading(now.temperature, entry.unit, 46f, room.width - 104.dp)
            if (entry.offline) {
                Spacer(GlanceModifier.height(2.dp))
                Text(offlineLine(forecast), style = style(11.sp, FontWeight.Medium, MUTED), maxLines = 1)
            }
        }
        Spacer(GlanceModifier.width(8.dp))
        Column(GlanceModifier.padding(top = 4.dp), horizontalAlignment = Alignment.End) {
            Box(GlanceModifier.height(44.dp), contentAlignment = Alignment.Center) { Glyph(now.code, now.isDay, 40) }
            Spacer(GlanceModifier.height(6.dp))
            Text(Condition.name(now.code), style = style(13.sp, SEMIBOLD, SECONDARY, TextAlign.End), maxLines = 2)
        }
    }
}

@Composable
private fun DaysList(entry: WidgetEntry, forecast: Forecast, count: Int, width: Dp) {
    val unit = entry.unit
    val other = unit.other
    val scale = PxScale(LocalContext.current)
    val now = forecast.now.temperature
    val shown = forecast.days.take(count).mapIndexed { i, d -> if (i == 0) d.including(now) else d }
    val from = min(now, shown.minOfOrNull { it.low } ?: now)
    val to = max(now, shown.maxOfOrNull { it.high } ?: now)
    val snug = width < 280.dp
    val name = if (snug) 36f else 42f
    val symbol = if (snug) 18f else 20f
    val spacing = if (snug) 6f else 8f
    val range = if (snug) 50f else 52f
    val bar = max(width.value - name - symbol - range - spacing * 3, 72f)
    Column(GlanceModifier.fillMaxWidth()) {
        shown.forEachIndexed { index, day ->
            val dayName = if (index == 0) "Today" else Forecast.weekday(day.date)
            // The gap rides on each row: a widget column holds at most ten children.
            Row(
                GlanceModifier.fillMaxWidth().padding(top = if (index == 0) 0.dp else 6.dp).semantics {
                    contentDescription = "$dayName: ${Condition.name(day.code)}. Low ${Speech.temperature(day.low)}. High ${Speech.temperature(day.high)}."
                },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(dayName, style = style(12.sp, SEMIBOLD), maxLines = 1, modifier = GlanceModifier.width(name.dp))
                Spacer(GlanceModifier.width(spacing.dp))
                Box(GlanceModifier.width(symbol.dp), contentAlignment = Alignment.Center) { Glyph(day.code, true, 13) }
                Spacer(GlanceModifier.width(spacing.dp))
                val bitmap = dayBar(scale, bar, unit.value(day.low), unit.value(day.high), day.low, day.high, from, to, if (index == 0) now else null)
                Image(
                    ImageProvider(bitmap), null,
                    GlanceModifier.defaultWeight().height((bitmap.height / scale.dp).dp),
                    contentScale = ContentScale.Fit,
                )
                Spacer(GlanceModifier.width(spacing.dp))
                Text(
                    "${other.value(day.low)}–${other.value(day.high)}${other.symbol}",
                    style = style(10.sp, alpha = MUTED, align = TextAlign.End), maxLines = 1,
                    modifier = GlanceModifier.width(range.dp),
                )
            }
        }
    }
}
