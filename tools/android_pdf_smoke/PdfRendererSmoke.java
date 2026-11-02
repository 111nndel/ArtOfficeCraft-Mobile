import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.pdf.PdfRenderer;
import android.os.ParcelFileDescriptor;
import java.io.File;

/** Headless Android framework test that does not launch an Activity. */
public final class PdfRendererSmoke {
  public static void main(String[] args) throws Exception {
    if (args.length < 2) throw new IllegalArgumentException("Usage: PDF path expectedPageCount");
    final int expectedCount = Integer.parseInt(args[1]);
    try (ParcelFileDescriptor fd = ParcelFileDescriptor.open(
           new File(args[0]), ParcelFileDescriptor.MODE_READ_ONLY);
         PdfRenderer document = new PdfRenderer(fd)) {
      if (document.getPageCount() != expectedCount) {
        throw new AssertionError("Expected " + expectedCount +
          " PDF pages, got " + document.getPageCount());
      }
      try (PdfRenderer.Page page = document.openPage(0)) {
        Bitmap image = Bitmap.createBitmap(480, 680, Bitmap.Config.ARGB_8888);
        try {
          image.eraseColor(Color.WHITE);
          page.render(image, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY);
          int dark = 0;
          for (int y = 0; y < image.getHeight(); y += 2) {
            for (int x = 0; x < image.getWidth(); x += 2) {
              if ((image.getPixel(x,y) & 0x00ffffff) != 0x00ffffff) dark++;
            }
          }
          if (expectedCount == 1 && dark < 120) {
            throw new AssertionError("Text PDF unexpectedly blank, pixels="+dark);
          }
          System.out.println("PASS_ANDROID_PDF_RENDER pages="+expectedCount+
            " pixels_nonwhite="+dark+" width="+image.getWidth()+
            " height="+image.getHeight());
        } finally { image.recycle(); }
      }
    }
  }
}
