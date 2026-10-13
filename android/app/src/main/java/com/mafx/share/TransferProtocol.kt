package com.mafx.share

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.IOException

/**
 * MAFX SHARE — Transfer Protocol
 *
 * Central configuration and protocol helpers for file transfers.
 *
 * This file is designed for Android API 26+ and Kotlin/JVM.
 */
internal object TransferProtocol {

    // Network configuration
    const val PORT = 45872
    const val CONNECT_TIMEOUT_MS = 10_000
    const val SOCKET_READ_TIMEOUT_MS = 30_000

    // Transfer configuration
    const val BUFFER_SIZE = 64 * 1024
    const val MAX_FILE_NAME_LENGTH = 180

    // Protocol identification
    const val PROTOCOL_VERSION = 1
    private const val MAGIC_NUMBER = 0x4D414658 // "MAFX"

    /**
     * Write the protocol header before transfer metadata.
     */
    @Throws(IOException::class)
    fun writeHeader(output: DataOutputStream) {
        output.writeInt(MAGIC_NUMBER)
        output.writeInt(PROTOCOL_VERSION)
        output.flush()
    }

    /**
     * Validate the protocol header received from another device.
     *
     * Returns false when the peer uses an incompatible protocol.
     */
    @Throws(IOException::class)
    fun readAndValidateHeader(input: DataInputStream): Boolean {
        val magic = input.readInt()
        val version = input.readInt()

        return magic == MAGIC_NUMBER &&
            version == PROTOCOL_VERSION
    }

    /**
     * Read an exact number of bytes.
     *
     * Throws EOFException if the connection ends prematurely.
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
            val count = input.read(
                buffer,
                offset,
                length - offset
            )

            if (count < 0) {
                throw EOFException(
                    "Connection closed before transfer completed."
                )
            }

            if (count == 0) {
                continue
            }

            offset += count
        }
    }

    /**
     * Validate a file size received from another device.
     *
     * Zero-byte files are valid.
     * Negative sizes are invalid.
     */
    fun isValidFileSize(size: Long): Boolean {
        return size >= 0L
    }

    /**
     * Calculate transfer progress safely.
     */
    fun progressPercent(
        transferredBytes: Long,
        totalBytes: Long
    ): Int {
        if (totalBytes <= 0L) {
            return 100
        }

        val safeTransferred = transferredBytes
            .coerceAtLeast(0L)
            .coerceAtMost(totalBytes)

        return (
            safeTransferred.toDouble() /
                totalBytes.toDouble() * 100.0
            ).toInt().coerceIn(0, 100)
    }

    /**
     * Convert an incoming filename into a safe local filename.
     *
     * Prevents directory traversal and removes control characters.
     */
    fun safeFileName(rawName: String?): String {
        val leafName = rawName
            ?.replace('\\', '/')
            ?.substringAfterLast('/')
            .orEmpty()

        val cleanedName = leafName
            .map { character ->
                when {
                    character.code < 32 -> '_'
                    character.code == 127 -> '_'
                    character in charArrayOf(
                        '<', '>', ':', '"', '|', '?', '*'
                    ) -> '_'

                    else -> character
                }
            }
            .joinToString("")
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
     * Generate a non-conflicting filename without deleting an existing file.
     *
     * Example:
     * photo.jpg
     * photo (1).jpg
     * photo (2).jpg
     */
    fun uniqueFileName(
        originalName: String,
        fileExists: (String) -> Boolean
    ): String {
        val safeName = safeFileName(originalName)

        if (!fileExists(safeName)) {
            return safeName
        }

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

            if (!fileExists(candidate)) {
                return candidate
            }

            counter++
        }

        throw IOException(
            "Unable to generate a unique filename."
        )
    }
}
