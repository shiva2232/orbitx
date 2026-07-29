package frpwrapper

import android.util.Log

/**
 * Kotlin bridge for the frpwrapper native library (.so).
 */
object Frpwrapper {
    init {
        try {
            System.loadLibrary("frpwrapper")
        } catch (e: UnsatisfiedLinkError) {
            Log.e("Frpwrapper", "Native library libfrpwrapper.so not found in jniLibs.", e)
        }
    }

    /**
     * Initializes the native layer with a writable directory for temporary configs.
     */
    @JvmStatic
    external fun init(cacheDir: String)

    /**
     * Starts the FRPS (Server) service.
     */
    @JvmStatic
    external fun startFrps(config: String)

    /**
     * Stops the FRPS service.
     */
    @JvmStatic
    external fun stopFrps()

    /**
     * Starts the FRPC (Client) service.
     */
    @JvmStatic
    external fun startFrpc(config: String)

    /**
     * Stops the FRPC service.
     */
    @JvmStatic
    external fun stopFrpc()

    /**
     * Checks if the FRPS server is currently active.
     */
    @JvmStatic
    external fun isFrpsRunning(): Boolean

    /**
     * Checks if the FRPC client is currently active.
     */
    @JvmStatic
    external fun isFrpcRunning(): Boolean

    /**
     * Verifies if a specific local port is reachable from the Go runtime.
     */
    @JvmStatic
    external fun checkPort(port: Int): Boolean
}
