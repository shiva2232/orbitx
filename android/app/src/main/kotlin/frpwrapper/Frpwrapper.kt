package frpwrapper

import android.util.Log

/**
 * Kotlin bridge for the frpwrapper native library.
 * This class provides the same interface as the Go-binded version,
 * allowing it to be used as a replacement if the AAR symbols are not resolving.
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
}
