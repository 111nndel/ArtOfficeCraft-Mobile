//! Minimal Android DeckCraft PPTX integration. No fabricated document operations.
use std::sync::Arc;
use deckcraft_model::{
    defaults, LayoutType, Presentation, Shape, ShapeId, TextBody, Xfrm,
};
use serde_json::{json, Value as J};
use super::{AcResult, decode, protect, MAX_INPUT_BYTES, MAX_TEXT_BYTES};

fn load(bytes: &[u8]) -> Result<Presentation, String> {
    deckcraft_pptx::import(bytes).map_err(|e| format!("PPTX read failed: {e}"))
}
fn save(p: &Presentation) -> Result<Vec<u8>, String> {
    let problems = p.validate();
    if !problems.is_empty() {
        return Err(format!("PPTX model inconsistency: {}",problems.join("; ")));
    }
    deckcraft_pptx::export(p).map_err(|e| format!("PPTX write failed: {e}"))
}
fn decode_request<'a>(ptr:*const u8, n:usize)->Result<&'a str,String>{
    std::str::from_utf8(decode(ptr,n,MAX_TEXT_BYTES)?)
      .map_err(|_|"Invalid edit request UTF-8".to_string())
}
fn add_text(p: &mut Presentation, index:usize, text:&str, is_title:bool)->Result<u32,String>{
    if text.len()>64*1024 {return Err("Text exceeds 64 KiB".into())}
    if index>=p.slides.len(){return Err("Slide index out of bounds".into())}
    if p.slides[index].shapes.len()>=5000 {return Err("Slide contains too many shapes".into())}
    let id=p.alloc_id().ok_or("No free shape identifier")?;
    let w=p.slide_size.width;
    let h=p.slide_size.height;
    let shape=Shape {
        id: ShapeId(id),
        name: if is_title {"Title"} else {"Text Box"}.into(),
        text: Some(TextBody::from_text(text)),
        text_box: true,
        xfrm:Some(if is_title {
            Xfrm::new(w*0.08,h*0.1,w*0.83,h*0.18)
        } else {
            Xfrm::new(w*0.08,h*0.31,w*0.82,h*0.49)
        }),
        ..Default::default()
    };
    Arc::make_mut(&mut p.slides[index]).shapes.push(shape);
    Ok(id)
}
#[unsafe(no_mangle)]
pub extern "C" fn ac_pptx_create(_: *const u8, _:usize)->AcResult {
    protect(||save(&Presentation::default()))
}
#[unsafe(no_mangle)]
pub extern "C" fn ac_pptx_inspect(data:*const u8,n:usize)->AcResult {
    protect(||{
        let bytes=decode(data,n,MAX_INPUT_BYTES)?;
        let presentation=load(bytes)?;
        let mut slides=Vec::new();
        for (i,slide) in presentation.slides.iter().enumerate() {
            let shapes:Vec<J>=slide.shapes.iter().take(120).map(|shape|{
                let rect=shape.xfrm.as_ref().map(|r|json!({
                    "x":r.x,"y":r.y,"w":r.w,"h":r.h,
                }));
                let fill_rgb=shape.fill.as_ref().and_then(|f|match f {
                    deckcraft_model::style::Fill::Solid{color}=>match &color.base {
                        deckcraft_model::style::ColorBase::Rgb{rgb}=>Some(format!("#{}",rgb.hex())),
                        deckcraft_model::style::ColorBase::System{last,..}=>Some(format!("#{}",last.hex())),
                        _=>None,
                    },
                    _=>None,
                });
                let stroke_rgb=shape.line.as_ref().and_then(|line|line.fill.as_ref())
                    .and_then(|f|match f {
                        deckcraft_model::style::Fill::Solid{color}=>match &color.base {
                            deckcraft_model::style::ColorBase::Rgb{rgb}=>Some(format!("#{}",rgb.hex())),
                            _=>None,
                        },
                        _=>None,
                    });
                let geometry=serde_json::to_value(&shape.geom).unwrap_or(J::Null);
                json!({
                    "id":shape.id.0,
                    "name":shape.name,
                    "kind":shape.kind_name(),
                    "geometry":geometry,
                    "fillRgb":fill_rgb,
                    "strokeRgb":stroke_rgb,
                    "text":shape.text.as_ref().map(|t|t.text()).unwrap_or_default(),
                    "rect":rect,
                    "editableText":shape.text.is_some() && !shape.locked,
                })
            }).collect();
            slides.push(json!({
                "index":i, "id":slide.id.0, "title":slide.title(),
                "name":slide.name, "shapes":shapes,
                "shapeCount":slide.shapes.len(),
                "truncated":slide.shapes.len()>120,
            }));
        }
        serde_json::to_vec(&json!({
            "type":"pptx","engine":"deckcraft",
            "width":presentation.slide_size.width,"height":presentation.slide_size.height,
            "slides":slides,
            "warnings":["Simplified text, rectangular graphics, direct RGB fills/strokes and position preview only. Imported images, groups, charts, SmartArt, fonts, animations and exact PowerPoint layout are not rendered. DOCX-like round-trip fidelity not guaranteed for complex PPTX files."]
        })).map_err(|e|e.to_string())
    })
}
/// JSON action: add_slide/title, add_text/slide/text, edit_text/slide/shape/text, delete_slide/slide.
#[unsafe(no_mangle)]
pub extern "C" fn ac_pptx_edit(data:*const u8,n:usize, request:*const u8, req_len:usize)->AcResult {
    protect(||{
        let bytes=decode(data,n,MAX_INPUT_BYTES)?;
        let value:J=serde_json::from_str(decode_request(request,req_len)?)
            .map_err(|e|format!("Invalid PPTX edit JSON: {e}"))?;
        let action=value.get("action").and_then(J::as_str).ok_or("Missing action")?;
        let index=value.get("slide").and_then(J::as_u64).unwrap_or(0) as usize;
        let text=value.get("text").and_then(J::as_str).unwrap_or_default();
        if text.len()>64*1024 {return Err("Slide text exceeds 64 KiB".into())}
        let mut p=load(bytes)?;
        match action {
            "add_slide"=>{
                if p.slides.len()>=256 {return Err("Preview supports at most 256 slides".into())}
                let layout=defaults::layout_of_kind(&p,LayoutType::Blank)
                    .or_else(||p.slides.first().map(|s|s.layout))
                    .ok_or("Presentation has no valid layout")?;
                let new=defaults::new_slide(&mut p,layout)
                    .ok_or("Could not allocate slide")?;
                p.slides.push(Arc::new(new));
                if !text.is_empty() {
                    let i=p.slides.len()-1;
                    add_text(&mut p,i,text,true)?;
                }
            },
            "add_text"=>{
                if p.slides.get(index).is_none(){return Err("Slide index out of bounds".into())}
                if text.trim().is_empty() {return Err("Text must not be empty".into())}
                add_text(&mut p,index,text,false)?;
            },
            "edit_text"=>{
                let id=value.get("shape").and_then(J::as_u64)
                    .and_then(|n|u32::try_from(n).ok())
                    .ok_or("Missing shape identifier")?;
                let slide=p.slides.get_mut(index).ok_or("Slide index out of bounds")?;
                let shape=Arc::make_mut(slide).shape_mut(ShapeId(id)).ok_or("Shape not found")?;
                if shape.locked {return Err("Shape is locked".into())}
                let body=shape.text.as_mut().ok_or("Shape is not a text shape")?;
                *body=TextBody::from_text(text);
            },
            "delete_slide"=>{
                if p.slides.len()<=1 {return Err("Cannot delete last slide".into())}
                if index>=p.slides.len() {return Err("Slide index out of bounds".into())}
                p.slides.remove(index);
            },
            _=>return Err(format!("Unsupported PPTX action: {action}")),
        }
        save(&p)
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    fn bytes(r:AcResult)->Vec<u8>{
        let b=if r.len==0 {Vec::new()} else {unsafe{std::slice::from_raw_parts(r.ptr,r.len).to_vec()}};
        let status=r.status;
        super::super::ac_result_free(r);
        assert_eq!(status,0,"{}",String::from_utf8_lossy(&b));
        b
    }
    fn edit(data:&[u8],v:J)->Vec<u8>{
        let j=v.to_string();
        bytes(ac_pptx_edit(data.as_ptr(),data.len(),j.as_ptr(),j.len()))
    }
    #[test]
    fn deck_round_trip_create_add_slide_add_text_change_delete(){
        let initial=bytes(ac_pptx_create(std::ptr::null(),0));
        assert!(initial.starts_with(b"PK"));
        let deck=load(&initial).unwrap();
        assert_eq!(deck.slides.len(),1);
        let added=edit(&initial,json!({"action":"add_slide","text":"Sprint review"}));
        let p=load(&added).unwrap();
        assert_eq!(p.slides.len(),2);
        let edited=edit(&added,json!({"action":"add_text","slide":1,"text":"Roadmap item"}));
        let s=load(&edited).unwrap();
        assert!(s.slides[1].shapes.iter().any(|sh| sh.text.as_ref().is_some_and(|t| t.text()=="Roadmap item")));
        let id=s.slides[1].shapes.iter().find(|sh| sh.text.as_ref().is_some_and(|t| t.text()=="Roadmap item")).unwrap().id.0;
        let changed=edit(&edited,json!({"action":"edit_text","slide":1,"shape":id,"text":"Updated roadmap"}));
        let view=bytes(ac_pptx_inspect(changed.as_ptr(),changed.len()));
        let j:J=serde_json::from_slice(&view).unwrap();
        assert_eq!(j["slides"].as_array().unwrap().len(),2);
        assert!(j["slides"][1]["shapes"].as_array().unwrap().iter().any(|v|v["text"]=="Updated roadmap"));
        let deleted=edit(&changed,json!({"action":"delete_slide","slide":1}));
        assert_eq!(load(&deleted).unwrap().slides.len(),1);
    }
    #[test]
    fn exports_actual_rgb_fill_for_slide_graphics(){
        let mut deck=Presentation::default();
        let id=add_text(&mut deck,0,"Colored shape",true).unwrap();
        let shape=Arc::make_mut(&mut deck.slides[0])
            .shape_mut(ShapeId(id)).unwrap();
        shape.fill=Some(serde_json::from_value(json!({
            "kind":"solid",
            "color":{"base":{"kind":"rgb",
                "rgb":{"r":21,"g":48,"b":90,"a":255}}}
        })).unwrap());
        let data=save(&deck).unwrap();
        let info=bytes(ac_pptx_inspect(data.as_ptr(),data.len()));
        let parsed:J=serde_json::from_slice(&info).unwrap();
        let shapes=parsed["slides"][0]["shapes"].as_array().unwrap();
        let colored=shapes.iter().find(|v|v["text"]=="Colored shape").unwrap();
        assert_eq!(colored["fillRgb"],"#15305A");
        assert!(!colored["geometry"].is_null());
    }

    #[test]
    fn errors_reject_invalid_input(){
        let r=ac_pptx_inspect(b"not-pptx".as_ptr(),8);
        assert_ne!(r.status,0);
        super::super::ac_result_free(r);
    }
}
