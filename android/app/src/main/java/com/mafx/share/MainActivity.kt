package com.mafx.share

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.database.Cursor
import android.graphics.Color
import android.net.Uri
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

class MainActivity : Activity() {

    private val green = Color.rgb(22, 163, 74)
    private val blue = Color.rgb(37, 99, 235)

    private val port = TransferProtocol.PORT
    private val pickFileRequest = 1001

    private val executor = Executors.newCachedThreadPool()
    private val receiving = AtomicBoolean(false)

    @Volatile
    private var serverSocket: ServerSocket? = null

    private var layout: LinearLayout? = null
    private var status: TextView? = null
    private var progress: ProgressBar? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.statusBarColor = green
        window.navigationBarColor = Color.WHITE

        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR

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

        val logo = TextView(this).apply {
            text = "MAFX SHARE"
            textSize = 30f
            setTextColor(green)
            gravity = Gravity.CENTER
        }

        val subtitle = TextView(this).apply {
            text = "Fast • Simple • Secure"
            textSize = 16f
            setTextColor(Color.DKGRAY)
            gravity = Gravity.CENTER
        }

        val sendButton = makeButton("SEND FILES", green) {
            openFilePicker()
        }

        val receiveButton = makeButton("RECEIVE FILES", blue) {
            startReceiving()
        }

        root.addView(logo, matchWidth())
        root.addView(subtitle, matchWidth())

        addSpace(root, 32)

        root.addView(sendButton, matchWidth())

        addSpace(root, 12)

        root.addView(receiveButton, matchWidth())

