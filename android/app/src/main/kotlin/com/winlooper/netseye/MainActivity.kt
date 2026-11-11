package com.winlooper.netseye

import android.Manifest
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingLocation: MethodChannel.Result? = null

    private var exo: ExoStreams? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val exoChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "netseye/exo")
        val streams = ExoStreams(applicationContext, flutterEngine.renderer, exoChannel)
        exo = streams
        exoChannel.setMethodCallHandler(streams::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "netseye/device").setMethodCallHandler { call, result ->
            when (call.method) {
                // TV: text entry uses NetSeye's own remote-friendly keyboard.
                "isTv" -> result.success(packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK))
                "network" -> result.success(network())
                "askLocation" -> askLocation(result)
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        exo?.releaseAll()
        exo = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun hasLocation() =
        checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    /** How we're connected, and the Wi-Fi name when Android lets us read it. */
    private fun network(): Map<String, Any?> {
        val cm = getSystemService(ConnectivityManager::class.java)
        val caps = cm?.getNetworkCapabilities(cm.activeNetwork)
        val type = when {
            caps == null -> "none"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "other"
        }
        var ssid: String? = null
        if (type == "wifi" && hasLocation()) {
            // Android only reveals the Wi-Fi name to apps holding the location
            // permission (and with location turned on).
            val wm = applicationContext.getSystemService(WifiManager::class.java)
            @Suppress("DEPRECATION")
            val raw = wm?.connectionInfo?.ssid
            if (raw != null && raw != WifiManager.UNKNOWN_SSID && raw.isNotBlank()) ssid = raw.trim('"')
        }
        return mapOf("type" to type, "ssid" to ssid, "canName" to hasLocation())
    }

    private fun askLocation(result: MethodChannel.Result) {
        if (hasLocation()) return result.success(true)
        pendingLocation?.success(false)
        pendingLocation = result
        requestPermissions(
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
            REQUEST_LOCATION,
        )
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_LOCATION) {
            pendingLocation?.success(hasLocation())
            pendingLocation = null
        }
    }

    private companion object {
        const val REQUEST_LOCATION = 4107
    }
}
