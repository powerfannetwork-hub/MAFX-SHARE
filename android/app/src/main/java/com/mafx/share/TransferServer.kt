package com.mafx.share

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.BufferedInputStream
import java.io.DataInputStream
import java.io.IOException
import java.net.ServerSocket
import java.net.SocketException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class TransferServer(
    context: Context,
    private val port: Int = 8988
) {
    companion object {
        const val DEFAULT_PORT = 8988
        private const val MAX_FILE_SIZE = 8L * 1024 * 1024 * 1024
    }

    private val appContext = context.applicationContext
    private val running = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor()

    @Volatile
    private var serverSocket: ServerSocket? = null

    var onStarted: ((Int) -> Unit)? = null
    var onFileReceived: ((String, Long) -> Unit)? = null
    var onError: ((String) -> Unit)? = null

    fun isRunning(): Boolean = running.get()

    fun start() {
        if (!running.compareAndSet(false, true)) return

        executor.execute {
            try {
                ServerSocket(port).use { server ->
                    serverSocket = server
                    onStarted?.invoke(server.localPort)

                    while (running.get()) {
                        try {
                            server.accept().use { socket ->
                                socket.soTimeout = 120_000
                                receiveFile(socket)
                            }
                        } catch (e: SocketException) {
                            if (running.get()) throw e
                        }
                    }
                }
            } catch (e: Exception) {
                if (running.get()) {
                    onError?.invoke(
                        e.message ?: "Unable to receive file."
                    )
                }
            } finally {
                running.set(false)
                serverSocket = null
            }
        }
    }

    private fun receiveFile(socket: java.net.Socket) {
        val input = DataInputStream(
            BufferedInputStream(socket.getInputStream())
        )

        val originalName = input.readUTF()
        val filename = sanitizeFilename(originalName)
        val fileSize = input.readLong()

        if (filename.isBlank()) {
            throw IOException("Invalid filename.")
        }

        if (fileSize < 0 || fileSize > MAX_FILE_SIZE) {
            throw IOException("Invalid file size.")
        }

        val uri = createDestination(filename)
        var received = 0L

        try {
            val output = appContext.contentResolver
                .openOutputStream(uri, "w")
                ?: throw IOException("Cannot create destination file.")

            output.use { out ->
                val buffer = ByteArray(64 * 1024)

                while (received < fileSize) {
                    val wanted = minOf(
                        buffer.size.toLong(),
                        fileSize - received
                    ).toInt()

                    val count = input.read(buffer, 0, wanted)

                    if (count < 0) {
                        throw IOException("Transfer interrupted.")
                    }

                    out.write(buffer, 0, count)
                    received += count
                }

                out.flush()
            }
        } catch (e: Exception) {
            try {
                appContext.contentResolver.delete(uri, null, null)
            } catch (_: Exception) {
            }

            throw e
        }

        onFileReceived?.invoke(filename, received)
    }

    private fun createDestination(filename: String): Uri {
        val resolver = appContext.contentResolver

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
            put(
                MediaStore.MediaColumns.MIME_TYPE,
                "application/octet-stream"
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    "${Environment.DIRECTORY_DOWNLOADS}/MAFX SHARE"
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Downloads.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Files.getContentUri("external")
        }

        val uri = resolver.insert(collection, values)
            ?: throw IOException("Cannot create destination file.")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val completed = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }

            resolver.update(uri, completed, null, null)
        }

        return uri
    }

    private fun sanitizeFilename(name: String): String {
        return name
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .filter {
                it >= ' ' &&
                    it != '\u007f' &&
                    it !in "<>:\"|?*"
            }
            .take(240)
            .trim()
    }

    fun stop() {
        running.set(false)

        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
    }
}
