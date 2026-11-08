package com.bradcowdrey.twodegrees.ui

import android.annotation.SuppressLint
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Umbrella
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.bradcowdrey.twodegrees.Alert
import com.bradcowdrey.twodegrees.Alerts
import com.bradcowdrey.twodegrees.City
import com.bradcowdrey.twodegrees.Forecast
import com.bradcowdrey.twodegrees.NextHours
import com.bradcowdrey.twodegrees.TempUnit
import com.bradcowdrey.twodegrees.Units

/** A full-screen page over the city pages: a day, an alert's full text, or the rain map. */
sealed interface Overlay {
    data class Day(val cityID: String, val index: Int) : Overlay
    data class AlertText(val city: City, val alert: Alert, val timeZone: String) : Overlay
    data class RainMap(val city: City) : Overlay
}

/** Extreme and Severe red, Moderate orange, Minor and Unknown yellow. */
fun alertColor(severity: String): Color = when (severity) {
    "Extreme", "Severe" -> Color(0xFFE5484D)
    "Moderate" -> Color(0xFFF2A65A)
    else -> Color(0xFFE9C98A)
}

/** One card per active alert, most severe first, above everything else on the page. */
@Composable
fun AlertCards(city: City, alerts: List<Alert>, forecast: Forecast, onOpen: (Overlay) -> Unit) {
    val ui = LocalMetrics.current
    Column(verticalArrangement = Arrangement.spacedBy(ui.dp(10f))) {
        alerts.forEach { alert ->
            val color = alertColor(alert.severity)
            val until = Alerts.until(alert, forecast.timeZone, forecast.now.time.toLocalDate())
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(ui.dp(16f))).background(color.copy(alpha = 0.22f))
                    .border(1.dp, color.copy(alpha = 0.7f), RoundedCornerShape(ui.dp(16f)))
                    .clickable { onOpen(Overlay.AlertText(city, alert, forecast.timeZone)) }
                    .padding(ui.dp(14f))
                    .semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(ui.dp(12f)),
            ) {
                Icon(Icons.Filled.Warning, null, tint = color, modifier = Modifier.size(ui.dp(26f)))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(alert.event, style = ui.text(17f, FontWeight.SemiBold))
                    if (until != null) Text(until, style = ui.text(14f, FontWeight.Medium), modifier = Modifier.alpha(0.9f))
                    alert.senderName?.let { Text(it, style = ui.text(13f), modifier = Modifier.alpha(0.7f)) }
                }
                Icon(Icons.Filled.ChevronRight, "Read the alert", tint = Color.White.copy(alpha = 0.7f))
            }
        }
    }
}

/** Next 2 hours: eight 15-minute bars (rain blue, snow white) and one line above them. */
@Composable
fun NextHoursCard(forecast: Forecast, units: Units) {
    val ui = LocalMetrics.current
    val steps = forecast.steps.take(8)
    val snow = NextHours.snowy(forecast)
    val color = if (snow) Color.White else Palette.rain
    val peak = steps.maxOfOrNull { it.precipitation } ?: 0.0
    Card("Next 2 hours", Icons.Filled.Umbrella) {
        Text(NextHours.sentence(forecast), style = ui.text(15f))
        HorizontalDivider(color = Color.White.copy(alpha = 0.2f))
        // Heights by mm: a light shower (1 mm in 15 minutes) fills the bar; heavier stays full.
        val top = maxOf(peak, 1.0)
        Canvas(Modifier.fillMaxWidth().height(ui.dp(64f)).semantics { contentDescription = NextHours.sentence(forecast) }) {
            val gap = 6.dp.toPx()
            val w = (size.width - gap * (steps.size - 1)) / steps.size.coerceAtLeast(1)
            steps.forEachIndexed { i, step ->
                val x = i * (w + gap)
                drawRoundRect(Color.White.copy(alpha = 0.12f), Offset(x, 0f), Size(w, size.height), CornerRadius(4.dp.toPx()))
                val h = (size.height * (step.precipitation / top).toFloat()).coerceIn(if (step.precipitation >= NextHours.WET) 3.dp.toPx() else 0f, size.height)
                if (h > 0) drawRoundRect(color, Offset(x, size.height - h), Size(w, h), CornerRadius(4.dp.toPx()))
            }
        }
        Row(Modifier.fillMaxWidth()) {
            steps.forEachIndexed { i, step ->
                Text(
                    if (i == 0) "Now" else if (i % 2 == 0) Forecast.clock(step.time) else "",
                    style = ui.text(11f, FontWeight.SemiBold), maxLines = 1, softWrap = false,
                    modifier = Modifier.weight(1f).alpha(0.7f),
                )
            }
        }
        if (peak >= NextHours.WET) {
            Text("Up to ${units.rain.text(peak)} in 15 minutes", style = ui.text(13f), modifier = Modifier.alpha(0.75f))
        }
    }
}

