package com.bradcowdrey.twodegrees.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import com.bradcowdrey.twodegrees.Condition.Glyph
import kotlin.math.cos
import kotlin.math.sin

/**
 * The weather symbols, drawn in code on a 24-unit grid so the app and the widgets (which need
 * bitmaps) share one set, in the iPhone's colors: a warm sun, a pale moon, white clouds, blue rain.
 */
object Glyphs {
    private const val SUN = 0xFFF4B860.toInt()
    private const val MOON = 0xFFEDE6F5.toInt()
    private const val CLOUD = 0xFFF5F2EE.toInt()
    private const val CLOUD_DIM = 0xFFC9CDD4.toInt()
    private const val RAIN = 0xFF8DB4E2.toInt()
    private const val BOLT = 0xFFF4B860.toInt()

    fun bitmap(glyph: Glyph, px: Int): Bitmap =
        Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888).also { draw(Canvas(it), glyph, px.toFloat()) }

    fun draw(canvas: Canvas, glyph: Glyph, size: Float) {
        canvas.save()
        canvas.scale(size / 24f, size / 24f)
        when (glyph) {
            Glyph.SUN -> sun(canvas, 12f, 12f, 1f)
            Glyph.MOON -> moon(canvas, 12f, 12f, 1f)
            Glyph.PARTLY_SUN -> { sun(canvas, 9f, 9f, 0.72f); cloud(canvas, 13.5f, 15.5f, 0.78f, CLOUD) }
            Glyph.PARTLY_MOON -> { moon(canvas, 9f, 9f, 0.7f); cloud(canvas, 13.5f, 15.5f, 0.78f, CLOUD) }
            Glyph.CLOUD -> cloud(canvas, 12f, 13f, 1f, CLOUD)
            Glyph.FOG -> {
                cloud(canvas, 12f, 10f, 0.85f, CLOUD_DIM)
                for ((i, y) in listOf(17.5f, 20.5f).withIndex()) line(canvas, 5f + i * 2, y, 19f - i * 2, y, CLOUD, 1.6f)
            }
            Glyph.DRIZZLE -> { cloud(canvas, 12f, 10f, 0.9f, CLOUD); drops(canvas, 3, 2.2f, RAIN) }
            Glyph.RAIN -> { cloud(canvas, 12f, 10f, 0.9f, CLOUD); drops(canvas, 3, 3.6f, RAIN) }
            Glyph.HEAVY_RAIN -> { cloud(canvas, 12f, 10f, 0.9f, CLOUD_DIM); drops(canvas, 4, 4.6f, RAIN) }
            Glyph.SLEET -> {
                cloud(canvas, 12f, 10f, 0.9f, CLOUD)
                drops(canvas, 2, 3.4f, RAIN)
                dot(canvas, 12f, 19.5f, 1.3f, CLOUD)
            }
            Glyph.SNOW -> {
                cloud(canvas, 12f, 10f, 0.9f, CLOUD)
                for ((x, y) in listOf(8f to 18f, 12f to 20.5f, 16f to 18f)) dot(canvas, x, y, 1.4f, CLOUD)
            }
            Glyph.STORM -> {
                cloud(canvas, 12f, 10f, 0.9f, CLOUD_DIM)
                val bolt = Path().apply {
                    moveTo(13f, 13f); lineTo(9f, 18.5f); lineTo(12f, 18.5f); lineTo(10.5f, 23f); lineTo(15.5f, 16.5f)
                    lineTo(12.5f, 16.5f); lineTo(14f, 13f); close()
                }
                canvas.drawPath(bolt, fill(BOLT))
            }
        }
        canvas.restore()
    }

    private fun fill(color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; style = Paint.Style.FILL }

    private fun stroke(color: Int, width: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color; style = Paint.Style.STROKE; strokeWidth = width; strokeCap = Paint.Cap.ROUND
    }

    private fun line(canvas: Canvas, x1: Float, y1: Float, x2: Float, y2: Float, color: Int, width: Float) =
        canvas.drawLine(x1, y1, x2, y2, stroke(color, width))

    private fun dot(canvas: Canvas, x: Float, y: Float, r: Float, color: Int) = canvas.drawCircle(x, y, r, fill(color))

    private fun sun(canvas: Canvas, cx: Float, cy: Float, s: Float) {
        canvas.drawCircle(cx, cy, 4.6f * s, fill(SUN))
        for (i in 0 until 8) {
            val a = Math.PI / 4 * i
            val (c, n) = cos(a).toFloat() to sin(a).toFloat()
            line(canvas, cx + c * 7f * s, cy + n * 7f * s, cx + c * 9.6f * s, cy + n * 9.6f * s, SUN, 1.8f * s)
        }
    }

    private fun moon(canvas: Canvas, cx: Float, cy: Float, s: Float) {
        val disc = Path().apply { addCircle(cx, cy, 7.5f * s, Path.Direction.CW) }
        val bite = Path().apply { addCircle(cx + 4f * s, cy - 3.2f * s, 6.4f * s, Path.Direction.CW) }
        disc.op(bite, Path.Op.DIFFERENCE)
        canvas.drawPath(disc, fill(MOON))
    }

    /** A cloud centred on (cx, cy), about 17 units wide at scale 1. */
    private fun cloud(canvas: Canvas, cx: Float, cy: Float, s: Float, color: Int) {
        val p = Path().apply {
            addCircle(cx - 4f * s, cy + 1f * s, 4f * s, Path.Direction.CW)
            addCircle(cx + 0.5f * s, cy - 2f * s, 5.2f * s, Path.Direction.CW)
            addCircle(cx + 4.8f * s, cy + 1.2f * s, 3.8f * s, Path.Direction.CW)
            addRoundRect(cx - 8f * s, cy + 1f * s, cx + 8.6f * s, cy + 5f * s, 2f * s, 2f * s, Path.Direction.CW)
        }
        p.op(Path(), Path.Op.UNION)   // merge the overlapping shapes into one outline
        canvas.drawPath(p, fill(color))
    }

    /** Slanted rain streaks under a raised cloud. */
    private fun drops(canvas: Canvas, count: Int, length: Float, color: Int) {
        val gap = 12f / count
        for (i in 0 until count) {
            val x = 12f - gap * (count - 1) / 2 + gap * i
            line(canvas, x + 0.8f, 16.5f, x - 0.8f, 16.5f + length, color, 1.7f)
        }
    }
}
