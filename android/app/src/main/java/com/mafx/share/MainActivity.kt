package com.mafx.share

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pInfo
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.OpenableColumns
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import com.google.zxing.integration.android.IntentIntegrator
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : Activity(), WifiDirectManager.Listener {

    private val green = Color.rgb(22, 163, 74)
    private val blue = Color.rgb(37, 99, 235)
    private val port = TransferProtocol.PORT

    private val pickerRequest = 1001
    private val permissionRequest = 1002

    private val executor = Executors.newCachedThreadPool()
    private val receiving = AtomicBoolean(false)

    @Volatile
    private var serverSocket: ServerSocket? = null

    private var root: LinearLayout? = null
    private var statusText: TextView? = null
    private var progressBar: ProgressBar? = null
    private var wifiDirect: WifiDirectManager? = null

    private var peers: List<WifiP2pDevice> = emptyList()
    private var connectionInfo: WifiP2pInfo? = null

    private var pendingFiles: List<Uri> = emptyList()

    @Volatile
    private var qrReceiverIp: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.statusBarColor = green
        window.navigationBarColor = Color.WHITE

        @Suppress("DEPRECATION")
        run {
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        }

        wifiDirect = WifiDirectManager(this, this)
        showHome()
    }

    private fun showHome() {
        val page = newPage()

        addText(page, "MAFX SHARE", 32f, green)
        addText(page, "FAST • SIMPLE • SECURE", 15f, Color.DKGRAY)

        space(page, 28)

        addButton(page, "CONNECT DEVICES", blue) {
            requestWifiPermissions()
        }

        space(page, 12)

        addButton(page, "SEND FILES", green) {
            openFilePicker()
        }

        space(page, 12)

        addButton(page, "RECEIVE FILES", blue) {
            startReceiving()
        }

        space(page, 12)

        addButton(page, "SCAN CONNECTION QR", green) {
            scanConnectionQr()
        }

        space(page, 22)

        addText(
            page,
            if (connectionInfo?.groupFormed == true) {
                "Wi-Fi Direct: Connected"
            } else {
                "Wi-Fi Direct: Not connected"
            },
            14f,
            Color.DKGRAY
        )

        setContentView(page)
    }

    private fun newPage(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(22), dp(24), dp(22), dp(24))
            setBackgroundColor(Color.WHITE)
        }.also {
            root = it
        }
    }

    private fun addText(
        parent: LinearLayout,
        value: String,
        size: Float,
        color: Int
    ): TextView {
        return TextView(this).apply {
            text = value
            textSize = size
            setTextColor(color)
            gravity = Gravity.CENTER
            setPadding(dp(4), dp(8), dp(4), dp(8))
            parent.addView(this, matchWidth())
        }
    }

    private fun addButton(
        parent: LinearLayout,
        label: String,
        color: Int,
        action: () -> Unit
    ) {
        parent.addView(
            Button(this).apply {
                text = label
                setTextColor(Color.WHITE)
                setBackgroundColor(color)
                setOnClickListener { action() }
            },
            matchWidth()
        )
    }

    private fun space(parent: LinearLayout, height: Int) {
        parent.addView(
            View(this),
            LinearLayout.LayoutParams(1, dp(height))
        )
    }

    private fun matchWidth() = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT
    )

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private fun toast(message: String) {
        runOnUiThread {
            Toast.makeText(
                this,
                message,
                Toast.LENGTH_LONG
            ).show()
        }
    }

    private fun updateStatus(message: String) {
        runOnUiThread {
            statusText?.text = message
        }
    }

    private fun updateProgress(
        percent: Int,
        message: String
    ) {
        runOnUiThread {
            progressBar?.progress = percent.coerceIn(0, 100)
            statusText?.text = message
        }
    }

    /**
     * Avoid scheduling excessive UI updates during large transfers.
     * The data transfer itself continues independently of the UI.
     */
    private fun shouldUpdateProgress(
        lastUpdateTime: Long,
        lastUpdateBytes: Long,
        currentBytes: Long,
        finished: Boolean
    ): Boolean {
        if (finished) return true

        val now = SystemClock.elapsedRealtime()

        return now - lastUpdateTime >=
            TransferProtocol.PROGRESS_UPDATE_INTERVAL_MS ||
            currentBytes - lastUpdateBytes >=
            TransferProtocol.PROGRESS_UPDATE_BYTES
    }

    /**
     * Apply socket settings suitable for bulk file transfers.
     * Android treats the buffer sizes as requested hints.
     */
    private fun configureTransferSocket(socket: Socket) {
        socket.tcpNoDelay = true
        socket.keepAlive = true
        socket.soTimeout = TransferProtocol.SOCKET_READ_TIMEOUT_MS

        try {
            socket.sendBufferSize = 1024 * 1024
        } catch (_: Exception) {
            // The operating system may not accept the requested size.
        }

        try {
            socket.receiveBufferSize = 1024 * 1024
        } catch (_: Exception) {
            // The operating system may not accept the requested size.
        }
    }

    // ---------------------------------------------------------
    // WI-FI DIRECT
    // ---------------------------------------------------------

    private fun requestWifiPermissions() {
        val permission = if (Build.VERSION.SDK_INT >= 33) {
            Manifest.permission.NEARBY_WIFI_DEVICES
        } else {
            Manifest.permission.ACCESS_FINE_LOCATION
        }

        if (checkSelfPermission(permission) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(permission),
                permissionRequest
            )
            return
        }

        wifiDirect?.initialize()
        wifiDirect?.discoverPeers()

        showPeers()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults
        )

        if (requestCode == permissionRequest) {
            if (
                grantResults.isNotEmpty() &&
                grantResults.all {
                    it == PackageManager.PERMISSION_GRANTED
                }
            ) {
                wifiDirect?.initialize()
                wifiDirect?.discoverPeers()
                showPeers()
            } else {
                toast(
                    "Permission is required to discover nearby devices."
                )
            }
        }
    }

    private fun showPeers() {
        val labels = peers.map {
            val name = it.deviceName.ifBlank { "Unknown device" }
            "$name\n${it.deviceAddress}"
        }.toTypedArray()

        AlertDialog.Builder(this)
            .setTitle("Nearby devices")
            .setMessage(
                if (labels.isEmpty()) {
                    "Searching for nearby devices. " +
                        "Keep Wi-Fi enabled on both phones."
                } else {
                    "Choose a device to connect."
                }
            )
            .setItems(labels) { _, index ->
                peers.getOrNull(index)?.let { device ->
                    updateStatus("Connecting to ${device.deviceName}...")
                    wifiDirect?.connect(device)
                }
            }
            .setPositiveButton("SEARCH AGAIN") { _, _ ->
                requestWifiPermissions()
            }
            .setNegativeButton("CLOSE", null)
            .show()
    }

    override fun onWifiDirectStateChanged(enabled: Boolean) {
        updateStatus(
            if (enabled) {
                "Wi-Fi Direct is enabled."
            } else {
                "Turn on Wi-Fi to use Wi-Fi Direct."
            }
        )
    }

    override fun onPeersAvailable(peers: List<WifiP2pDevice>) {
        this.peers = peers
        updateStatus("${peers.size} nearby device(s) found.")
    }

    override fun onConnectionChanged(info: WifiP2pInfo?) {
        connectionInfo = info

        if (info?.groupFormed == true) {
            val address = info.groupOwnerAddress?.hostAddress
                ?: "Unknown"

            updateStatus(
                "Wi-Fi Direct connected.\n" +
                    "Group owner: $address"
            )

            toast("Wi-Fi Direct connected.")
        } else {
            updateStatus("Wi-Fi Direct disconnected.")
        }
    }

    override fun onError(message: String) {
        updateStatus(message)
        toast(message)
    }

    // ---------------------------------------------------------
    // MULTI-FILE PICKER
    // ---------------------------------------------------------

    private fun openFilePicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }

        try {
            startActivityForResult(intent, pickerRequest)
        } catch (_: Exception) {
            toast("Unable to open file picker.")
        }
    }

    @Deprecated("Uses Activity result callback for compatibility")
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)

        val qrResult = IntentIntegrator.parseActivityResult(
            requestCode,
            resultCode,
            data
        )

        if (qrResult != null) {
            val contents = qrResult.contents

            if (contents.isNullOrBlank()) {
                toast("QR scanning cancelled.")
                return
            }

            val info = QrCodeHelper.parsePayload(contents)

            if (info == null) {
                toast("Invalid MAFX SHARE QR code.")
                return
            }

            if (pendingFiles.isNotEmpty()) {
                val files = pendingFiles
                pendingFiles = emptyList()
                sendFiles(files, info.ipAddress)
            } else {
                askToSelectFiles(info.ipAddress)
            }

            return
        }

        if (
            requestCode != pickerRequest ||
            resultCode != RESULT_OK ||
            data == null
        ) {
            if (requestCode == pickerRequest) {
                qrReceiverIp = null
            }
            return
        }

        val selected = mutableListOf<Uri>()

        data.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) {
                selected.add(clip.getItemAt(i).uri)
            }
        }

        if (selected.isEmpty()) {
            data.data?.let { selected.add(it) }
        }

        if (selected.isEmpty()) {
            qrReceiverIp = null
            toast("No files selected.")
            return
        }

        val files = selected.distinct()
        val receiverIp = qrReceiverIp
        qrReceiverIp = null

        if (!receiverIp.isNullOrBlank()) {
            pendingFiles = emptyList()
            sendFiles(files, receiverIp)
        } else {
            pendingFiles = files
            askForReceiverIp()
        }
    }

    private fun askForReceiverIp() {
        val input = EditText(this).apply {
            hint = "Receiver IP address"
            setSingleLine(true)
        }

        AlertDialog.Builder(this)
            .setTitle("Connect to receiver")
            .setMessage(
                "${pendingFiles.size} file(s) selected.\n\n" +
                    "Both phones must be connected to the same " +
                    "Wi-Fi or hotspot, or have a working Wi-Fi Direct " +
                    "connection with a reachable receiver address.\n\n" +
                    "Enter the receiver IP, or scan its connection QR."
            )
            .setView(input)
            .setNeutralButton("SCAN QR") { _, _ ->
                scanConnectionQr()
            }
            .setNegativeButton("CANCEL", null)
            .setPositiveButton("SEND", null)
            .create()
            .also { dialog ->
                dialog.setOnShowListener {
                    dialog.getButton(
                        AlertDialog.BUTTON_POSITIVE
                    ).setOnClickListener {
                        val ip = input.text.toString().trim()

                        if (!isValidIpv4(ip)) {
                            input.error = "Enter a valid IPv4 address."
                            return@setOnClickListener
                        }

                        dialog.dismiss()

                        val files = pendingFiles
                        pendingFiles = emptyList()
                        sendFiles(files, ip)
                    }
                }

                dialog.show()
            }
    }

    private fun askToSelectFiles(ip: String) {
        AlertDialog.Builder(this)
            .setTitle("Receiver connected")
            .setMessage(
                "Receiver address: $ip\n\nChoose files to send."
            )
            .setNegativeButton("CANCEL", null)
            .setPositiveButton("SELECT FILES") { _, _ ->
                openFilePickerForReceiver(ip)
            }
            .show()
    }

    private fun openFilePickerForReceiver(ip: String) {
        qrReceiverIp = ip

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }

        try {
            startActivityForResult(intent, pickerRequest)
        } catch (_: Exception) {
            qrReceiverIp = null
            toast("Unable to open file picker.")
        }
    }

    // ---------------------------------------------------------
    // QR CODE
    // ---------------------------------------------------------

    private fun scanConnectionQr() {
        try {
            IntentIntegrator(this)
                .setPrompt("Scan the receiver's MAFX SHARE QR code")
                .setBeepEnabled(false)
                .setOrientationLocked(false)
                .setDesiredBarcodeFormats(
                    IntentIntegrator.QR_CODE
                )
                .initiateScan()
        } catch (_: Exception) {
            toast("Unable to start QR scanner.")
        }
    }

    private fun showConnectionQr(ip: String) {
        val payload = try {
            QrCodeHelper.createPayload(ip, port)
        } catch (e: Exception) {
            toast("Could not create QR code: ${e.message}")
            return
        }

        val bitmap: Bitmap = try {
            QrCodeHelper.createBitmap(payload)
        } catch (_: Exception) {
            toast("Could not generate QR code.")
            return
        }

        val page = newPage()

        addText(page, "MAFX SHARE", 28f, green)
        addText(page, "SCAN TO CONNECT", 19f, blue)

        space(page, 12)

        page.addView(
            ImageView(this).apply {
                setImageBitmap(bitmap)
                adjustViewBounds = true
                scaleType = ImageView.ScaleType.FIT_CENTER
            },
            LinearLayout.LayoutParams(
                dp(280),
                dp(280)
            )
        )

        space(page, 12)

        addText(page, "IP ADDRESS", 14f, Color.DKGRAY)
        addText(page, ip, 23f, green)
        addText(page, "Port: $port", 15f, Color.DKGRAY)

        space(page, 12)

        addText(
            page,
            "Keep this screen open while the other phone scans the QR code.",
            14f,
            Color.DKGRAY
        )

        space(page, 20)

        addButton(page, "STOP RECEIVING", blue) {
            stopReceiving()
            showHome()
        }

        setContentView(page)
    }

    // ---------------------------------------------------------
    // RECEIVE FILES
    // ---------------------------------------------------------

    private fun startReceiving() {
        if (!receiving.compareAndSet(false, true)) {
            toast("Receiver is already running.")
            return
        }

        val ip = getLocalIp()

        if (ip == null) {
            receiving.set(false)

            AlertDialog.Builder(this)
                .setTitle("Network unavailable")
                .setMessage(
                    "Connect to a Wi-Fi network or hotspot first. " +
                        "Then try receiving again."
                )
                .setPositiveButton("OK", null)
                .show()

            return
        }

        showConnectionQr(ip)

        executor.execute {
            var server: ServerSocket? = null

            try {
                server = ServerSocket()
                server.reuseAddress = true
                server.bind(InetSocketAddress(port))
                serverSocket = server

                updateStatus("Waiting for incoming files...")

                while (receiving.get()) {
                    val client = try {
                        server.accept()
                    } catch (e: IOException) {
                        if (receiving.get()) throw e
                        break
                    }

                    if (receiving.get()) {
                        executor.execute {
                            receiveFile(client)
                        }
                    } else {
                        client.close()
                    }
                }
            } catch (e: Exception) {
                if (receiving.get()) {
                    updateStatus(
                        "Receiver error: ${e.message ?: "Unknown error"}"
                    )
                }
            } finally {
                try {
                    server?.close()
                } catch (_: Exception) {
                }

                if (serverSocket === server) {
                    serverSocket = null
                }

                receiving.set(false)
            }
        }
    }

    private fun receiveFile(socket: Socket) {
        socket.use { connection ->
            try {
                configureTransferSocket(connection)

                val input = DataInputStream(
                    BufferedInputStream(
                        connection.getInputStream(),
                        TransferProtocol.BUFFER_SIZE
                    )
                )

                val output = DataOutputStream(
                    BufferedOutputStream(
                        connection.getOutputStream(),
                        TransferProtocol.BUFFER_SIZE
                    )
                )

                if (!TransferProtocol.readAndValidateHeader(input)) {
                    throw IOException("Incompatible MAFX SHARE protocol.")
                }

                val name = TransferProtocol.safeFileName(
                    input.readUTF()
                )

                val size = input.readLong()

                if (!TransferProtocol.isValidFileSize(size)) {
                    output.writeBoolean(false)
                    output.flush()
                    throw IOException("Invalid file size.")
                }

                val directory = getExternalFilesDir("Received")
                    ?: throw IOException("Received folder unavailable.")

                if (!directory.exists() && !directory.mkdirs()) {
                    throw IOException("Could not create Received folder.")
                }

                val uniqueName = TransferProtocol.uniqueFileName(name) {
                    File(directory, it).exists() ||
                        File(directory, "$it.part").exists()
                }

                val destination = File(directory, uniqueName)
                val temporary = File(directory, "$uniqueName.part")

                output.writeBoolean(true)
                output.flush()

                val buffer = ByteArray(TransferProtocol.BUFFER_SIZE)

                var total = 0L
                var lastUpdateTime = SystemClock.elapsedRealtime()
                var lastUpdateBytes = 0L

                FileOutputStream(temporary).use { fileOutput ->
                    while (total < size) {
                        val wanted = minOf(
                            buffer.size.toLong(),
                            size - total
                        ).toInt()

                        val count = input.read(buffer, 0, wanted)

                        if (count < 0) {
                            throw EOFException(
                                "Connection ended before transfer completed."
                            )
                        }

                        if (count == 0) continue

                        fileOutput.write(buffer, 0, count)
                        total += count

                        val finished = total >= size

                        if (
                            shouldUpdateProgress(
                                lastUpdateTime,
                                lastUpdateBytes,
                                total,
                                finished
                            )
                        ) {
                            val percent = TransferProtocol.progressPercent(
                                total,
                                size
                            )

                            updateProgress(
                                percent,
                                "Receiving $uniqueName: $percent%"
                            )

                            lastUpdateTime = SystemClock.elapsedRealtime()
                            lastUpdateBytes = total
                        }
                    }

                    fileOutput.fd.sync()
                }

                if (!temporary.renameTo(destination)) {
                    temporary.delete()
                    throw IOException("Could not save received file.")
                }

                updateProgress(
                    100,
                    "Received successfully!\n\n$uniqueName"
                )
            } catch (e: Exception) {
                updateStatus(
                    "Receive failed: ${e.message ?: "Connection error"}"
                )
            }
        }
    }

    // ---------------------------------------------------------
    // SEND MULTIPLE FILES
    // ---------------------------------------------------------

    private fun sendFiles(files: List<Uri>, ip: String) {
        if (files.isEmpty()) {
            toast("No files selected.")
            return
        }

        if (!isValidIpv4(ip)) {
            toast("Invalid receiver IP address.")
            return
        }

        val page = newPage()

        addText(page, "SENDING FILES", 25f, green)

        statusText = addText(
            page,
            "Preparing ${files.size} file(s)...",
            16f,
            Color.DKGRAY
        )

        space(page, 12)

        progressBar = ProgressBar(
            this,
            null,
            android.R.attr.progressBarStyleHorizontal
        ).apply {
            max = 100
            progress = 0
        }

        page.addView(progressBar, matchWidth())

        space(page, 20)

        addButton(page, "BACK TO HOME", blue) {
            showHome()
        }

        setContentView(page)

        executor.execute {
            var completed = 0

            for (uri in files) {
                if (isFinishing) break

                try {
                    sendOneFile(uri, ip)
                    completed++

                    updateStatus(
                        "Sent $completed of ${files.size} file(s)."
                    )
                } catch (e: Exception) {
                    updateStatus(
                        "Failed: ${getFileName(uri)}\n" +
                            (e.message ?: "Connection error")
                    )
                    break
                }

                updateProgress(
                    completed * 100 / files.size,
                    "Sent $completed of ${files.size} file(s)."
                )
            }

            if (completed == files.size) {
                updateProgress(
                    100,
                    "All ${files.size} file(s) sent successfully!"
                )
            }
        }
    }

    private fun sendOneFile(uri: Uri, ip: String) {
        val name = TransferProtocol.safeFileName(getFileName(uri))
        val size = getFileSize(uri)

        if (size < 0L) {
            throw IOException(
                "Could not determine the file size of $name."
            )
        }

        Socket().use { socket ->
            socket.connect(
                InetSocketAddress(ip, port),
                TransferProtocol.CONNECT_TIMEOUT_MS
            )

            configureTransferSocket(socket)

            val output = DataOutputStream(
                BufferedOutputStream(
                    socket.getOutputStream(),
                    TransferProtocol.BUFFER_SIZE
                )
            )

            val input = DataInputStream(
                BufferedInputStream(
                    socket.getInputStream(),
                    TransferProtocol.BUFFER_SIZE
                )
            )

            TransferProtocol.writeHeader(output)
            output.writeUTF(name)
            output.writeLong(size)
            output.flush()

            if (!input.readBoolean()) {
                throw IOException("Receiver rejected $name.")
            }

            val source = contentResolver.openInputStream(uri)
                ?: throw IOException("Cannot open $name.")

            source.use { stream ->
                val buffer = ByteArray(TransferProtocol.BUFFER_SIZE)

                var total = 0L
                var lastUpdateTime = SystemClock.elapsedRealtime()
                var lastUpdateBytes = 0L

                while (total < size) {
                    val wanted = minOf(
                        buffer.size.toLong(),
                        size - total
                    ).toInt()

                    val count = stream.read(buffer, 0, wanted)

                    if (count < 0) {
                        throw EOFException(
                            "File ended before transfer completed."
                        )
                    }

                    if (count == 0) continue

                    output.write(buffer, 0, count)
                    total += count

                    val finished = total >= size

                    if (
                        shouldUpdateProgress(
                            lastUpdateTime,
                            lastUpdateBytes,
                            total,
                            finished
                        )
                    ) {
                        val percent = TransferProtocol.progressPercent(
                            total,
                            size
                        )

                        updateStatus("Sending $name: $percent%")

                        lastUpdateTime = SystemClock.elapsedRealtime()
                        lastUpdateBytes = total
                    }
                }

                output.flush()
            }
        }
    }

    // ---------------------------------------------------------
    // NETWORK AND FILE HELPERS
    // ---------------------------------------------------------

    private fun getLocalIp(): String? {
        return try {
            val interfaces =
                NetworkInterface.getNetworkInterfaces() ?: return null

            val candidates = mutableListOf<Pair<Int, String>>()

            while (interfaces.hasMoreElements()) {
                val network = interfaces.nextElement()

                if (!network.isUp || network.isLoopback) continue

                val addresses = network.inetAddresses

                while (addresses.hasMoreElements()) {
                    val address = addresses.nextElement()

                    if (
                        address !is Inet4Address ||
                        address.isLoopbackAddress
                    ) {
                        continue
                    }

                    val host = address.hostAddress ?: continue

                    if (host.startsWith("169.254.")) continue

                    val interfaceName = network.name.lowercase()

                    val priority = when {
                        interfaceName.startsWith("wlan") -> 0
                        interfaceName.startsWith("ap") -> 1
                        interfaceName.startsWith("wifi") -> 2
                        interfaceName.startsWith("p2p") -> 3
                        else -> 4
                    }

                    candidates.add(priority to host)
                }
            }

            candidates.sortedBy { it.first }.firstOrNull()?.second
        } catch (_: Exception) {
            null
        }
    }

    private fun isValidIpv4(ip: String): Boolean {
        val parts = ip.split(".")

        if (parts.size != 4) return false

        return parts.all {
            it.isNotEmpty() &&
                it.length <= 3 &&
                it.all { character -> character in '0'..'9' } &&
                (it.toIntOrNull() ?: -1) in 0..255
        }
    }

    private fun getFileName(uri: Uri): String {
        var name = "shared_file"

        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(
                    OpenableColumns.DISPLAY_NAME
                )

                if (index >= 0) {
                    name = cursor.getString(index) ?: name
                }
            }
        }

        return name
    }

    private fun getFileSize(uri: Uri): Long {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.SIZE),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(
                    OpenableColumns.SIZE
                )

                if (index >= 0 && !cursor.isNull(index)) {
                    return cursor.getLong(index)
                }
            }
        }

        return -1L
    }

    private fun stopReceiving() {
        receiving.set(false)

        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }

        serverSocket = null
    }

    override fun onDestroy() {
        stopReceiving()
        wifiDirect?.release()
        executor.shutdownNow()
        super.onDestroy()
    }
}
