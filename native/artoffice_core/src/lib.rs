//! ArtOfficeCraft Mobile native bridge (alpha).
//! FFI is deliberately limited to tested document operations.
//! Source engine: pinned WordCraft 0.14.0.
use std::{panic::{catch_unwind, AssertUnwindSafe}, sync::Arc};
#[cfg(test)]
use std::ptr;
use serde_json::json;
mod word_edit;
mod grid;
mod deck;
mod pdf;
use wordcraft_doc::{Block, CharProps, Document, Paragraph};
const MAX_INPUT_BYTES: usize = 64 * 1024 * 1024;
const MAX_TEXT_BYTES: usize = 4 * 1024 * 1024;

#[repr(C)]
pub struct AcResult {
    /// 0 = success; 1 = user/data error; 2 = internal panic
    pub status: i32,
    pub ptr: *mut u8,
    pub len: usize,
    pub capacity: usize,
}
impl AcResult {
    fn from_vec(status:i32, mut v:Vec<u8>) -> Self {
        let result=Self {status,ptr:v.as_mut_ptr(),len:v.len(),capacity:v.capacity()};
        std::mem::forget(v);
        result
    }
    fn ok(v:Vec<u8>) -> Self { Self::from_vec(0,v) }
    fn err(msg:&str) -> Self { Self::from_vec(1,msg.as_bytes().to_vec()) }
}
fn decode<'a>(ptr:*const u8, len:usize, max:usize)->Result<&'a [u8], String> {
    if len>max {return Err(format!("Buffer too large: {len} bytes"));}
    if len==0 {return Ok(&[]);}
    if ptr.is_null() {return Err("Null input buffer".to_string());}
    // SAFETY: the caller guarantees that ptr points to len readable bytes for this synchronous call.
    Ok(unsafe {std::slice::from_raw_parts(ptr,len)})
}
fn protect<F>(f:F)->AcResult where F:FnOnce()->Result<Vec<u8>,String> {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(bytes))=>AcResult::ok(bytes),
        Ok(Err(message))=>AcResult::err(&message),
        Err(_)=>AcResult::from_vec(2,b"Native document engine panicked".to_vec()),
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn ac_engine_abi_version()->u32 {1}
#[unsafe(no_mangle)]
pub extern "C" fn ac_engine_info()->AcResult {
    protect(||{
        let sources:serde_json::Value=serde_json::from_str(include_str!("../../../upstream/engines.lock.json")).map_err(|e|e.to_string())?;
        serde_json::to_vec(&json!({"abi":1,"coreVersion":env!("CARGO_PKG_VERSION"),"engines":sources["engines"],
            "capabilities":["docx.paragraph.edit","docx.character.format","docx.paragraph.format","xlsx.cell.formula","xlsx.cell.style","pptx.slide.text","pdf.page.organize"]})).map_err(|e|e.to_string())
    })
}

/// A compact JSON preview. It is NOT a layout-preserving DOCX renderer.
#[unsafe(no_mangle)]
pub extern "C" fn ac_docx_inspect(data:*const u8,len:usize)->AcResult {
    protect(||{
        let bytes=decode(data,len,MAX_INPUT_BYTES)?;
        let doc=wordcraft_docx::read(bytes).map_err(|e|format!("DOCX read failed: {e}"))?;
        let mut paragraphs=Vec::<String>::new();
        let mut table_count=0;
        for b in &doc.body {
            match b.as_ref() {
                Block::Para(p)=> paragraphs.push(p.plain_text()),
                Block::Table(_)=>table_count+=1,
            }
        }
        serde_json::to_vec(&json!({
            "type":"docx","engine":"wordcraft","mode":"text_preview",
            "paragraphs":paragraphs,"blocks":word_edit::preview(&doc),"tables":table_count,
            "warnings":["Text preview omits document layout, images, and table contents. Saving via append preserves the parsed WordCraft document model, but round-trip fidelity is not yet validated for all DOCX features."]
        })).map_err(|e|e.to_string())
    })
}

