package com.mafx.share

import android.app.AlertDialog
import android.content.Context
import android.graphics.Bitmap
import android.view.Gravity
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

object ReceiveQrDialog {

    fun show(
        context: Context,
        ipAddress: String,
        port: Int,
        payload: String,
        onStop: () -> Unit
    ) {
        val padding = (20 * context.resources.displayMetrics.density).toInt()

        val layout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(padding, padding, padding, padding)
        }

        val title = TextView(context).apply {
            text = "Scan to Connect"
            textSize = 22f
            setTextColor(android.graphics.Color.rgb(8, 35, 62))
            gravity = Gravity.CENTER
        }

        layout.addView(
            title,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        val description = TextView(context).apply {
            text = "Scan this QR code using the other MAFX SHARE device."
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(0, padding / 2, 0, padding / 2)
        }

        layout.addView(description)

        val bitmap: Bitmap = ConnectionQr.generateBitmap(payload, 700)

        val qrImage = ImageView(context).apply {
            setImageBitmap(bitmap)
            adjustViewBounds = true
            contentDescription = "MAFX SHARE connection QR code"
        }

        layout.addView(
            qrImage,
            LinearLayout.LayoutParams(
                (280 * context.resources.displayMetrics.density).toInt(),
                (280 * context.resources.displayMetrics.density).toInt()
            )
        )

        val address = TextView(context).apply {
            text = "IP Address: $ipAddress\nPort: $port\n\nKeep this screen open while receiving."
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(0, padding / 2, 0, 0)
        }

        layout.addView(address)

        val dialog = AlertDialog.Builder(context)
            .setView(layout)
            .setNegativeButton("STOP RECEIVING", null)
            .setPositiveButton("DONE", null)
            .create()

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_NEGATIVE)
                .setOnClickListener {
                    onStop()
                    dialog.dismiss()
                }
        }

        dialog.show()
    }
}
