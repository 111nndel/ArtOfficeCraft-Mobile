//! Bounded PNG recognition through Tesseract's stable C API. No Android/JNI types.
//! The caller supplies only application-owned model and native-library locations.
use std::{ffi::{CStr, CString, c_char, c_int, c_void}, io::Cursor, path::Path, ptr, sync::Mutex};
use serde_json::{Value, json};
use super::{AcResult, decode, protect};

const MAX_IMAGE: usize = 24 * 1024 * 1024;
const MAX_TEXT: usize = 64 * 1024;
static OCR: Mutex<()> = Mutex::new(());
type Handle = *mut c_void;

struct Library(Handle);
impl Library {
    fn open(path: &str) -> Result<Self, String> {
        if !Path::new(path).is_absolute() && !(cfg!(target_os="android") && path == "libtesseract.so") {
            return Err("OCR library must come from the application bundle".into());
        }
        let name = CString::new(path).map_err(|_| "Invalid OCR library path")?;
        // SAFETY: the app supplies the bundled library; name is null terminated.
        let handle = unsafe { loader::open(&name) };
        if handle.is_null() { return Err("Bundled Tesseract library is unavailable".into()); }
        Ok(Self(handle))
    }
    fn symbol<F: Copy>(&self, name: &CStr) -> Result<F, String> {
        // SAFETY: this live library owns all symbols; F is the matching C API type below.
        let address = unsafe { loader::symbol(self.0, name.as_ptr()) };
        if address.is_null() { return Err(format!("Missing OCR symbol {}", name.to_string_lossy())); }
        assert_eq!(std::mem::size_of::<F>(), std::mem::size_of::<Handle>());
        Ok(unsafe { std::mem::transmute_copy(&address) })
    }
}
impl Drop for Library {
    fn drop(&mut self) { unsafe { loader::close(self.0); } }
}

#[cfg(unix)]
mod loader {
    use super::*;
    #[cfg_attr(any(target_os="android", target_os="linux"), link(name="dl"))]
    unsafe extern "C" {
        fn dlopen(path: *const c_char, flags: c_int) -> Handle;
        pub fn dlsym(handle: Handle, name: *const c_char) -> Handle;
        fn dlclose(handle: Handle) -> c_int;
    }
    pub unsafe fn open(path: &CStr) -> Handle { unsafe { dlopen(path.as_ptr(), 2) } } // RTLD_NOW, local symbols.
    pub unsafe fn symbol(handle: Handle, name: *const c_char) -> Handle { unsafe { dlsym(handle, name) } }
    pub unsafe fn close(handle: Handle) { unsafe { dlclose(handle); } }
}
#[cfg(windows)]
mod loader {
    use super::*;
    #[link(name="kernel32")]
    unsafe extern "system" {
        fn LoadLibraryExW(path: *const u16, file: Handle, flags: u32) -> Handle;
        fn GetProcAddress(handle: Handle, name: *const c_char) -> Handle;
        fn FreeLibrary(handle: Handle) -> c_int;
    }
    pub unsafe fn open(path: &CStr) -> Handle {
        let wide: Vec<_> = path.to_string_lossy().encode_utf16().chain([0]).collect();
        unsafe { LoadLibraryExW(wide.as_ptr(), ptr::null_mut(), 0x100 | 0x1000) }
    }
    pub unsafe fn symbol(handle: Handle, name: *const c_char) -> Handle { unsafe { GetProcAddress(handle, name) } }
    pub unsafe fn close(handle: Handle) { unsafe { FreeLibrary(handle); } }
}

