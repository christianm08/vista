package app.vista.vista

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Dice a Flutter se gira su una TV: interfaccia da telecomando.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vista/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTv" -> {
                        val ui = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                        val tv = ui.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
                            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                        result.success(tv)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
