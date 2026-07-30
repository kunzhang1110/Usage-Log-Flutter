package com.example.usage_log_flutter

import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "usage_log/app_info"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAppInfos" -> result.success(getAppInfos(call.arguments as? List<*>))
                    else -> result.notImplemented()
                }
            }
    }

    // Resolves the label and icon for each requested package in one pass, so the
    // Dart side makes a single channel call instead of two per usage event.
    private fun getAppInfos(names: List<*>?): Map<String, Map<String, Any?>> {
        val pm = applicationContext.packageManager
        val out = HashMap<String, Map<String, Any?>>()
        if (names == null) return out
        for (raw in names) {
            val name = raw as? String ?: continue
            try {
                val info = pm.getApplicationInfo(name, 0)
                out[name] = mapOf(
                    "label" to pm.getApplicationLabel(info).toString(),
                    "icon" to drawableToPngBytes(pm.getApplicationIcon(info)),
                )
            } catch (e: PackageManager.NameNotFoundException) {
                // Leave unresolved; Dart falls back to the package name / a Material icon.
            }
        }
        return out
    }

    private fun drawableToPngBytes(drawable: Drawable): ByteArray {
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            drawable.bitmap
        } else {
            val width = drawable.intrinsicWidth.coerceAtLeast(1)
            val height = drawable.intrinsicHeight.coerceAtLeast(1)
            val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            bmp
        }
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }
}
