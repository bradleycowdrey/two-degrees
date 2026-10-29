package com.bradcowdrey.twodegrees.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bradcowdrey.twodegrees.AppFont
import com.bradcowdrey.twodegrees.Condition
import com.bradcowdrey.twodegrees.R

/** The Mac and iPhone apps' colors. */
object Palette {
    val bg = Color(0xFF1A1816)
    val cream = Color(0xFFFFF1E5)
    val textSecondary = Color(0xFFE0D8D0)
    val textMuted = Color(0xFFB0A898)
    val crimson = Color(0xFF990F3D)
    val pink = Color(0xFFE04A7A)
    val rain = Color(0xFF8DB4E2)
    val card = Color(0x33000000)
    val cardStroke = Color(0x1FFFFFFF)

    private val stops = listOf(
        -10.0 to Triple(127, 167, 217), 8.0 to Triple(143, 190, 214), 16.0 to Triple(233, 201, 138),
        25.0 to Triple(242, 166, 90), 34.0 to Triple(224, 74, 122),
    )

    /** A temperature's color on the day bars, cool blue to hot pink. */
    fun temperature(celsius: Double): Color {
        if (celsius <= stops[0].first) return rgb(stops[0].second)
        for (i in 1 until stops.size) {
            if (celsius <= stops[i].first) {
                val (a, ca) = stops[i - 1]
                val (b, cb) = stops[i]
                val k = ((celsius - a) / (b - a)).toFloat()
                return Color(
                    (ca.first + (cb.first - ca.first) * k) / 255f,
                    (ca.second + (cb.second - ca.second) * k) / 255f,
                    (ca.third + (cb.third - ca.third) * k) / 255f,
                )
            }
        }
        return rgb(stops.last().second)
    }

    private fun rgb(c: Triple<Int, Int, Int>) = Color(c.first / 255f, c.second / 255f, c.third / 255f)
}

/** The sky behind a city: a vertical gradient for its weather and time of day, as on the iPhone. */
object Sky {
    fun colors(code: Int, isDay: Boolean): Pair<Color, Color> = when {
        code in 95..99 -> Color(0xFF3A3346) to Color(0xFF16131B)
        Condition.isSnow(code) -> if (isDay) Color(0xFF7C8EA0) to Color(0xFF3E4A57) else Color(0xFF323B47) to Color(0xFF14181E)
        code in 51..82 && isDay -> Color(0xFF4F5E70) to Color(0xFF232A33)
        code in 51..82 -> Color(0xFF252C36) to Color(0xFF101317)
        isDay && code in setOf(3, 45, 48) -> Color(0xFF667585) to Color(0xFF2E3640)
        isDay && code in setOf(0, 1) -> Color(0xFF3D74B0) to Color(0xFF1C3A5E)
        isDay && code == 2 -> Color(0xFF4F78A3) to Color(0xFF24384F)
        code in setOf(0, 1) -> Color(0xFF141E3C) to Color(0xFF0A0E1C)
        else -> Color(0xFF262A33) to Color(0xFF111317)
    }

    fun brush(code: Int, isDay: Boolean): Brush = colors(code, isDay).let { Brush.verticalGradient(listOf(it.first, it.second)) }
}

val Inter = FontFamily(
    Font(R.font.inter_regular, FontWeight.Normal),
    Font(R.font.inter_medium, FontWeight.Medium),
    Font(R.font.inter_semibold, FontWeight.SemiBold),
)

/** Sizes scaled by the app's Text Size (the phone's own font size scales `sp` on top). */
data class Metrics(val scale: Float, val family: FontFamily) {
    fun dp(value: Float): Dp = (value * scale).dp
    fun sp(value: Float): TextUnit = (value * scale).sp
    fun text(size: Float, weight: FontWeight = FontWeight.Normal, align: TextAlign? = null) =
        TextStyle(fontFamily = family, fontSize = sp(size), fontWeight = weight, textAlign = align ?: TextAlign.Unspecified, color = Color.White)

    companion object {
        fun of(scale: Float, font: AppFont) = Metrics(scale, if (font == AppFont.INTER) Inter else FontFamily.Default)
    }
}

val LocalMetrics = compositionLocalOf { Metrics(1f, FontFamily.Default) }

/** A weather symbol (see Glyphs). */
@Composable
fun WeatherGlyph(code: Int, isDay: Boolean, size: Dp, modifier: Modifier = Modifier) {
    val glyph = Condition.glyph(code, isDay)
    Canvas(modifier.size(size)) {
        drawIntoCanvas { Glyphs.draw(it.nativeCanvas, glyph, this.size.minDimension) }
    }
}

@Composable
fun SkyBackground(code: Int, isDay: Boolean, modifier: Modifier = Modifier) {
    Box(modifier.background(Sky.brush(code, isDay)))
}
