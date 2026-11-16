package ai.artofficecraft.artofficecraft_mobile

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executor
import java.util.zip.ZipFile

class AppUpdateFileProvider : FileProvider()

/** Package verification and installer handoff only; networking/policy live in Dart. */
@Suppress("DEPRECATION")
class AppUpdates(private val activity: Activity, messenger: BinaryMessenger, private val worker: Executor) {
    private val channel = MethodChannel(messenger, "artofficecraft/app_updates")
    private val directory = File(activity.cacheDir, "updates")
    private val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
    private fun code(info: PackageInfo) = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    private fun signatures(info: PackageInfo): Set<String> =
        (if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures)
            ?.map { hash(it.toByteArray()) }?.toSet() ?: emptySet()
    private fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private fun installed() = activity.packageManager.getPackageInfo(activity.packageName, flags)

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "identity") {
                try {
                    check(directory.isDirectory || directory.mkdirs())
                    val info = installed()
                    result.success(mapOf("version" to info.versionName, "code" to code(info),
                        "abi" to Build.SUPPORTED_ABIS.first(), "directory" to directory.absolutePath))
                } catch (_: Exception) { result.error("UPDATE_IDENTITY", "Cannot read installed package", null) }
            } else if (call.method == "verify" || call.method == "install") {
                val path = call.argument<String>("path")
                val expected = call.argument<String>("sha256")
                val version = call.argument<Number>("code")?.toLong()
                if (path == null || expected == null || version == null || !expected.matches(Regex("[0-9a-f]{64}"))) {
                    result.error("UPDATE_ARGS", "Invalid update request", null)
                } else worker.execute {
                    try {
                        val file = File(path).canonicalFile
                        require(file.parentFile == directory.canonicalFile &&
                            (file.name == "update.apk" || file.name.matches(Regex("update-[0-9]+\\.part"))))
                        require(file.isFile && file.length() in 1..160L * 1024 * 1024)
                        val digest = MessageDigest.getInstance("SHA-256")
                        file.inputStream().use { stream ->
                            val buffer = ByteArray(32768)
                            while (true) { val count = stream.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
                        }
                        require(digest.digest().joinToString("") { "%02x".format(it) } == expected) { "Checksum mismatch" }
                        val current = installed()
                        val candidate = requireNotNull(activity.packageManager.getPackageArchiveInfo(file.path, flags))
                        require(candidate.packageName == activity.packageName && code(candidate) == version && version > code(current))
                        val signers = signatures(current)
                        require(signers.isNotEmpty() && signatures(candidate) == signers) { "Signing certificate mismatch" }
                        ZipFile(file).use { require(it.getEntry("lib/${Build.SUPPORTED_ABIS.first()}/libapp.so") != null) { "Unsupported ABI" } }
                        activity.runOnUiThread {
                            try {
                                if (call.method == "verify") result.success(null)
                                else if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                                    activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
                                    result.success(false)
                                } else {
                                    val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
                                    activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                                    result.success(true)
                                }
                            } catch (_: Exception) { result.error("UPDATE_INSTALL", "Cannot open Android installer", null) }
                        }
                    } catch (_: Exception) {
                        activity.runOnUiThread { result.error("UPDATE_VERIFY", "APK verification failed", null) }
                    }
                }
            } else result.notImplemented()
        }
    }
    fun close() { channel.setMethodCallHandler(null) }
}
