package frpwrapper

import android.util.Log

/**
 * Kotlin bridge for the frpwrapper native library.
 */
object Frpwrapper {
    init {
        try {
            System.loadLibrary("frpwrapper")
        } catch (e: UnsatisfiedLinkError) {
            Log.e("Frpwrapper", "Native library frpwrapper not found. Make sure libfrpwrapper.so is in jniLibs.", e)
        }
    }

    /**
     * Initializes the native layer with a writable directory.
     */
    @JvmStatic
    external fun init(cacheDir: String)

    /**
     * StartFrps runs the server service
     */
    @JvmStatic
    external fun startFrps(configContent: String)

    /**
     * StopFrps gracefully shuts down the server
     */
    @JvmStatic
    external fun stopFrps()

    /**
     * StartFrpc runs the FRP client from an in-memory configuration string
     */
    @JvmStatic
    external fun startFrpc(configContent: String)

    /**
     * StopFrpc gracefully shuts down the client
     */
    @JvmStatic
    external fun stopFrpc()

    /**
     * Checks if the FRPS server is currently running in the Go layer.
     */
    @JvmStatic
    external fun isFrpsRunning(): Boolean

    /**
     * Checks if the FRPC client is currently running in the Go layer.
     */
    @JvmStatic
    external fun isFrpcRunning(): Boolean

    /**
     * Checks if a local port is open from the Go runtime's perspective.
     */
    @JvmStatic
    external fun checkPort(port: Int): Boolean
}
