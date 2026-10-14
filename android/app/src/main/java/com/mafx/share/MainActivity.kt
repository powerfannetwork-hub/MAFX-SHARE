package com.mafx.share

import android.Manifest
import android.app.AlertDialog
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pInfo
import android.os.Build
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

    private var receiveSession: ReceiveSession? = null
    private var transferClient: TransferClient? = null

    private var selectedDestinationIp: String? = null
    private var selectedDestinationPort: Int =
        TransferClient.DEFAULT_PORT

    private var receivingMode = false
    private var peerDialogShowing = false

    private var pendingWifiAction: (() -> Unit)? = null

    private val permissionLauncher =
        registerForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions()
        ) { results ->

            val allGranted = results.values.all { it }

            if (allGranted) {
                val action = pendingWifiAction
                pendingWifiAction = null

                if (wifiDirectManager.start()) {
                    action?.invoke()
                }
            } else {
                pendingWifiAction = null

                showError(
                    "MAFX SHARE yana buƙatar izinin " +
                        "Wi-Fi Direct. Ka ba shi izinin " +
                        "Nearby devices a saitin wayarka."
                )
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

        setStatus(
            "A shirye. Za ka iya haɗa wayoyi kusa " +
                "ta Wi-Fi Direct ba tare da internet ba."
        )
    }

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
        }
    }

    // --------------------------------------------------
    // RECEIVE FILES
    // --------------------------------------------------

    private fun startReceiving() {

        receivingMode = true

        receiveQrImage.setImageDrawable(null)

        receiveInfoText.text =
            "Ana shirya haɗin Wi-Fi Direct..."

        setStatus(
            "Ana kunna Wi-Fi Direct domin karɓar fayiloli."
        )

        withWifiPermissions {

            wifiDirectManager.createReceiverGroup {

                runOnUiThread {
                    setStatus(
                        "An shirya haɗin. " +
                            "Ana jiran wayar da za ta aika."
                    )

                    wifiDirectManager.requestConnectionInfo()
                }
            }
        }
    }

    private fun startReceiveServer(
        preferredIp: String
    ) {

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
                try {
                    val bitmap: Bitmap =
                        ConnectionQr.generateBitmap(payload)

                    receiveQrImage.setImageBitmap(bitmap)

                    receiveInfoText.text =
                        "An shirya karɓar fayil!\n" +
                            "IP: $ip\n" +
                            "Port: $port\n\n" +
                            "Ka buɗe FIND NEARBY DEVICES " +
                            "a wayar da za ta aika, ko ka " +
                            "duba wannan QR code."

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
                setStatus("Kuskuren karɓa: $message")
                showError(message)
            }
        }

        session.start()
    }

    private fun stopReceiving() {

        receiveSession?.stop()
        receiveSession = null

        receivingMode = false

        receiveQrImage.setImageDrawable(null)

        receiveInfoText.text =
            "An dakatar da karɓar fayil."

        wifiDirectManager.disconnect()

        setStatus("An dakatar da karɓar fayil.")
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
                    "Ka kunna Wi-Fi a saitin wayarka."
                )
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
                    WifiP2pDevice.AVAILABLE ->
                        "Available"

                    WifiP2pDevice.INVITED ->
                        "Invited"

                    WifiP2pDevice.CONNECTED ->
                        "Connected"

                    WifiP2pDevice.FAILED ->
                        "Failed"

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

    override fun onConnectionInfoAvailable(
        info: WifiP2pInfo
    ) {

        runOnUiThread {

            if (!info.groupFormed) {
                return@runOnUiThread
            }

            if (receivingMode) {

                if (info.isGroupOwner) {

                    val ip = info.groupOwnerAddress
                        ?.hostAddress

                    if (ip.isNullOrBlank()) {
                        showError(
                            "An haɗu amma ba a gano IP ba."
                        )
                        return@runOnUiThread
                    }

                    setStatus(
                        "An haɗa Wi-Fi Direct. " +
                            "Ana shirya karɓar fayil."
                    )

                    startReceiveServer(ip)

                } else {

                    setStatus(
                        "An haɗu da wata waya, " +
                            "amma wannan wayar ba ita " +
                            "ce mai karɓar haɗin ba."
                    )
                }

                return@runOnUiThread
            }

            // Lokacin aika fayil, muna tsammanin
            // wayar mai karɓa ce group owner.

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
        // Ana iya samun wannan yayin fara haɗin.
        // Saboda haka ba za mu katse aikin nan take ba.
    }

    override fun onError(message: String) {

        runOnUiThread {
            setStatus("Wi-Fi Direct: $message")
            showError(message)
        }
    }

    // --------------------------------------------------
    // QR SCAN, MANUAL IP AND FILE SENDING
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

                setStatus("Ana aika fayil...")
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
                setStatus("Aika ya gaza: $message")
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
        if (::statusText.isInitialized) {
            statusText.text = message
        }
    }

    private fun showError(
        message: String
    ) {

        runOnUiThread {

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

    override fun onDestroy() {

        receiveSession?.stop()

        transferClient?.shutdown()

        wifiDirectManager.stopMonitoring()

        super.onDestroy()
    }
}
