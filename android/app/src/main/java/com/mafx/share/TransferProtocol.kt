package com.mafx.share

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.IOException
import java.util.Locale

/**
 * MAFX SHARE transfer protocol helpers.
 *
 * Keep the default port aligned with TransferClient and TransferServer.
 * The current Client/Server wire format is:
 * UTF filename, Long file size, then exactly file-size raw bytes.
 *
 * Header helpers remain available for any code that explicitly uses them;
 * do not add header calls to only one side of the current Client/Server pair.
 */
internal object TransferProtocol {

    const val PORT = 8988

    const val CONNECT_TIMEOUT_MS = 10_000
    const val SOCKET_READ_TIMEOUT_MS = 60_000

    const val BUFFER_SIZE = 1024 * 1024

    const val PROGRESS_UPDATE_INTERVAL_MS = 150L
    const val PROGRESS_UPDATE_BYTES = 1024L * 1024L

    const val MAX_FILE_NAME_LENGTH = 180
    const val PROTOCOL_VERSION = 1

    private const val MAGIC_NUMBER = 0x4D414658 // MAFX

    /**
     * Write a versioned protocol header.
     * Only use this when both sender and receiver expect the header.
     */
    @Throws(IOException::class)
    fun writeHeader(output: DataOutputStream) {
        output.writeInt(MAGIC_NUMBER)
        output.writeInt(PROTOCOL_VERSION)
        output.flush()
    }

    /**
     * Verify a versioned protocol header.
     * Only use this when both sender and receiver expect the header.
     */
    @Throws(IOException::class)
    fun readAndValidateHeader(input: DataInputStream): Boolean {
        val magic = input.readInt()
        val version = input.readInt()
        return magic == MAGIC_NUMBER && version == PROTOCOL_VERSION
    }

    /**
     * Read exactly the requested number of bytes.
     */
    @Throws(IOException::class)
    fun readFully(
        input: DataInputStream,
        buffer: ByteArray,
        length: Int
    ) {
        require(length in 0..buffer.size) {
            "Invalid read length."
        }

        var offset = 0
        while (offset < length) {
            val count = input.read(buffer, offset, length - offset)
            if (count < 0) {
                throw EOFException(
                    "Connection closed before transfer completed."
                )
            }
            if (count == 0) continue
            offset += count
        }
    }

    /**
     * Zero-byte files are allowed; negative sizes are rejected.
     */
    fun isValidFileSize(size: Long): Boolean = size >= 0L

    /**
     * Calculate progress without overflowing a Long multiplication.
     */
    fun progressPercent(
        transferredBytes: Long,
        totalBytes: Long
    ): Int {
        if (totalBytes <= 0L) return 100

        val safeTransferred = transferredBytes
            .coerceAtLeast(0L)
            .coerceAtMost(totalBytes)

        return (
            safeTransferred.toDouble() / totalBytes.toDouble() * 100.0
        ).toInt().coerceIn(0, 100)
    }

    /**
     * Format transfer speed for the user interface.
     */
    fun formatSpeed(bytesPerSecond: Double): String {
        if (!bytesPerSecond.isFinite() || bytesPerSecond <= 0.0) {
            return "0 MB/s"
        }

        val megabytesPerSecond = bytesPerSecond / (1024.0 * 1024.0)
        return if (megabytesPerSecond >= 100.0) {
            String.format(Locale.US, "%.0f MB/s", megabytesPerSecond)
        } else {
            String.format(Locale.US, "%.1f MB/s", megabytesPerSecond)
        }
    }

    /**
     * Sanitize an incoming filename. The returned value is not a path.
     */
    fun safeFileName(rawName: String?): String {
        val leafName = rawName
            ?.replace('\\', '/')
            ?.substringAfterLast('/')
            .orEmpty()

        val invalidCharacters = charArrayOf('<', '>', ':', '"', '|', '?', '*')
        val cleanedName = buildString {
            for (character in leafName) {
                when {
                    character.code < 32 -> append('_')
                    character.code == 127 -> append('_')
                    character in invalidCharacters -> append('_')
                    else -> append(character)
                }
            }
        }
            .trim()
            .take(MAX_FILE_NAME_LENGTH)
            .trimEnd('.', ' ')

        return when {
            cleanedName.isBlank() -> "received_file"
            cleanedName == "." -> "received_file"
            cleanedName == ".." -> "received_file"
            else -> cleanedName
        }
    }

    /**
     * Generate a unique filename without overwriting an existing file.
     */
    fun uniqueFileName(
        originalName: String,
        fileExists: (String) -> Boolean
    ): String {
        val safeName = safeFileName(originalName)
        if (!fileExists(safeName)) return safeName

        val dotIndex = safeName.lastIndexOf('.')
        val hasExtension = dotIndex > 0

        val baseName = if (hasExtension) {
            safeName.substring(0, dotIndex)
        } else {
            safeName
        }

        val extension = if (hasExtension) {
            safeName.substring(dotIndex)
        } else {
            ""
        }

        var counter = 1
        while (counter < Int.MAX_VALUE) {
            val candidate = "$baseName ($counter)$extension"
            if (!fileExists(candidate)) return candidate
            counter++
        }

        throw IOException("Unable to generate a unique filename.")
    }
}
