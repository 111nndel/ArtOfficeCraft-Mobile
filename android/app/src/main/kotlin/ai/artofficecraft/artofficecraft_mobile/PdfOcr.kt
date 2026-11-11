package ai.artofficecraft.artofficecraft_mobile

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.googlecode.tesseract.android.TessBaseAPI
import com.googlecode.tesseract.android.TessBaseAPI.PageIteratorLevel.RIL_TEXTLINE
import com.googlecode.tesseract.android.TessBaseAPI.PageIteratorLevel.RIL_WORD
import java.io.File

internal class PdfOcr(private val context: Context) {
    fun recognize(png: ByteArray): Map<String, Any> {
        require(png.size in 24..24 * 1024 * 1024 &&
            png.take(8) == listOf<Byte>(-119, 80, 78, 71, 13, 10, 26, 10)) { "Invalid OCR PNG" }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(png, 0, png.size, bounds)
        require(bounds.outWidth in 1..2880 && bounds.outHeight in 1..2880 &&
            bounds.outWidth.toLong() * bounds.outHeight <= 4_200_000L) { "OCR image exceeds memory limit" }
        val bitmap = requireNotNull(BitmapFactory.decodeByteArray(png, 0, png.size)) { "Cannot decode OCR image" }
        try {
            return recognizeBitmap(bitmap)
        } finally {
            bitmap.recycle()
        }
    }

    private fun recognizeBitmap(bitmap: Bitmap): Map<String, Any> {
        val directory = File(context.cacheDir, "pdf-ocr-65727574")
        val tessdata = File(directory, "tessdata")
        check(tessdata.isDirectory || tessdata.mkdirs()) { "Cannot prepare OCR models" }
        copyModel(tessdata, "eng", 4113088)
        copyModel(tessdata, "rus", 3861738)
        val engine = TessBaseAPI()
        try {
            check(engine.init(directory.absolutePath, "rus+eng", TessBaseAPI.OEM_LSTM_ONLY)) {
                "Cannot initialize PDF OCR"
            }
            engine.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
            engine.setImage(bitmap)
            val text = engine.getUTF8Text().orEmpty()
            check(text.length <= 64 * 1024) { "Too much recognized text on one page" }
            return mapOf("text" to text, "words" to wordBoxes(engine, bitmap))
        } finally {
            engine.recycle()
        }
    }

    private fun wordBoxes(engine: TessBaseAPI, bitmap: Bitmap): List<Map<String, Any>> {
        val iterator = engine.resultIterator ?: return emptyList()
        try {
            val words = mutableListOf<Map<String, Any>>()
            var line: IntArray? = null
            var characters = 0
            iterator.begin()
            do {
                if (line == null || iterator.isAtBeginningOf(RIL_TEXTLINE)) {
                    line = iterator.getBoundingBox(RIL_TEXTLINE)
                }
                val text = iterator.getUTF8Text(RIL_WORD)?.trim().orEmpty()
                if (text.isEmpty()) continue
                characters += text.length
                if (words.size == 4096 || characters > 64 * 1024) return emptyList()
                val word = iterator.getBoundingBox(RIL_WORD) ?: return emptyList()
                val left = word[0].coerceIn(0, bitmap.width)
                val top = (line ?: word)[1].coerceIn(0, bitmap.height)
                val right = word[2].coerceIn(0, bitmap.width)
                val bottom = (line ?: word)[3].coerceIn(0, bitmap.height)
                if (left >= right || top >= bottom) return emptyList()
                words.add(mapOf("text" to text, "rect" to listOf(
                    left.toDouble() / bitmap.width, top.toDouble() / bitmap.height,
                    right.toDouble() / bitmap.width, bottom.toDouble() / bitmap.height,
                )))
            } while (iterator.next(RIL_WORD))
            return words
        } finally {
            iterator.delete()
        }
    }

    private fun copyModel(tessdata: File, language: String, size: Long) {
        val name = "$language.traineddata"
        val target = File(tessdata, name)
        if (target.isFile && target.length() == size) return
        val temporary = File.createTempFile(language, ".pending", tessdata)
        try {
            context.assets.open("ocr/tessdata/$name").use { input ->
                temporary.outputStream().use { output -> input.copyTo(output) }
            }
            check(temporary.length() == size && temporary.renameTo(target)) {
                "Cannot prepare OCR model"
            }
        } finally {
            temporary.delete()
        }
    }
}
