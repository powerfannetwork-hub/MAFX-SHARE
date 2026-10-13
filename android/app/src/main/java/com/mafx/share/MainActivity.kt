package com.mafx.share

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Color
import android.net.Uri
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pInfo
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
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
    private val pickFileRequest = 1001
    private val wifiPermissionRequest = 1002

    private val executor = Executors.newCachedThreadPool()
    private val receiving = AtomicBoolean(false)

    @Volatile
    private var serverSocket: ServerSocket? = null

    private var layout: LinearLayout? = null
    private var status: TextView? = null
    private var progress: ProgressBar? = null
    private var wifiDirect: WifiDirectManager? = null

    private var discoveredPeers: List<WifiP2pDevice> = emptyList()
    private var connectedInfo: WifiP2pInfo? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.statusBarColor = green
        window.navigationBarColor = Color.WHITE
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR

        wifiDirect = WifiDirectManager(this, this)
        showHome()
    }

    private fun showHome() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(24), dp(24), dp(24))
            setBackgroundColor(Color.WHITE)
        }

        layout = root

        root.addView(
            TextView(this).apply {
                text = "MAFX SHARE"
                textSize = 30f
                setTextColor(green)
                gravity = Gravity.CENTER
            },
            matchWidth()
        )

        root.addView(
            TextView(this).apply {
                text = "Fast • Simple • Secure"
                textSize = 16f
                setTextColor(Color.DKGRAY)
                gravity = Gravity.CENTER
            },
            matchWidth()
        )

        addSpace(root, 28)

        root.addView(
            makeButton("CONNECT DEVICES", blue) {
                requestWifiPermissionsAndDiscover()
            },
            matchWidth()
        )

        addSpace(root, 12)

        root.addView(
            makeButton("SEND FILES", green) {
                openFilePicker()
            },
            matchWidth()
        )

        addSpace(root, 12)

        root.addView(
            makeButton("RECEIVE FILES", blue) {
                startReceiving()
            },
            matchWidth()
        )

        addSpace(root, 20)

        root.addView(
            TextView(this).apply {
                text = if (connectedInfo?.groupFormed == true) {
                    "Wi-Fi Direct: Connected"
                } else {
                    "Wi-Fi Direct: Not connected"
                }
                textSize = 14f
                gravity = Gravity.CENTER
                setTextColor(Color.DKGRAY)
            },
            matchWidth()
        )

        setContentView(root)
    }

    private fun requestWifiPermissionsAndDiscover() {
        val permissions = requiredWifiPermissions()
        val missing = permissions.filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }

        if (missing.isNotEmpty()) {
            requestPermissions(
                missing.toTypedArray(),
                wifiPermissionRequest
            )
            return
        }

        initializeAndDiscover()
    }

    private fun requiredWifiPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= 33) {
            arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
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

        if (requestCode != wifiPermissionRequest) return

        if (grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        ) {
            initializeAndDiscover()
        } else {
            showMessage(
                "Permission required",
                "Allow the required nearby-device permission to use Wi-Fi Direct."
            )
        }
    }

    private fun initializeAndDiscover() {
        wifiDirect?.initialize()
        wifiDirect?.discoverPeers()

        updateStatus("Searching for nearby devices...")
        showPeerList()
    }

    private fun showPeerList() {
        val names = discoveredPeers.map { device ->
            val deviceName = device.deviceName
                .takeIf { it.isNotBlank() }
                ?: "Unnamed device"

            "$deviceName\n${device.deviceAddress}\n${deviceStatus(device.status)}"
        }.toTypedArray()

        AlertDialog.Builder(this)
            .setTitle("Nearby devices")
            .setMessage(
                if (names.isEmpty()) {
                    "Searching for devices...\n\n" +
                        "Keep Wi-Fi enabled on both phones. " +
                        "The other phone may need to open its sharing screen."
                } else {
                    "Select a device to connect."
                }
            )
            .setItems(names) { _, index ->
                val device = discoveredPeers.getOrNull(index)
                if (device != null) {
                    connectToDevice(device)
                }
            }
            .setPositiveButton("SEARCH AGAIN") { _, _ ->
                requestWifiPermissionsAndDiscover()
            }
            .setNegativeButton("CLOSE", null)
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

    private fun connectToDevice(device: WifiP2pDevice) {
        updateStatus("Connecting to ${device.deviceName}...")
        wifiDirect?.connect(device)
    }

    override fun onWifiDirectStateChanged(enabled: Boolean) {
        runOnUiThread {
            if (enabled) {
                updateStatus("Wi-Fi Direct is enabled.")
            } else {
                updateStatus("Turn on Wi-Fi to use Wi-Fi Direct.")
            }
        }
    }

    override fun onPeersAvailable(peers: List<WifiP2pDevice>) {
        runOnUiThread {
            discoveredPeers = peers
            updateStatus(
                if (peers.isEmpty()) {
                    "No devices found yet. Search again."
                } else {
                    "${peers.size} nearby device(s) found."
                }
            )
        }
    }

    override fun onConnectionChanged(info: WifiP2pInfo?) {
        runOnUiThread {
            connectedInfo = info

            if (info?.groupFormed == true) {
                val ownerAddress =
                    info.groupOwnerAddress?.hostAddress ?: "Unknown"

                updateStatus(
                    "Wi-Fi Direct connected.\n" +
                        "Group owner: $ownerAddress"
                )

                showMessage(
                    "Device connected",
                    "Wi-Fi Direct connection established.\n\n" +
                        "Group owner address: $ownerAddress\n\n" +
                        "File transfer over this connection still needs " +
                        "to be linked to the transfer server."
                )
            } else {
                updateStatus("Wi-Fi Direct disconnected.")
            }
        }
    }

    override fun onError(message: String) {
        runOnUiThread {
            updateStatus(message)
            Toast.makeText(
                this,
                message,
                Toast.LENGTH_LONG
            ).show()
        }
    }

    private fun openFilePicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }

        try {
            startActivityForResult(intent, pickFileRequest)
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

        if (requestCode != pickFileRequest || resultCode != RESULT_OK) {
            return
        }

        val uri = data?.data ?: return

        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: Exception) {
            // Persistent access may not be supported by every provider.
        }

        askForReceiverIp(uri)
    }

    private fun askForReceiverIp(uri: Uri) {
        val input = EditText(this).apply {
            hint = "Example: 192.168.1.10"
            setSingleLine(true)
            inputType =
                InputType.TYPE_CLASS_TEXT or
                    InputType.TYPE_TEXT_VARIATION_URI
        }

        AlertDialog.Builder(this)
            .setTitle("Receiver IP address")
            .setMessage(
                "For the current transfer method, connect both phones " +
                    "to the same Wi-Fi or hotspot.\n\n" +
                    "On the receiving phone, tap RECEIVE FILES and " +
                    "enter the displayed IP address."
            )
            .setView(input)
            .setNegativeButton("Cancel", null)
            .setPositiveButton("SEND", null)
            .create()
            .also { dialog ->
                dialog.setOnShowListener {
                    dialog.getButton(AlertDialog.BUTTON_POSITIVE)
                        .setOnClickListener {
                            val ip = input.text.toString().trim()

                            if (ip.isBlank()) {
                                input.error = "Enter the receiver IP address."
                                return@setOnClickListener
                            }

                            dialog.dismiss()
                            sendFile(uri, ip)
                        }
                }
                dialog.show()
            }
    }

    private fun startReceiving() {
        if (!receiving.compareAndSet(false, true)) {
            toast("Receiver is already running.")
            return
        }

        val ipAddress = getLocalIp()

        if (ipAddress == null) {
            receiving.set(false)
            showMessage(
                "Network unavailable",
                "No suitable local IPv4 address was found. " +
                    "Connect to Wi-Fi or a hotspot and try again."
            )
            return
        }

        val root = createTransferScreen(
            "RECEIVE FILES",
            blue,
            "Starting receiver..."
        )

        root.addView(
            TextView(this).apply {
                text =
                    "RECEIVER IP ADDRESS\n\n$ipAddress\n\n" +
                        "Port: $port\n\n" +
                        "Enter this IP address on the sending phone.\n\n" +
                        "Keep this screen open while receiving files."
                textSize = 17f
                gravity = Gravity.CENTER
                setTextColor(Color.DKGRAY)
            },
            0,
            matchWidth()
        )

        addSpace(root, 20)

        root.addView(
            makeButton("STOP RECEIVING", blue) {
                stopReceiving()
                showHome()
            },
            matchWidth()
        )

        executor.execute {
            var server: ServerSocket? = null

            try {
                server = ServerSocket()
                server.reuseAddress = true
                server.bind(InetSocketAddress(port))
                serverSocket = server

                updateStatus("Waiting for sender...")

                while (receiving.get()) {
                    val client = try {
                        server.accept()
                    } catch (e: IOException) {
                        if (receiving.get()) throw e
                        break
                    }

                    if (!receiving.get()) {
                        client.close()
                        break
                    }

                    executor.execute {
                        receiveFile(client)
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
                connection.tcpNoDelay = true
                connection.soTimeout =
                    TransferProtocol.SOCKET_READ_TIMEOUT_MS

                val input = DataInputStream(
                    BufferedInputStream(connection.getInputStream())
                )
                val output = DataOutputStream(
                    BufferedOutputStream(connection.getOutputStream())
                )

                if (!TransferProtocol.readAndValidateHeader(input)) {
                    throw IOException("Incompatible MAFX SHARE protocol.")
                }

                val receivedName = input.readUTF()
                val size = input.readLong()

                if (!TransferProtocol.isValidFileSize(size)) {
                    output.writeBoolean(false)
                    output.flush()
                    throw IOException("Invalid file size.")
                }

                val directory = getExternalFilesDir("Received")
                    ?: throw IOException("Destination folder unavailable.")

                if (!directory.exists() && !directory.mkdirs()) {
                    throw IOException("Cannot create destination folder.")
                }

                val fileName = TransferProtocol.uniqueFileName(
                    receivedName
                ) { candidate ->
                    File(directory, candidate).exists() ||
                        File(directory, "$candidate.part").exists()
                }

                val destination = File(directory, fileName)
                val temporary = File(directory, "$fileName.part")

                output.writeBoolean(true)
                output.flush()

                val buffer = ByteArray(TransferProtocol.BUFFER_SIZE)
                var total = 0L

                FileOutputStream(temporary, false).use { fileOutput ->
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

                        val percent = TransferProtocol.progressPercent(
                            total,
                            size
                        )

                        updateProgress(
                            percent,
                            "Receiving $fileName: $percent%"
                        )
                    }

                    fileOutput.fd.sync()
                }

                if (destination.exists() || !temporary.renameTo(destination)) {
                    throw IOException("Could not finalize received file.")
                }

                updateProgress(
                    100,
                    "Received successfully!\n\n$fileName\n\n" +
                        "Saved in the app's Received folder."
                )
            } catch (e: Exception) {
                updateStatus(
                    "Transfer failed: ${e.message ?: "Connection error"}"
                )
            }
        }
    }

    private fun sendFile(uri: Uri, ip: String) {
        val fileName = TransferProtocol.safeFileName(getFileName(uri))
        val size = getFileSize(uri)

        if (size < 0L) {
            toast("Cannot determine the file size. Choose another file.")
            return
        }

        createTransferScreen(
            "SENDING FILE",
            green,
            "Connecting to $ip..."
        )

        val root = layout ?: return

        addSpace(root, 20)

        root.addView(
            makeButton("BACK TO HOME", blue) {
                showHome()
            },
            matchWidth()
        )

        executor.execute {
            try {
                Socket().use { socket ->
                    socket.connect(
                        InetSocketAddress(ip, port),
                        TransferProtocol.CONNECT_TIMEOUT_MS
                    )
                    socket.tcpNoDelay = true
                    socket.soTimeout =
                        TransferProtocol.SOCKET_READ_TIMEOUT_MS

                    val output = DataOutputStream(
                        BufferedOutputStream(socket.getOutputStream())
                    )
                    val input = DataInputStream(
                        BufferedInputStream(socket.getInputStream())
                    )

                    TransferProtocol.writeHeader(output)
                    output.writeUTF(fileName)
                    output.writeLong(size)
                    output.flush()

                    if (!input.readBoolean()) {
                        throw IOException("The receiver rejected this file.")
                    }

                    val source = contentResolver.openInputStream(uri)
                        ?: throw IOException("Cannot open selected file.")

                    source.use { stream ->
                        val buffer =
                            ByteArray(TransferProtocol.BUFFER_SIZE)
                        var total = 0L

                        while (total < size) {
                            val wanted = minOf(
                                buffer.size.toLong(),
                                size - total
                            ).toInt()

                            val count = stream.read(buffer, 0, wanted)

                            if (count < 0) {
                                throw EOFException(
                                    "Source file ended before transfer completed."
                                )
                            }
                            if (count == 0) continue

                            output.write(buffer, 0, count)
                            total += count

                            val percent = TransferProtocol.progressPercent(
                                total,
                                size
                            )

                            updateProgress(
                                percent,
                                "Sending $fileName: $percent%"
                            )
                        }
                    }

                    output.flush()
                    updateProgress(100, "File sent successfully!\n\n$fileName")
                }
            } catch (e: Exception) {
                updateStatus(
                    "Send failed: ${e.message ?: "Connection error"}\n\n" +
                        "Check the receiver IP, port, and network."
                )
            }
        }
    }

    private fun createTransferScreen(
        title: String,
        titleColor: Int,
        initialStatus: String
    ): LinearLayout {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(24), dp(24), dp(24))
            setBackgroundColor(Color.WHITE)
        }

        layout = root

        root.addView(
            TextView(this).apply {
                text = title
                textSize = 25f
                gravity = Gravity.CENTER
                setTextColor(titleColor)
            },
            matchWidth()
        )

        addSpace(root, 24)

        status = TextView(this).apply {
            text = initialStatus
            textSize = 16f
            gravity = Gravity.CENTER
            setTextColor(Color.DKGRAY)
        }
        root.addView(status, matchWidth())

        addSpace(root, 16)

        progress = ProgressBar(
            this,
            null,
            android.R.attr.progressBarStyleHorizontal
        ).apply {
            max = 100
            this.progress = 0
        }
        root.addView(progress, matchWidth())

        setContentView(root)
        return root
    }

    private fun getFileName(uri: Uri): String {
        var name = "shared_file"

        val cursor: Cursor? = contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null
        )

        cursor?.use {
            if (it.moveToFirst()) {
                val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) name = it.getString(index) ?: name
            }
        }

        return name
    }

    private fun getFileSize(uri: Uri): Long {
        val cursor = contentResolver.query(
            uri,
            arrayOf(OpenableColumns.SIZE),
            null,
            null,
            null
        )

        cursor?.use {
            if (it.moveToFirst()) {
                val index = it.getColumnIndex(OpenableColumns.SIZE)
                if (index >= 0 && !it.isNull(index)) {
                    return it.getLong(index)
                }
            }
        }

        return -1L
    }

    private fun getLocalIp(): String? {
        return try {
            val interfaces =
                NetworkInterface.getNetworkInterfaces() ?: return null
            val addressesFound = mutableListOf<Pair<Int, String>>()

            while (interfaces.hasMoreElements()) {
                val network = interfaces.nextElement()
                if (!network.isUp || network.isLoopback) continue

                val addresses = network.inetAddresses

                while (addresses.hasMoreElements()) {
                    val address = addresses.nextElement()

                    if (address !is Inet4Address ||
                        address.isLoopbackAddress
                    ) continue

                    val host = address.hostAddress ?: continue
                    if (host.startsWith("169.254.")) continue

                    val name = network.name.lowercase()
                    val priority = when {
                        name.startsWith("wlan") -> 0
                        name.startsWith("ap") -> 1
                        name.startsWith("wifi") -> 2
                        else -> 3
                    }

                    addressesFound.add(priority to host)
                }
            }

            addressesFound.sortedBy { it.first }.firstOrNull()?.second
        } catch (_: Exception) {
            null
        }
    }

    private fun stopReceiving() {
        receiving.set(false)

        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }

        serverSocket = null
    }

    private fun updateStatus(message: String) {
        runOnUiThread {
            status?.text = message
        }
    }

    private fun updateProgress(percent: Int, message: String) {
        runOnUiThread {
            progress?.progress = percent.coerceIn(0, 100)
            status?.text = message
        }
    }

    private fun makeButton(
        label: String,
        color: Int,
        action: () -> Unit
    ): Button {
        return Button(this).apply {
            text = label
            setTextColor(Color.WHITE)
            setBackgroundColor(color)
            setOnClickListener { action() }
        }
    }

    private fun matchWidth() = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT
    )

    private fun addSpace(parent: LinearLayout, height: Int) {
        parent.addView(
            View(this),
            LinearLayout.LayoutParams(1, dp(height))
        )
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private fun toast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
    }

    private fun showMessage(title: String, message: String) {
        AlertDialog.Builder(this)
            .setTitle(title)
            .setMessage(message)
            .setPositiveButton("OK", null)
            .show()
    }

    override fun onDestroy() {
        stopReceiving()
        wifiDirect?.release()
        executor.shutdownNow()
        super.onDestroy()
    }
}
