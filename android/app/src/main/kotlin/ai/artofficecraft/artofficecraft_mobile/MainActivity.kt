package ai.artofficecraft.artofficecraft_mobile

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.PersistableBundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Android storage, clipboard, incoming URI grants and installer handoff only. */
class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var incomingDocuments: IncomingDocuments? = null
    private var appUpdates: AppUpdates? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        incomingDocuments = IncomingDocuments(this, flutterEngine.dartExecutor.binaryMessenger, worker).also { it.accept(intent) }
        appUpdates = AppUpdates(this, flutterEngine.dartExecutor.binaryMessenger, worker)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "artofficecraft/workspace")
            .setMethodCallHandler { call, result ->
                if (call.method == "directory") {
                    try {
                        val directory = File(filesDir, "workspace")
                        check(directory.isDirectory || directory.mkdirs()) { "Workspace unavailable" }
                        result.success(directory.absolutePath)
                    } catch (_: Exception) {
                        result.error("WORKSPACE_UNAVAILABLE", "Cannot open private workspace", null)
                    }
                } else result.notImplemented()
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "artofficecraft/reading")
            .setMethodCallHandler { call, result ->
                val format = call.argument<String>("format")
                if (format != "pdf" && format != "deck") {
                    result.error("BAD_FORMAT", "Unknown reading format", null)
                    return@setMethodCallHandler
                }
                val preferences = getSharedPreferences("reading_modes", Context.MODE_PRIVATE)
                // Read-only compatibility for preferences saved before Dart files.
                if (call.method == "read") result.success(preferences.getString(format, null))
                else result.notImplemented()
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "artofficecraft/grid_clipboard")
            .setMethodCallHandler { call, result ->
                try {
                    val manager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    when (call.method) {
                        "write" -> {
                            val text = call.argument<String>("text")
                            val token = call.argument<String>("token")
                            require(text != null && text.length <= 256 * 1024 &&
                                token != null && token.matches(Regex("[0-9a-f]{32}"))) { "Invalid clipboard data" }
                            val clip = ClipData.newPlainText("ArtOfficeCraft cells", text)
                            clip.description.extras = PersistableBundle().apply { putString("ai.artofficecraft.gridToken", token) }
                            manager.setPrimaryClip(clip)
                            result.success(null)
                        }
                        "read" -> {
                            val clip = manager.primaryClip
                            val text = if (clip != null && clip.itemCount > 0) clip.getItemAt(0).text?.toString() else null
                            if (text == null) result.success(null)
                            else {
                                require(text.length <= 256 * 1024) { "Clipboard text too large" }
                                val token = clip?.description?.extras?.getString("ai.artofficecraft.gridToken")
                                result.success(mapOf("text" to text, "token" to token))
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("CLIPBOARD_UNAVAILABLE", "Cannot access Android clipboard", null)
                }
            }

    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incomingDocuments?.accept(intent)
    }

    override fun onDestroy() {
        incomingDocuments?.close()
        appUpdates?.close()
        worker.shutdown()
        super.onDestroy()
    }
}
