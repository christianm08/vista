package app.vista.vista

import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** Il player è aperto: premendo Home si passa al Picture-in-Picture. */
    private var autoPip = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vista/device")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                // Dice a Flutter se gira su una TV: interfaccia da telecomando.
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
                // Apre un flusso in un altro player (VLC, MX Player…).
                "openVideo" -> {
                    val url = call.argument<String>("url") ?: ""
                    val title = call.argument<String>("title") ?: ""
                    val view = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(Uri.parse(url), "video/*")
                        putExtra("title", title)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    try {
                        startActivity(Intent.createChooser(view, "Apri con"))
                        result.success(true)
                    } catch (e: ActivityNotFoundException) {
                        result.success(false)
                    }
                }
                // Spazio libero (byte) dove finiscono le registrazioni.
                "freeSpace" -> {
                    val path = call.argument<String>("path") ?: filesDir.path
                    result.success(
                        try {
                            StatFs(path).availableBytes
                        } catch (e: IllegalArgumentException) {
                            null
                        }
                    )
                }
                "canPip" -> result.success(canPip())
                "enterPip" -> result.success(enterPip())
                "setAutoPip" -> {
                    autoPip = call.arguments == true
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun canPip(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun enterPip(): Boolean {
        if (!canPip()) return false
        return try {
            enterPictureInPictureMode(
                PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build()
            )
        } catch (e: IllegalStateException) {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPip) enterPip()
    }

    override fun onPictureInPictureModeChanged(inPip: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(inPip, newConfig)
        channel?.invokeMethod("pipChanged", inPip)
    }
}
