package com.bradcowdrey.twodegrees.widget

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.lifecycle.lifecycleScope
import com.bradcowdrey.twodegrees.City
import com.bradcowdrey.twodegrees.OpenMeteo
import com.bradcowdrey.twodegrees.WeatherStore
import com.bradcowdrey.twodegrees.ui.Palette
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * A widget's settings, as on the iPhone: "Use Two Degrees' City" (on: it shows the app's current city;
 * off: choose any city, saved or searched).
 */
class WidgetConfigActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(0), navigationBarStyle = SystemBarStyle.dark(0))
        super.onCreate(savedInstanceState)
        val id = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) { finish(); return }
        // Leaving without choosing keeps the default (the app's city): the widget is still added.
        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id))
        val store = WeatherStore.get(this)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                Settings(store.current, WidgetData.chosenCity(this, id)) { city ->
                    WidgetData.choose(this, id, city)
                    lifecycleScope.launch {
                        runCatching {
                            val glanceId = GlanceAppWidgetManager(this@WidgetConfigActivity).getGlanceIdBy(id)
                            TwoDegreesWidget().update(this@WidgetConfigActivity, glanceId)
                        }
                        finish()
                    }
                }
            }
        }
    }
}

@Composable
private fun Settings(state: WeatherStore.State, chosen: City?, onDone: (City?) -> Unit) {
    var useApp by remember { mutableStateOf(chosen == null) }
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<City>>(emptyList()) }
    LaunchedEffect(query) {
        val text = query.trim()
        if (text.length < 2) { results = emptyList(); return@LaunchedEffect }
        delay(300)
        results = withContext(Dispatchers.IO) { runCatching { OpenMeteo.search(text) }.getOrDefault(emptyList()) }
    }
    Column(Modifier.fillMaxSize().background(Palette.bg).systemBarsPadding().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Widget", color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.SemiBold)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Use Two Degrees' City", color = Color.White, fontSize = 17.sp)
                Text(
                    if (useApp) "Showing ${state.active.name}. Change it in Two Degrees." else "Choose a city for this widget.",
                    color = Palette.textMuted, fontSize = 14.sp,
                )
            }
            Switch(checked = useApp, onCheckedChange = { useApp = it; if (it) onDone(null) })
        }
        HorizontalDivider(color = Color.White.copy(alpha = 0.15f))
        if (!useApp) {
            OutlinedTextField(
                value = query, onValueChange = { query = it }, singleLine = true,
                placeholder = { Text("Search for a city") }, leadingIcon = { Icon(Icons.Filled.Search, null) },
                shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth(),
            )
            LazyColumn(contentPadding = PaddingValues(vertical = 4.dp)) {
                items(if (query.trim().length >= 2) results else state.cities, key = { it.id + it.name }) { city ->
                    Row(
                        Modifier.fillMaxWidth().clickable { onDone(city) }.padding(vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(if (city.isCurrent) "My Location" else city.name, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Medium)
                            Text(if (city.isCurrent) "Wherever you are · now ${city.name}" else city.region, color = Palette.textMuted, fontSize = 14.sp)
                        }
                        if (chosen?.id == city.id) Icon(Icons.Filled.Check, "Chosen", tint = Color.White)
                    }
                    HorizontalDivider(color = Color.White.copy(alpha = 0.08f))
                }
            }
        }
    }
}