macro_rules! api {
    ($($field:ident: $symbol:literal => $kind:ty),+ $(,)?) => {
        struct Api { $($field: $kind,)+ _library: Library }
        impl Api {
            fn load(path: &str) -> Result<Self, String> {
                let library = Library::open(path)?;
                Ok(Self { $($field: library.symbol::<$kind>(CStr::from_bytes_with_nul(concat!($symbol, "\0").as_bytes()).unwrap())?,)+ _library: library })
            }
        }
    }
}
// Signatures from the exact bundled Tesseract 5.5.1 include/tesseract/capi.h.
api! {
    create: "TessBaseAPICreate" => unsafe extern "C" fn() -> Handle,
    delete: "TessBaseAPIDelete" => unsafe extern "C" fn(Handle),
    init: "TessBaseAPIInit2" => unsafe extern "C" fn(Handle, *const c_char, *const c_char, c_int) -> c_int,
    mode: "TessBaseAPISetPageSegMode" => unsafe extern "C" fn(Handle, c_int),
    image: "TessBaseAPISetImage" => unsafe extern "C" fn(Handle, *const u8, c_int, c_int, c_int, c_int),
    recognize: "TessBaseAPIRecognize" => unsafe extern "C" fn(Handle, Handle) -> c_int,
    text: "TessBaseAPIGetUTF8Text" => unsafe extern "C" fn(Handle) -> *mut c_char,
    free_text: "TessDeleteText" => unsafe extern "C" fn(*const c_char),
    iterator: "TessBaseAPIGetIterator" => unsafe extern "C" fn(Handle) -> Handle,
    delete_iterator: "TessResultIteratorDelete" => unsafe extern "C" fn(Handle),
    page_iterator: "TessResultIteratorGetPageIterator" => unsafe extern "C" fn(Handle) -> Handle,
    next: "TessResultIteratorNext" => unsafe extern "C" fn(Handle, c_int) -> c_int,
    word: "TessResultIteratorGetUTF8Text" => unsafe extern "C" fn(Handle, c_int) -> *mut c_char,
    bounds: "TessPageIteratorBoundingBox" => unsafe extern "C" fn(Handle, c_int, *mut c_int, *mut c_int, *mut c_int, *mut c_int) -> c_int,
}
struct Engine { handle: Handle, api: Api }
impl Drop for Engine {
    // Delete the engine before dropping the library containing its destructor.
    fn drop(&mut self) { unsafe { (self.api.delete)(self.handle); } }
}
struct Iterator<'a> { handle: Handle, api: &'a Api }
impl Drop for Iterator<'_> {
    fn drop(&mut self) { unsafe { (self.api.delete_iterator)(self.handle); } }
}
impl Api {
    fn copy_text(&self, text: *mut c_char) -> Result<String, String> {
        if text.is_null() { return Ok(String::new()); }
        // Tesseract owns a documented null-terminated allocation; always free it.
        let result = (|| {
            let bytes = unsafe { CStr::from_ptr(text) }.to_bytes();
            if bytes.len() > MAX_TEXT * 4 { return Err("Too much OCR text".into()); }
            let text = std::str::from_utf8(bytes).map_err(|_| "Invalid OCR UTF-8")?;
            if text.chars().count() > MAX_TEXT { return Err("Too much OCR text".into()); }
            Ok(text.trim().to_owned())
        })();
        unsafe { (self.free_text)(text); }
        result
    }
    fn bbox(&self, page: Handle, level: c_int) -> Option<[i32;4]> {
        let mut b = [0;4];
        let [left,top,right,bottom] = &mut b;
        (unsafe { (self.bounds)(page, level, left,top,right,bottom) } != 0).then_some(b)
    }
}

fn pixels(bytes: &[u8]) -> Result<(Vec<u8>, i32, i32, i32), String> {
    if !bytes.starts_with(b"\x89PNG\r\n\x1a\n") { return Err("Expected OCR PNG".into()); }
    let mut decoder = png::Decoder::new_with_limits(Cursor::new(bytes), png::Limits { bytes: 32 * 1024 * 1024 });
    decoder.set_ignore_text_chunk(true);
    decoder.set_transformations(png::Transformations::EXPAND | png::Transformations::STRIP_16);
    let mut reader = decoder.read_info().map_err(|e| format!("Invalid OCR PNG: {e}"))?;
    let (w,h) = (reader.info().width, reader.info().height);
    if w == 0 || h == 0 || w > 2880 || h > 2880 || u64::from(w)*u64::from(h) > 4_200_000 {
        return Err("OCR image exceeds memory limit".into());
    }
    let size = reader.output_buffer_size().filter(|s| *s <= 4_200_000*4).ok_or("OCR image exceeds memory limit")?;
    let mut buffer = vec![0;size];
    let info = reader.next_frame(&mut buffer).map_err(|e| format!("Invalid OCR pixels: {e}"))?;
    buffer.truncate(info.buffer_size());
    let channels = match info.color_type { png::ColorType::Grayscale => 1, png::ColorType::Rgb => 3, png::ColorType::GrayscaleAlpha => 2, png::ColorType::Rgba => 4, _ => return Err("Unsupported OCR PNG colour".into()) };
    if info.width != w || info.height != h || info.bit_depth != png::BitDepth::Eight || buffer.len() != w as usize*h as usize*channels {
        return Err("OCR PNG frame geometry does not match its pixel buffer".into());
    }
    if channels == 1 || channels == 3 { return Ok((buffer,w as i32,h as i32,channels as i32)); }
    let mut rgb = Vec::with_capacity(w as usize*h as usize*3);
    for p in buffer.chunks_exact(channels) {
        let alpha = u16::from(p[channels-1]);
        for c in 0..3 {
            let value = u16::from(p[if channels == 2 { 0 } else { c }]);
            rgb.push(((value*alpha + 255*(255-alpha) + 127)/255) as u8);
        }
    }
    Ok((rgb,w as i32,h as i32,3))
}

