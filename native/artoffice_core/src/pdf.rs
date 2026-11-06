//! Pinned PDFCraft page structure, annotations and text edits.
//! Navigation reads the upstream outline without executing bookmark actions.
use std::{fmt::Write as _, sync::Arc};
use pdfcraft_annot::{Meta, NewAnnotation, NoteIcon, Shape, Style, add_annotation};
use pdfcraft_cos::{Document,Dict,Object,SaveOptions,write_full};
use pdfcraft_edit::{BlockStyle, TextBlock, TextSession, stamp, text::register_text_font, text_blocks};
use pdfcraft_fonts::{document_latin_fonts, embedding::covers, pdf::Metrics, wrap_with};
use pdfcraft_model::{pages,Page};
use serde_json::{json,Value as J};
use super::{AcResult,decode,protect,MAX_INPUT_BYTES,MAX_TEXT_BYTES};

fn parse(data:&[u8])->Result<Document,String>{
    if !data.starts_with(b"%PDF-"){return Err("Expected PDF header %PDF-".into());}
    Document::open(Arc::new(data.to_vec())).map_err(|e|format!("PDFCraft open: {e}"))
}
fn save(doc:&Document)->Result<Vec<u8>,String>{
    let out=write_full(doc,&SaveOptions::default())
        .map_err(|e|format!("PDFCraft write: {e}"))?;
    if out.len()>MAX_INPUT_BYTES{return Err("PDF output larger than 64 MiB".into());}
    let reread=parse(&out)?;
    if pages(&reread).is_empty(){return Err("Saved PDF has no readable pages".into());}
    Ok(out)
}
fn index_page(doc:&Document,index:usize)->Result<Page,String>{
    pages(doc).get(index).cloned().ok_or("PDF page not found".into())
}
/// Replace a possibly nested page tree with a flat tree, preserving effective
/// inherited attributes on every page. No attempt to fix complex form/bookmark
/// semantics; do not assume full fidelity for such files.
fn set_order(doc:&mut Document,sequence:&[Page])->Result<(),String>{
    if sequence.is_empty(){return Err("Cannot remove all PDF pages".into());}
    let catalog=doc.root().ok_or("No PDF Catalog")?;
    let root=doc.get(catalog).as_dict()
        .and_then(|d|d.reference(b"Pages")).ok_or("No PDF page-tree root")?;
    for page in sequence {
        let mut attrs=page.dict.clone();
        let original=page.obj;
        attrs.set(b"Parent".to_vec(),Object::Ref(root));
        doc.update_dict(original,|d|{
            for k in [b"Resources".as_slice(),b"MediaBox",b"CropBox",b"Rotate"] {
                if !d.contains(k) {
                    if let Some(value)=attrs.get(k) {d.set(k.to_vec(),value.clone());}
                }
            }
            d.set(b"Parent".to_vec(),Object::Ref(root));
        }).map_err(|e|format!("Cannot update PDF page: {e}"))?;
    }
    doc.update_dict(root,|d|{
        d.set(b"Type".to_vec(),Object::name("Pages"));
        d.set(b"Kids".to_vec(),Object::Array(sequence.iter().map(|p|Object::Ref(p.obj)).collect()));
        d.set(b"Count".to_vec(),Object::Int(sequence.len() as i64));
        for key in [b"Resources".as_slice(),b"MediaBox",b"CropBox",b"Rotate",b"Parent"]{d.remove(key);}
    }).map_err(|e|format!("Cannot update PDF page tree: {e}"))?;
    Ok(())
}
fn blank_page(doc:&mut Document,width:f64,height:f64)->Page{
    let mut d=Dict::new();
    d.set(b"Type".to_vec(),Object::name("Page"));
    d.set(b"MediaBox".to_vec(),Object::Array(vec![
        Object::Int(0),Object::Int(0),Object::Real(width),Object::Real(height)
    ]));
    d.set(b"Resources".to_vec(),Object::Dict(Dict::new()));
    let obj=doc.add(d.clone());
    Page{obj,dict:d}
}

