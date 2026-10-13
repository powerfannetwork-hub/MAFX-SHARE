package com.mafx.share

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.NetworkInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Looper
import androidx.core.content.ContextCompat

/**
 * Manages Wi-Fi Direct discovery and connections for MAFX SHARE.
 *
 * This class manages peer discovery and connection only.
 * File transfer must be started separately after a connection succeeds.
 */
internal class WifiDirectManager(
    private val context: Context,
    private val listener: Listener
) {
    interface Listener {
        fun onWifiDirectStateChanged(enabled: Boolean)
        fun onPeersAvailable(peers: List<WifiP2pDevice>)
        fun onConnectionChanged(info: WifiP2pInfo?)
        fun onError(message: String)
    }

    private val manager: WifiP2pManager? =
        context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager

    private var channel: WifiP2pManager.Channel? = null
    private var receiverRegistered = false
    private var discoveryRunning = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val state = intent.getIntExtra(
                        WifiP2pManager.EXTRA_WIFI_STATE,
                        -1
                    )

                    listener.onWifiDirectStateChanged(
                        state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    )
                }

                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    requestPeers()
                }

                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    handleConnectionChanged(intent)
                }
            }
        }
    }

    private val intentFilter = IntentFilter().apply {
        addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
        addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
        addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
    }

    fun initialize() {
        if (!hasRequiredPermissions()) {
            listener.onError(
                "Wi-Fi Direct permission is missing. Grant the required permission first."
            )
            return
        }

        val wifiManager = manager
        if (wifiManager == null) {
            listener.onError("Wi-Fi Direct is not supported on this device.")
            return
        }

        if (channel != null) {
            registerReceiverIfNeeded()
            return
        }

        channel = wifiManager.initialize(
            context,
            Looper.getMainLooper()
        ) {
            channel = null
            discoveryRunning = false
            listener.onError(
                "Wi-Fi Direct connection channel was lost. Please initialize it again."
            )
        }

        if (channel == null) {
            listener.onError("Unable to initialize Wi-Fi Direct.")
            return
        }

        registerReceiverIfNeeded()
    }

    fun discoverPeers() {
        if (!ready()) return

        manager?.discoverPeers(
            channel,
            object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    discoveryRunning = true
                }

                override fun onFailure(reason: Int) {
                    discoveryRunning = false
                    listener.onError(
                        "Device discovery failed: ${failureReason(reason)}"
                    )
                }
            }
        )
    }

    fun requestPeers() {
        if (!ready()) return

        manager?.requestPeers(
            channel
        ) { devices: WifiP2pDeviceList ->
            listener.onPeersAvailable(devices.deviceList.toList())
        }
    }

    fun connect(device: WifiP2pDevice) {
        if (!ready()) return

        val config = WifiP2pConfig().apply {
            deviceAddress = device.deviceAddress
        }

        manager?.connect(
            channel,
            config,
            object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    // Connection negotiation has started.
                    // Actual connection status arrives via the broadcast receiver.
                }

                override fun onFailure(reason: Int) {
                    listener.onError(
                        "Unable to connect to ${device.deviceName}: " +
                            failureReason(reason)
                    )
                }
            }
        )
    }

    fun cancelDiscovery() {
        if (!ready()) return

        manager?.stopPeerDiscovery(
            channel,
            object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    discoveryRunning = false
                }

                override fun onFailure(reason: Int) {
                    discoveryRunning = false
                }
            }
        )
    }

    fun disconnect() {
        if (!ready()) return

        manager?.cancelConnect(
            channel,
            object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    // The connection-change broadcast reports the final state.
                }

                override fun onFailure(reason: Int) {
                    listener.onError(
                        "Unable to cancel the Wi-Fi Direct connection: " +
                            failureReason(reason)
                    )
                }
            }
        )
    }

    fun release() {
        if (receiverRegistered) {
            try {
                context.unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
                // The receiver was already unregistered.
            }

            receiverRegistered = false
        }

        discoveryRunning = false
        channel = null
    }

    private fun handleConnectionChanged(intent: Intent) {
        val networkInfo = getNetworkInfo(intent)

        if (networkInfo?.isConnected != true) {
            listener.onConnectionChanged(null)
            return
        }

        if (!ready()) return

        manager?.requestConnectionInfo(
            channel
        ) { info: WifiP2pInfo ->
            listener.onConnectionChanged(info)
        }
    }

    @Suppress("DEPRECATION")
    private fun getNetworkInfo(intent: Intent): NetworkInfo? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(
                WifiP2pManager.EXTRA_NETWORK_INFO,
                NetworkInfo::class.java
            )
        } else {
            intent.getParcelableExtra(
                WifiP2pManager.EXTRA_NETWORK_INFO
            )
        }
    }

    private fun registerReceiverIfNeeded() {
        if (receiverRegistered) return

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(
                    receiver,
                    intentFilter,
                    Context.RECEIVER_NOT_EXPORTED
                )
            } else {
                @Suppress("DEPRECATION")
                context.registerReceiver(receiver, intentFilter)
            }

            receiverRegistered = true
        } catch (exception: SecurityException) {
            listener.onError(
                "Unable to register Wi-Fi Direct receiver: " +
                    (exception.message ?: "permission denied")
            )
        }
    }

    private fun ready(): Boolean {
        if (!hasRequiredPermissions()) {
            listener.onError(
                "Wi-Fi Direct permission is missing. Grant the required permission first."
            )
            return false
        }

        if (manager == null || channel == null) {
            listener.onError(
                "Wi-Fi Direct is not initialized. Initialize it first."
            )
            return false
        }

        return true
    }

    private fun hasRequiredPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.NEARBY_WIFI_DEVICES
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun failureReason(reason: Int): String {
        return when (reason) {
            WifiP2pManager.P2P_UNSUPPORTED ->
                "Wi-Fi Direct is not supported."

            WifiP2pManager.BUSY ->
                "The Wi-Fi Direct service is busy. Try again."

            WifiP2pManager.ERROR ->
                "A system error occurred."

            else ->
                "Unknown error (code $reason)."
        }
    }
}
