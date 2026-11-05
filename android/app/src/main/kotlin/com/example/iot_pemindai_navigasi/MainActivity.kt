package com.example.iot_pemindai_navigasi

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "iot_pemindai_navigasi/hotspot"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "openHotspotSettings") {
                    openHotspotSettings()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    // Android melarang aplikasi menyalakan hotspot langsung, jadi buka
    // halaman pengaturan Hotspot/Tethering sistem agar user menyalakannya.
    private fun openHotspotSettings() {
        val intents = listOf(
            Intent("android.settings.TETHERING_SETTINGS"),
            Intent(Settings.ACTION_WIRELESS_SETTINGS),
            Intent(Settings.ACTION_SETTINGS)
        )
        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return
            } catch (e: Exception) {
                // Coba halaman pengaturan berikutnya.
            }
        }
    }
}
