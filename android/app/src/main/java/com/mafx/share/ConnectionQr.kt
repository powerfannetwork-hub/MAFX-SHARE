package com.mafx.share

import android.graphics.Bitmap
import android.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import org.json.JSONObject

object ConnectionQr {

    const val DEFAULT_PORT = 8988

    data class ConnectionInfo(
        val ipAddress: String,
        val port: Int
    )

    fun createPayload(
        ipAddress: String,
        port: Int = DEFAULT_PORT
    ): String {
        require(ipAddress.isNotBlank()) {
            "IP address cannot be empty."
        }

        require(port in 1..65535) {
            "Invalid port."
        }

        return JSONObject().apply {
            put("app", "MAFX_SHARE")
            put("version", 1)
            put("ip", ipAddress.trim())
            put("port", port)
        }.toString()
    }

    fun parsePayload(payload: String): ConnectionInfo {
        val json = JSONObject(payload)

        require(json.optString("app") == "MAFX_SHARE") {
            "This QR code is not for MAFX SHARE."
        }

        require(json.optInt("version") == 1) {
            "Unsupported connection QR version."
        }

        val ipAddress = json.optString("ip").trim()
        val port = json.optInt("port", DEFAULT_PORT)

        require(ipAddress.isNotBlank()) {
            "QR code does not contain an IP address."
        }

        require(port in 1..65535) {
            "QR code contains an invalid port."
        }

        return ConnectionInfo(
            ipAddress = ipAddress,
            port = port
        )
    }

    fun generateBitmap(
        payload: String,
        size: Int = 700
    ): Bitmap {
        require(payload.isNotBlank()) {
            "QR content cannot be empty."
        }

        require(size >= 200) {
            "QR image size must be at least 200 pixels."
        }

        val hints = mapOf(
            EncodeHintType.ERROR_CORRECTION to
                ErrorCorrectionLevel.M,
            EncodeHintType.MARGIN to 2,
            EncodeHintType.CHARACTER_SET to "UTF-8"
        )

        val matrix = MultiFormatWriter().encode(
            payload,
            BarcodeFormat.QR_CODE,
            size,
            size,
            hints
        )

        val pixels = IntArray(size * size)

        for (y in 0 until size) {
            for (x in 0 until size) {
                pixels[y * size + x] =
                    if (matrix[x, y]) Color.BLACK else Color.WHITE
            }
        }

        return Bitmap.createBitmap(
            pixels,
            size,
            size,
            Bitmap.Config.ARGB_8888
        )
    }
}
