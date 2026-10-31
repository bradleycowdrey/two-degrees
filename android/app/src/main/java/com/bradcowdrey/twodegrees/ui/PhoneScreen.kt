package com.bradcowdrey.twodegrees.ui

import android.content.Intent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.NearMe
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bradcowdrey.twodegrees.Brand
import com.bradcowdrey.twodegrees.WeatherStore

/** What the self-test asks the screen to show (CI screenshots). */
data class ShowOptions(val scrollTo: String? = null, val list: Boolean = false, val locationPrompt: Boolean = false)

/**
 * The app's layout, after the iPhone's: one full-screen page per city that you swipe between, on that
 * city's sky, with a bottom bar of Share, page dots and the city list.
 */
@Composable
fun PhoneScreen(
    store: WeatherStore,
    show: ShowOptions,
    skipTerms: Boolean,
    onReady: () -> Unit = {},
    onLocationSetting: () -> Unit = {},
) {
    val state by store.state.collectAsStateWithLifecycle()
    val tablet = LocalConfiguration.current.screenWidthDp >= 600
    val metrics = Metrics.of(state.textSize.scale * if (tablet) 1.3f else 1f, state.font)
    var showingList by rememberSaveable { mutableStateOf(show.list) }
    var agreed by remember { mutableStateOf(skipTerms || store.termsAccepted) }

    LaunchedEffect(agreed) { if (agreed) onReady() }
    if (!agreed) {
        TermsScreen(onAgree = { store.termsAccepted = true; agreed = true })
        return
    }
    // Right after the terms, once: "Show the weather where you are?"
    if (show.locationPrompt || (!skipTerms && !state.locationAsked)) {
        LocationPromptScreen(onAnswer = { yes -> store.answerLocationPrompt(yes); if (yes) onLocationSetting() })
        return
    }
    CompositionLocalProvider(LocalMetrics provides metrics) {
        val sky = state.activeForecast?.now
        val (top, bottom) = Sky.colors(sky?.code ?: 3, sky?.isDay ?: true)
        val topColor by animateColorAsState(top, tween(600), label = "sky top")
        val bottomColor by animateColorAsState(bottom, tween(600), label = "sky bottom")
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(topColor, bottomColor)))) {
            val index = state.cities.indexOfFirst { it.id == state.activeID }.coerceAtLeast(0)
            val pager = rememberPagerState(initialPage = index) { state.cities.size }
            // The pager and the store's current city follow each other.
            LaunchedEffect(index) { if (pager.currentPage != index) pager.scrollToPage(index) }
            LaunchedEffect(pager) {
                snapshotFlow { pager.settledPage }.collect { page ->
                    store.current.cities.getOrNull(page)?.let { if (it.id != store.current.activeID) store.select(it) }
                }
            }
            HorizontalPager(pager, Modifier.fillMaxSize(), key = { state.cities.getOrNull(it)?.id ?: it }) { page ->
                state.cities.getOrNull(page)?.let { CityPage(it, state, store, show.scrollTo, bottomInset = 64.dp) }
            }
            BottomBar(state, onList = { showingList = true }, modifier = Modifier.align(Alignment.BottomCenter))
        }
        if (showingList) CityList(store, onDismiss = { showingList = false }, onLocationSetting = onLocationSetting)
    }
}

/** Share · page dots · city list, on a dark translucent bar. */
@Composable
private fun BottomBar(state: WeatherStore.State, onList: () -> Unit, modifier: Modifier) {
    val context = LocalContext.current
    Box(modifier.fillMaxWidth().background(Color(0x99101216)).navigationBarsPadding()) {
        HorizontalDivider(color = Color.White.copy(alpha = 0.15f))
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = {
                val send = Intent(Intent.ACTION_SEND).setType("text/plain")
                    .putExtra(Intent.EXTRA_SUBJECT, Brand.APP_NAME)
                    .putExtra(Intent.EXTRA_TEXT, "${Brand.SHARE_MESSAGE} ${Brand.PRODUCT_PAGE}")
                context.startActivity(Intent.createChooser(send, "Share Two Degrees"))
            }) { Icon(Icons.Filled.Share, "Share Two Degrees", tint = Color.White) }
            Row(
                Modifier.weight(1f).semantics {
                    val i = state.cities.indexOfFirst { it.id == state.activeID } + 1
                    contentDescription = "${state.active.name}, city $i of ${state.cities.size}"
                },
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
            ) {
                state.cities.forEach { city ->
                    val alpha = if (city.id == state.activeID) 1f else 0.35f
                    if (city.isCurrent) {
                        // Where you are gets an arrow, as on the iPhone.
                        Icon(Icons.Filled.NearMe, null, tint = Color.White.copy(alpha = alpha), modifier = Modifier.size(9.dp))
                    } else {
                        Box(Modifier.size(7.dp).clip(CircleShape).background(Color.White.copy(alpha = alpha)))
                    }
                }
            }
            IconButton(onClick = onList) { Icon(Icons.AutoMirrored.Filled.List, "Cities and settings", tint = Color.White) }
        }
    }
}
