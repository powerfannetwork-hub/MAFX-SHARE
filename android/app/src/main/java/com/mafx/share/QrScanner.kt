package com.mafx.share

import android.app.Activity
import com.google.zxing.integration.android.IntentIntegrator

object QrScanner {

    fun scan(activity: Activity) {
        IntentIntegrator(activity).apply {
            setDesiredBarcodeFormats(
                IntentIntegrator.QR_CODE
            )
            setPrompt("Scan MAFX SHARE connection QR code")
            setBeepEnabled(false)
            setOrientationLocked(false)
            setBarcodeImageEnabled(false)
        }.initiateScan()
    }
}
