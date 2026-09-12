package com.shiva2232.orbitx

object PowerPresentBridge {
    init {
        try {
            System.loadLibrary("powerpresent")
        } catch (e: UnsatisfiedLinkError) {
            e.printStackTrace()
        }
    }

    @JvmStatic
    external fun init()

    @JvmStatic
    external fun loadUrl(url: String)

    @JvmStatic
    external fun sendGesture(action: String, x: Float, y: Float)
}
