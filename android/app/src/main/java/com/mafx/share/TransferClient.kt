package com.mafx.share

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataOutputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class TransferClient(context: Context) {

    companion object {
        const val DEFAULT_PORT = 8988
        private const val CONNECT_TIMEOUT = 10_000
        private const val SOCKET_TIMEOUT = 120_000
        private const val BUFFER_SIZE = 256 * 1024
    }

    private val appContext = context.applicationContext
    private val executor = Executors.newSingleThreadExecutor()
    private val sending = AtomicBoolean(false)

    @Volatile
    private var activeSocket: Socket? = null

    var onProgress: ((String, Long, Long) -> Unit)? = null
    var onCompleted: ((String, Long) -> Unit)? = null
    var onError: ((String) -> Unit)? = null

    fun isSending(): Boolean = sending.get()

    fun sendFile(
        destinationIp: String,
        fileUri: Uri,
        port: Int = DEFAULT_PORT
    ) {
        if (!sending.compareAndSet(false, true)) {
            onError?.invoke("A transfer is already in progress.")
            return
        }

        executor.execute {
            var filename = "file"
            var totalBytes = 0L

            try {
                val ip = destinationIp.trim()

                if (ip.isBlank()) {
                    throw IOException("Enter the receiver's IP address.")
                }

                if (port !in 1..65535) {
                    throw IOException("Invalid receiver port.")
                }

                filename = getFilename(fileUri)
                totalBytes = getFileSize(fileUri)

                if (totalBytes < 0L) {
                    throw IOException("Cannot determine the file size.")
                }

                val socket = Socket()
                activeSocket = socket

                socket.connect(
                    InetSocketAddress(ip, port),
                    CONNECT_TIMEOUT
                )

                socket.soTimeout = SOCKET_TIMEOUT
                socket.tcpNoDelay = true
                socket.sendBufferSize = BUFFER_SIZE

                val input = appContext.contentResolver
                    .openInputStream(fileUri)
                    ?: throw IOException("Cannot open the selected file.")

                input.use { fileInput ->
                    DataOutputStream(
                        BufferedOutputStream(
                            socket.getOutputStream(),
                            BUFFER_SIZE
                        )
                    ).use { output ->

                        output.writeUTF(filename)
                        output.writeLong(totalBytes)

                        val buffer = ByteArray(BUFFER_SIZE)
                        var sentBytes = 0L

                        while (sentBytes < totalBytes) {
                            if (Thread.currentThread().isInterrupted) {
                                throw IOException("Transfer cancelled.")
                            }

                            val wanted = minOf(
                                buffer.size.toLong(),
                                totalBytes - sentBytes
                            ).toInt()

                            val count = fileInput.read(
                                buffer,
                                0,
                                wanted
                            )

                            if (count < 0) {
                                throw IOException(
                                    "The selected file ended unexpectedly."
                                )
                            }

                            output.write(buffer, 0, count)
                            sentBytes += count

                            onProgress?.invoke(
                                filename,
                                sentBytes,
                                totalBytes
                            )
                        }

                        output.flush()
                    }
                }

                onCompleted?.invoke(filename, totalBytes)

            } catch (e: Exception) {
                onError?.invoke(
                    e.message ?: "File transfer failed."
                )
            } finally {
                try {
                    activeSocket?.close()
                } catch (_: Exception) {
                }

                activeSocket = null
                sending.set(false)
            }
        }
    }

    private fun getFilename(uri: Uri): String {
        var result: String? = null
        var cursor: Cursor? = null

        try {
            cursor = appContext.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )

            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(
                    OpenableColumns.DISPLAY_NAME
                )

                if (index >= 0) {
                    result = cursor.getString(index)
                }
            }
        } finally {
            cursor?.close()
        }

        return sanitizeFilename(result ?: uri.lastPathSegment ?: "file")
    }

    private fun getFileSize(uri: Uri): Long {
        appContext.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.SIZE),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.SIZE)

                if (index >= 0 && !cursor.isNull(index)) {
                    val size = cursor.getLong(index)

                    if (size >= 0L) return size
                }
            }
        }

        val descriptor = appContext.contentResolver
            .openAssetFileDescriptor(uri, "r")
            ?: throw IOException("Cannot access the selected file.")

        descriptor.use {
            if (it.length >= 0L) {
                return it.length
            }
        }

        throw IOException("This file provider does not report file size.")
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
            .trim()
            .take(240)
            .ifBlank { "file" }
    }

    fun cancel() {
        try {
            activeSocket?.close()
        } catch (_: Exception) {
        }
    }

    fun shutdown() {
        cancel()
        executor.shutdownNow()
    }
}
