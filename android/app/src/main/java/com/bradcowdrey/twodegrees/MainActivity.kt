package com.bradcowdrey.twodegrees

import android.Manifest
import android.content.Intent
import android.os.Bundle
import android.text.format.DateFormat
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.lifecycleScope
import com.bradcowdrey.twodegrees.ui.PhoneScreen
import com.bradcowdrey.twodegrees.ui.ShowOptions
import kotlinx.coroutines.launch

/**
 * The app: one screen of city pages. Extras for the self-test (CI): `selftest` runs the checks and
 * writes files/report.txt (`locate` adds Use My Location); `show` scrolls to "days", "tiles" or "more"
 * (the newer tiles), opens tomorrow's "day", or opens the "list" (with its ⋮ "menu", or its "units" page).
 */
class MainActivity : ComponentActivity() {
    private val store by lazy { WeatherStore.get(this) }
    private var ready = false
    /** Counts widget taps, so the screen closes the list each time. */
    private var widgetTaps by mutableIntStateOf(0)

    /** Asks for approximate location once; after that, Android's own settings decide. */
    private val askLocation = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { store.locateNow() }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(0), navigationBarStyle = SystemBarStyle.dark(0))
        super.onCreate(savedInstanceState)
        Forecast.uses24Hour = DateFormat.is24HourFormat(this)
        val selfTest = intent.getBooleanExtra("selftest", false)
        val show = intent.getStringExtra("show")
        store.locate = { PhoneLocation.currentCity(applicationContext) }
        // Not again when the activity is recreated, or reopened from Recents.
        val fromHistory = (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        if (savedInstanceState == null && !fromHistory) openWidgetCity(intent)
        setContent {
            PhoneScreen(
                store,
                ShowOptions(
                    scrollTo = show?.takeIf { it in setOf("days", "tiles", "more") },
                    list = show in setOf("list", "menu", "units", "notifications"),
                    locationPrompt = show == "location",
                    day = show == "day",
                    menu = when (show) { "menu" -> "main"; "units", "notifications" -> show; else -> null },
                ),
                skipTerms = selfTest,
                // Use My Location starts once the terms are agreed (the self-test checks it itself).
                onReady = { if (!selfTest) { ready = true; useLocation() } },
                onLocationSetting = ::useLocation,
                widgetTaps = widgetTaps,
            )
        }
        if (selfTest) lifecycleScope.launch { SelfTest.run(this@MainActivity, store, locate = intent.getBooleanExtra("locate", false)) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        openWidgetCity(intent)
    }

    /** A widget tap: opens its city's page, over anything open (the list, a day). */
    private fun openWidgetCity(intent: Intent) {
        val city = WidgetTap.decode(intent.getStringExtra(WidgetTap.KEY)) ?: return
        store.openFromWidget(city)
        widgetTaps++
    }

    /** Finds where you are, asking for permission the first time. */
    private fun useLocation() {
        if (!store.current.locationAsked) return   // our own question comes first
        if (!store.current.useLocation) { store.locateNow(); return }
        val prefs = getSharedPreferences("two-degrees", MODE_PRIVATE)
        if (!PhoneLocation.allowed(this) && !prefs.getBoolean("locationAsked", false)) {
            prefs.edit().putBoolean("locationAsked", true).apply()
            askLocation.launch(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION))
        } else {
            store.locateNow()
        }
    }

    override fun onResume() {
        super.onResume()
        // Coming back to the app checks where you are and refreshes anything older than one refresh interval.
        if (ready) store.locateNow()
        store.refreshIfDue()
    }
}
