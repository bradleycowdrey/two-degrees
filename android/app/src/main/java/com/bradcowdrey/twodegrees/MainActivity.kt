package com.bradcowdrey.twodegrees

import android.os.Bundle
import android.text.format.DateFormat
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import com.bradcowdrey.twodegrees.ui.PhoneScreen
import com.bradcowdrey.twodegrees.ui.ShowOptions
import kotlinx.coroutines.launch

/**
 * The app: one screen of city pages. Extras for the self-test (CI): `selftest` runs the checks and
 * writes files/report.txt; `show` scrolls to "days" or "tiles", or opens the "list".
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(0), navigationBarStyle = SystemBarStyle.dark(0))
        super.onCreate(savedInstanceState)
        Forecast.uses24Hour = DateFormat.is24HourFormat(this)
        val store = WeatherStore.get(this)
        val selfTest = intent.getBooleanExtra("selftest", false)
        val show = intent.getStringExtra("show")
        setContent {
            PhoneScreen(store, ShowOptions(scrollTo = show?.takeIf { it != "list" }, list = show == "list"), skipTerms = selfTest)
        }
        if (selfTest) lifecycleScope.launch { SelfTest.run(this@MainActivity, store) }
    }

    override fun onResume() {
        super.onResume()
        // Coming back to the app refreshes anything older than one refresh interval.
        WeatherStore.get(this).refreshIfDue()
    }
}
