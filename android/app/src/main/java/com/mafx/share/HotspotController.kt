package com.mafx.share

import android.app.AlertDialog
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
import com.google.zxing.integration.android.IntentIntegrator
import com.journeyapps.barcodescanner.ScanIntentResult

class MainActivity : AppCompatActivity() {

    private lateinit var statusText: TextView
    private lateinit var progressBar: ProgressBar
    private lateinit var progressText: TextView
    private lateinit var receiveQrImage: ImageView
    private lateinit var receiveInfoText: TextView

    private var receiveSession: ReceiveSession? = null
    private var transferClient: TransferClient? = null
    private var wifiDirect: WifiDirectManager? = null

    private var selectedDestinationIp: String? = null
    private var selectedDestinationPort: Int =
        TransferClient.DEFAULT_PORT

    private var receivingMode = false
    private var connectionHandled = false

    private var pendingAction: (() -> Unit)? = null

    private val permissionLauncher =
        registerForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions()
        ) { results ->

            val allGranted = WifiDirectManager
                .requiredPermissions()
                .all { results[it] == true }

            if (allGranted) {
                pendingAction?.invoke()
            } else {
                setStatus(
                    "Allow nearby Wi-Fi devices permission " +
                        "in Android settings."
                )
                showError(
                    "MAFX SHARE needs permission to discover " +
                        "and connect to nearby devices."
                )
            }

            pendingAction = null
        }

    private val filePicker =
        registerForActivityResult(
            ActivityResultContracts.OpenDocument()
        ) { uri ->

            if (uri == null) {
                setStatus("File selection cancelled.")
                return@registerForActivityResult
            }

            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: Exception) {
                // Some document providers do not support this.
            }

            val ip = selectedDestinationIp

            if (ip.isNullOrBlank()) {
                askForReceiverIp { receiverIp ->
                    selectedDestinationIp = receiverIp
                    sendSelectedFile(
                        receiverIp,
                        uri,
                        TransferClient.DEFAULT_PORT
                    )
                }
            } else {
                sendSelectedFile(
                    ip,
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
                setStatus("QR scan cancelled.")
                return@registerForActivityResult
            }

            try {
                val connection =
                    ConnectionQr.parsePayload(contents)

                selectedDestinationIp = connection.ipAddress
                selectedDestinationPort = connection.port

                setStatus(
                    "Receiver found: ${connection.ipAddress}"
                )

                askToChooseFile(
                    connection.ipAddress,
                    connection.port
                )

            } catch (e: Exception) {
                showError(
                    e.message ?: "Invalid MAFX SHARE QR code."
                )
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        title = "MAFX SHARE"

        buildScreen()

        transferClient = TransferClient(applicationContext)

        setupWifiDirect()

        setStatus("Ready. Choose Send or Receive.")
    }

    private fun setupWifiDirect() {

        wifiDirect = WifiDirectManager(
            this,
            object : WifiDirectManager.Listener {

                override fun onWifiP2pStateChanged(
                    enabled: Boolean
                ) {
                    runOnUiThread {
                        if (enabled) {
                            setStatus("Wi-Fi Direct is enabled.")
                        } else {
                            setStatus(
                                "Turn on Wi-Fi to use nearby transfer."
                            )
                        }
                    }
                }

                override fun onPeersAvailable(
                    peers: List<WifiP2pDevice>
                ) {
                    runOnUiThread {
                        showNearbyDevices(peers)
                    }
                }

                override fun onConnectionInfoAvailable(
                    info: WifiP2pInfo
                ) {
                    runOnUiThread {
                        handleWifiConnection(info)
                    }
                }

                override fun onDisconnected() {
                    runOnUiThread {
                        connectionHandled = false
                    }
                }

                override fun onError(message: String) {
                    runOnUiThread {
                        setStatus(message)
                    }
                }
            }
        )
    }

    private fun ensureWifiPermission(
        action: () -> Unit
    ) {
        val missing = WifiDirectManager
            .requiredPermissions()
            .filter { permission ->
                androidx.core.content.ContextCompat
                    .checkSelfPermission(
                        this,
                        permission
                    ) != android.content.pm.PackageManager
                    .PERMISSION_GRANTED
            }

        if (missing.isEmpty()) {
            action()
        } else {
            pendingAction = action
            permissionLauncher.launch(
                missing.toTypedArray()
            )
        }
    }

    private fun startWifiDirect(
        action: () -> Unit
    ) {
        ensureWifiPermission {
            val manager = wifiDirect

            if (manager == null || !manager.start()) {
                setStatus("Could not start Wi-Fi Direct.")
                return@ensureWifiPermission
            }

            action()
        }
    }

    private fun buildScreen() {

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(20), dp(20), dp(20), dp(20))
        }

        val scroll = ScrollView(this).apply {
            isFillViewport = true
            addView(root)
        }

        val titleView = TextView(this).apply {
            text = "MAFX SHARE"
            textSize = 28f
            setTypeface(null, android.graphics.Typeface.BOLD)
            gravity = Gravity.CENTER
        }

        root.addView(
            titleView,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(64)
            )
        )

        val subtitle = TextView(this).apply {
            text = "Fast file sharing between Android devices"
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
            setPadding(dp(10), dp(10), dp(10), dp(10))
        }

        root.addView(
            statusText,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        addButton(root, "RECEIVE FILES") {
            startReceivingMode()
        }

        addButton(root, "FIND NEARBY DEVICES") {
            findNearbyDevices()
        }

        addButton(root, "SEND FILES") {
            selectedDestinationPort =
                TransferClient.DEFAULT_PORT

            askToChooseFile(
                selectedDestinationIp,
                selectedDestinationPort
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
            receiveSession?.stop()
            receiveSession = null

            receiveQrImage.setImageDrawable(null)
            receiveInfoText.text = "Receiver stopped."

            setStatus("Receiving stopped.")
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
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(12), dp(8), dp(8))
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
                "MAFX SHARE receiver QR code"
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

    private fun startReceivingMode() {

        receivingMode = true
        connectionHandled = false

        setStatus("Preparing Wi-Fi Direct receiver...")

        startWifiDirect {

            val manager = wifiDirect ?: return@startWifiDirect

            manager.createReceiverGroup {

                runOnUiThread {
                    setStatus(
                        "Receiver connection created. " +
                            "Now search for this phone from the sender."
                    )

                    manager.requestConnectionInfo()
                }
            }
        }
    }

    private fun findNearbyDevices() {

        receivingMode = false
        connectionHandled = false

        setStatus("Searching for nearby devices...")

        startWifiDirect {
            wifiDirect?.discoverPeers()
        }
    }

    private fun showNearbyDevices(
        peers: List<WifiP2pDevice>
    ) {

        if (peers.isEmpty()) {
            setStatus(
                "No nearby Wi-Fi Direct devices found yet. " +
                    "Make sure the other phone has Wi-Fi enabled."
            )
            return
        }

        val names = peers.map { device ->
            val name = device.deviceName
                .takeIf { it.isNotBlank() }
                ?: "Android device"

            "$name — ${deviceStatus(device.status)}"
        }.toTypedArray()

        AlertDialog.Builder(this)
            .setTitle("Nearby devices")
            .setItems(names) { _, index ->

                val device = peers[index]

                setStatus(
                    "Connecting to ${device.deviceName}..."
                )

                connectionHandled = false

                wifiDirect?.connectToDevice(device)
            }
            .setNegativeButton("CANCEL", null)
            .show()
    }

    private fun deviceStatus(status: Int): String {
        return when (status) {
            WifiP2pDevice.AVAILABLE -> "Available"
            WifiP2pDevice.INVITED -> "Invited"
            WifiP2pDevice.CONNECTED -> "Connected"
            WifiP2pDevice.FAILED -> "Failed"
            WifiP2pDevice.UNAVAILABLE -> "Unavailable"
            else -> "Unknown"
        }
    }

    private fun handleWifiConnection(
        info: WifiP2pInfo
    ) {

        if (!info.groupFormed) {
            return
        }

        if (receivingMode) {

            if (!info.isGroupOwner) {
                setStatus(
                    "Waiting for the receiver connection..."
                )
                return
            }

            if (receiveSession?.isRunning() == true) {
                return
            }

            startReceivingServer()
            return
        }

        if (connectionHandled) {
            return
        }

        val receiverIp =
            info.groupOwnerAddress?.hostAddress

        if (receiverIp.isNullOrBlank()) {
            setStatus(
                "Connected, but could not get the receiver IP."
            )
            return
        }

        selectedDestinationIp = receiverIp
        selectedDestinationPort =
            TransferClient.DEFAULT_PORT

        connectionHandled = true

        setStatus("Connected to receiver: $receiverIp")

        askToChooseFile(
            receiverIp,
            TransferClient.DEFAULT_PORT
        )
    }

    private fun startReceivingServer() {

        if (receiveSession?.isRunning() == true) {
            return
        }

        receiveQrImage.setImageDrawable(null)
        receiveInfoText.text =
            "Starting the file receiver..."

        val session = ReceiveSession(applicationContext)
        receiveSession = session

        session.onReady = { ip, port, payload ->

            runOnUiThread {
                try {
                    val bitmap: Bitmap =
                        ConnectionQr.generateBitmap(payload)

                    receiveQrImage.setImageBitmap(bitmap)

                    receiveInfoText.text =
                        "Receiver ready\n" +
                            "IP: $ip\n" +
                            "Port: $port\n" +
                            "You can also use the QR code."

                    setStatus("Waiting for incoming files...")

                } catch (e: Exception) {
                    showError(
                        e.message
                            ?: "Could not generate receiver QR."
                    )
                }
            }
        }

        session.onFileReceived = { filename, size ->

            runOnUiThread {
                setStatus(
                    "Received: $filename (${formatBytes(size)})"
                )

                Toast.makeText(
                    this,
                    "File received: $filename",
                    Toast.LENGTH_LONG
                ).show()
            }
        }

        session.onError = { message ->

            runOnUiThread {
                setStatus("Receive error: $message")
                showError(message)
            }
        }

        session.start()
    }

    private fun askToChooseFile(
        ip: String?,
        port: Int
    ) {
        if (!ip.isNullOrBlank()) {
            selectedDestinationIp = ip
        }

        selectedDestinationPort = port

        AlertDialog.Builder(this)
            .setTitle("Choose file")
            .setMessage(
                if (selectedDestinationIp.isNullOrBlank()) {
                    "Choose a file. You will need the receiver IP."
                } else {
                    "Choose a file to send to " +
                        "$selectedDestinationIp:$port"
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
            hint = "Example: 192.168.49.1"
            setSingleLine(true)
            setText(selectedDestinationIp.orEmpty())
        }

        AlertDialog.Builder(this)
            .setTitle("Receiver IP address")
            .setMessage(
                "Enter the receiver's local IP address."
            )
            .setView(input)
            .setNegativeButton("CANCEL", null)
            .setPositiveButton("CONTINUE") { _, _ ->

                val ip = input.text.toString().trim()

                if (!isValidIpText(ip)) {
                    showError("Enter a valid IPv4 address.")
                } else {
                    onIpReady(ip)
                }
            }
            .show()
    }

    private fun isValidIpText(ip: String): Boolean {

        val parts = ip.split(".")

        if (parts.size != 4) return false

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
        progressText.text = "Preparing file..."

        setStatus("Connecting to $ip:$port...")

        client.onProgress = { filename, sent, total ->

            runOnUiThread {

                val percent =
                    if (total <= 0L) 100
                    else (
                        sent.toDouble() /
                            total.toDouble() * 100
                        ).toInt().coerceIn(0, 100)

                progressBar.progress = percent

                progressText.text =
                    "$filename: $percent% " +
                        "(${formatBytes(sent)} / ${formatBytes(total)})"

                setStatus("Sending file...")
            }
        }

        client.onCompleted = { filename, size ->

            runOnUiThread {

                progressBar.progress = 100
                progressText.text = "Transfer finished: 100%"

                setStatus(
                    "Sent: $filename (${formatBytes(size)})."
                )

                Toast.makeText(
                    this,
                    "File sent: $filename",
                    Toast.LENGTH_LONG
                ).show()
            }
        }

        client.onError = { message ->

            runOnUiThread {
                setStatus("Send failed: $message")
                showError(message)
            }
        }

        client.sendFile(ip, uri, port)
    }

    private fun setStatus(message: String) {
        if (::statusText.isInitialized) {
            statusText.text = message
        }
    }

    private fun showError(message: String) {

        runOnUiThread {
            AlertDialog.Builder(this)
                .setTitle("MAFX SHARE")
                .setMessage(message)
                .setPositiveButton("OK", null)
                .show()
        }
    }

    private fun formatBytes(bytes: Long): String {

        if (bytes < 1024L) return "$bytes B"

        val kb = bytes / 1024.0
        if (kb < 1024.0) {
            return String.format("%.1f KB", kb)
        }

        val mb = kb / 1024.0
        if (mb < 1024.0) {
            return String.format("%.1f MB", mb)
        }

        return String.format("%.2f GB", mb / 1024.0)
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    override fun onDestroy() {

        receiveSession?.stop()
        transferClient?.shutdown()
        wifiDirect?.stopMonitoring()

        super.onDestroy()
    }
}
