package com.voltraware.gios0901

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gios0901/updates")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installedVersion" -> {
                        @Suppress("DEPRECATION")
                        val info = packageManager.getPackageInfo(packageName, 0)
                        @Suppress("DEPRECATION")
                        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                        result.success(mapOf("name" to info.versionName, "code" to code))
                    }
                    "download" -> {
                        val version = call.argument<String>("version")
                        val code = call.argument<Int>("code")
                        if (version == null || !Regex("""\d+\.\d+\.\d+""").matches(version) || code == null || code <= 0) {
                            result.error("invalid_release", "Invalid release", null)
                            return@setMethodCallHandler
                        }
                        val url = "https://github.com/jerrywu-voltraware/gios0901-android-demo/releases/download/v$version/GIOS0901-Demo-$version-$code.apk"
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            result.success(null)
                        } catch (error: ActivityNotFoundException) {
                            result.error("no_browser", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
