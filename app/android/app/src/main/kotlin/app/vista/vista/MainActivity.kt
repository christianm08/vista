package app.vista.vista

import android.app.UiModeManager
import android.content.Context
import android.content.Intent
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
                    // Apre la prima app installata dell'elenco (sulla TV
                    // l'ingresso Leanback). Restituisce false se nessuna c'è.
                    "openApp" -> {
                        val packages = call.argument<List<String>>("packages") ?: emptyList()
                        var opened = false
                        for (p in packages) {
                            val intent = packageManager.getLeanbackLaunchIntentForPackage(p)
                                ?: packageManager.getLaunchIntentForPackage(p)
                            if (intent != null) {
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                opened = true
                                break
                            }
                        }
                        result.success(opened)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
