//! Owned, bounded PDF raster sessions. Tokens are IDs, never caller pointers.
//! Dart's existing worker serializes calls; the mutex also covers other FFI callers
//! and does not assume that an isolate stays on one operating-system thread.
use std::{collections::BTreeMap, sync::{Arc, Mutex, OnceLock}};
use pdfcraft_render::{PageRenderer, RenderConfig, RenderRequest, RequestKind};
use serde_json::{Value, json};
use super::{AcResult, MAX_INPUT_BYTES, decode, protect};

struct Session {
    renderer: PageRenderer,
    sizes: Vec<(f64, f64)>,
}
#[derive(Default)]
struct Sessions { next: u64, documents: BTreeMap<u64, Session> }
static SESSIONS: OnceLock<Mutex<Sessions>> = OnceLock::new();

fn integer(request: &Value, field: &str) -> Result<u64, String> {
    request[field].as_u64().ok_or_else(|| format!("Invalid PDF raster {field}"))
}

/// JSON commands: open (PDF input), page (session/page/width), close (session).
/// Open returns {session,pageCount}; page returns a white-composited RGB PNG.
/// Two sessions permit an atomic replacement: open new, then close old.
#[unsafe(no_mangle)]
pub extern "C" fn ac_pdf_render(data: *const u8, len: usize, request: *const u8, request_len: usize) -> AcResult {
    protect(|| {
        let bytes = decode(data, len, MAX_INPUT_BYTES)?;
        let request: Value = serde_json::from_slice(decode(request, request_len, 1024)?)
            .map_err(|e| format!("Invalid PDF raster request: {e}"))?;
        let mut sessions = SESSIONS.get_or_init(|| Mutex::new(Sessions::default()))
            .lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        match request["op"].as_str() {
            Some("open") => {
                if sessions.documents.len() >= 2 { return Err("Close an existing PDF raster session first".into()); }
                if !bytes.starts_with(b"%PDF-") { return Err("Expected PDF header %PDF-".into()); }
                let shared = Arc::new(bytes.to_vec());
                let doc = pdfcraft_cos::Document::open(shared.clone()).map_err(|e| e.to_string())?;
                let pages = pdfcraft_model::pages(&doc);
                if pages.is_empty() || pages.len() > 10000 { return Err("Invalid PDF raster page count".into()); }
                let sizes: Vec<_> = pages.iter().map(|p| p.display_size(&doc)).collect();
                if sizes.iter().any(|(w,h)| !w.is_finite() || !h.is_finite() || *w <= 0.0 || *h <= 0.0 || *w > 1e6 || *h > 1e6) {
                    return Err("Invalid PDF page geometry".into());
                }
                drop(doc);
                let renderer = PageRenderer::new(shared, RenderConfig { reject_oversize: true, ..RenderConfig::default() });
                if renderer.page_count() != sizes.len() { return Err("PDF raster page-tree mismatch".into()); }
                let count = sizes.len();
                let id = sessions.next.checked_add(1).filter(|id| *id <= i64::MAX as u64).ok_or("PDF session IDs exhausted")?;
                sessions.next = id;
                sessions.documents.insert(id, Session { renderer, sizes });
                serde_json::to_vec(&json!({"session":id,"pageCount":count})).map_err(|e| e.to_string())
            }
            Some("close") => {
                sessions.documents.remove(&integer(&request,"session")?);
                Ok(Vec::new())
            }
            Some("page") => {
                let id = integer(&request,"session")?;
                let page = usize::try_from(integer(&request,"page")?).map_err(|_| "PDF page index overflow")?;
                let width = integer(&request,"width")?;
                if !(96..=1600).contains(&width) { return Err("PDF raster width must be 96..1600".into()); }
                let session = sessions.documents.get_mut(&id).ok_or("PDF raster session is closed")?;
                let &(w,h) = session.sizes.get(page).ok_or("PDF page not found")?;
                // Bound allocations before asking the renderer for pixels.
                let scale = (width as f64 / w).min(2880.0 / h).min((4_200_000.0 / (w*h)).sqrt()) as f32;
                let rendered = session.renderer.render(RenderRequest {
                    page, kind: RequestKind::Pixels, tile: None, scale, tag: id, preview: false,
                });
                if let Some(error) = rendered.error { return Err(error); }
                if !rendered.warnings.is_empty() { return Err(format!("Incomplete PDF raster: {:?}", rendered.warnings)); }
                let pixels = (rendered.width as usize).checked_mul(rendered.height as usize).ok_or("Raster size overflow")?;
                if pixels == 0 || pixels > 4_200_000 || rendered.width > 2880 || rendered.height > 2880 || rendered.rgba.len() != pixels*4 {
                    return Err("Invalid or oversized PDF raster".into());
                }
                let mut rgb = Vec::with_capacity(pixels*3);
                for p in rendered.rgba.chunks_exact(4) {
                    let white = 255-p[3];
                    rgb.extend_from_slice(&[p[0].saturating_add(white),p[1].saturating_add(white),p[2].saturating_add(white)]);
                }
                let mut png = Vec::new();
                {
                    let mut encoder = png::Encoder::new(&mut png, rendered.width, rendered.height);
                    encoder.set_color(png::ColorType::Rgb);
                    encoder.set_depth(png::BitDepth::Eight);
                    let mut writer = encoder.write_header().map_err(|e| e.to_string())?;
                    writer.write_image_data(&rgb).map_err(|e| e.to_string())?;
                    writer.finish().map_err(|e| e.to_string())?;
                }
                Ok(png)
            }
            _ => Err("Unknown PDF raster operation".into()),
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    fn take(result: AcResult) -> Result<Vec<u8>, String> {
        let status = result.status;
        let bytes = if result.len == 0 { vec![] } else { unsafe { std::slice::from_raw_parts(result.ptr,result.len).to_vec() } };
        crate::ac_result_free(result);
        if status == 0 { Ok(bytes) } else { Err(String::from_utf8_lossy(&bytes).into_owned()) }
    }
    fn call(bytes: &[u8], request: Value) -> Result<Vec<u8>, String> {
        let request = serde_json::to_vec(&request).unwrap();
        take(ac_pdf_render(bytes.as_ptr(),bytes.len(),request.as_ptr(),request.len()))
    }
    #[test]
    fn raster_lifecycle_limits_and_cross_thread_ownership() {
        let pdf = take(crate::pdf::ac_pdf_create(std::ptr::null(),0)).unwrap();
        assert!(call(b"not a PDF",json!({"op":"open"})).is_err());
        let first: Value = serde_json::from_slice(&call(&pdf,json!({"op":"open"})).unwrap()).unwrap();
        let id = first["session"].as_u64().unwrap();
        assert_eq!(first["pageCount"],1);
        // This must work from a different OS thread, not only an isolate's first thread.
        let png = std::thread::spawn(move || call(&[],json!({"op":"page","session":id,"page":0,"width":600})).unwrap()).join().unwrap();
        assert!(png.starts_with(b"\x89PNG\r\n\x1a\n"));
        assert_eq!(u32::from_be_bytes(png[16..20].try_into().unwrap()),600);
        for request in [json!({"op":"page","session":id,"page":-1,"width":600}),json!({"op":"page","session":id,"page":1,"width":600}),json!({"op":"page","session":id,"page":0,"width":1601}),json!({"op":"bogus"})] { assert!(call(&[],request).is_err()); }
        let second: Value = serde_json::from_slice(&call(&pdf,json!({"op":"open"})).unwrap()).unwrap();
        assert!(call(&pdf,json!({"op":"open"})).is_err());
        for session in [id,second["session"].as_u64().unwrap(),id] { call(&[],json!({"op":"close","session":session})).unwrap(); }
        assert!(call(&[],json!({"op":"page","session":id,"page":0,"width":600})).is_err());
        assert!(take(ac_pdf_render(std::ptr::null(),0,std::ptr::null(),1025)).is_err());
    }
}
