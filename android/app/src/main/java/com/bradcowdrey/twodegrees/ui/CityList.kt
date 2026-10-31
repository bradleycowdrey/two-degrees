package com.bradcowdrey.twodegrees.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bradcowdrey.twodegrees.AppFont
import com.bradcowdrey.twodegrees.Brand
import com.bradcowdrey.twodegrees.City
import com.bradcowdrey.twodegrees.Condition
import com.bradcowdrey.twodegrees.Forecast
import com.bradcowdrey.twodegrees.OpenMeteo
import com.bradcowdrey.twodegrees.TempUnit
import com.bradcowdrey.twodegrees.TextSize
import com.bradcowdrey.twodegrees.WeatherStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * Every saved city as a card on its own sky, like the iPhone's list: search to add a city (works
 * offline too), tap a card to open it, Edit to remove and reorder. The ⋮ menu holds the settings.
 */
@Composable
fun CityList(store: WeatherStore, onDismiss: () -> Unit, onLocationSetting: () -> Unit = {}) {
    val ui = LocalMetrics.current
    val state by store.state.collectAsStateWithLifecycle()
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<City>>(emptyList()) }
    var searching by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf(false) }
    val searchingText = query.trim().length >= 2

    BackHandler { if (query.isNotEmpty()) query = "" else if (editing) editing = false else onDismiss() }

    LaunchedEffect(query) {
        val text = query.trim()
        if (text.length < 2) { results = emptyList(); searching = false; return@LaunchedEffect }
        searching = true
        delay(300)   // wait for typing to pause
        results = withContext(Dispatchers.IO) { runCatching { OpenMeteo.search(text) }.getOrDefault(emptyList()) }
        searching = false
    }

    Box(Modifier.fillMaxSize().background(Color.Black).systemBarsPadding().imePadding(), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = 640.dp).fillMaxSize()) {
            Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 4.dp, top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onDismiss) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = Color.White) }
                Spacer(Modifier.weight(1f))
                if (editing) TextButton(onClick = { editing = false }) { Text("Done", style = ui.text(16f, FontWeight.SemiBold)) }
                SettingsMenu(store, state, onEdit = { editing = true }, onLocationSetting = onLocationSetting)
            }
            Text(Brand.APP_NAME, style = ui.text(32f, FontWeight.SemiBold), modifier = Modifier.padding(horizontal = 16.dp))
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = { Text("Search for a city", style = ui.text(16f).copy(color = Color.White.copy(alpha = 0.5f))) },
                leadingIcon = { Icon(Icons.Filled.Search, null, tint = Color.White.copy(alpha = 0.6f)) },
                trailingIcon = { if (query.isNotEmpty()) IconButton(onClick = { query = "" }) { Icon(Icons.Filled.Close, "Clear", tint = Color.White) } },
                singleLine = true,
                textStyle = ui.text(16f),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, autoCorrectEnabled = false, imeAction = ImeAction.Search),
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedContainerColor = Color(0xFF1E1E22), unfocusedContainerColor = Color(0xFF1E1E22),
                    focusedBorderColor = Color.Transparent, unfocusedBorderColor = Color.Transparent, cursorColor = Color.White,
                ),
                modifier = Modifier.fillMaxWidth().padding(16.dp, 10.dp),
            )
            LazyColumn(contentPadding = PaddingValues(16.dp, 4.dp, 16.dp, 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (searchingText) {
                    if (!state.canAdd) item {
                        Text("You can keep up to ${WeatherStore.MAX_CITIES} cities. Remove one to add another.", style = ui.text(15f).copy(color = Palette.textMuted))
                    }
                    if (searching && results.isEmpty()) item {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
                            Text("Searching…", style = ui.text(15f).copy(color = Palette.textMuted))
                        }
                    } else if (results.isEmpty()) item {
                        Text("No places match “${query.trim()}”.", style = ui.text(15f).copy(color = Palette.textMuted))
                    }
                    items(results, key = { it.id + it.name }) { city ->
                        val saved = state.cities.any { it.id == city.id }
                        Row(
                            Modifier.fillMaxWidth().clickable(enabled = saved || state.canAdd) {
                                store.add(city); query = ""; onDismiss()
                            }.padding(vertical = 8.dp).alpha(if (saved || state.canAdd) 1f else 0.4f),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(city.name, style = ui.text(17f, FontWeight.SemiBold))
                                Text(city.region, style = ui.text(14f).copy(color = Palette.textMuted))
                            }
                            if (saved) Icon(Icons.Filled.Check, "Saved", tint = Palette.textMuted)
                        }
                        HorizontalDivider(color = Color.White.copy(alpha = 0.1f))
                    }
                } else {
                    itemsIndexed(state.cities, key = { _, c -> c.id }) { index, city ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            if (editing) {
                                IconButton(onClick = { store.remove(city) }, enabled = state.cities.size > 1) {
                                    Icon(Icons.Filled.Delete, if (city.isCurrent) "Stop using My Location" else "Remove ${city.name}", tint = if (state.cities.size > 1) Palette.pink else Color.Gray)
                                }
                            }
                            CityCard(city, state, Modifier.weight(1f).clickable(enabled = !editing) { store.select(city); onDismiss() })
                            if (editing) {
                                Column {
                                    IconButton(onClick = { store.move(index, index - 1) }, enabled = index > 0) {
                                        Icon(Icons.Filled.KeyboardArrowUp, "Move ${city.name} up", tint = Color.White)
                                    }
                                    IconButton(onClick = { store.move(index, index + 1) }, enabled = index < state.cities.lastIndex) {
                                        Icon(Icons.Filled.KeyboardArrowDown, "Move ${city.name} down", tint = Color.White)
                                    }
                                }
                            }
                        }
                    }
                    item {
                        Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("The weather in °F and °C at once. Data: Open-Meteo, GeoNames.", style = ui.text(13f, align = TextAlign.Center).copy(color = Palette.textMuted))
                            Text("Made by ${Brand.AUTHOR} · bradcowdrey.com", style = ui.text(13f).copy(color = Palette.textMuted))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SettingsMenu(store: WeatherStore, state: WeatherStore.State, onEdit: () -> Unit, onLocationSetting: () -> Unit) {
    val ui = LocalMetrics.current
    val uri = LocalUriHandler.current
    val context = LocalContext.current
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }) { Icon(Icons.Filled.MoreVert, "More", tint = Color.White) }
        MaterialTheme(colorScheme = androidx.compose.material3.darkColorScheme()) {
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                DropdownMenuItem(text = { Text("Edit List") }, enabled = state.cities.size > 1, onClick = { open = false; onEdit() })
                HorizontalDivider()
                DropdownMenuItem(
                    text = { Text("Use My Location") },
                    onClick = { store.setUseLocation(!state.useLocation); onLocationSetting() },
                    trailingIcon = { if (state.useLocation) Icon(Icons.Filled.Check, "On") },
                )
                if (state.useLocation && state.locationStatus == com.bradcowdrey.twodegrees.LocationStatus.DENIED) {
                    // Android asks only once: point to where it's turned back on.
                    DropdownMenuItem(text = { Text("Allow Location in Settings…") }, onClick = {
                        open = false
                        context.startActivity(
                            android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                .setData(android.net.Uri.fromParts("package", context.packageName, null)),
                        )
                    })
                }
                HorizontalDivider()
                MenuLabel("Units")
                for (unit in TempUnit.entries) {
                    val label = if (unit == TempUnit.FAHRENHEIT) "°F large, °C beside" else "°C large, °F beside"
                    DropdownMenuItem(text = { Text(label) }, onClick = { store.setUnit(unit) },
                        trailingIcon = { if (state.unit == unit) Icon(Icons.Filled.Check, "Selected") })
                }
                HorizontalDivider()
                MenuLabel("Text Size")
                for (size in TextSize.entries) {
                    DropdownMenuItem(text = { Text(size.label) }, onClick = { store.setTextSize(size) },
                        trailingIcon = { if (state.textSize == size) Icon(Icons.Filled.Check, "Selected") })
                }
                HorizontalDivider()
                MenuLabel("Font")
                for (font in AppFont.entries) {
                    DropdownMenuItem(text = { Text(font.label) }, onClick = { store.setFont(font) },
                        trailingIcon = { if (state.font == font) Icon(Icons.Filled.Check, "Selected") })
                }
                HorizontalDivider()
                DropdownMenuItem(text = { Text("Share Two Degrees") }, onClick = {
                    open = false
                    val send = android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain")
                        .putExtra(android.content.Intent.EXTRA_TEXT, "${Brand.SHARE_MESSAGE} ${Brand.PRODUCT_PAGE}")
                    context.startActivity(android.content.Intent.createChooser(send, "Share Two Degrees"))
                })
                DropdownMenuItem(text = { Text("Get Two Degrees for Mac and iPhone") }, onClick = { open = false; uri.openUri(Brand.PRODUCT_PAGE) })
                DropdownMenuItem(text = { Text("Terms & Privacy") }, onClick = { open = false; uri.openUri(Brand.LEGAL) })
                DropdownMenuItem(text = { Text("Report an Issue") }, onClick = { open = false; uri.openUri(Brand.ISSUES) })
            }
        }
    }
}

