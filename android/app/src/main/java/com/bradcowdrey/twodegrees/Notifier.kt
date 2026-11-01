package com.bradcowdrey.twodegrees

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * Severe Weather and Rain Starting Soon, both off until turned on, for where you are (or the first
 * city). Checked by the 30-minute background refresh. Each alert once (by its id), rain at most once
 * every 3 hours; both remembered in preferences.
 */
object Notifier {
    private const val CHANNEL = "weather"
    private const val RAIN_INTERVAL_MS = 3 * 60 * 60 * 1000L

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(CHANNEL, "Weather", NotificationManager.IMPORTANCE_HIGH)
            .apply { description = "Severe weather alerts and rain starting soon" }
        context.getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }

    /** Whether Two Degrees may post notifications (Android 13 asks; earlier, they can be turned off in Settings). */
    fun allowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    /** Whether the system's permission question should be asked (Android 13 and later, not yet granted). */
    fun needsPermission(context: Context): Boolean = Build.VERSION.SDK_INT >= 33 &&
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED

    /** Two Degrees' notification settings in the phone's Settings app. */
    fun settingsIntent(context: Context): Intent =
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** After a refresh: anything new to say? */
    fun check(context: Context, store: WeatherStore) {
        val s = store.current
        if ((!s.notifySevere && !s.notifyRain) || !allowed(context)) return
        val city = s.notifyCity
        val prefs = context.getSharedPreferences("two-degrees", Context.MODE_PRIVATE)
        if (s.notifySevere) {
            val alerts = s.alerts[city.id].orEmpty()
            val sent = prefs.getStringSet("notifiedAlerts", emptySet()).orEmpty()
            val fresh = alerts.filter { Alerts.notifies(it) && it.id !in sent }
            fresh.forEach { alert -> post(context, alert.id.hashCode(), "${alert.event} · ${city.name}", alert.headline ?: alert.event) }
            // Keep only the ids still active (and those just sent), so the list stays small.
            val active = alerts.map { it.id }.toSet()
            prefs.edit().putStringSet("notifiedAlerts", sent.filter { it in active }.toSet() + fresh.map { it.id }).apply()
        }
        if (s.notifyRain) {
            val forecast = s.forecasts[city.id] ?: return
            val (time, snow) = NextHours.startingSoon(forecast) ?: return
            val now = System.currentTimeMillis()
            if (now - prefs.getLong("rainNotifiedAt", 0) < RAIN_INTERVAL_MS) return
            val word = if (snow) "Snow" else "Rain"
            post(context, 1, "$word starting soon · ${city.name}", "$word is expected around ${Forecast.clock(time)}.")
            prefs.edit().putLong("rainNotifiedAt", now).apply()
        }
    }

    @SuppressLint("MissingPermission")   // checked by allowed() first
    private fun post(context: Context, id: Int, title: String, body: String) {
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(id, notification) }
    }
}
