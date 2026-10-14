package com.mafx.share

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper

class HotspotController(context: Context) {

    interface Listener {
        fun onHotspotStarted(
            ssid: String,
            password: String
        )

        fun onHotspotStopped()

        fun onHotspotError(message: String)
    }

    private val appContext = context.applicationContext

    private val wifiManager =
        appContext.getSystemService(
            Context.WIFI_SERVICE
        ) as WifiManager

    private val mainHandler =
        Handler(Looper.getMainLooper())

    private var reservation:
        WifiManager.LocalOnlyHotspotReservation? = null

    private var currentListener: Listener? = null

    @Volatile
    private var starting = false

    @Volatile
    private var stopped = false

    fun isRunning(): Boolean {
        return reservation != null
    }

    fun start(listener: Listener) {

        if (starting || reservation != null) {
            listener.onHotspotError(
                "Hotspot yana aiki ko ana ƙoƙarin kunna shi."
            )
            return
        }

        currentListener = listener
        starting = true
        stopped = false

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            starting = false

            listener.onHotspotError(
                "Wannan hanyar Hotspot tana buƙatar " +
                    "Android 8.0 ko sama."
            )
            return
        }

        try {

            wifiManager.startLocalOnlyHotspot(
                object :
                    WifiManager.LocalOnlyHotspotCallback() {

                    override fun onStarted(
                        hotspotReservation:
                            WifiManager.LocalOnlyHotspotReservation
                    ) {

                        reservation = hotspotReservation
                        starting = false

                        if (stopped) {
                            stop()
                            return
                        }

                        try {

                            val credentials =
                                if (
                                    Build.VERSION.SDK_INT >=
                                    Build.VERSION_CODES.R
                                ) {
                                    val config =
                                        hotspotReservation
                                            .softApConfiguration

                                    Pair(
                                        config.ssid.orEmpty(),
                                        config.passphrase.orEmpty()
                                    )
                                } else {

                                    @Suppress("DEPRECATION")
                                    val config =
                                        hotspotReservation
                                            .wifiConfiguration

                                    Pair(
                                        config?.SSID.orEmpty()
                                            .trim('"'),
                                        config?.preSharedKey.orEmpty()
                                            .trim('"')
                                    )
                                }

                            mainHandler.post {

                                currentListener
                                    ?.onHotspotStarted(
                                        credentials.first,
                                        credentials.second
                                    )
                            }

                        } catch (e: Exception) {

                            mainHandler.post {
                                currentListener
                                    ?.onHotspotError(
                                        "An kunna Hotspot, amma " +
                                            "an kasa karanta bayanansa: " +
                                            (e.message ?: "Unknown error")
                                    )
                            }
                        }
                    }

                    override fun onStopped() {

                        reservation = null
                        starting = false

                        mainHandler.post {
                            currentListener
                                ?.onHotspotStopped()
                        }
                    }

                    override fun onFailed(
                        reason: Int
                    ) {

                        reservation = null
                        starting = false

                        val message = when (reason) {

                            ERROR_NO_CHANNEL ->
                                "Ba a samu Wi-Fi channel ba."

                            ERROR_INCOMPATIBLE_MODE ->
                                "Wayar tana wani Wi-Fi mode " +
                                    "wanda bai dace da Hotspot ba."

                            ERROR_TETHERING_DISALLOWED ->
                                "Wayar ba ta yarda da wannan " +
                                    "hanyar Hotspot ba."

                            ERROR_GENERIC ->
                                "An kasa kunna Hotspot."

                            else ->
                                "An kasa kunna Hotspot. " +
                                    "Error code: $reason"
                        }

                        mainHandler.post {
                            currentListener
                                ?.onHotspotError(message)
                        }
                    }
                },
                mainHandler
            )

        } catch (e: SecurityException) {

            starting = false

            listener.onHotspotError(
                "An hana izinin Hotspot. Ka tabbatar " +
                    "an ba MAFX SHARE izinin Wi-Fi."
            )

        } catch (e: Exception) {

            starting = false

            listener.onHotspotError(
                "Kuskuren kunna Hotspot: " +
                    (e.message ?: "Unknown error")
            )
        }
    }

    fun stop() {

        stopped = true
        starting = false

        try {
            reservation?.close()
        } catch (_: Exception) {
        }

        reservation = null
        currentListener = null
    }
}
