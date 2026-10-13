package com.mafx.share

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.atomic.AtomicBoolean

class ReceiveSession(context: Context) {

    companion object {
        const val PORT = 8988
    }

    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val started = AtomicBoolean(false)

    private var server: TransferServer? = null

    var onReady: ((String, Int, String) -> Unit)? = null
    var onFileReceived: ((String, Long) -> Unit)? = null
    var onError: ((String) -> Unit)? = null

    fun start() {
        if (!started.compareAndSet(false, true)) return

        val receiver = TransferServer(appContext, PORT)
        server = receiver

        receiver.onStarted = { port ->
            val ip = NetworkAddress.getLocalIPv4Address()

            mainHandler.post {
                if (ip.isNullOrBlank()) {
                    started.set(false)
                    receiver.stop()
                    onError?.invoke(
                        "Ba a gano adireshin Wi-Fi ba. Ka tabbatar an haɗa na'urorin."
                    )
                } else {
                    val qrPayload = ConnectionQr.createPayload(ip, port)
                    onReady?.invoke(ip, port, qrPayload)
                }
            }
        }

        receiver.onFileReceived = { filename, size ->
            mainHandler.post {
                onFileReceived?.invoke(filename, size)
            }
        }

        receiver.onError = { message ->
            mainHandler.post {
                started.set(false)
                onError?.invoke(message)
            }
        }

        receiver.start()
    }

    fun isRunning(): Boolean = server?.isRunning() == true

    fun stop() {
        started.set(false)
        server?.stop()
        server = null
    }
}