@Composable
private fun MenuLabel(text: String) {
    Text(text.uppercase(), style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.6f), modifier = Modifier.padding(16.dp, 8.dp, 16.dp, 2.dp))
}

/** One city in the list: name, local time and condition on the left; both temperatures and today's range on the right; its own sky behind. */
@Composable
private fun CityCard(city: City, state: WeatherStore.State, modifier: Modifier) {
    val ui = LocalMetrics.current
    val forecast = state.forecasts[city.id]
    val unit = state.unit
    val other = unit.other
    val shape = RoundedCornerShape(ui.dp(16f))
    Row(
        modifier.clip(shape)
            .background(forecast?.let { Sky.brush(it.now.code, it.now.isDay) } ?: androidx.compose.ui.graphics.SolidColor(Color(0xFF262626)))
            .border(1.5.dp, if (city.id == state.activeID) Color.White.copy(alpha = 0.5f) else Color.Transparent, shape)
            .padding(ui.dp(14f))
            .height(ui.dp(104f))
            .semantics(mergeDescendants = true) {},
    ) {
        Column(Modifier.weight(1f)) {
            // As on the iPhone: where you are reads "My Location", with the place beneath.
            Text(if (city.isCurrent) "My Location" else city.name, style = ui.text(22f, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                if (city.isCurrent) city.name else forecast?.let { Forecast.clock(it.now.time) } ?: city.region,
                style = ui.text(14f, FontWeight.Medium), modifier = Modifier.alpha(0.85f), maxLines = 1,
            )
            Spacer(Modifier.weight(1f))
            Text(
                forecast?.let { Condition.name(it.now.code) } ?: if (city.id in state.failed) "Offline" else "Loading…",
                style = ui.text(14f, FontWeight.Medium), modifier = Modifier.alpha(0.85f),
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            if (forecast != null) {
                val t = forecast.now.temperature
                Text(reading(unit.value(t), unit), style = ui.text(40f, FontWeight.Light), maxLines = 1)
                Text(other.spaced(t), style = ui.text(15f, FontWeight.Medium), modifier = Modifier.alpha(0.8f))
                Spacer(Modifier.weight(1f))
                forecast.days.firstOrNull()?.including(t)?.let { today ->
                    Text("H:${unit.value(today.high)}${unit.symbol}  L:${unit.value(today.low)}${unit.symbol}", style = ui.text(13f, FontWeight.Medium))
                }
            } else {
                Text("––°", style = ui.text(40f, FontWeight.Light), modifier = Modifier.alpha(0.5f))
            }
        }
    }
}