fn text_notes(doc: &Document, all: &[Page]) -> Vec<J> {
    let mut notes = Vec::new();
    for (page, source) in all.iter().enumerate() {
        let Some(entries) = source.dict.get(b"Annots").map(|value| doc.resolve(value)) else { continue };
        let Some(entries) = entries.as_array() else { continue };
        for entry in entries.iter().take(4096) {
            let item = doc.resolve(entry);
            let Some(dict) = item.as_dict() else { continue };
            if dict.name(b"Subtype") != Some(b"Text") { continue; }
            let Some(value) = dict.get(b"Contents").map(|value| doc.resolve(value)) else { continue };
            let Some(text) = value.as_string().filter(|text| text.bytes.len() <= 16 * 1024) else { continue };
            notes.push(json!({"page":page,"text":text.to_text()}));
            if notes.len() == 1024 { return notes; }
        }
    }
    notes
}

const MAX_TEXT_BLOCKS: usize = 256;
const MAX_BLOCK_BYTES: usize = 16 * 1024;

fn editable_block(block: &TextBlock) -> bool {
    !block.invisible
        && !block.editor_text.trim().is_empty()
        && block.editor_text.len() <= MAX_BLOCK_BYTES
        && block.editor_text.chars().count() <= 4096
        && !block.editor_text.contains('\u{fffd}')
}

fn insert_text(doc: &mut Document, page: &Page, index: usize, request: &J) -> Result<(), String> {
    if doc.permissions().is_some_and(|permission| !permission.modify()) {
        return Err("This PDF restricts content editing".into());
    }
    let text = request["text"].as_str().map(str::trim)
        .filter(|text| !text.is_empty() && text.len() <= 4000 && text.chars().count() <= 1000
            && !text.chars().any(|c| c.is_control() && !matches!(c, '\n' | '\r')))
        .ok_or("Expected text up to 1000 characters")?;
    let coordinate = |key| request[key].as_f64().filter(|n| (0.0..=1.0).contains(n))
        .ok_or("Choose a position inside the PDF page");
    let size = request["size"].as_f64().filter(|n| (8.0..=72.0).contains(n))
        .ok_or("Invalid PDF text size")?;
    let (width, height) = page.display_size(doc);
    if ![width, height].iter().all(|n| n.is_finite() && *n > 0.0 && *n <= 10_000_000.0) {
        return Err("Invalid PDF page dimensions".into());
    }
    let left = coordinate("x")? * width;
    let top = (1.0 - coordinate("y")?) * height;
    let available = width - left - 2.0;
    let no_room = "The text does not fit here. Choose another position or a smaller size.";
    if available < size || top < size {
        return Err(no_room.into());
    }
    let face = document_latin_fonts(false).into_iter().find(|face| covers(face.bytes, text))
        .ok_or("The PDF insertion font does not support all characters in this text")?;
    let name = register_text_font(doc, index, face.bytes).map_err(|err| err.to_string())?;
    let installed = doc.get(page.obj);
    let resources = installed.as_dict().and_then(|d| d.get(b"Resources"))
        .and_then(|o| doc.dict(o)).ok_or("Missing PDF page resources")?;
    let fonts = resources.get(b"Font").and_then(|o| doc.dict(o))
        .ok_or("Missing PDF page fonts")?;
    let font = fonts.get(name.as_bytes()).and_then(|o| doc.dict(o))
        .ok_or("Missing embedded PDF text font")?;
    let metrics = Metrics::from_dict(doc, &font);
    let advance = |bytes: &[u8]| metrics.codes(bytes).into_iter()
        .map(|(code, _)| metrics.width(code) * size).sum::<f64>();
    let lines = wrap_with(text, size, available, |s, _| {
        metrics.encode(s).map_or(f64::INFINITY, |bytes| advance(&bytes))
    });
    let leading = size * 1.25;
    let first_baseline = top - metrics.ascent * size;
    if first_baseline - leading * lines.len().saturating_sub(1) as f64 + metrics.descent * size < 1.0 {
        return Err(no_room.into());
    }
    let matrix = page.view_matrix(doc).map(|n| format!("{n:.9}")).join(" ");
    let mut content = format!("q\n{matrix} cm\n0 g\nBT /{name} {size:.4} Tf\n");
    for (i, line) in lines.iter().enumerate() {
        let bytes = metrics.encode(line).ok_or("Could not encode the inserted PDF text")?;
        if advance(&bytes) > available + 0.001 {
            return Err(no_room.into());
        }
        let baseline = first_baseline - leading * i as f64;
        write!(content, "1 0 0 1 {left:.6} {baseline:.6} Tm\n<").map_err(|e| e.to_string())?;
        for byte in bytes {
            write!(content, "{byte:02X}").map_err(|e| e.to_string())?;
        }
        content.push_str("> Tj\n");
    }
    content.push_str("ET\nQ\n");
    stamp(doc, index, "AOCText", content.into_bytes()).map_err(|err| err.to_string())?;
    // stamp adds a standard Helvetica resource for marks. This stream only uses
    // Inter, so restore the pre-stamp dictionary, including any existing PCHelv.
    doc.update_dict(page.obj, |d| d.set(b"Resources".to_vec(), Object::Dict(resources)))
        .map_err(|err| err.to_string())
}

