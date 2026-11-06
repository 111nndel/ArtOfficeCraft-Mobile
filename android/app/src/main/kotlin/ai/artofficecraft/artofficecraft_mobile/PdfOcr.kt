package ai.artofficecraft.artofficecraft_mobile

import android.content.Context
import android.graphics.Bitmap
import com.googlecode.tesseract.android.TessBaseAPI
import java.io.File

internal class PdfOcr(private val context: Context) {
    fun recognize(bitmap: Bitmap): String {
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
            return text
        } finally {
            engine.recycle()
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