        setContentView(root)
    }

    private fun openFilePicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }

        try {
            startActivityForResult(intent, pickFileRequest)
        } catch (e: Exception) {
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

        if (requestCode != pickFileRequest ||
            resultCode != RESULT_OK
        ) {
            return
        }

        val uri = data?.data ?: return

        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: Exception) {
            // Some document providers do not support persistent access.
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
                "Connect both phones to the same Wi-Fi or hotspot.\n\n" +
                    "On the receiving phone, tap RECEIVE FILES.\n" +
                    "Enter the IP address displayed on that phone."
            )
            .setView(input)
            .setNegativeButton("Cancel", null)
            .setPositiveButton("SEND", null)
            .create()
            .also { dialog ->
                dialog.setOnShowListener {
                    dialog.getButton(
                        AlertDialog.BUTTON_POSITIVE
                    ).setOnClickListener {
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

            AlertDialog.Builder(this)
                .setTitle("Network unavailable")
                .setMessage(
                    "No suitable local IPv4 address was found.\n\n" +
                        "Connect to Wi-Fi or another phone's hotspot, " +
                        "then try again."
                )
                .setPositiveButton("OK", null)
                .show()

            return
        }

        val root = createTransferScreen(
            title = "RECEIVE FILES",
            titleColor = blue,
            initialStatus = "Starting receiver..."
        )

        val instructions = TextView(this).apply {
            text =
                "RECEIVER IP ADDRESS\n\n" +
                    "$ipAddress\n\n" +
                    "Port: $port\n\n" +
                    "Enter this IP address on the sending phone.\n\n" +
                    "Keep this screen open while receiving files."

            textSize = 17f
            gravity = Gravity.CENTER
            setTextColor(Color.DKGRAY)
        }

        root.addView(instructions, 0, matchWidth())

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
                        if (receiving.get()) {
                            throw e
                        }

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
                    BufferedInputStream(
                        connection.getInputStream()
                    )
                )

                val output = DataOutputStream(
                    BufferedOutputStream(
                        connection.getOutputStream()
                    )
                )

                // Verify that the sender uses the MAFX protocol.
                if (!TransferProtocol.readAndValidateHeader(input)) {
                    throw IOException(
                        "Incompatible MAFX SHARE protocol."
                    )
                }

                val receivedName = input.readUTF()

                val size = input.readLong()

                if (!TransferProtocol.isValidFileSize(size)) {
                    output.writeBoolean(false)
                    output.flush()

                    throw IOException("Invalid file size.")
                }

                val directory = getExternalFilesDir("Received")
                    ?: throw IOException(
                        "Destination folder is unavailable."
                    )

                if (!directory.exists() && !directory.mkdirs()) {
                    throw IOException(
                        "Cannot create destination folder."
                    )
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

                try {
                    FileOutputStream(temporary, false).use { fileOutput ->
                        while (total < size) {
                            val wanted = minOf(
                                buffer.size.toLong(),
                                size - total
                            ).toInt()

                            val count = input.read(
                                buffer,
                                0,
                                wanted
                            )

                            if (count < 0) {
                                throw EOFException(
                                    "Connection ended before the file " +
                                        "was fully received."
                                )
                            }

                            if (count == 0) {
                                continue
                            }

                            fileOutput.write(buffer, 0, count)
                            total += count

                            val percent =
                                TransferProtocol.progressPercent(
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

                    if (destination.exists()) {
                        throw IOException(
                            "Destination already exists."
                        )
                    }

                    if (!temporary.renameTo(destination)) {
                        throw IOException(
                            "Could not finalize the received file."
                        )
                    }

                    updateProgress(
                        100,
                        "Received successfully!\n\n" +
                            "$fileName\n\n" +
                            "Saved in the app's Received folder."
                    )
                } catch (e: Exception) {
                    // Keep an incomplete .part file for possible
                    // future recovery rather than deleting user data.
                    throw e
                }
            } catch (e: Exception) {
                updateStatus(
                    "Transfer failed: " +
                        (e.message ?: "Connection error")
                )
            }
        }
    }

    private fun sendFile(uri: Uri, ip: String) {
        val originalName = getFileName(uri)

        val fileName = TransferProtocol.safeFileName(originalName)
        val size = getFileSize(uri)

        if (size < 0L) {
            toast(
                "Cannot determine the file size. " +
                    "Choose a file with a known size."
            )
            return
        }

        createTransferScreen(
            title = "SENDING FILE",
            titleColor = green,
            initialStatus = "Connecting to $ip..."
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
                        BufferedOutputStream(
                            socket.getOutputStream()
                        )
                    )

                    val input = DataInputStream(
                        BufferedInputStream(
                            socket.getInputStream()
                        )
                    )

                    // Protocol header must match the receiver.
                    TransferProtocol.writeHeader(output)

                    output.writeUTF(fileName)
                    output.writeLong(size)
                    output.flush()

                    val accepted = input.readBoolean()

                    if (!accepted) {
                        throw IOException(
                            "The receiver rejected this file."
                        )
                    }

                    val source = contentResolver.openInputStream(uri)
                        ?: throw IOException(
                            "Cannot open the selected file."
                        )

                    source.use { stream ->
                        val buffer =
                            ByteArray(TransferProtocol.BUFFER_SIZE)

                        var total = 0L

                        while (total < size) {
                            val wanted = minOf(
                                buffer.size.toLong(),
                                size - total
                            ).toInt()

                            val count = stream.read(
                                buffer,
                                0,
                                wanted
                            )

                            if (count < 0) {
                                throw EOFException(
                                    "The source file ended before " +
                                        "the transfer completed."
                                )
                            }

                            if (count == 0) {
                                continue
                            }

                            output.write(buffer, 0, count)
                            total += count

                            val percent =
                                TransferProtocol.progressPercent(
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

                    updateProgress(
                        100,
                        "File sent successfully!\n\n$fileName"
                    )
                }
            } catch (e: Exception) {
                updateStatus(
                    "Send failed: " +
                        (e.message ?: "Connection error") +
                        "\n\nCheck that both phones are connected " +
                        "to the same network and that the receiver " +
                        "is waiting."
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

        val heading = TextView(this).apply {
            text = title
            textSize = 25f
            gravity = Gravity.CENTER
            setTextColor(titleColor)
        }

        status = TextView(this).apply {
            text = initialStatus
            textSize = 16f
            gravity = Gravity.CENTER
            setTextColor(Color.DKGRAY)
        }

        progress = ProgressBar(
            this,
            null,
            android.R.attr.progressBarStyleHorizontal
        ).apply {
            max = 100
            this.progress = 0
        }

        root.addView(heading, matchWidth())

        addSpace(root, 24)

        root.addView(status, matchWidth())

        addSpace(root, 16)

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
                val index = it.getColumnIndex(
                    OpenableColumns.DISPLAY_NAME
                )

                if (index >= 0) {
                    name = it.getString(index) ?: name
                }
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
                val index = it.getColumnIndex(
                    OpenableColumns.SIZE
                )

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
                NetworkInterface.getNetworkInterfaces()
                    ?: return null

            val addressesFound = mutableListOf<Pair<Int, String>>()

            while (interfaces.hasMoreElements()) {
                val network = interfaces.nextElement()

                if (!network.isUp || network.isLoopback) {
                    continue
                }

                val addresses = network.inetAddresses

                while (addresses.hasMoreElements()) {
                    val address = addresses.nextElement()

                    if (address !is Inet4Address ||
                        address.isLoopbackAddress
                    ) {
                        continue
                    }

                    val host = address.hostAddress ?: continue

                    if (host.startsWith("169.254.")) {
                        continue
                    }

                    // Prefer typical Wi-Fi and hotspot interfaces.
                    val interfaceName =
                        network.name.lowercase()

                    val priority = when {
                        interfaceName.startsWith("wlan") -> 0
                        interfaceName.startsWith("ap") -> 1
                        interfaceName.startsWith("wifi") -> 2
                        else -> 3
                    }

                    addressesFound.add(priority to host)
                }
            }

            addressesFound
                .sortedBy { it.first }
                .firstOrNull()
                ?.second
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

    private fun updateProgress(
        percent: Int,
        message: String
    ) {
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
            setOnClickListener {
                action()
            }
        }
    }

    private fun matchWidth(): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
    }

    private fun addSpace(
        parent: LinearLayout,
        height: Int
    ) {
        val space = View(this)

        parent.addView(
            space,
            LinearLayout.LayoutParams(
                1,
                dp(height)
            )
        )
    }

    private fun dp(value: Int): Int {
        return (
            value * resources.displayMetrics.density
        ).toInt()
    }

    private fun toast(message: String) {
        Toast.makeText(
            this,
            message,
            Toast.LENGTH_LONG
        ).show()
    }

    override fun onDestroy() {
        stopReceiving()
        executor.shutdownNow()
        super.onDestroy()
    }
}
