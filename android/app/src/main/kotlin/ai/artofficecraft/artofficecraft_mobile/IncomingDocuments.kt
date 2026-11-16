package ai.artofficecraft.artofficecraft_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executor

/** Android URI grants only. Format selection and editor navigation live in Dart. */
class IncomingDocuments(private val activity: Activity, messenger: BinaryMessenger, private val worker: Executor) {
    private val channel = MethodChannel(messenger, "artofficecraft/incoming_documents")
    private val pending = ArrayDeque<Pair<Uri, String?>>()
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "take" -> {
                    val item = pending.removeFirstOrNull()
                    if (item == null) result.success(null)
                    else worker.execute {
                        try {
                            val copied = copy(item.first, item.second)
                            activity.runOnUiThread { result.success(copied) }
                        } catch (_: Exception) {
                            activity.runOnUiThread { result.error("INCOMING_FILE", "Cannot read this document", null) }
                        }
                    }
                }
                "release" -> {
                    val path = call.argument<String>("path")
                    val file = path?.let { File(it) }
                    if (file != null && file.parentFile?.canonicalFile == activity.cacheDir.canonicalFile && file.name.startsWith("incoming-")) file.delete()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    fun accept(intent: Intent?) {
        val uri: Uri? = try {
            when (intent?.action) {
                Intent.ACTION_VIEW -> intent.data
                Intent.ACTION_SEND -> intent.getParcelableExtra<android.os.Parcelable>(Intent.EXTRA_STREAM) as? Uri
                else -> null
            }
        } catch (_: Exception) {
            channel.invokeMethod("error", "Invalid incoming document URI")
            return
        }
        if (uri == null) return
        if (pending.size >= 8) {
            channel.invokeMethod("error", "Incoming document queue is full")
            return
        }
        pending.addLast(uri to intent?.type)
        channel.invokeMethod("available", null)
    }

    private fun copy(uri: Uri, suppliedType: String?): Map<String, Any?> {
        require(uri.scheme == "content" || uri.scheme == "file") { "Only local documents are supported" }
        if (uri.scheme == "file") {
            val source = File(requireNotNull(uri.path)).canonicalFile
            val privateRoot = File(activity.applicationInfo.dataDir).canonicalPath + File.separator
            require(!source.path.startsWith(privateRoot)) { "Private paths cannot be imported" }
        }
        val resolver = activity.contentResolver
        var name = uri.lastPathSegment ?: "Document"
        if (uri.scheme == "content") resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val title = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (title >= 0 && !cursor.isNull(title)) name = cursor.getString(title)
                val size = cursor.getColumnIndex(OpenableColumns.SIZE)
                require(size < 0 || cursor.isNull(size) || cursor.getLong(size) <= 64L * 1024 * 1024) { "Document too large" }
            }
        }
        val type = suppliedType ?: resolver.getType(uri)
        val file = File.createTempFile("incoming-", ".tmp", activity.cacheDir)
        try {
            requireNotNull(resolver.openInputStream(uri)).use { input ->
                file.outputStream().use { output ->
                    val buffer = ByteArray(32768)
                    var total = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        require(total <= 64L * 1024 * 1024) { "Document too large" }
                        output.write(buffer, 0, count)
                    }
                    require(total > 0) { "Empty document" }
                }
            }
            return mapOf("path" to file.absolutePath, "name" to name.take(255), "mime" to type)
        } catch (error: Exception) {
            file.delete()
            throw error
        }
    }

    fun close() { channel.setMethodCallHandler(null); pending.clear() }
}
