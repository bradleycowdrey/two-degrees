package com.bradcowdrey.twodegrees

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.math.roundToLong

/** What Use My Location found. */
sealed interface LocationResult {
    data class Found(val city: City) : LocationResult
    /** Location is off, or Two Degrees isn't allowed to use it. */
    data object Denied : LocationResult
    /** No fix in time. */
    data object Unavailable : LocationResult
}

/** Where Use My Location stands, for the settings. */
enum class LocationStatus { IDLE, LOCATING, FOUND, DENIED, UNAVAILABLE, OFF }

/**
 * Use My Location on Android: one rough fix (approximate location is enough), named by the phone's
 * geocoder, or by the bundled city list when that can't (offline). The permission itself is asked by
 * the activity; this only reads.
 */
object PhoneLocation {
    fun allowed(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    suspend fun currentCity(context: Context): LocationResult {
        if (!allowed(context)) return LocationResult.Denied
        val manager = context.getSystemService(LocationManager::class.java) ?: return LocationResult.Unavailable
        val providers = manager.getProviders(true)
        if (providers.isEmpty()) return LocationResult.Denied   // Location is off in the phone's settings
        val location = fix(manager, providers) ?: return LocationResult.Unavailable
        return LocationResult.Found(name(context, location.latitude, location.longitude))
    }

    /** A fix from the last 10 minutes, or a fresh one within 15 seconds. */
    @SuppressLint("MissingPermission")
    private suspend fun fix(manager: LocationManager, providers: List<String>): Location? {
        val recent = providers.mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
            .maxByOrNull { it.time }
        if (recent != null && System.currentTimeMillis() - recent.time < 10 * 60 * 1000) return recent
        val provider = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.FUSED_PROVIDER, LocationManager.GPS_PROVIDER)
            .firstOrNull { it in providers } ?: providers.first()
        val fresh = withTimeoutOrNull(15_000) {
            suspendCancellableCoroutine { continuation ->
                if (Build.VERSION.SDK_INT >= 30) {
                    val cancel = CancellationSignal()
                    continuation.invokeOnCancellation { cancel.cancel() }
                    manager.getCurrentLocation(provider, cancel, { it.run() }) { continuation.resume(it) }
                } else {
                    @Suppress("DEPRECATION")
                    manager.requestSingleUpdate(provider, { continuation.resume(it) }, android.os.Looper.getMainLooper())
                }
            }
        }
        return fresh ?: recent
    }

    /** The place's name and region; its coordinates rounded to about a kilometre, all the forecast needs. */
    suspend fun name(context: Context, latitude: Double, longitude: Double): City {
        val lat = (latitude * 100).roundToLong() / 100.0
        val lon = (longitude * 100).roundToLong() / 100.0
        val address = withContext(Dispatchers.IO) {
            if (!Geocoder.isPresent()) return@withContext null
            withTimeoutOrNull(8_000) {
                runCatching {
                    val geocoder = Geocoder(context, Locale.getDefault())
                    if (Build.VERSION.SDK_INT >= 33) {
                        suspendCancellableCoroutine { c ->
                            geocoder.getFromLocation(latitude, longitude, 1, object : Geocoder.GeocodeListener {
                                override fun onGeocode(addresses: MutableList<android.location.Address>) { c.resume(addresses.firstOrNull()) }
                                override fun onError(errorMessage: String?) { c.resume(null) }
                            })
                        }
                    } else {
                        @Suppress("DEPRECATION")
                        geocoder.getFromLocation(latitude, longitude, 1)?.firstOrNull()
                    }
                }.getOrNull()
            }
        }
        val name = address?.locality ?: address?.subAdminArea
        if (address != null && name != null) {
            val region = listOfNotNull(address.adminArea, address.countryName).filter { it != name }.joinToString(", ")
            return City(name, region, lat, lon, isCurrent = true)
        }
        val nearest = withContext(Dispatchers.Default) { OfflineCities.nearest(lat, lon) }
        return (nearest ?: City("My Location", "", lat, lon)).copy(isCurrent = true)
    }
}
