package com.mafx.share

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Looper
import androidx.core.content.ContextCompat

/**
 * Wi-Fi Direct manager for MAFX SHARE.
 *
 * Responsibilities:
 * - Discover nearby Wi-Fi Direct devices.
 * - Request a connection to a selected device.
 * - Create a Wi-Fi Direct group for receiving.
 * - Report connection information to the Activity.
 *
 * This class does not replace TransferClient or TransferServer.
 */
class WifiDirectManager(
    context: Context,
    private val listener: Listener
) {

    interface Listener {
        fun onWifiP2pStateChanged(enabled: Boolean)

        fun onPeersAvailable(peers: List<WifiP2pDevice>)

        fun onConnectionInfoAvailable(info: WifiP2pInfo)

        fun onDisconnected()

        fun onError(message: String)
    }

    private val appContext = context.applicationContext

    private val manager: WifiP2pManager? =
        appContext.getSystemService(Context.WIFI_P2P_SERVICE)
            as? WifiP2pManager

    private val channel: WifiP2pManager.Channel? =
        manager?.initialize(
            appContext,
            Looper.getMainLooper()
        ) {
            listener.onError(
                "Wi-Fi Direct channel was disconnected. Try again."
            )
        }

    private var registered = false

    private val receiver = object : BroadcastReceiver() {

        override fun onReceive(
            context: Context?,
            intent: Intent?
        ) {
            when (intent?.action) {

                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val state = intent.getIntExtra(
                        WifiP2pManager.EXTRA_WIFI_STATE,
                        WifiP2pManager.WIFI_P2P_STATE_DISABLED
                    )

                    listener.onWifiP2pStateChanged(
                        state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    )
                }

                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    requestPeers()
                }

                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    requestConnectionInfo()
                }
            }
        }
    }

    companion object {

        fun requiredPermissions(): Array<String> {
            return if (Build.VERSION.SDK_INT >= 33) {
                arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES)
            } else {
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
            }
        }
    }

    private fun hasRequiredPermission(): Boolean {
        return requiredPermissions().all { permission ->
            ContextCompat.checkSelfPermission(
                appContext,
                permission
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun checkReady(): Boolean {
        if (manager == null || channel == null) {
            listener.onError(
                "This phone could not initialize Wi-Fi Direct."
            )
            return false
        }

        if (!hasRequiredPermission()) {
            listener.onError(
                "MAFX SHARE needs the nearby Wi-Fi devices permission. " +
                    "Allow it in Android settings and try again."
            )
            return false
        }

        return true
    }

    /**
     * Register for Wi-Fi Direct system broadcasts.
     * Call this before discovering or connecting to devices.
     */
    fun start(): Boolean {
        if (!checkReady()) return false

        if (registered) return true

        val filter = IntentFilter().apply {
            addAction(
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION
            )
            addAction(
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION
            )
            addAction(
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION
            )
        }

        try {
            ContextCompat.registerReceiver(
                appContext,
                receiver,
                filter,
                ContextCompat.RECEIVER_EXPORTED
            )

            registered = true
            return true
        } catch (e: Exception) {
            listener.onError(
                e.message ?: "Could not start Wi-Fi Direct monitoring."
            )
            return false
        }
    }

    /**
     * Find nearby Wi-Fi Direct devices.
     */
    fun discoverPeers() {
        if (!checkReady()) return

        val wifiManager = manager ?: return
        val wifiChannel = channel ?: return

        wifiManager.discoverPeers(
            wifiChannel,
            object : WifiP2pManager.ActionListener {

                override fun onSuccess() {
                    // The peers-changed broadcast will provide the list.
                }

                override fun onFailure(reason: Int) {
                    listener.onError(
                        "Could not search for nearby devices. " +
                            "Wi-Fi Direct error code: $reason"
                    )
                }
            }
        )
    }

    /**
     * Return the latest list of discovered devices.
     */
    fun requestPeers() {
        if (!checkReady()) return

        val wifiManager = manager ?: return
        val wifiChannel = channel ?: return

        wifiManager.requestPeers(
            wifiChannel
        ) { devices: WifiP2pDeviceList ->
            listener.onPeersAvailable(
                devices.deviceList.toList()
            )
        }
    }

    /**
     * Connect to the selected phone.
     *
     * groupOwnerIntent = 0 prefers that the other phone
     * becomes the Wi-Fi Direct group owner.
     *
     * This is a preference, not a guarantee.
     */
    fun connectToDevice(device: WifiP2pDevice) {
        if (!checkReady()) return

        val wifiManager = manager ?: return
        val wifiChannel = channel ?: return

        val config = WifiP2pConfig().apply {
            deviceAddress = device.deviceAddress
            groupOwnerIntent = 0
        }

        wifiManager.connect(
            wifiChannel,
            config,
            object : WifiP2pManager.ActionListener {

                override fun onSuccess() {
                    // Wait for the connection-changed broadcast.
                }

                override fun onFailure(reason: Int) {
                    listener.onError(
                        "Could not connect to ${device.deviceName}. " +
                            "Wi-Fi Direct error code: $reason"
                    )
                }
            }
        )
    }

    /**
     * Create a Wi-Fi Direct group on this phone.
     * Intended for the receiving phone.
     */
    fun createReceiverGroup(
        onCreated: () -> Unit
    ) {
        if (!checkReady()) return

        val wifiManager = manager ?: return
        val wifiChannel = channel ?: return

        wifiManager.createGroup(
            wifiChannel,
            object : WifiP2pManager.ActionListener {

                override fun onSuccess() {
                    onCreated()
                }

                override fun onFailure(reason: Int) {
                    listener.onError(
                        "Could not create the receiving connection. " +
                            "Wi-Fi Direct error code: $reason"
                    )
                }
            }
        )
    }

    /**
     * Request the IP and group-owner information after connection.
     */
    fun requestConnectionInfo() {
        if (!checkReady()) return

        val wifiManager = manager ?: return
        val wifiChannel = channel ?: return

        wifiManager.requestConnectionInfo(
            wifiChannel
        ) { info: WifiP2pInfo ->

            if (info.groupFormed) {
                listener.onConnectionInfoAvailable(info)
            } else {
                listener.onDisconnected()
            }
        }
    }

    /**
     * Disconnect and remove the Wi-Fi Direct group.
     */
    fun disconnect() {
        val wifiManager = manager ?: return
        val wifiChannel = channel ?: return

        if (!hasRequiredPermission()) return

        wifiManager.removeGroup(
            wifiChannel,
            object : WifiP2pManager.ActionListener {

                override fun onSuccess() {
                    listener.onDisconnected()
                }

                override fun onFailure(reason: Int) {
                    listener.onError(
                        "Could not disconnect Wi-Fi Direct. " +
                            "Error code: $reason"
                    )
                }
            }
        )
    }

    /**
     * Stop monitoring Wi-Fi Direct broadcasts.
     */
    fun stopMonitoring() {
        if (!registered) return

        try {
            appContext.unregisterReceiver(receiver)
        } catch (_: Exception) {
            // Receiver may already have been unregistered.
        }

        registered = false
    }
}
