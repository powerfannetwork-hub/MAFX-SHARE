package com.mafx.share

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import android.widget.TextView
import android.widget.LinearLayout
import android.view.Gravity
import android.graphics.Color
import android.view.ViewGroup
import android.graphics.Typeface

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.statusBarColor = Color.rgb(6, 43, 69)
        window.navigationBarColor = Color.rgb(6, 43, 69)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(32, 32, 32, 32)
            setBackgroundColor(Color.rgb(244, 248, 252))
        }

        val title = TextView(this).apply {
            text = "MAFX SHARE"
            textSize = 30f
            setTextColor(Color.rgb(8, 168, 90))
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }

        val subtitle = TextView(this).apply {
            text = "Fast • Secure • Offline File Sharing"
            textSize = 15f
            setTextColor(Color.rgb(6, 43, 69))
            gravity = Gravity.CENTER
        }

        val sendButton = createButton("SEND FILES")
        val receiveButton = createButton("RECEIVE FILES")
        val connectButton = createButton("CONNECT DEVICE")

        root.addView(
            title,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        val subtitleParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        subtitleParams.setMargins(0, 12, 0, 40)
        root.addView(subtitle, subtitleParams)

        listOf(sendButton, receiveButton, connectButton).forEach { button ->
            val params = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                58
            )
            params.setMargins(0, 10, 0, 10)
            root.addView(button, params)
        }

        setContentView(root)
    }

    private fun createButton(label: String): TextView {
        return TextView(this).apply {
            text = label
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.rgb(8, 168, 90))
        }
    }
}
