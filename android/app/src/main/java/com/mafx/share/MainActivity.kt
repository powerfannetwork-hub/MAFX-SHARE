package com.mafx.share

import android.app.Activity
import android.os.Bundle
import android.graphics.Color
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class MainActivity : Activity() {

    private val green = Color.rgb(22, 163, 74)
    private val blue = Color.rgb(37, 99, 235)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.statusBarColor = green
        window.navigationBarColor = Color.WHITE
        window.decorView.systemUiVisibility =
            android.view.View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(28, 32, 28, 32)
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

        val sendButton = Button(this).apply {
            text = "SEND FILES"
            setTextColor(Color.WHITE)
            setBackgroundColor(green)
            setOnClickListener {
                showMessage("Send feature is being prepared.")
            }
        }

        val receiveButton = Button(this).apply {
            text = "RECEIVE FILES"
            setTextColor(Color.WHITE)
            setBackgroundColor(blue)
            setOnClickListener {
                showMessage("Receive feature is being prepared.")
            }
        }

        layout.addView(logo, matchWidth())
        layout.addView(subtitle, matchWidth())
        addSpace(layout, 36)
        layout.addView(sendButton, matchWidth())
        addSpace(layout, 12)
        layout.addView(receiveButton, matchWidth())

        setContentView(layout)
    }

    private fun matchWidth(): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
    }

    private fun addSpace(layout: LinearLayout, height: Int) {
        val space = android.view.View(this)
        layout.addView(
            space,
            LinearLayout.LayoutParams(
                1,
                (height * resources.displayMetrics.density).toInt()
            )
        )
    }

    private fun showMessage(message: String) {
        android.widget.Toast.makeText(
            this,
            message,
            android.widget.Toast.LENGTH_SHORT
        ).show()
    }
}
