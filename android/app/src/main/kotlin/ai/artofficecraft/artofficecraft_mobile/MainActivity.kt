package ai.artofficecraft.artofficecraft_mobile

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import kotlin.math.roundToInt

/**
 * First-party Android PDF rasterization; Rust PDFCraft owns document edits.
 *
 * A single worker serializes all open/render/close operations. Only one
 * document is resident per FlutterActivity, with an opaque session token.
 * All temporary PDF data stays in app-private cache and is removed on close.
 * No network, Wi-Fi, or broad storage permissions are required.
 */
class MainActivity : FlutterActivity() {
    private data class PdfSession(
        val id: Int,
        val file: File,
        val descriptor: ParcelFileDescriptor,
        val renderer: PdfRenderer,
    ) {
        fun close() {
            try { renderer.close() } finally {
                try { descriptor.close() } finally { file.delete() }
            }
        }
    }

    private val worker = Executors.newSingleThreadExecutor()
    private var active: PdfSession? = null
    private var nextId = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "artofficecraft/pdf_renderer",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openDocument" -> {
                    val data = call.argument<ByteArray>("pdf")
                    if (data == null || data.size !in 5..64 * 1024 * 1024 ||
                        !validHeader(data)
                    ) {
                        result.error("BAD_ARGS", "Invalid PDF document bytes", null)
                        return@setMethodCallHandler
                    }
                    worker.execute {
                        try {
                            val info = open(data)
                            runOnUiThread { result.success(info) }
                        } catch (_: Exception) {
                            runOnUiThread {
                                result.error(
                                    "PDF_OPEN",
                                    "Cannot open this PDF (unsupported, encrypted or invalid)",
                                    null,
                                )
                            }
                        }
                    }
                }
                "renderPage" -> {
                    val id = call.argument<Int>("session")
                    val pageIndex = call.argument<Int>("page")
                    val width = call.argument<Int>("width")
                    if (id == null || id <= 0 ||
                        pageIndex == null || pageIndex < 0 ||
                        width == null || width !in 96..1600
                    ) {
                        result.error("BAD_ARGS", "Invalid page render request", null)
                        return@setMethodCallHandler
                    }
                    worker.execute {
                        try {
                            val session = active
                            require(session != null && session.id == id) {
                                "PDF document session is no longer active"
                            }
                            val png = renderPage(session, pageIndex, width)
                            runOnUiThread { result.success(png) }
                        } catch (_: Exception) {
                            runOnUiThread {
                                result.error(
                                    "PDF_RENDER",
                                    "Cannot render this page or the PDF session is closed",
                                    null,
                                )
                            }
                        }
                    }
                }
                "closeDocument" -> {
                    val id = call.argument<Int>("session")
                    if (id == null) {
                        result.error("BAD_ARGS", "Missing PDF session", null)
                        return@setMethodCallHandler
                    }
                    worker.execute {
                        if (active?.id == id) closeActive()
                        runOnUiThread { result.success(null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun validHeader(bytes: ByteArray): Boolean =
        bytes[0] == '%'.code.toByte() &&
        bytes[1] == 'P'.code.toByte() &&
        bytes[2] == 'D'.code.toByte() &&
        bytes[3] == 'F'.code.toByte() &&
        bytes[4] == '-'.code.toByte()

    private fun closeActive() {
        val previous = active
        active = null
        try { previous?.close() } catch (_: Exception) {
            // A closed/invalid descriptor must not prevent the next document.
        }
    }

    private fun open(data: ByteArray): Map<String, Int> {
        val file = File.createTempFile("artofficecraft-session-", ".pdf", cacheDir)
        var descriptor: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        try {
            FileOutputStream(file).use { output ->
                output.write(data)
                output.fd.sync()
            }
            descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            renderer = PdfRenderer(descriptor)
            require(renderer.pageCount in 1..10000) { "Invalid page count" }
            val newId = ++nextId
            // The new document must open successfully before closing the old one.
            closeActive()
            active = PdfSession(newId, file, descriptor, renderer)
            return mapOf("session" to newId, "pageCount" to renderer.pageCount)
        } catch (e: Exception) {
            try { renderer?.close() } catch (_: Exception) {}
            try { descriptor?.close() } catch (_: Exception) {}
            file.delete()
            throw e
        }
    }

    private fun renderPage(session: PdfSession, index: Int, widthRequest: Int): ByteArray {
        require(index < session.renderer.pageCount) { "Invalid page" }
        session.renderer.openPage(index).use { page ->
            require(page.width > 0 && page.height > 0) { "Invalid page dimensions" }
            val ratio = page.height.toDouble() / page.width.toDouble()
            val width = minOf(widthRequest, (2880.0 / ratio).toInt())
            require(width >= 32) { "Unusually tall page" }
            val height = (width * ratio).roundToInt()
            require(height in 1..2880 && width.toLong() * height <= 4_200_000L) {
                "Page exceeds raster memory limit"
            }
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            try {
                bitmap.eraseColor(Color.WHITE)
                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                return ByteArrayOutputStream().use { output ->
                    require(bitmap.compress(Bitmap.CompressFormat.PNG, 90, output)) {
                        "Cannot encode PNG"
                    }
                    output.toByteArray()
                }
            } finally {
                bitmap.recycle()
            }
        }
    }

    override fun onDestroy() {
        worker.execute { closeActive() }
        worker.shutdown()
        super.onDestroy()
    }
}
