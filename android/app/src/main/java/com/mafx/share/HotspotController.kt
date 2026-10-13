package com.mafx.share

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.Executor

class HotspotController(
    context: Context
) {

    private val appContext = context.applicationContext

    private val wifiManager =
        appContext.getSystemService(
            Context.WIFI_SERVICE
        ) as WifiManager

    private var reservation:
        WifiManager.LocalOnlyHotspotReservation? = null

    private val mainHandler =
        Handler(Looper.getMainLooper())

    private val executor = Executor { command ->
        mainHandler.post(command)
    }

    var onHotspotReady:
        ((ssid: String, password: String) -> Unit)? = null

    var onHotspotStopped:
        (() -> Unit)? = null

    var onError:
        ((String) -> Unit)? = null

    private var isStarting = false

    fun startHotspot() {

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            onError?.invoke(
                "This Android version does not support this hotspot method."
            )
            return
        }

        if (reservation != null || isStarting) {
            return
        }

        isStarting = true

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {

                wifiManager.startLocalOnlyHotspot(
                    executor,
                    object :
                        WifiManager.LocalOnlyHotspotCallback() {

                        override fun onStarted(
                            newReservation:
                                WifiManager.LocalOnlyHotspotReservation
                        ) {
                            isStarting = false
                            reservation = newReservation

                            publishCredentials(newReservation)
                        }

                        override fun onStopped() {
                            isStarting = false
                            reservation = null

                            onHotspotStopped?.invoke()
                        }

                        override fun onFailed(reason: Int) {
                            isStarting = false

                            onError?.invoke(
                                "Hotspot failed to start. Error: $reason"
                            )
                        }
                    }
                )

            } else {

                @Suppress("DEPRECATION")
                wifiManager.startLocalOnlyHotspot(
                    object :
                        WifiManager.LocalOnlyHotspotCallback() {

                        override fun onStarted(
                            newReservation:
                                WifiManager.LocalOnlyHotspotReservation
                        ) {
                            isStarting = false
                            reservation = newReservation

                            publishCredentials(newReservation)
                        }

                        override fun onStopped() {
                            isStarting = false
                            reservation = null

                            onHotspotStopped?.invoke()
                        }

                        override fun onFailed(reason: Int) {
                            isStarting = false

                            onError?.invoke(
                                "Hotspot failed to start. Error: $reason"
                            )
                        }
                    },
                    mainHandler
                )
            }

        } catch (e: SecurityException) {
            isStarting = false

            onError?.invoke(
                "Permission denied. Allow the required nearby Wi-Fi permission first."
            )

        } catch (e: Exception) {
            isStarting = false

            Log.e(
                "MAFX_HOTSPOT",
                "Unable to start hotspot",
                e
            )

            onError?.invoke(
                e.message ?: "Unknown hotspot error"
            )
        }
    }

    private fun publishCredentials(
        hotspotReservation:
            WifiManager.LocalOnlyHotspotReservation
    ) {

        try {
            @Suppress("DEPRECATION")
            val configuration =
                hotspotReservation.wifiConfiguration

            @Suppress("DEPRECATION")
            val ssid = configuration?.SSID

            @Suppress("DEPRECATION")
            val password = configuration?.preSharedKey

            if (
                ssid.isNullOrBlank() ||
                password.isNullOrBlank()
            ) {
                onError?.invoke(
                    "Android did not provide hotspot credentials."
                )
                return
            }

            onHotspotReady?.invoke(
                ssid.removeSurrounding("\""),
                password.removeSurrounding("\"")
            )

        } catch (e: Exception) {
            Log.e(
                "MAFX_HOTSPOT",
                "Unable to read hotspot credentials",
                e
            )

            onError?.invoke(
                "Unable to read hotspot details."
            )
        }
    }

    fun stopHotspot() {
        isStarting = false

        try {
            reservation?.close()
        } catch (e: Exception) {
            Log.e(
                "MAFX_HOTSPOT",
                "Error stopping hotspot",
                e
            )
        } finally {
            reservation = null
        }
    }

    fun isHotspotRunning(): Boolean {
        return reservation != null
    }
}
