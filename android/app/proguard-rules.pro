# Preserve JNI methods and classes used by the native Go engine
-keep class com.shiva2232.orbitx.VpnBridge {
    native <methods>;
}

-keep class com.shiva2232.orbitx.HomeVpnService {
    static boolean protectSocketFromNative(int);
}

-keep class frpwrapper.Frpwrapper {
    native <methods>;
}

# General rule for all native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
