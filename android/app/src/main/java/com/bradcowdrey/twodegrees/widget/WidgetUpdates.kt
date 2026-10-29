package com.bradcowdrey.twodegrees.widget

import android.content.Context
import androidx.glance.appwidget.updateAll
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.bradcowdrey.twodegrees.WeatherStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.concurrent.TimeUnit

/** Keeps the widgets current: a refresh every 30 minutes while online, and a redraw whenever the app's cities change. */
object WidgetUpdates {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    fun schedule(context: Context) {
        val request = PeriodicWorkRequestBuilder<RefreshWorker>(30, TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork("widgets", ExistingPeriodicWorkPolicy.KEEP, request)
    }

    fun redraw(context: Context) {
        val app = context.applicationContext
        scope.launch { runCatching { TwoDegreesWidget().updateAll(app) } }
    }

    class RefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
        override suspend fun doWork(): Result {
            WeatherStore.get(applicationContext).refreshNow()
            TwoDegreesWidget().updateAll(applicationContext)
            return Result.success()
        }
    }
}