/// Add a real WordCraft paragraph. Returns an entire new DOCX as bytes.
/// The caller must save these bytes to a NEW file before replacing an original.
#[unsafe(no_mangle)]
pub extern "C" fn ac_docx_append_paragraph(
    data:*const u8,len:usize,text:*const u8,text_len:usize
)->AcResult {
    protect(||{
        let bytes=decode(data,len,MAX_INPUT_BYTES)?;
        let text_bytes=decode(text,text_len,MAX_TEXT_BYTES)?;
        let value=std::str::from_utf8(text_bytes).map_err(|_|"Paragraph is not valid UTF-8".to_string())?;
        if value.contains('\0') {return Err("Paragraph contains zero byte".to_string());}
        let mut doc=wordcraft_docx::read(bytes).map_err(|e|format!("DOCX read failed: {e}"))?;
        if doc.settings.protection.is_some() || doc.settings.protect_formatting {return Err("Protected DOCX cannot be edited".into())}
        if doc.settings.track_changes {return Err("Track changes must be resolved in a full editor first".into())}
        let mut p=Paragraph::with_text(value,CharProps::default());
        p.props.align=Some(wordcraft_doc::props::Align::Justify);
        p.props.suppress_hyphens=Some(true);
        doc.body.push(Arc::new(Block::Para(p)));
        wordcraft_docx::write(&doc).map_err(|e|format!("DOCX write failed: {e}"))
    })
}
/// Fresh DOCX with one paragraph, for engine tests and new files.
#[unsafe(no_mangle)]
pub extern "C" fn ac_docx_create(text:*const u8,text_len:usize)->AcResult {
    protect(||{
        let value=std::str::from_utf8(decode(text,text_len,MAX_TEXT_BYTES)?).map_err(|_|"Paragraph is not valid UTF-8".to_string())?;
        let mut doc=Document::new();
        doc.settings.auto_hyphenation=false;
        doc.body.clear();
        let mut p=Paragraph::with_text(value,CharProps::default());
        p.props.align=Some(wordcraft_doc::props::Align::Justify);
        p.props.suppress_hyphens=Some(true);
        doc.body.push(Arc::new(Block::Para(p)));
        wordcraft_docx::write(&doc).map_err(|e|format!("DOCX create failed: {e}"))
    })
}
/// Reclaim a buffer returned by one of ac_docx_* functions exactly once.
#[unsafe(no_mangle)]
pub extern "C" fn ac_result_free(result:AcResult) {
    if result.ptr.is_null() || result.capacity==0 {return;}
    if result.len>result.capacity {return;}
    // SAFETY: only buffers allocated by AcResult::from_vec may be passed here.
    unsafe {drop(Vec::from_raw_parts(result.ptr,result.len,result.capacity));}
}
#[cfg(test)]
mod tests {
    use super::*;
    fn decoded(result:AcResult) -> Result<Vec<u8>,String> {
        let status=result.status;
        let bytes=if result.len==0 {vec![]} else {
            unsafe{std::slice::from_raw_parts(result.ptr,result.len).to_vec()}
        };
        ac_result_free(result);
        if status==0 {Ok(bytes)} else {Err(String::from_utf8_lossy(&bytes).to_string())}
    }
    #[test]
    fn creates_inspects_appends_and_reopens_docx(){
        let first="Первый абзац — ArtOfficeCraft";
        let doc=decoded(ac_docx_create(first.as_ptr(),first.len())).unwrap();
        assert!(doc.starts_with(b"PK"));
        let summary=decoded(ac_docx_inspect(doc.as_ptr(),doc.len())).unwrap();
        let j:serde_json::Value=serde_json::from_slice(&summary).unwrap();
        assert!(j["paragraphs"].as_array().unwrap().iter().any(|p|p.as_str()==Some(first)));
        let appended="Тест второго абзаца";
        let next=decoded(ac_docx_append_paragraph(doc.as_ptr(),doc.len(),appended.as_ptr(),appended.len())).unwrap();
        let reopened=wordcraft_docx::read(&next).unwrap();
        assert!(reopened.body.iter().any(|b|matches!(b.as_ref(),Block::Para(p) if p.text==appended)));
    }
    #[test]
    fn invalid_file_fails_safely(){
        let result=ac_docx_inspect(b"not-docx".as_ptr(),8);
        assert_ne!(result.status,0);
        ac_result_free(result);
    }
    #[test]
    fn null_input_is_rejected(){
        let result=ac_docx_inspect(ptr::null(),40);
        assert_ne!(result.status,0);
        ac_result_free(result);
    }
}