#[unsafe(no_mangle)]
pub extern "C" fn ac_pdf_text_blocks(data: *const u8, len: usize, page: usize) -> AcResult {
    protect(|| {
        let doc = parse(decode(data, len, MAX_INPUT_BYTES)?)?;
        if doc.permissions().is_some_and(|permission| !permission.modify()) {
            return Err("This PDF restricts content editing".into());
        }
        let blocks = text_blocks(&doc, page).map_err(|err| err.to_string())?;
        let mut visible = blocks.iter().enumerate().filter(|(_, block)| editable_block(block));
        let items: Vec<J> = visible.by_ref().take(MAX_TEXT_BLOCKS)
            .map(|(id, block)| json!({"id":id,"text":block.editor_text}))
            .collect();
        serde_json::to_vec(&json!({"blocks":items,"limited":visible.next().is_some()}))
            .map_err(|err| err.to_string())
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn ac_pdf_create(_: *const u8,_:usize)->AcResult{
    protect(||{
        let mut doc=Document::new_empty();
        let page=blank_page(&mut doc,595.0,842.0);
        set_order(&mut doc,&[page])?;
        save(&doc)
    })
}
#[unsafe(no_mangle)]
pub extern "C" fn ac_pdf_inspect(data:*const u8,n:usize)->AcResult{
    protect(||{
        let doc=parse(decode(data,n,MAX_INPUT_BYTES)?)?;
        let all=pages(&doc);
        if all.is_empty(){return Err("PDF contains no accessible pages".into());}
        if all.len()>10000 {return Err("PDF preview limited to 10000 pages".into());}
        let meta:Vec<J>=all.iter().enumerate().map(|(i,p)|{
            let (w,h)=p.display_size(&doc);
            json!({"index":i,"width":w,"height":h,"rotation":p.rotation(&doc)})
        }).collect();
        let outline = pdfcraft_organize::bookmark_page(&doc, 0, 4096);
        let bookmarks: Vec<J> = outline.bookmarks.into_iter().map(|entry| json!({
            "title": entry.title.chars().take(512).collect::<String>(),
            "page": entry.page.filter(|&page| page < all.len()),
            "depth": entry.path.len().saturating_sub(1),
        })).collect();
        serde_json::to_vec(&json!({
            "type":"pdf","engine":"pdfcraft-cos-model","pageCount":meta.len(),
            "pages":meta,
            "bookmarks":bookmarks,
            "notes":text_notes(&doc, &all),
            "outlineLimited":outline.next.is_some(),
            "warnings":[
                "Page contents are not rendered in this preview.",
                "Structure edits to complex PDF may alter forms, bookmarks, annotations or metadata.",
                "Digital signatures are invalidated by editing and re-saving."
            ]
        })).map_err(|e|e.to_string())
    })
}
#[unsafe(no_mangle)]
pub extern "C" fn ac_pdf_edit(data:*const u8,n:usize,req:*const u8,req_len:usize)->AcResult{
    protect(||{
        let input=decode(data,n,MAX_INPUT_BYTES)?;
        let text=std::str::from_utf8(decode(req,req_len,MAX_TEXT_BYTES)?)
            .map_err(|_|"Invalid PDF request encoding")?;
        let j:J=serde_json::from_str(text).map_err(|e|format!("Invalid PDF JSON: {e}"))?;
        let action=j.get("action").and_then(J::as_str).ok_or("Missing action")?;
        let index=j.get("page").and_then(J::as_u64)
            .and_then(|n|usize::try_from(n).ok()).ok_or("Missing or invalid page")?;
        let mut doc=parse(input)?;
        let mut all=pages(&doc);
        if all.len()>10000{return Err("PDF too many pages".into());}
        if index>=all.len(){return Err("PDF page out of range".into());}
        match action {
            "insert_text" => insert_text(&mut doc, &all[index], index, &j)?,
            "replace_text_block" => {
                if doc.permissions().is_some_and(|permission| !permission.modify()) {
                    return Err("This PDF restricts content editing".into());
                }
                let id = j["block"].as_u64().and_then(|n| usize::try_from(n).ok())
                    .ok_or("Missing PDF text block")?;
                let text = j["text"].as_str().filter(|text| {
                    !text.trim().is_empty() && text.len() <= MAX_BLOCK_BYTES
                        && text.chars().count() <= 4096
                        && !text.chars().any(|c| c.is_control() && !matches!(c, '\n' | '\r' | '\t'))
                }).ok_or("Expected PDF text up to 4096 characters")?;
                let session = TextSession::open(&doc, index, id).map_err(|err| err.to_string())?;
                let source = session.source();
                if !editable_block(source) || j["original"].as_str() != Some(&source.editor_text) {
                    return Err("The selected PDF text is unavailable or has changed".into());
                }
                if source.editor_text == text {
                    return Ok(input.to_vec());
                }
                session.commit(&mut doc, Some(text), &BlockStyle::default())
                    .map_err(|err| err.to_string())?;
            },
            "add_note" => {
                let text = j["text"].as_str().map(str::trim)
                    .filter(|text| !text.is_empty() && text.len() <= 4096 && !text.contains('\0'))
                    .ok_or("Expected a non-empty PDF note up to 4096 bytes")?;
                let [left, bottom, right, top] = all[index].crop(&doc);
                let margin = 12.0_f64.min((right-left).abs()/4.0).min((top-bottom).abs()/4.0);
                let shape = Shape::Note { at: [left+margin, top-margin], icon: NoteIcon::Comment };
                let note = NewAnnotation {
                    page: index,
                    style: Style::default_for(&shape),
                    shape,
                    contents: text.to_owned(),
                    author: String::new(),
                };
                add_annotation(&mut doc, &note, &Meta::default()).map_err(|err| err.to_string())?;
            },
            "rotate_cw"|"rotate_ccw"=>{
                let p=index_page(&doc,index)?;
                let old=p.rotation(&doc);
                let offset=if action=="rotate_cw"{90}else{-90};
                let rotate=(old+offset).rem_euclid(360);
                doc.update_dict(p.obj,|d|d.set(b"Rotate".to_vec(),Object::Int(rotate)))
                    .map_err(|e|format!("Page rotation failed: {e}"))?;
            },
            "insert_blank"=>{
                if all.len()>=10000{return Err("Page limit reached".into());}
                let page=blank_page(&mut doc,595.0,842.0);
                all.insert(index+1,page);
                set_order(&mut doc,&all)?;
            },
            "duplicate"=>{
                if all.len()>=10000{return Err("Page limit reached".into());}
                let page=all[index].clone();
                // Refuse duplication when annotations, structure tagging or
                // forms could make shared references point at wrong pages.
                if [b"Annots".as_slice(),b"StructParents",b"Tabs",b"AA"]
                    .iter().any(|k|page.dict.contains(k)) {
                    return Err("Complex page duplication unsupported (annotations or tagging)".into());
                }
                let mut dictionary=page.dict.clone();
                dictionary.remove(b"Parent");
                let ref_id=doc.add(dictionary.clone());
                all.insert(index+1,Page{obj:ref_id,dict:dictionary});
                set_order(&mut doc,&all)?;
            },
            "delete"=>{
                if all.len()<=1{return Err("Cannot delete the last PDF page".into());}
                if all[index].dict.contains(b"Annots"){
                    return Err("Deleting pages with annotations is not yet supported".into());
                }
                all.remove(index);
                set_order(&mut doc,&all)?;
            },
            "move_to"=>{
                let target=j.get("to").and_then(J::as_u64).and_then(|n|usize::try_from(n).ok()).ok_or("Missing target page")?;
                if target>=all.len() {return Err("Target page out of range".into())}
                let page=all.remove(index);all.insert(target,page);set_order(&mut doc,&all)?;
            },
            "move_up"=>{
                if index==0{return Err("Page already first".into());}
                all.swap(index,index-1);set_order(&mut doc,&all)?;
            },
            "move_down"=>{
                if index+1>=all.len(){return Err("Page already last".into());}
                all.swap(index,index+1);set_order(&mut doc,&all)?;
            },
            _=>return Err(format!("Unsupported PDF action: {action}")),
        }
        save(&doc)
    })
}
#[cfg(test)]
mod tests{
    use super::*;
    fn result(r:AcResult)->Result<Vec<u8>,String>{
        let data=if r.len==0 {Vec::new()}else{unsafe{std::slice::from_raw_parts(r.ptr,r.len).to_vec()}};
        let code=r.status;
        super::super::ac_result_free(r);
        if code==0{Ok(data)}else{Err(String::from_utf8_lossy(&data).into_owned())}
    }
    fn edit(input:&[u8],action:&str,page:usize)->Vec<u8>{
        let s=json!({"action":action,"page":page}).to_string();
        result(ac_pdf_edit(input.as_ptr(),input.len(),s.as_ptr(),s.len())).unwrap()
    }
    #[test]
    fn pdf_create_duplicate_rotate_move_insert_delete(){
        let a=result(ac_pdf_create(std::ptr::null(),0)).unwrap();
        assert!(a.starts_with(b"%PDF-"));
        let b=edit(&a,"duplicate",0);
        assert_eq!(pages(&parse(&b).unwrap()).len(),2);
        let c=edit(&b,"rotate_cw",0);
        let doc=parse(&c).unwrap();
        assert_eq!(pages(&doc)[0].rotation(&doc),90);
        let e=edit(&c,"move_down",0);
        let d=parse(&e).unwrap();
        assert_eq!(pages(&d)[1].rotation(&d),90);
        let f=edit(&e,"insert_blank",1);
        assert_eq!(pages(&parse(&f).unwrap()).len(),3);
        let g=edit(&f,"delete",2);
        let info=result(ac_pdf_inspect(g.as_ptr(),g.len())).unwrap();
        let value:J=serde_json::from_slice(&info).unwrap();
        assert_eq!(value["pageCount"],2);
    }
    #[test]
    fn reject_invalid_and_last_page_removal(){
        assert!(result(ac_pdf_inspect(b"garbage".as_ptr(),7)).is_err());
        let one=result(ac_pdf_create(std::ptr::null(),0)).unwrap();
        let s=json!({"action":"delete","page":0}).to_string();
        assert!(result(ac_pdf_edit(one.as_ptr(),one.len(),s.as_ptr(),s.len())).is_err());
    }

    #[test]
    fn direct_page_move_keeps_rotation_and_geometry() {
        let one=result(ac_pdf_create(std::ptr::null(),0)).unwrap();
        let two=edit(&one,"insert_blank",0);
        let three=edit(&two,"insert_blank",1);
        let rotated=edit(&three,"rotate_cw",0);
        let request=json!({"action":"move_to","page":0,"to":2}).to_string();
        let moved=result(ac_pdf_edit(rotated.as_ptr(),rotated.len(),request.as_ptr(),request.len())).unwrap();
        let doc=parse(&moved).unwrap();let all=pages(&doc);
        assert_eq!(all.len(),3);assert_eq!(all[2].rotation(&doc),90);assert_eq!(all[0].rotation(&doc),0);
        let request=json!({"action":"move_to","page":0,"to":3}).to_string();
        assert!(result(ac_pdf_edit(rotated.as_ptr(),rotated.len(),request.as_ptr(),request.len())).is_err());
        let original=parse(&rotated).unwrap();assert_eq!(pages(&original)[0].rotation(&original),90);
    }

    #[test]
    fn inspection_reports_local_bookmark_destinations_in_page_order() {
        let initial = result(ac_pdf_create(std::ptr::null(), 0)).unwrap();
        let two = edit(&initial, "insert_blank", 0);
        let mut doc = parse(&two).unwrap();
        pdfcraft_organize::add_bookmark(&mut doc, &[], 0, "Вторая страница", 1).unwrap();
        let bytes = save(&doc).unwrap();
        let info = result(ac_pdf_inspect(bytes.as_ptr(), bytes.len())).unwrap();
        let value: J = serde_json::from_slice(&info).unwrap();
        assert_eq!(value["bookmarks"], json!([
            {"title":"Вторая страница","page":1,"depth":0}
        ]));
    }
}
