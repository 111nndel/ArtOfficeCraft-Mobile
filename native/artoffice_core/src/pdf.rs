//! PDFCraft 0.17.0 COS + model integration. Limited page-structure edits.
//! We deliberately avoid the unbuildable upstream pdfcraft-organize crate in v0.17.0.
use std::sync::Arc;
use pdfcraft_cos::{Document,Dict,Object,SaveOptions,write_full};
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
        serde_json::to_vec(&json!({
            "type":"pdf","engine":"pdfcraft-cos-model","pageCount":meta.len(),
            "pages":meta,
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
}
