package com.mafx.share

import android.app.Activity
import android.os.Bundle
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.content.Context
import android.database.Cursor
import android.provider.OpenableColumns
import android.widget.*
import java.io.*
import java.net.ServerSocket
import java.net.Socket
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : Activity() {

    private val green = Color.rgb(22, 163, 74)
    private val blue = Color.rgb(37, 99, 235)
    private val port = 45872

    private val executor = Executors.newCachedThreadPool()
    private val receiving = AtomicBoolean(false)

    private var serverSocket: ServerSocket? = null
    private lateinit var layout: LinearLayout
    private lateinit var status: TextView
    private lateinit var progress: ProgressBar

    private val pickFile =
        registerForActivityResult(
            android.app.ActivityResultContracts.StartActivityForResult()
        ) { result ->
            if (result.resultCode == RESULT_OK) {
                result.data?.data?.let { uri ->
                    askForReceiverIp(uri)
                }
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.statusBarColor = green
        window.navigationBarColor = Color.WHITE
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR

        showHome()
    }

    private fun showHome() {
        layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(24), dp(24), dp(24))
            setBackgroundColor(Color.WHITE)
        }

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

        val send = makeButton("SEND FILES", green) {
            openFilePicker()
        }

        val receive = makeButton("RECEIVE FILES", blue) {
            startReceiving()
        }

        layout.addView(logo, matchWidth())
        layout.addView(subtitle, matchWidth())
        addSpace(32)
        layout.addView(send, matchWidth())
        addSpace(12)
        layout.addView(receive, matchWidth())

        setContentView(layout)
    }

    private fun startReceiving() {
        layout.removeAllViews()

        val title = TextView(this).apply {
            text = "RECEIVE FILES"
            textSize = 26f
            gravity = Gravity.CENTER
            setTextColor(blue)
        }

        val ip = getLocalIp()

        val instructions = TextView(this).apply {
            text = if (ip != null) {
                "Connect both phones to the same Wi-Fi or hotspot.\n\n" +
                    "Receiver IP address:\n$ip\n\n" +
                    "Port: $port\n\n" +
                    "Enter this IP address on the sending phone."
            } else {
                "Connect this phone to a Wi-Fi network or another " +
                    "phone's hotspot, then try again."
            }
            textSize = 17f
            gravity = Gravity.CENTER
            setTextColor(Color.DKGRAY)
        }

        status = TextView(this).apply {
            text = "Waiting for a connection..."
            textSize = 16f
            gravity = Gravity.CENTER
            setTextColor(green)
        }

        progress = ProgressBar(
            this, null, android.R.attr.progressBarStyleHorizontal
        ).apply {
            max = 100
            progress = 0
        }

        layout.addView(title, matchWidth())
        addSpace(20)
        layout.addView(instructions, matchWidth())
        addSpace(20)
        layout.addView(status, matchWidth())
        addSpace(12)
        layout.addView(progress, matchWidth())

        layout.addView(
            makeButton("STOP RECEIVING", blue) {
                stopReceiving()
                showHome()
            },
            matchWidth()
        )

        if (ip == null) return

        if (!receiving.compareAndSet(false, true)) return

        executor.execute {
            try {
                val server = ServerSocket(port)
                serverSocket = server

                while (receiving.get()) {
                    val socket = server.accept()
                    executor.execute {
                        receiveFile(socket)
                    }
                }
            } catch (e: Exception) {
                if (receiving.get()) {
                    updateStatus("Receiver error: ${e.message}")
                }
            } finally {
                receiving.set(false)
            }
        }
    }

    private fun receiveFile(socket: Socket) {
        socket.use { connection ->
            connection.soTimeout = 0

            try {
                val input = DataInputStream(
                    BufferedInputStream(connection.getInputStream())
                )

                val output = DataOutputStream(
                    BufferedOutputStream(connection.getOutputStream())
                )

                val rawName = input.readUTF()
                val fileName = File(rawName).name
                    .replace(Regex("[^A-Za-z0-9._ -]"), "_")
                    .take(180)
                    .ifBlank { "received_file" }

                val size = input.readLong()

                if (size < 0L) {
                    throw IOException("Invalid file size.")
                }

                val directory = getExternalFilesDir("Received")
                    ?: throw IOException("Storage unavailable.")

                if (!directory.exists() && !directory.mkdirs()) {
                    throw IOException("Cannot create destination folder.")
                }

                val destination = File(directory, fileName)
                val temporary = File(directory, "$fileName.part")

                output.writeBoolean(true)
                output.flush()

                val buffer = ByteArray(64 * 1024)
                var total = 0L

                FileOutputStream(temporary, false).use { fileOutput ->
                    while (total < size) {
                        val wanted = minOf(
                            buffer.size.toLong(),
                            size - total
                        ).toInt()

                        val count = input.read(buffer, 0, wanted)

                        if (count < 0) {
                            throw EOFException("Connection interrupted.")
                        }

                        fileOutput.write(buffer, 0, count)
                        total += count

                        val percent =
                            if (size == 0L) 100
                            else ((total * 100) / size).toInt()

                        updateProgress(
                            percent,
                            "Receiving $fileName: $percent%"
                        )
                    }

                    fileOutput.fd.sync()
                }

                if (destination.exists()) {
                    destination.delete()
                }

                if (!temporary.renameTo(destination)) {
                    throw IOException("Could not finalize received file.")
                }

                updateProgress(
                    100,
                    "Received successfully: $fileName\n" +
                        "Saved in MAFX SHARE/Received"
                )

            } catch (e: Exception) {
                updateStatus("Transfer failed: ${e.message}")
            }
        }
    }

    private fun openFilePicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }

        pickFile.launch(intent)
    }

    private fun askForReceiverIp(uri: Uri) {
        val input = EditText(this).apply {
            hint = "Receiver IP, e.g. 192.168.1.10"
            setSingleLine(true)
        }

        AlertDialog.Builder(this)
            .setTitle("Receiver IP address")
            .setMessage(
                "Connect both phones to the same Wi-Fi or hotspot."
            )
            .setView(input)
            .setNegativeButton("Cancel", null)
            .setPositiveButton("SEND") { _, _ ->
                val ip = input.text.toString().trim()

                if (ip.isBlank()) {
                    toast("Enter the receiver IP address.")
                } else {
                    sendFile(uri, ip)
                }
            }
            .show()
    }

    private fun sendFile(uri: Uri, ip: String) {
        val fileName = getFileName(uri)

        val size = getFileSize(uri)

        if (size < 0L) {
            toast("Cannot determine file size. Choose another file.")
            return
        }

        layout.removeAllViews()

        status = TextView(this).apply {
            text = "Connecting to $ip..."
            textSize = 17f
            gravity = Gravity.CENTER
            setTextColor(green)
        }

        progress = ProgressBar(
            this, null, android.R.attr.progressBarStyleHorizontal
        ).apply {
            max = 100
            progress = 0
        }

        layout.addView(
            TextView(this).apply {
                text = "SENDING FILE"
                textSize = 25f
                gravity = Gravity.CENTER
                setTextColor(green)
            },
            matchWidth()
        )

        addSpace(24)
        layout.addView(status, matchWidth())
        addSpace(16)
        layout.addView(progress, matchWidth())

        layout.addView(
            makeButton("BACK TO HOME", blue) {
                showHome()
            },
            matchWidth()
        )

        executor.execute {
            try {
                Socket().use { socket ->
                    socket.connect(
                        java.net.InetSocketAddress(ip, port),
                        10000
                    )

                    socket.tcpNoDelay = true

                    val output = DataOutputStream(
                        BufferedOutputStream(socket.getOutputStream())
                    )

                    val input = DataInputStream(
                        BufferedInputStream(socket.getInputStream())
                    )

                    output.writeUTF(fileName)
                    output.writeLong(size)
                    output.flush()

                    val accepted = input.readBoolean()

                    if (!accepted) {
                        throw IOException("Receiver rejected the file.")
                    }

                    contentResolver.openInputStream(uri).use { stream ->
                        if (stream == null) {
                            throw IOException("Cannot open selected file.")
                        }

                        val buffer = ByteArray(64 * 1024)
                        var total = 0L

                        while (total < size) {
                            val wanted = minOf(
                                buffer.size.toLong(),
                                size - total
                            ).toInt()

                            val count = stream.read(buffer, 0, wanted)

                            if (count < 0) {
                                throw EOFException("Source file ended early.")
                            }

                            output.write(buffer, 0, count)
                            total += count

                            val percent =
                                if (size == 0L) 100
                                else ((total * 100) / size).toInt()

                            updateProgress(
                                percent,
                                "Sending $fileName: $percent%"
                            )
                        }
                    }

                    output.flush()

                    updateProgress(100, "File sent successfully: $fileName")
                }
            } catch (e: Exception) {
                updateStatus(
                    "Send failed: ${e.message}\n" +
                        "Check the IP, Wi-Fi and receiver."
                )
            }
        }
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
                val index = it.getColumnIndex(OpenableColumns.SIZE)
                if (index >= 0 && !it.isNull(index)) {
                    return it.getLong(index)
                }
            }
        }

        return -1L
    }

    private fun getLocalIp(): String? {
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces()

            while (interfaces.hasMoreElements()) {
                val network = interfaces.nextElement()

                if (!network.isUp || network.isLoopback) continue

                val addresses = network.inetAddresses

                while (addresses.hasMoreElements()) {
                    val address = addresses.nextElement()

                    if (address is Inet4Address &&
                        !address.isLoopbackAddress
                    ) {
                        val host = address.hostAddress

                        if (host != null &&
                            !host.startsWith("169.254.")
                        ) {
                            return host
                        }
                    }
                }
            }
        } catch (_: Exception) {
        }

        return null
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
            if (::status.isInitialized) {
                status.text = message
            }
        }
    }

    private fun updateProgress(percent: Int, message: String) {
        runOnUiThread {
            if (::progress.isInitialized) {
                progress.progress = percent
            }

            if (::status.isInitialized) {
                status.text = message
            }
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

    private fun matchWidth(): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
    }

    private fun addSpace(height: Int) {
        val space = View(this)

        layout.addView(
            space,
            LinearLayout.LayoutParams(
                1,
                dp(height)
            )
        )
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private fun toast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
    }

    override fun onDestroy() {
        stopReceiving()
        executor.shutdownNow()
        super.onDestroy()
    }
}