fn recognize(bytes: &[u8], request: &Value) -> Result<Vec<u8>, String> {
    let _serial = OCR.lock().unwrap_or_else(|p| p.into_inner());
    // Decode and validate before loading native code or initializing OCR models.
    let (image,w,h,channels) = pixels(bytes)?;
    let path = request["models"].as_str().ok_or("Missing OCR model directory")?;
    if !Path::new(path).is_absolute() { return Err("OCR models require an absolute application path".into()); }
    for (name,size) in [("eng",4113088),("rus",3861738)] {
        if std::fs::metadata(Path::new(path).join(format!("{name}.traineddata"))).map_err(|_| "OCR model missing")?.len() != size {
            return Err("Invalid OCR model size".into());
        }
    }
    let models = CString::new(path).map_err(|_| "Invalid OCR model directory")?;
    let api = Api::load(request["library"].as_str().ok_or("Missing bundled OCR library")?)?;
    let handle = unsafe { (api.create)() };
    if handle.is_null() { return Err("Cannot create OCR engine".into()); }
    let engine = Engine { handle, api };
    let api = &engine.api;
    // OEM_LSTM_ONLY=1; PSM_AUTO=3. Models, mode and languages match the old adapter.
    if unsafe { (api.init)(handle, models.as_ptr(), c"rus+eng".as_ptr(), 1) } != 0 { return Err("Cannot initialize offline OCR".into()); }
    unsafe {
        (api.mode)(handle,3);
        (api.image)(handle,image.as_ptr(),w,h,channels,w*channels);
        if (api.recognize)(handle,ptr::null_mut()) != 0 { return Err("Cannot recognize image".into()); }
    }
    let text = api.copy_text(unsafe { (api.text)(handle) })?;
    let mut words = Vec::new();
    let iterator = unsafe { (api.iterator)(handle) };
    if !iterator.is_null() {
        let iterator = Iterator { handle: iterator, api };
        let page = unsafe { (api.page_iterator)(iterator.handle) };
        if page.is_null() { return Err("Invalid OCR iterator".into()); }
        let mut characters = 0;
        loop {
            let word = api.copy_text(unsafe { (api.word)(iterator.handle,3) })?;
            if !word.is_empty() {
                characters += word.chars().count();
                if words.len() == 4096 || characters > MAX_TEXT { words.clear(); break; }
                let b = api.bbox(page,3).ok_or("Missing OCR word bounds")?;
                let line = api.bbox(page,2).unwrap_or(b);
                let (l,r,t,b) = (b[0].clamp(0,w),b[2].clamp(0,w),line[1].clamp(0,h),line[3].clamp(0,h));
                if l >= r || t >= b { return Err("Invalid OCR word bounds".into()); }
                words.push(json!({"text":word,"rect":[l as f64/w as f64,t as f64/h as f64,r as f64/w as f64,b as f64/h as f64]}));
            }
            if unsafe { (api.next)(iterator.handle,3) } == 0 { break; }
        }
    }
    // Engine, iterator, text, image and library ownership all end within this call.
    serde_json::to_vec(&json!({"text":text,"words":words})).map_err(|e|e.to_string())
}

#[unsafe(no_mangle)]
pub extern "C" fn ac_image_ocr(data: *const u8, len: usize, request: *const u8, request_len: usize) -> AcResult {
    protect(|| {
        let image = decode(data,len,MAX_IMAGE)?;
        let options: Value = serde_json::from_slice(decode(request,request_len,8192)?).map_err(|_| "Invalid OCR options")?;
        recognize(image,&options)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    fn png(w:u32,h:u32,colour:png::ColorType,data:&[u8]) -> Vec<u8> {
        let mut out=Vec::new();
        { let mut e=png::Encoder::new(&mut out,w,h);e.set_color(colour);e.set_depth(png::BitDepth::Eight);e.write_header().unwrap().write_image_data(data).unwrap(); }
        out
    }
    #[test]
    fn bounded_png_formats_and_white_alpha_compositing() {
        assert!(pixels(b"not PNG").is_err());
        for (colour,data,expected) in [
            (png::ColorType::Rgb,vec![10,20,30],vec![10,20,30]),
            (png::ColorType::Grayscale,vec![80],vec![80]),
            (png::ColorType::Rgba,vec![0,0,0,0],vec![255,255,255]),
            (png::ColorType::GrayscaleAlpha,vec![0,128],vec![127,127,127]),
        ] { assert_eq!(pixels(&png(1,1,colour,&data)).unwrap().0,expected); }
        assert!(pixels(&png(2881,1,png::ColorType::Grayscale,&vec![0;2881])).unwrap_err().contains("memory limit"));
        let image=png(2100,2100,png::ColorType::Grayscale,&vec![255;2100*2100]);
        assert!(recognize(&image,&json!({})).unwrap_err().contains("memory limit"));
    }
    #[test]
    fn malformed_inputs_never_require_tesseract_or_models() {
        for (data,request) in [(b"bad".as_slice(),b"{}".as_slice()),(b"",b"not JSON")] {
            let result=ac_image_ocr(data.as_ptr(),data.len(),request.as_ptr(),request.len());assert_ne!(result.status,0);crate::ac_result_free(result);
        }
        let result=ac_image_ocr(ptr::null(),MAX_IMAGE+1,ptr::null(),0);assert_ne!(result.status,0);crate::ac_result_free(result);
        assert!(Library::open("./user-document.so").is_err());
        assert!(Library::open("/does-not-exist/artofficecraft-tesseract.so").is_err());
    }
}