/** The rain map's card: opens it full screen at this city. */
@Composable
fun MapCard(city: City, onOpen: (Overlay) -> Unit) {
    val ui = LocalMetrics.current
    Box(Modifier.clickable { onOpen(Overlay.RainMap(city)) }.semantics(mergeDescendants = true) {}) {
        Card("Map", Icons.Filled.Map) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Rain radar around ${city.name}: the past two hours.", style = ui.text(15f), modifier = Modifier.weight(1f))
                Icon(Icons.Filled.ChevronRight, "Open the map", tint = Color.White.copy(alpha = 0.7f))
            }
        }
    }
}

/** A full-screen page with a close button top left and a title beside it. */
@Composable
fun OverlayPage(title: String, onClose: () -> Unit, background: Modifier, actions: @Composable () -> Unit = {}, content: @Composable () -> Unit) {
    val ui = LocalMetrics.current
    Column(Modifier.fillMaxSize().then(background).statusBarsPadding().navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onClose) { Icon(Icons.Filled.Close, "Close", tint = Color.White) }
            Text(title, style = ui.text(17f, FontWeight.SemiBold), maxLines = 1, modifier = Modifier.weight(1f))
            actions()
        }
        Box(Modifier.weight(1f).fillMaxWidth()) { content() }
    }
}

/** An alert's full text, from the NWS. */
@Composable
fun AlertPage(overlay: Overlay.AlertText, onClose: () -> Unit) {
    val ui = LocalMetrics.current
    val uri = LocalUriHandler.current
    val alert = overlay.alert
    val color = alertColor(alert.severity)
    OverlayPage(alert.event, onClose, Modifier.background(Color(0xFF15171C))) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(Icons.Filled.Warning, null, tint = color, modifier = Modifier.size(ui.dp(28f)))
                Column {
                    Text(alert.event, style = ui.text(22f, FontWeight.SemiBold))
                    Text(
                        listOfNotNull(Alerts.until(alert, overlay.timeZone, null), alert.senderName).joinToString(" · "),
                        style = ui.text(14f), modifier = Modifier.alpha(0.75f),
                    )
                }
            }
            alert.headline?.let { Text(it, style = ui.text(17f, FontWeight.Medium)) }
            alert.description?.let { Text(it.trim(), style = ui.text(15f)) }
            alert.instruction?.let {
                Column(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(color.copy(alpha = 0.18f)).padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text("WHAT TO DO", style = ui.text(12f, FontWeight.SemiBold), modifier = Modifier.alpha(0.7f))
                    Text(it.trim(), style = ui.text(15f))
                }
            }
            Text(
                "More at weather.gov", style = ui.text(15f, FontWeight.Medium).copy(textDecoration = TextDecoration.Underline),
                modifier = Modifier.clickable { uri.openUri(Alerts.moreURL(overlay.city)) },
            )
            Text(Alerts.NOTE, style = ui.text(13f), modifier = Modifier.alpha(0.65f).padding(bottom = 24.dp))
        }
    }
}

/** The rain map: the shared web page (RainViewer radar on an OpenFreeMap map), full screen. */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun RainMapPage(city: City, unit: TempUnit, onClose: () -> Unit) {
    val ui = LocalMetrics.current
    val context = LocalContext.current
    var offline by remember {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        val caps = manager?.getNetworkCapabilities(manager.activeNetwork)
        mutableStateOf(caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) != true)
    }
    val url = "https://bradleycowdrey.github.io/two-degrees/radar.html?lat=%.4f&lon=%.4f&z=7&units=%s"
        .format(java.util.Locale.US, city.latitude, city.longitude, unit.letter)
    OverlayPage("Rain map · ${city.name}", onClose, Modifier.background(Color(0xFF111317))) {
        if (offline) {
            Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Filled.WifiOff, null, tint = Color.White, modifier = Modifier.size(32.dp))
                Text("The map needs an internet connection.", style = ui.text(16f), modifier = Modifier.padding(top = 12.dp).widthIn(max = 320.dp))
            }
        } else {
            AndroidView(
                factory = { ctx ->
                    WebView(ctx).apply {
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        setBackgroundColor(android.graphics.Color.rgb(17, 19, 23))
                        webViewClient = object : WebViewClient() {
                            override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                                if (request?.isForMainFrame == true) offline = true
                            }
                        }
                        loadUrl(url)
                    }
                },
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}
