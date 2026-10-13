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
import java.net.Socket
import java.net.SocketException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Receives one file at a time over TCP and saves it to Downloads/MAFX SHARE.
 *
 * Wire format: writeUTF(filename), writeLong(fileSize), then exactly fileSize bytes.
 */
class TransferServer(
    context: Context,
    private val port: Int = DEFAULT_PORT
) {
    companion object {
        const val DEFAULT_PORT = 8988
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
                        val socket = try {
                            server.accept()
                        } catch (e: SocketException) {
                            // Closing the server socket is the normal way to stop the server.
                            if (!running.get()) break
                            throw e
                        }

                        // A bad or interrupted transfer must not terminate the listening server.
                        socket.use { client ->
                            try {
                                client.soTimeout = 120_000
                                receiveFile(client)
                            } catch (e: Exception) {
                                if (running.get()) {
                                    onError?.invoke(e.message ?: "Unable to receive this file.")
                                }
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                if (running.get()) {
                    onError?.invoke(e.message ?: "Unable to start the file receiver.")
                }
            } finally {
                serverSocket = null
                running.set(false)
            }
        }
    }

    private fun receiveFile(socket: Socket) {
        val input = DataInputStream(BufferedInputStream(socket.getInputStream()))
        val filename = sanitizeFilename(input.readUTF())
        val fileSize = input.readLong()

        if (filename.isBlank()) throw IOException("Invalid filename.")
        if (fileSize < 0L) throw IOException("Invalid file size.")

        // Stream data in chunks; never load the entire file into memory.
        val uri = createDestination(filename)
        var received = 0L
        var completed = false

        try {
            val output = appContext.contentResolver.openOutputStream(uri, "w")
                ?: throw IOException("Cannot create destination file.")

            output.use { out ->
                val buffer = ByteArray(1024 * 1024) // 1 MiB buffer

                while (received < fileSize) {
                    val wanted = minOf(buffer.size.toLong(), fileSize - received).toInt()
                    val count = input.read(buffer, 0, wanted)

                    if (count < 0) {
                        throw IOException("Transfer interrupted before the file was complete.")
                    }
                    if (count == 0) continue

                    out.write(buffer, 0, count)
                    received += count.toLong()
                }

                out.flush()
            }

            // Publish the file only after all expected bytes have been written.
            finishDestination(uri)
            completed = true
            onFileReceived?.invoke(filename, received)
        } finally {
            if (!completed) {
                try {
                    appContext.contentResolver.delete(uri, null, null)
                } catch (_: Exception) {
                    // Preserve the original transfer error.
                }
            }
        }
    }

    private fun createDestination(filename: String): Uri {
        val resolver = appContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    "${Environment.DIRECTORY_DOWNLOADS}/MAFX SHARE"
                )
                // Keep the file hidden from other apps until transfer completes.
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Downloads.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Files.getContentUri("external")
        }

        return resolver.insert(collection, values)
            ?: throw IOException("Cannot create destination file.")
    }

    private fun finishDestination(uri: Uri) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            val updated = appContext.contentResolver.update(uri, values, null, null)
            if (updated <= 0) {
                throw IOException("Could not finalize the received file.")
            }
        }
    }

    private fun sanitizeFilename(name: String): String {
        return name
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .filter { it >= ' ' && it != '\u007f' && it !in "<>:\"|?*" }
            .take(240)
            .trim()
    }

    fun stop() {
        running.set(false)
        try {
            serverSocket?.close()
        } catch (_: Exception) {
            // The server may already be closed.
        }
    }
}
