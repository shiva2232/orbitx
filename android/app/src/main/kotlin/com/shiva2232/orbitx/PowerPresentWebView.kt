package com.shiva2232.orbitx

import android.content.Context
import android.graphics.PointF
import android.view.MotionEvent
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class PowerPresentWebViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<String, Any?>
        return PowerPresentWebView(context, messenger, viewId, params)
    }
}

class PowerPresentWebView(
    context: Context,
    messenger: BinaryMessenger,
    id: Int,
    params: Map<String, Any?>?
) : PlatformView, MethodChannel.MethodCallHandler {

    private val webView: WebView = WebView(context)
    private val methodChannel: MethodChannel =
        MethodChannel(messenger, "power_present_webview_$id")
    private val lastPosition = PointF(0f, 0f)

    init {
        PowerPresentBridge.init()
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.allowContentAccess = true
        webView.settings.allowFileAccess = true
        webView.webViewClient = WebViewClient()
        webView.webChromeClient = WebChromeClient()
        methodChannel.setMethodCallHandler(this)

        val initialUrl = params?.get("url") as? String ?: "https://example.com"
        PowerPresentBridge.loadUrl(initialUrl)
        webView.loadUrl(initialUrl)
    }

    override fun getView(): WebView = webView

    override fun dispose() {
        methodChannel.setMethodCallHandler(null)
        webView.destroy()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setInitialUrl" -> {
                val url = call.argument<String>("url")
                if (url != null) {
                    PowerPresentBridge.loadUrl(url)
                    webView.loadUrl(url)
                    result.success(null)
                } else {
                    result.error("ARG_ERR", "Missing url", null)
                }
            }
            "loadUrl" -> {
                val url = call.argument<String>("url")
                if (url != null) {
                    PowerPresentBridge.loadUrl(url)
                    webView.loadUrl(url)
                    result.success(null)
                } else {
                    result.error("ARG_ERR", "Missing url", null)
                }
            }
            "reload" -> {
                webView.reload()
                result.success(null)
            }
            "gesture" -> {
                val args = call.arguments as? Map<String, Any?>
                if (args != null) {
                    handleGesture(args)
                    val action = args["action"] as? String
                    val x = (args["x"] as? Number)?.toFloat() ?: 0f
                    val y = (args["y"] as? Number)?.toFloat() ?: 0f
                    if (action != null) {
                        PowerPresentBridge.sendGesture(action, x, y)
                    }
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleGesture(args: Map<String, Any?>?) {
        if (args == null) return
        val action = args["action"] as? String ?: return
        val width = webView.width.coerceAtLeast(1)
        val height = webView.height.coerceAtLeast(1)
        val x = (args["x"] as? Number)?.toFloat() ?: lastPosition.x / width
        val y = (args["y"] as? Number)?.toFloat() ?: lastPosition.y / height
        val px = (x * width).coerceIn(0f, width.toFloat())
        val py = (y * height).coerceIn(0f, height.toFloat())
        lastPosition.set(px, py)

        val eventAction = when (action) {
            "tapDown" -> MotionEvent.ACTION_DOWN
            "panUpdate" -> MotionEvent.ACTION_MOVE
            "panEnd" -> MotionEvent.ACTION_UP
            else -> null
        } ?: return

        val eventTime = System.currentTimeMillis()
        val motionEvent = MotionEvent.obtain(
            eventTime,
            eventTime,
            eventAction,
            px,
            py,
            0
        )

        webView.dispatchTouchEvent(motionEvent)
        motionEvent.recycle()
    }
}
