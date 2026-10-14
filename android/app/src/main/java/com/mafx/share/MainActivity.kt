package com.mafx.share

import android.app.AlertDialog
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pInfo
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat

import com.google.zxing.integration.android.IntentIntegrator
import com.journeyapps.barcodescanner.ScanIntentResult

class MainActivity : AppCompatActivity(),
    WifiDirectManager.Listener {

    private lateinit var statusText: TextView
    private lateinit var progressBar: ProgressBar
    private lateinit var progressText: TextView
    private lateinit var receiveQrImage: ImageView
    private lateinit var receiveInfoText: TextView

    private lateinit var wifiDirectManager: WifiDirectManager
    private lateinit var hotspotController: HotspotController

    private var receiveSession: ReceiveSession? = null
    private var transferClient: TransferClient? = null

    private var selectedDestinationIp: String? = null
    private var selectedDestinationPort: Int =
        TransferClient.DEFAULT_PORT

    private var receivingMode = false
    private var peerDialogShowing = false
    private var pendingWifiAction: (() -> Unit)? = null

    private var hotspotFallbackAttempted = false
    private var usingHotspotFallback = false
    private var hotspotSsid: String? = null
    private var hotspotPassword: String? = null

    private var destroyed = false

    private val permissionLauncher =
        registerForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions()
        ) { results ->

            val allGranted =
                results.values.all { it }

            if (allGranted) {
                val action = pendingWifiAction
                pendingWifiAction = null

                if (wifiDirectManager.start()) {
                    action?.invoke()
                } else if (receivingMode) {
                    startHotspotFallback()
                }
            } else {
                pendingWifiAction = null

                if (receivingMode) {
                    startHotspotFallback()
                } else {
                    showError(
                        "MAFX SHARE yana buƙatar izinin " +
                            "Nearby devices domin amfani da Wi-Fi Direct."
                    )
                }
            }
        }

    private val filePicker =
        registerForActivityResult(
            ActivityResultContracts.OpenDocument()
        ) { uri ->

            if (uri == null) {
                setStatus("Ba a zaɓi fayil ba.")
                return@registerForActivityResult
            }

            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: Exception) {
                // Wasu masu samar da fayil ba sa goyon bayan wannan.
            }

            val destinationIp = selectedDestinationIp

            if (destinationIp.isNullOrBlank()) {
                askForReceiverIp { ip ->
                    selectedDestinationIp = ip
                    selectedDestinationPort =
                        TransferClient.DEFAULT_PORT

                    sendSelectedFile(
                        ip,
                        uri,
                        selectedDestinationPort
                    )
                }
            } else {
                sendSelectedFile(
                    destinationIp,
                    uri,
                    selectedDestinationPort
                )
            }
        }

    private val qrScanLauncher =
        registerForActivityResult(
            ActivityResultContracts.StartActivityForResult()
        ) { result ->

            val scanResult =
                ScanIntentResult.parseActivityResult(
                    result.resultCode,
                    result.data
                )

            val contents = scanResult.contents

            if (contents.isNullOrBlank()) {
                setStatus("Ba a karanta QR code ba.")
                return@registerForActivityResult
            }

            try {
                val connection =
                    ConnectionQr.parsePayload(contents)

                selectedDestinationIp = connection.ipAddress
                selectedDestinationPort = connection.port

                Toast.makeText(
                    this,
                    "An gano mai karɓa: " +
                        "${connection.ipAddress}:${connection.port}",
                    Toast.LENGTH_LONG
                ).show()

                askToChooseFile(
                    connection.ipAddress,
                    connection.port
                )
            } catch (e: Exception) {
                showError(
                    e.message ?: "QR code ɗin bai dace ba."
                )
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        title = "MAFX SHARE"

        buildScreen()

        transferClient = TransferClient(applicationContext)

        wifiDirectManager = WifiDirectManager(
            this,
            this
        )

        hotspotController =
            HotspotController(applicationContext)

        setStatus(
            "A shirye. Za ka iya aika fayiloli tsakanin wayoyi " +
                "ta Wi-Fi Direct ko Hotspot."
        )
    }

    // --------------------------------------------------
    // SCREEN
    // --------------------------------------------------

    private fun buildScreen() {

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(
                dp(20),
                dp(20),
                dp(20),
                dp(20)
            )
        }

        val scroll = ScrollView(this).apply {
            isFillViewport = true
            addView(root)
        }

        val heading = TextView(this).apply {
            text = "MAFX SHARE"
            textSize = 28f
            setTypeface(
                null,
                android.graphics.Typeface.BOLD
            )
            gravity = Gravity.CENTER
        }

        root.addView(
            heading,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(64)
            )
        )

        val subtitle = TextView(this).apply {
            text = "Share files between Android devices"
            textSize = 15f
            gravity = Gravity.CENTER
        }

        root.addView(
            subtitle,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(42)
            )
        )

        statusText = TextView(this).apply {
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(
                dp(10),
                dp(10),
                dp(10),
                dp(10)
            )
        }

        root.addView(
            statusText,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        addButton(root, "RECEIVE FILES") {
            startReceiving()
        }

        addButton(root, "FIND NEARBY DEVICES") {
            findNearbyDevices()
        }

        addButton(root, "SEND FILES") {
            receivingMode = false

            selectedDestinationPort =
                TransferClient.DEFAULT_PORT

            askToChooseFile(
                selectedDestinationIp,
                TransferClient.DEFAULT_PORT
            )
        }

        addButton(root, "SCAN RECEIVER QR") {
            val intent = IntentIntegrator(this)
                .setDesiredBarcodeFormats(
                    IntentIntegrator.QR_CODE
                )
                .setPrompt(
                    "Scan the MAFX SHARE receiver QR code"
                )
                .setBeepEnabled(false)
                .setOrientationLocked(false)
                .createScanIntent()

            qrScanLauncher.launch(intent)
        }

        addButton(root, "ENTER RECEIVER IP") {
            askForReceiverIp { ip ->

                selectedDestinationIp = ip
                selectedDestinationPort =
                    TransferClient.DEFAULT_PORT

                askToChooseFile(
                    ip,
                    TransferClient.DEFAULT_PORT
                )
            }
        }

        addButton(root, "STOP RECEIVING") {
            stopReceiving()
        }

        progressBar = ProgressBar(
            this,
            null,
            android.R.attr.progressBarStyleHorizontal
        ).apply {
            max = 100
            progress = 0
        }

        root.addView(
            progressBar,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(24)
            )
        )

        progressText = TextView(this).apply {
            text = "Transfer progress: 0%"
            textSize = 13f
            gravity = Gravity.CENTER
        }

        root.addView(
            progressText,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(36)
            )
        )

        receiveInfoText = TextView(this).apply {
            text = "Ba a fara karɓar fayil ba."
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(
                dp(8),
                dp(12),
                dp(8),
                dp(8)
            )
        }

        root.addView(
            receiveInfoText,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        receiveQrImage = ImageView(this).apply {
            contentDescription =
                "MAFX SHARE receiver connection QR code"

            adjustViewBounds = true
            scaleType = ImageView.ScaleType.FIT_CENTER
        }

        root.addView(
            receiveQrImage,
            LinearLayout.LayoutParams(
                dp(240),
                dp(240)
            ).apply {
                gravity = Gravity.CENTER
            }
        )

        setContentView(scroll)
    }

    private fun addButton(
        parent: LinearLayout,
        text: String,
        action: () -> Unit
    ) {
        val button = Button(this).apply {
            this.text = text
            isAllCaps = false

            setOnClickListener {
                action()
            }
        }

        parent.addView(
            button,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(52)
            ).apply {
                topMargin = dp(7)
                bottomMargin = dp(7)
            }
        )
    }

    // --------------------------------------------------
    // WIFI PERMISSIONS
    // --------------------------------------------------

    private fun withWifiPermissions(
        action: () -> Unit
    ) {
        val missingPermissions =
            WifiDirectManager.requiredPermissions()
                .filter { permission ->
                    ContextCompat.checkSelfPermission(
                        this,
                        permission
                    ) != PackageManager.PERMISSION_GRANTED
                }

        if (missingPermissions.isNotEmpty()) {
            pendingWifiAction = action

            permissionLauncher.launch(
                missingPermissions.toTypedArray()
            )
            return
        }

        if (wifiDirectManager.start()) {
            action()
        } else if (receivingMode) {
            startHotspotFallback()
        }
    }

    // --------------------------------------------------
    // RECEIVE FILES
    // --------------------------------------------------

    private fun startReceiving() {

        receivingMode = true
        hotspotFallbackAttempted = false
        usingHotspotFallback = false
        hotspotSsid = null
        hotspotPassword = null

        receiveSession?.stop()
        receiveSession = null

        receiveQrImage.setImageDrawable(null)

        receiveInfoText.text =
            "Ana shirya haɗin Wi-Fi Direct..."

        setStatus(
            "Ana kunna Wi-Fi Direct domin karɓar fayiloli."
        )

        withWifiPermissions {

            if (!receivingMode) return@withWifiPermissions

            wifiDirectManager.createReceiverGroup {

                runOnUiThread {
                    if (!receivingMode || destroyed) {
                        return@runOnUiThread
                    }

                    setStatus(
                        "An shirya haɗin. " +
                            "Ana jiran wayar da za ta aika."
                    )

                    wifiDirectManager.requestConnectionInfo()
                }
            }
        }
    }

    // --------------------------------------------------
    // HOTSPOT FALLBACK
    // --------------------------------------------------

    private fun startHotspotFallback() {

        if (!receivingMode ||
            hotspotFallbackAttempted ||
            destroyed
        ) {
            return
        }

        hotspotFallbackAttempted = true
        usingHotspotFallback = true

        runOnUiThread {
            setStatus(
                "Wi-Fi Direct bai yi nasara ba. " +
                    "Ana ƙoƙarin kunna Hotspot..."
            )

            receiveInfoText.text =
                "Ana ƙoƙarin kunna Hotspot..."
        }

        hotspotController.start(
            object : HotspotController.Listener {

                override fun onHotspotStarted(
                    ssid: String,
                    password: String
                ) {
                    runOnUiThread {

                        if (!receivingMode || destroyed) {
                            hotspotController.stop()
                            return@runOnUiThread
                        }

                        hotspotSsid = ssid
                        hotspotPassword = password

                        val ip =
                            NetworkAddress.getLocalIPv4Address()

                        if (ip.isNullOrBlank()) {
                            setStatus(
                                "An kunna Hotspot amma ba a gano IP ba."
                            )

                            showError(
                                "An kunna Hotspot, amma ba a gano IP ba.\n\n" +
                                    "Ka duba saitunan Hotspot na wayarka. " +
                                    "Idan matsalar ta ci gaba, sake gwadawa."
                            )
                            return@runOnUiThread
                        }

                        setStatus(
                            "An kunna Hotspot. Haɗa ɗayar wayar da shi."
                        )

                        startReceiveServer(ip)
                    }
                }

                override fun onHotspotStopped() {
                    runOnUiThread {
                        if (receivingMode && !destroyed) {
                            setStatus(
                                "An dakatar da Hotspot."
                            )
                        }
                    }
                }

                override fun onHotspotError(
                    message: String
                ) {
                    runOnUiThread {

                        if (!receivingMode || destroyed) {
                            return@runOnUiThread
                        }

                        setStatus(
                            "An kasa kunna Hotspot."
                        )

                        receiveInfoText.text =
                            "Ba a iya kunna Hotspot ba."

                        showError(
                            "$message\n\n" +
                                "Ka tabbatar Wi-Fi yana kunne, " +
                                "sannan ka sake gwadawa."
                        )
                    }
                }
            }
        )
    }

    // --------------------------------------------------
    // START FILE RECEIVING SERVER
    // --------------------------------------------------

    private fun startReceiveServer(
        preferredIp: String
    ) {
        if (!receivingMode || destroyed) return

        if (receiveSession?.isRunning() == true) {
            return
        }

        receiveInfoText.text =
            "Ana fara sabar karɓar fayil..."

        val session = ReceiveSession(
            applicationContext,
            preferredIp
        )

        receiveSession = session

        session.onReady = { ip, port, payload ->

            runOnUiThread {

                if (!receivingMode || destroyed) {
                    return@runOnUiThread
                }

                try {
                    val bitmap: Bitmap =
                        ConnectionQr.generateBitmap(payload)

                    receiveQrImage.setImageBitmap(bitmap)

                    receiveInfoText.text =
                        if (usingHotspotFallback) {

                            "An shirya karɓar fayil ta Hotspot!\n\n" +
                                "Hotspot name: ${hotspotSsid.orEmpty()}\n" +
                                "Password: ${hotspotPassword.orEmpty()}\n" +
                                "Receiver IP: $ip\n" +
                                "Port: $port\n\n" +
                                "A ɗayar wayar, buɗe saitunan Wi-Fi " +
                                "ka haɗa da wannan Hotspot. " +
                                "Bayan haɗawa, buɗe MAFX SHARE " +
                                "ka zaɓi ENTER RECEIVER IP."

                        } else {

                            "An shirya karɓar fayil!\n" +
                                "IP: $ip\n" +
                                "Port: $port\n\n" +
                                "Ka buɗe FIND NEARBY DEVICES " +
                                "a wayar da za ta aika, ko ka " +
                                "duba wannan QR code."
                        }

                    setStatus(
                        "MAFX SHARE yana jiran fayil."
                    )

                } catch (e: Exception) {
                    showError(
                        e.message
                            ?: "An kasa samar da QR code."
                    )
                }
            }
        }

        session.onFileReceived = { filename, size ->

            runOnUiThread {

                if (destroyed) return@runOnUiThread

                setStatus(
                    "An karɓi $filename " +
                        "(${formatBytes(size)})"
                )

                Toast.makeText(
                    this,
                    "An karɓi fayil: $filename",
                    Toast.LENGTH_LONG
                ).show()
            }
        }

        session.onError = { message ->

            runOnUiThread {

                if (destroyed) return@runOnUiThread

                setStatus(
                    "Kuskuren karɓa: $message"
                )

                showError(message)
            }
        }

        session.start()
    }

    private fun stopReceiving() {

        receivingMode = false

        receiveSession?.stop()
        receiveSession = null

        if (::hotspotController.isInitialized) {
            hotspotController.stop()
        }

        hotspotFallbackAttempted = false
        usingHotspotFallback = false
        hotspotSsid = null
        hotspotPassword = null

        receiveQrImage.setImageDrawable(null)

        receiveInfoText.text =
            "An dakatar da karɓar fayil."

        if (::wifiDirectManager.isInitialized) {
            wifiDirectManager.disconnect()
        }

        setStatus(
            "An dakatar da karɓar fayil."
        )
    }

    // --------------------------------------------------
    // FIND NEARBY DEVICES
    // --------------------------------------------------

    private fun findNearbyDevices() {

        receivingMode = false
        peerDialogShowing = false

        setStatus(
            "Ana neman wayoyin da ke kusa..."
        )

        withWifiPermissions {
            wifiDirectManager.discoverPeers()
        }
    }

    override fun onWifiP2pStateChanged(
        enabled: Boolean
    ) {
        runOnUiThread {

            if (enabled) {
                setStatus(
                    "Wi-Fi Direct yana aiki."
                )
            } else {
                setStatus(
                    "Wi-Fi Direct a kashe yake."
                )

                if (receivingMode) {
                    startHotspotFallback()
                }
            }
        }
    }

    override fun onPeersAvailable(
        peers: List<WifiP2pDevice>
    ) {
        runOnUiThread {

            if (receivingMode) {
                return@runOnUiThread
            }

            if (peers.isEmpty()) {
                setStatus(
                    "Ba a gano wata waya ba tukuna. " +
                        "Ka tabbatar wayar mai karɓa ta " +
                        "buɗe RECEIVE FILES."
                )
                return@runOnUiThread
            }

            if (peerDialogShowing) {
                return@runOnUiThread
            }

            peerDialogShowing = true

            val deviceNames = peers.map { device ->

                val name = device.deviceName
                    .takeIf { it.isNotBlank() }
                    ?: "Android device"

                val state = when (device.status) {
                    WifiP2pDevice.AVAILABLE -> "Available"
                    WifiP2pDevice.INVITED -> "Invited"
                    WifiP2pDevice.CONNECTED -> "Connected"
                    WifiP2pDevice.FAILED -> "Failed"
                    else -> "Unknown"
                }

                "$name — $state"

            }.toTypedArray()

            AlertDialog.Builder(this)
                .setTitle("Wayoyin da ke kusa")
                .setItems(deviceNames) { _, which ->

                    val device = peers[which]

                    setStatus(
                        "Ana haɗawa da " +
                            device.deviceName + "..."
                    )

                    wifiDirectManager.connectToDevice(
                        device
                    )
                }
                .setOnDismissListener {
                    peerDialogShowing = false
                }
                .setNegativeButton("CLOSE", null)
                .show()
        }
    }

    // --------------------------------------------------
    // WIFI DIRECT CONNECTION INFORMATION
    // --------------------------------------------------

    override fun onConnectionInfoAvailable(
        info: WifiP2pInfo
    ) {
        runOnUiThread {

            if (!info.groupFormed) {
                if (receivingMode) {
                    startHotspotFallback()
                }
                return@runOnUiThread
            }

            if (receivingMode) {

                if (info.isGroupOwner) {

                    val ip = info.groupOwnerAddress
                        ?.hostAddress

                    if (ip.isNullOrBlank()) {
                        startHotspotFallback()
                        return@runOnUiThread
                    }

                    setStatus(
                        "An haɗa Wi-Fi Direct. " +
                            "Ana shirya karɓar fayil."
                    )

                    usingHotspotFallback = false
                    startReceiveServer(ip)

                } else {

                    setStatus(
                        "An haɗu da wata waya, amma wannan " +
                            "wayar ba ita ce mai karɓar haɗin ba."
                    )
                }

                return@runOnUiThread
            }

            if (info.isGroupOwner) {

                setStatus(
                    "An haɗu, amma wannan wayar ce " +
                        "mai karɓar haɗin. Ka fara " +
                        "RECEIVE FILES a wayar da za ta karɓa."
                )

                return@runOnUiThread
            }

            val receiverIp = info.groupOwnerAddress
                ?.hostAddress

            if (receiverIp.isNullOrBlank()) {
                showError(
                    "An haɗu amma ba a gano IP " +
                        "na wayar mai karɓa ba."
                )
                return@runOnUiThread
            }

            selectedDestinationIp = receiverIp
            selectedDestinationPort =
                TransferClient.DEFAULT_PORT

            setStatus(
                "An haɗu da wayar mai karɓa: $receiverIp"
            )

            Toast.makeText(
                this,
                "An haɗu! Zaɓi fayil ɗin da za ka aika.",
                Toast.LENGTH_LONG
            ).show()

            askToChooseFile(
                receiverIp,
                TransferClient.DEFAULT_PORT
            )
        }
    }

    override fun onDisconnected() {
        // Ba za mu dakatar da aikin nan take ba.
    }

    override fun onError(
        message: String
    ) {
        runOnUiThread {

            if (receivingMode &&
                !hotspotFallbackAttempted
            ) {
                startHotspotFallback()
                return@runOnUiThread
            }

            setStatus(
                "Wi-Fi Direct: $message"
            )

            showError(message)
        }
    }

    // --------------------------------------------------
    // CHOOSE FILE
    // --------------------------------------------------

    private fun askToChooseFile(
        ip: String?,
        port: Int
    ) {
        if (!ip.isNullOrBlank()) {
            selectedDestinationIp = ip
        }

        selectedDestinationPort = port

        AlertDialog.Builder(this)
            .setTitle("Zaɓi fayil")
            .setMessage(
                if (selectedDestinationIp.isNullOrBlank()) {
                    "Zaɓi fayil. Za a tambaye ka IP " +
                        "na wayar da za ta karɓa."
                } else {
                    "Zaɓi fayil da za a aika zuwa " +
                        "$selectedDestinationIp:$selectedDestinationPort"
                }
            )
            .setNegativeButton("CANCEL", null)
            .setPositiveButton("CHOOSE FILE") { _, _ ->
                filePicker.launch(arrayOf("*/*"))
            }
            .show()
    }

    // --------------------------------------------------
    // ENTER RECEIVER IP
    // --------------------------------------------------

    private fun askForReceiverIp(
        onIpReady: (String) -> Unit
    ) {
        val input = EditText(this).apply {
            hint = "Misali: 192.168.49.1"
            setSingleLine(true)
            setText(
                selectedDestinationIp.orEmpty()
            )
        }

        AlertDialog.Builder(this)
            .setTitle("IP na wayar mai karɓa")
            .setMessage(
                "Shigar da IPv4 address na wayar mai karɓa."
            )
            .setView(input)
            .setNegativeButton("CANCEL", null)
            .setPositiveButton("CONTINUE") { _, _ ->

                val ip = input.text
                    .toString()
                    .trim()

                if (!isValidIpText(ip)) {
                    showError(
                        "Shigar da IPv4 address mai inganci."
                    )
                } else {
                    onIpReady(ip)
                }
            }
            .show()
    }

    private fun isValidIpText(
        ip: String
    ): Boolean {

        val parts = ip.split(".")

        if (parts.size != 4) {
            return false
        }

        return parts.all { part ->

            val number = part.toIntOrNull()

            number != null &&
                number in 0..255 &&
                part.isNotBlank()
        }
    }

    // --------------------------------------------------
    // SEND FILE
    // --------------------------------------------------

    private fun sendSelectedFile(
        ip: String,
        uri: android.net.Uri,
        port: Int = TransferClient.DEFAULT_PORT
    ) {

        val client = transferClient
            ?: TransferClient(applicationContext).also {
                transferClient = it
            }

        progressBar.progress = 0
        progressText.text = "Ana shirya fayil..."

        setStatus(
            "Ana haɗawa da $ip:$port..."
        )

        client.onProgress = { filename, sent, total ->

            runOnUiThread {

                val percent =
                    if (total <= 0L) {
                        100
                    } else {
                        (
                            sent.toDouble() /
                                total.toDouble() *
                                100
                        ).toInt().coerceIn(0, 100)
                    }

                progressBar.progress = percent

                progressText.text =
                    "$filename: $percent% " +
                        "(${formatBytes(sent)} / " +
                        "${formatBytes(total)})"

                setStatus(
                    "Ana aika fayil..."
                )
            }
        }

        client.onCompleted = { filename, size ->

            runOnUiThread {

                progressBar.progress = 100

                progressText.text =
                    "An gama aika fayil: 100%"

                setStatus(
                    "An aika $filename " +
                        "(${formatBytes(size)})."
                )

                Toast.makeText(
                    this,
                    "An aika fayil: $filename",
                    Toast.LENGTH_LONG
                ).show()
            }
        }

        client.onError = { message ->

            runOnUiThread {

                setStatus(
                    "Aika ya gaza: $message"
                )

                showError(message)
            }
        }

        client.sendFile(
            ip,
            uri,
            port
        )
    }

    // --------------------------------------------------
    // HELPERS
    // --------------------------------------------------

    private fun setStatus(
        message: String
    ) {
        if (::statusText.isInitialized && !destroyed) {
            statusText.text = message
        }
    }

    private fun showError(
        message: String
    ) {
        runOnUiThread {

            if (destroyed || isFinishing) {
                return@runOnUiThread
            }

            AlertDialog.Builder(this)
                .setTitle("MAFX SHARE")
                .setMessage(message)
                .setPositiveButton("OK", null)
                .show()
        }
    }

    private fun formatBytes(
        bytes: Long
    ): String {

        if (bytes < 1024L) {
            return "$bytes B"
        }

        val kb = bytes / 1024.0

        if (kb < 1024.0) {
            return String.format("%.1f KB", kb)
        }

        val mb = kb / 1024.0

        if (mb < 1024.0) {
            return String.format("%.1f MB", mb)
        }

        return String.format(
            "%.2f GB",
            mb / 1024.0
        )
    }

    private fun dp(
        value: Int
    ): Int {
        return (
            value * resources.displayMetrics.density
        ).toInt()
    }

    // --------------------------------------------------
    // CLEANUP
    // --------------------------------------------------

    override fun onDestroy() {

        destroyed = true

        receiveSession?.stop()
        receiveSession = null

        transferClient?.shutdown()
        transferClient = null

        if (::hotspotController.isInitialized) {
            hotspotController.stop()
        }

        if (::wifiDirectManager.isInitialized) {
            wifiDirectManager.stopMonitoring()
        }

        super.onDestroy()
    }
}
