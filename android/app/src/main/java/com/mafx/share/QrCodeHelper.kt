package com.mafx.share

import android.graphics.Bitmap
import android.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import java.net.URI
import java.net.URLEncoder
import java.net.URLDecoder
import java.nio.charset.StandardCharsets

/**
 * QR Code utilities for MAFX SHARE.
 *
 * The QR code carries connection information only.
 * It does not itself connect the phones or enable a hotspot.
 */
internal object QrCodeHelper {

    private const val QR_SIZE = 640
    private const val SCHEME = "mafxshare"
    private const val HOST = "connect"

    data class ConnectionInfo(
        val ipAddress: String,
        val port: Int
    )

    /**
     * Creates the connection payload to encode in a QR code.
     */
    fun createPayload(ipAddress: String, port: Int): String {
        require(isValidIpv4(ipAddress)) {
            "Invalid IPv4 address."
        }

        require(port in 1..65535) {
            "Invalid port."
        }

        return "$SCHEME://$HOST?ip=$ipAddress&port=$port"
    }

    /**
     * Parses and validates a MAFX SHARE connection QR payload.
     */
    fun parsePayload(payload: String): ConnectionInfo? {
        return try {
            val uri = URI(payload.trim())

            if (!uri.scheme.equals(SCHEME, ignoreCase = true)) {
                return null
            }

            if (!uri.host.equals(HOST, ignoreCase = true)) {
                return null
            }

            val parameters = parseQuery(uri.rawQuery ?: return null)

            val ip = parameters["ip"] ?: return null
            val port = parameters["port"]?.toIntOrNull() ?: return null

            if (!isValidIpv4(ip)) return null
            if (port !in 1..65535) return null

            ConnectionInfo(
                ipAddress = ip,
                port = port
            )
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Generates a QR bitmap using ZXing.
     */
    fun createBitmap(payload: String): Bitmap {
        val hints = mapOf(
            EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M,
            EncodeHintType.MARGIN to 2,
            EncodeHintType.CHARACTER_SET to "UTF-8"
        )

        val matrix = MultiFormatWriter().encode(
            payload,
            BarcodeFormat.QR_CODE,
            QR_SIZE,
            QR_SIZE,
            hints
        )

        val pixels = IntArray(QR_SIZE * QR_SIZE)

        for (y in 0 until QR_SIZE) {
            for (x in 0 until QR_SIZE) {
                pixels[y * QR_SIZE + x] =
                    if (matrix[x, y]) Color.BLACK else Color.WHITE
            }
        }

        return Bitmap.createBitmap(
            pixels,
            QR_SIZE,
            QR_SIZE,
            Bitmap.Config.ARGB_8888
        )
    }

    private fun parseQuery(query: String): Map<String, String> {
        val result = mutableMapOf<String, String>()

        for (part in query.split("&")) {
            val separator = part.indexOf("=")
            if (separator <= 0) continue

            val key = decode(part.substring(0, separator))
            val value = decode(part.substring(separator + 1))

            result[key] = value
        }

        return result
    }

    private fun decode(value: String): String {
        return URLDecoder.decode(
            value,
            StandardCharsets.UTF_8.name()
        )
    }

    private fun isValidIpv4(address: String): Boolean {
        val parts = address.split(".")
        if (parts.size != 4) return false

        return parts.all { part ->
            if (part.isEmpty() || part.length > 3) {
                false
            } else {
                part.all { it in '0'..'9' } &&
                    part.toIntOrNull() in 0..255
            }
        }
    }
}
