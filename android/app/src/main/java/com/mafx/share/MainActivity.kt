package com.mafx.share

import android.Manifest
import android.app.AlertDialog
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

class MainActivity : AppCompatActivity() {

    private val green = Color.rgb(0, 170, 91)
    private val blue = Color.rgb(15, 105, 245)
    private val navy = Color.rgb(8, 35, 62)
    private val white = Color.WHITE
    private val pageBackground = Color.rgb(244, 248, 252)
    private val textColor = Color.rgb(30, 43, 60)
    private val muted = Color.rgb(115, 130, 148)

    private lateinit var root: LinearLayout
    private lateinit var content: LinearLayout
    private lateinit var bottomBar: LinearLayout

    private var currentPage = "Home"
    private var hotspotController: HotspotController? = null

    private val hotspotPermissionLauncher =
        registerForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions()
        ) { results ->
            if (results.values.all { it }) {
                startMAFXHotspot()
            } else {
                Toast.makeText(
                    this,
                    "Please allow the required Wi-Fi permission.",
                    Toast.LENGTH_LONG
                ).show()
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.statusBarColor = navy
        window.navigationBarColor = white

        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR

        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(white)
            clipToPadding = false
        }

        content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(pageBackground)
        }

        bottomBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setBackgroundColor(white)
            elevation = dp(10).toFloat()
        }

        root.addView(
            content,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        )

        root.addView(
            bottomBar,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(66)
            )
        )

        setContentView(root)

        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or
                    WindowInsetsCompat.Type.displayCutout()
            )

            view.setPadding(
                bars.left,
                bars.top,
                bars.right,
                bars.bottom
            )

            insets
        }

        ViewCompat.requestApplyInsets(root)
        showPage("Home")
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private fun rounded(
        color: Int,
        radius: Int = 18,
        strokeColor: Int? = null
    ): GradientDrawable {
        return GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(radius).toFloat()

            if (strokeColor != null) {
                setStroke(dp(1), strokeColor)
            }
        }
    }

    private fun label(
        value: String,
        size: Float = 14f,
        color: Int = textColor,
        bold: Boolean = false
    ): TextView {
        return TextView(this).apply {
            text = value
            textSize = size
            setTextColor(color)

            if (bold) {
                setTypeface(null, Typeface.BOLD)
            }

            gravity = Gravity.CENTER_VERTICAL
        }
    }

    private fun button(
        title: String,
        color: Int,
        onClick: () -> Unit
    ): Button {
        return Button(this).apply {
            text = title
            textSize = 14f
            isAllCaps = false
            setTextColor(white)
            background = rounded(color, 16)
            setPadding(dp(12), dp(8), dp(12), dp(8))

            setOnClickListener {
                onClick()
            }
        }
    }

    private fun card(
        parent: LinearLayout,
        padding: Int = 16
    ): LinearLayout {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(
                dp(padding),
                dp(padding),
                dp(padding),
                dp(padding)
            )
            background = rounded(white, 20)
            elevation = dp(2).toFloat()
        }

        val params = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            setMargins(dp(16), dp(7), dp(16), dp(7))
        }

        parent.addView(box, params)
        return box
    }

    private fun space(
        parent: LinearLayout,
        height: Int = 12
    ) {
        parent.addView(
            View(this),
            LinearLayout.LayoutParams(1, dp(height))
        )
    }

    private fun heading(
        parent: LinearLayout,
        title: String,
        subtitle: String? = null
    ) {
        parent.addView(
            label(title, 23f, textColor, true),
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(dp(18), dp(18), dp(18), dp(4))
            }
        )

        if (subtitle != null) {
            parent.addView(
                label(subtitle, 13f, muted),
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    setMargins(dp(18), 0, dp(18), dp(12))
                }
            )
        }
    }

    private fun showPage(page: String) {
        currentPage = page
        content.removeAllViews()
        content.setBackgroundColor(pageBackground)

        when (page) {
            "Home" -> homePage()
            "Send" -> sendPage()
            "Receive" -> receivePage()
            "Connect" -> connectPage()
            "Nearby Devices" -> nearbyPage()
            "Transfers" -> transfersPage()
            "History" -> historyPage()
            "Settings" -> settingsPage()
            "Photos", "Videos", "Music", "Apps", "Files" ->
                categoryPage(page)
            else -> homePage()
        }

        buildBottomBar()
    }

    private fun scrollPage(): LinearLayout {
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            clipToPadding = false
        }

        val page = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 0, 0, dp(16))
        }

        scroll.addView(page)

        content.addView(
            scroll,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT
            )
        )

        return page
    }

    private fun homePage() {
        val page = scrollPage()

        val banner = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(20), dp(28), dp(20), dp(28))
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(navy, Color.rgb(0, 81, 145), blue)
            ).apply {
                cornerRadii = floatArrayOf(
                    0f, 0f, 0f, 0f,
                    dp(25).toFloat(), dp(25).toFloat(),
                    dp(25).toFloat(), dp(25).toFloat()
                )
            }
        }

        banner.addView(
            label("MΛFX", 38f, white, true).apply {
                gravity = Gravity.CENTER
            }
        )

        banner.addView(
            label("MAFX SHARE", 27f, white, true).apply {
                gravity = Gravity.CENTER
            }
        )

        banner.addView(
            label("Fast  •  Secure  •  Unlimited", 14f, white).apply {
                gravity = Gravity.CENTER
            }
        )

        page.addView(
            banner,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(205)
            )
        )

        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(12), dp(12), dp(12), dp(4))
        }

        actions.addView(
            actionCard(
                "➤",
                "SEND",
                "Send files to another device",
                green
            ) {
                showPage("Send")
            },
            LinearLayout.LayoutParams(0, dp(164), 1f).apply {
                setMargins(dp(4), 0, dp(5), 0)
            }
        )

        actions.addView(
            actionCard(
                "⬇",
                "RECEIVE",
                "Receive files from another device",
                blue
            ) {
                showPage("Receive")
            },
            LinearLayout.LayoutParams(0, dp(164), 1f).apply {
                setMargins(dp(5), 0, dp(4), 0)
            }
        )

        page.addView(actions)

        heading(page, "Quick Access", "Choose a file category")

        val categories = listOf(
            Triple("▧", "Photos", green),
            Triple("▣", "Videos", blue),
            Triple("♫", "Music", Color.rgb(145, 70, 230)),
            Triple("▦", "Apps", Color.rgb(240, 125, 30)),
            Triple("▤", "Files", Color.rgb(0, 160, 155)),
            Triple("•••", "More", navy)
        )

        for (row in categories.chunked(3)) {
            val line = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
            }

            for ((icon, name, color) in row) {
                val item = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER
                    setPadding(dp(4), dp(8), dp(4), dp(8))

                    setOnClickListener {
                        if (name == "More") {
                            showPage("Settings")
                        } else {
                            showPage(name)
                        }
                    }
                }

                val iconView = TextView(this).apply {
                    text = icon
                    textSize = 25f
                    setTextColor(white)
                    gravity = Gravity.CENTER
                    background = rounded(color, 14)
                }

                item.addView(
                    iconView,
                    LinearLayout.LayoutParams(dp(52), dp(48))
                )

                item.addView(
                    label(name, 12f, textColor, true).apply {
                        gravity = Gravity.CENTER
                    }
                )

                line.addView(
                    item,
                    LinearLayout.LayoutParams(0, dp(85), 1f)
                )
            }

            page.addView(
                line,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    setMargins(dp(12), 0, dp(12), 0)
                }
            )
        }

        val status = card(page)
        status.addView(label("DEVICE STATUS", 12f, muted, true))
        space(status, 8)
        status.addView(
            label("●  MAFX SHARE is ready", 15f, green, true)
        )
        space(status, 4)
        status.addView(
            label("Connect two devices to begin sharing.", 13f, muted)
        )
    }

    private fun actionCard(
        icon: String,
        title: String,
        subtitle: String,
        color: Int,
        click: () -> Unit
    ): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(10), dp(8), dp(10))
            background = rounded(color, 22)

            setOnClickListener { click() }

            addView(
                label(icon, 34f, white, true).apply {
                    gravity = Gravity.CENTER
                }
            )

            addView(
                label(title, 20f, white, true).apply {
                    gravity = Gravity.CENTER
                }
            )

            space(this, 6)

            addView(
                label(subtitle, 11f, white).apply {
                    gravity = Gravity.CENTER
                    textAlignment = View.TEXT_ALIGNMENT_CENTER
                }
            )
        }
    }

    private fun sendPage() {
        val page = scrollPage()

        heading(page, "Send Files", "Choose what you want to share")

        val categories = listOf(
            "▧" to "Photos",
            "▣" to "Videos",
            "♫" to "Music",
            "▦" to "Apps",
            "▤" to "Files"
        )

        for ((icon, name) in categories) {
            val box = card(page, 14)
            box.orientation = LinearLayout.HORIZONTAL
            box.gravity = Gravity.CENTER_VERTICAL

            box.addView(
                label(icon, 26f, green, true),
                LinearLayout.LayoutParams(dp(45), dp(42))
            )

            box.addView(
                label(name, 16f, textColor, true),
                LinearLayout.LayoutParams(0, dp(42), 1f)
            )

            box.addView(label("›", 27f, muted))

            box.setOnClickListener {
                showPage(name)
            }
        }

        val info = card(page)
        info.addView(label("Selected files", 17f, textColor, true))
        space(info, 6)
        info.addView(label("Choose a category to continue.", 13f, muted))
        space(info, 12)

        info.addView(
            button("NEXT  →", green) {
                showPage("Connect")
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(52)
            )
        )
    }

    private fun categoryPage(category: String) {
        val page = scrollPage()

        heading(page, category, "Select files to prepare for sharing")

        val box = card(page)
        box.gravity = Gravity.CENTER

        box.addView(
            label("▤", 55f, blue, true).apply {
                gravity = Gravity.CENTER
            }
        )

        space(box, 12)

        box.addView(
            label("Choose $category", 18f, textColor, true).apply {
                gravity = Gravity.CENTER
            }
        )

        space(box, 8)

        box.addView(
            label(
                "The file picker and transfer engine must be connected to select and send real files.",
                13f,
                muted
            ).apply {
                gravity = Gravity.CENTER
                textAlignment = View.TEXT_ALIGNMENT_CENTER
            }
        )

        space(box, 18)

        box.addView(
            button("CONTINUE", green) {
                showPage("Connect")
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(50)
            )
        )
    }

    private fun receivePage() {
        val page = scrollPage()

        heading(page, "Receiving Files", "Get ready to receive files")

        val box = card(page)
        box.gravity = Gravity.CENTER

        space(box, 10)

        box.addView(
            label("📱      )))      📱", 28f, blue, true).apply {
                gravity = Gravity.CENTER
            }
        )

        space(box, 18)

        box.addView(
            label("Waiting for sender...", 20f, textColor, true).apply {
                gravity = Gravity.CENTER
            }
        )

        space(box, 8)

        box.addView(
            label(
                "Start the connection method on both devices. Starting a hotspot alone does not start file receiving.",
                13f,
                muted
            ).apply {
                gravity = Gravity.CENTER
                textAlignment = View.TEXT_ALIGNMENT_CENTER
            }
        )

        space(box, 22)

        box.addView(
            button("CONNECT TO DEVICE", blue) {
                showPage("Connect")
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(52)
            )
        )

        val note = card(page)
        note.addView(label("Connection status", 15f, textColor, true))
        space(note, 8)
        note.addView(label("Not connected", 14f, muted))
    }

    private fun connectPage() {
        val page = scrollPage()

        heading(
            page,
            "Connect to Device",
            "Choose a connection method"
        )

        val hero = card(page)

        hero.gravity = Gravity.CENTER
        hero.setPadding(dp(20), dp(28), dp(20), dp(28))
        hero.background = rounded(navy, 24)

        hero.addView(
            label("◎", 70f, Color.rgb(0, 220, 190), true).apply {
                gravity = Gravity.CENTER
            }
        )

        space(hero, 12)

        hero.addView(
            label("Connect your devices", 20f, white, true).apply {
                gravity = Gravity.CENTER
            }
        )

        space(hero, 8)

        hero.addView(
            label(
                "Create a temporary Wi-Fi hotspot or explore other connection options.",
                13f,
                white
            ).apply {
                gravity = Gravity.CENTER
                textAlignment = View.TEXT_ALIGNMENT_CENTER
            }
        )

        // Hotspot controls
        val hotspotCard = card(page)

        hotspotCard.addView(
            label("Wi-Fi Hotspot", 18f, textColor, true)
        )

        space(hotspotCard, 6)

        hotspotCard.addView(
            label(
                "Create a local Wi-Fi network for the other device to join.",
                13f,
                muted
            )
        )

        space(hotspotCard, 14)

        hotspotCard.addView(
            button("START HOTSPOT", green) {
                requestHotspotPermission()
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(52)
            )
        )

        space(hotspotCard, 8)

        hotspotCard.addView(
            button("STOP HOTSPOT", navy) {
                hotspotController?.stopHotspot()
                Toast.makeText(
                    this,
                    "Hotspot stop requested",
                    Toast.LENGTH_SHORT
                ).show()
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(48)
            )
        )

        // Other connection methods
        val methods = listOf(
            Triple("◉", "Wi-Fi Direct", "Find nearby devices"),
            Triple("▦", "Scan QR Code", "Scan a compatible connection QR")
        )

        for ((icon, title, subtitle) in methods) {
            val box = card(page, 14)

            box.orientation = LinearLayout.HORIZONTAL
            box.gravity = Gravity.CENTER_VERTICAL

            box.addView(
                label(icon, 25f, green, true),
                LinearLayout.LayoutParams(dp(42), dp(48))
            )

            val texts = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
            }

            texts.addView(label(title, 15f, textColor, true))
            texts.addView(label(subtitle, 11f, muted))

            box.addView(
                texts,
                LinearLayout.LayoutParams(0, dp(48), 1f)
            )

            box.addView(label("›", 25f, muted))

            box.setOnClickListener {
                when (title) {
                    "Wi-Fi Direct" -> showPage("Nearby Devices")

                    "Scan QR Code" -> Toast.makeText(
                        this,
                        "QR scanner is not connected yet.",
                        Toast.LENGTH_LONG
                    ).show()
                }
            }
        }

        page.addView(
            button("SEARCH NEARBY DEVICES", blue) {
                showPage("Nearby Devices")
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(54)
            ).apply {
                setMargins(dp(16), dp(8), dp(16), dp(8))
            }
        )
    }

    private fun requestHotspotPermission() {
        val permissions = when {
            Build.VERSION.SDK_INT >= 33 -> arrayOf(
                Manifest.permission.NEARBY_WIFI_DEVICES
            )

            else -> arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION
            )
        }

        val missing = permissions.filter {
            ContextCompat.checkSelfPermission(
                this,
                it
            ) != PackageManager.PERMISSION_GRANTED
        }

        if (missing.isEmpty()) {
            startMAFXHotspot()
        } else {
            hotspotPermissionLauncher.launch(missing.toTypedArray())
        }
    }

    private fun startMAFXHotspot() {
        if (hotspotController == null) {
            hotspotController = HotspotController(this)
        }

        val controller = hotspotController ?: return

        controller.onHotspotReady = { ssid, password ->
            runOnUiThread {
                AlertDialog.Builder(this)
                    .setTitle("MAFX SHARE Hotspot Ready")
                    .setMessage(
                        "Wi-Fi name: $ssid\n\n" +
                            "Password: $password\n\n" +
                            "Connect the other device to this Wi-Fi network."
                    )
                    .setPositiveButton("OK", null)
                    .setNegativeButton("STOP HOTSPOT") { _, _ ->
                        controller.stopHotspot()
                    }
                    .show()
            }
        }

        controller.onError = { message ->
            runOnUiThread {
                Toast.makeText(
                    this,
                    message,
                    Toast.LENGTH_LONG
                ).show()
            }
        }

        controller.onHotspotStopped = {
            runOnUiThread {
                Toast.makeText(
                    this,
                    "Hotspot stopped",
                    Toast.LENGTH_SHORT
                ).show()
            }
        }

        controller.startHotspot()
    }

    private fun nearbyPage() {
        val page = scrollPage()

        heading(
            page,
            "Nearby Devices",
            "Available connection options"
        )

        val info = card(page)

        info.addView(
            label("Device discovery", 17f, textColor, true)
        )

        space(info, 8)

        info.addView(
            label(
                "Nearby device discovery is not yet connected to the Wi-Fi Direct manager.",
                13f,
                muted
            )
        )

        val localDevice = card(page)

        localDevice.orientation = LinearLayout.HORIZONTAL
        localDevice.gravity = Gravity.CENTER_VERTICAL

        localDevice.addView(
            label("▣", 30f, green, true),
            LinearLayout.LayoutParams(dp(50), dp(55))
        )

        val deviceInfo = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }

        deviceInfo.addView(
            label(
                Build.MODEL ?: "Android Device",
                15f,
                textColor,
                true
            )
        )

        deviceInfo.addView(label("This device", 12f, green))

        localDevice.addView(
            deviceInfo,
            LinearLayout.LayoutParams(0, dp(55), 1f)
        )

        localDevice.addView(label("✓", 22f, green, true))

        page.addView(
            button("BACK TO CONNECTION OPTIONS", blue) {
                showPage("Connect")
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(52)
            ).apply {
                setMargins(dp(16), dp(8), dp(16), dp(8))
            }
        )
    }

    private fun transfersPage() {
        val page = scrollPage()

        heading(page, "Transfers", "Monitor your file transfers")

        val tabs = card(page)
        tabs.orientation = LinearLayout.HORIZONTAL

        tabs.addView(
            label("ONGOING", 14f, green, true),
            LinearLayout.LayoutParams(0, dp(42), 1f)
        )

        tabs.addView(
            label("COMPLETED", 14f, muted, true),
            LinearLayout.LayoutParams(0, dp(42), 1f)
        )

        val empty = card(page)
        empty.gravity = Gravity.CENTER

        space(empty, 25)

        empty.addView(
            label("⇄", 52f, blue, true).apply {
                gravity = Gravity.CENTER
            }
        )

        space(empty, 12)

        empty.addView(
            label("No active transfers", 19f, textColor, true).apply {
                gravity = Gravity.CENTER
            }
        )

        space(empty, 6)

        empty.addView(
            label(
                "Your transfer progress will appear here when the transfer engine is connected.",
                13f,
                muted
            ).apply {
                gravity = Gravity.CENTER
                textAlignment = View.TEXT_ALIGNMENT_CENTER
            }
        )

        space(empty, 25)

        page.addView(
            button("SEND FILES", green) {
                showPage("Send")
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(52)
            ).apply {
                setMargins(dp(16), dp(8), dp(16), dp(8))
            }
        )
    }

    private fun historyPage() {
        val page = scrollPage()

        heading(
            page,
            "History",
            "Previously sent and received files"
        )

        val box = card(page)
        box.gravity = Gravity.CENTER

        space(box, 24)

        box.addView(
            label("◷", 52f, blue, true).apply {
                gravity = Gravity.CENTER
            }
        )

        space(box, 12)

        box.addView(
            label("No transfer history", 18f, textColor, true).apply {
                gravity = Gravity.CENTER
            }
        )

        space(box, 8)

        box.addView(
            label(
                "Completed transfers will appear here when history tracking is connected.",
                13f,
                muted
            ).apply {
                gravity = Gravity.CENTER
                textAlignment = View.TEXT_ALIGNMENT_CENTER
            }
        )

        space(box, 24)
    }

    private fun settingsPage() {
        val page = scrollPage()

        heading(page, "Settings", "Customize your experience")

        val device = card(page)

        device.orientation = LinearLayout.HORIZONTAL
        device.gravity = Gravity.CENTER_VERTICAL

        device.addView(
            label("MΛ", 35f, green, true),
            LinearLayout.LayoutParams(dp(55), dp(55))
        )

        val deviceText = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }

        deviceText.addView(
            label("MAFX SHARE", 17f, textColor, true)
        )

        deviceText.addView(
            label(Build.MODEL ?: "Android Device", 12f, muted)
        )

        device.addView(deviceText)

        heading(page, "Network & Connection")

        settingsRow(page, "▤", "Wi-Fi Direct", "Connection options")
        settingsRow(page, "◉", "Hotspot", "Connection options")
        settingsRow(page, "⌁", "Network", "Network preferences")

        heading(page, "File Transfer")

        settingsRow(page, "↗", "Transfer Speed", "High-speed transfer")
        settingsRow(page, "◷", "Auto Resume", "Transfer preferences")

        heading(page, "App Settings")

        settingsRow(page, "◎", "Language", "English")
        settingsRow(page, "◐", "Theme", "System default")
        settingsRow(page, "ⓘ", "About MAFX SHARE", "Version 1.0.0")
    }

    private fun settingsRow(
        page: LinearLayout,
        icon: String,
        title: String,
        subtitle: String
    ) {
        val box = card(page, 13)

        box.orientation = LinearLayout.HORIZONTAL
        box.gravity = Gravity.CENTER_VERTICAL

        box.addView(
            label(icon, 24f, blue, true),
            LinearLayout.LayoutParams(dp(42), dp(48))
        )

        val texts = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }

        texts.addView(label(title, 14f, textColor, true))
        texts.addView(label(subtitle, 12f, muted))

        box.addView(
            texts,
            LinearLayout.LayoutParams(0, dp(48), 1f)
        )

        box.addView(label("›", 24f, muted))

        box.setOnClickListener {
            when (title) {
                "Hotspot" -> showPage("Connect")
                "Wi-Fi Direct" -> showPage("Nearby Devices")
            }
        }
    }

    private fun buildBottomBar() {
        bottomBar.removeAllViews()

        bottomBar.setPadding(dp(6), dp(5), dp(6), dp(5))
        bottomBar.elevation = dp(12).toFloat()

        val items = listOf(
            Triple("⌂", "Home", "Home"),
            Triple("⇄", "Transfers", "Transfers"),
            Triple("◷", "History", "History"),
            Triple("⚙", "Settings", "Settings")
        )

        for ((icon, title, destination) in items) {
            val selected = currentPage == destination

            val item = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(dp(2), dp(5), dp(2), dp(5))

                background = if (selected) {
                    rounded(Color.rgb(226, 248, 237), 16)
                } else {
                    rounded(white, 16)
                }

                isClickable = true
                isFocusable = true
                contentDescription = title

                setOnClickListener {
                    if (currentPage != destination) {
                        showPage(destination)
                    }
                }
            }

            item.addView(
                label(
                    icon,
                    25f,
                    if (selected) Color.rgb(0, 125, 67)
                    else Color.rgb(55, 69, 86),
                    true
                ).apply {
                    gravity = Gravity.CENTER
                    includeFontPadding = false
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(30)
                )
            )

            item.addView(
                label(
                    title,
                    11f,
                    if (selected) Color.rgb(0, 125, 67)
                    else Color.rgb(55, 69, 86),
                    selected
                ).apply {
                    gravity = Gravity.CENTER
                    includeFontPadding = false
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(20)
                )
            )

            bottomBar.addView(
                item,
                LinearLayout.LayoutParams(0, dp(56), 1f).apply {
                    setMargins(dp(3), 0, dp(3), 0)
                }
            )
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        // Keep the hotspot running unless the user explicitly stops it.
        // This avoids unexpectedly disconnecting a connected device.
    }

    @Deprecated("Deprecated in Android")
    override fun onBackPressed() {
        if (currentPage != "Home") {
            showPage("Home")
        } else {
            super.onBackPressed()
        }
    }
}
