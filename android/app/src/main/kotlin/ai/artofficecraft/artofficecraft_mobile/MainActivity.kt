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
 * On-device PDF page rasterization for the Flutter preview.
 * Editing and saving the PDF remain exclusively in the Rust PDFCraft bridge.
 * No Internet or storage permissions are requested.
 */
class MainActivity : FlutterActivity() {
    private val pdfWorker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "artofficecraft/pdf_renderer",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "renderPage" -> {
                    val bytes = call.argument<ByteArray>("pdf")
                    val pageIndex = call.argument<Int>("page")
                    val requestedWidth = call.argument<Int>("width")
                    if (bytes == null || bytes.isEmpty() || bytes.size > 64 * 1024 * 1024 ||
                        pageIndex == null || pageIndex < 0 ||
                        requestedWidth == null || requestedWidth !in 96..1600
                    ) {
                        result.error("BAD_ARGS", "Invalid PDF render request", null)
                        return@setMethodCallHandler
                    }
                    pdfWorker.execute {
                        try {
                            val image = renderPage(bytes, pageIndex, requestedWidth)
                            runOnUiThread { result.success(image) }
                        } catch (ex: Exception) {
                            // Avoid returning private document content or filesystem paths.
                            runOnUiThread {
                                result.error(
                                    "PDF_RENDER",
                                    "Cannot render this PDF page (unsupported, password protected or invalid PDF)",
                                    null,
                                )
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun renderPage(data: ByteArray, index: Int, targetWidth: Int): ByteArray {
        if (data.size < 5 || data[0] != '%'.code.toByte() ||
            data[1] != 'P'.code.toByte() || data[2] != 'D'.code.toByte() ||
            data[3] != 'F'.code.toByte() || data[4] != '-'.code.toByte()
        ) {
            throw IllegalArgumentException("Not a PDF")
        }
        val localFile = File.createTempFile("artofficecraft-page-", ".pdf", cacheDir)
        try {
            FileOutputStream(localFile).use { output ->
                output.write(data)
                output.fd.sync()
            }
            return ParcelFileDescriptor.open(localFile, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                PdfRenderer(fd).use { document ->
                    require(index < document.pageCount) { "Page out of range" }
                    document.openPage(index).use { page ->
                        require(page.width > 0 && page.height > 0) { "Invalid page dimensions" }
                        val ratio = page.height.toDouble() / page.width.toDouble()
                        val width = minOf(targetWidth, (2880.0 / ratio).toInt())
                        require(width >= 32) { "Unusually tall page" }
                        val height = (width * ratio).roundToInt()
                        require(height in 1..2880 && width.toLong() * height <= 4_200_000L) {
                            "Page raster exceeds memory bounds"
                        }
                        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                        try {
                            bitmap.eraseColor(Color.WHITE)
                            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            ByteArrayOutputStream().use { output ->
                                require(bitmap.compress(Bitmap.CompressFormat.PNG, 90, output)) {
                                    "Cannot encode rendered page"
                                }
                                output.toByteArray()
                            }
                        } finally {
                            bitmap.recycle()
                        }
                    }
                }
            }
        } finally {
            localFile.delete()
        }
    }

    override fun onDestroy() {
        pdfWorker.shutdown()
        super.onDestroy()
    }
}
