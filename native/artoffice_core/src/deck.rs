//! Minimal Android DeckCraft PPTX integration. No fabricated document operations.
use std::sync::Arc;
use deckcraft_model::{
    defaults, LayoutType, Presentation, Shape, ShapeId, ShapeKind, TextBody, Xfrm,
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

fn movable(shape: &Shape) -> bool {
    !shape.locked
        && matches!(shape.kind, ShapeKind::Shape | ShapeKind::Picture { .. })
        && shape.xfrm.is_some_and(|rect| {
            [rect.x, rect.y, rect.w, rect.h].into_iter().all(f64::is_finite)
                && rect.w > 0.0 && rect.h > 0.0 && rect.rot == 0.0
        })
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
                let picture=match &shape.kind {
                    ShapeKind::Picture{fill}=>Some(fill),
                    _=>match shape.fill.as_ref(){
                        Some(deckcraft_model::style::Fill::Picture(fill))=>Some(fill),
                        _=>None,
                    },
                };
                let image_id=picture.and_then(|f|{
                    presentation.media(f.media).filter(|media|{
                        media.link.is_none() && !media.data.is_empty() &&
                        media.data.len()<=8*1024*1024 &&
                        matches!(media.content_type.as_str(),"image/png"|"image/jpeg"|"image/jpg"|"image/webp")
                    }).map(|_|f.media.0)
                });
                let geometry=serde_json::to_value(&shape.geom).unwrap_or(J::Null);
                json!({
                    "id":shape.id.0,
                    "name":shape.name,
                    "kind":shape.kind_name(),
                    "geometry":geometry,
                    "imageId":image_id,
                    "fillRgb":fill_rgb,
                    "strokeRgb":stroke_rgb,
                    "text":shape.text.as_ref().map(|t|t.text()).unwrap_or_default(),
                    "rect":rect,
                    "movable":movable(shape),
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
            "warnings":["Simplified text, rectangular graphics, direct RGB fills/strokes and position preview only. Embedded PNG/JPEG/WebP images are available in the preview; external links, groups, charts, SmartArt, fonts, animations and exact PowerPoint layout are not rendered. DOCX-like round-trip fidelity not guaranteed for complex PPTX files."]
        })).map_err(|e|e.to_string())
    })
}
/// Read an embedded PNG/JPEG/WebP referenced by a picture shape on a slide.
/// FFI request JSON: {"slide":0,"media":123}. External links are never fetched.
#[unsafe(no_mangle)]
pub extern "C" fn ac_pptx_image(
    data:*const u8,n:usize,request:*const u8,request_len:usize,
)->AcResult{
    protect(||{
        let bytes=decode(data,n,MAX_INPUT_BYTES)?;
        let arg:J=serde_json::from_str(decode_request(request,request_len)?)
            .map_err(|e|format!("Invalid PPTX image request: {e}"))?;
        let index=arg.get("slide").and_then(J::as_u64)
            .and_then(|v|usize::try_from(v).ok())
            .ok_or("Missing slide index")?;
        let id=arg.get("media").and_then(J::as_u64)
            .and_then(|v|u32::try_from(v).ok())
            .ok_or("Missing media identifier")?;
        let p=load(bytes)?;
        let slide=p.slides.get(index).ok_or("PPTX slide out of range")?;
        let referenced=slide.shapes.iter().any(|shape|{
            let fill=match &shape.kind{
                ShapeKind::Picture{fill}=>Some(fill),
                _=>match shape.fill.as_ref(){
                    Some(deckcraft_model::style::Fill::Picture(fill))=>Some(fill),
                    _=>None,
                },
            };
            fill.is_some_and(|f|f.media.0==id)
        });
        if !referenced {return Err("Slide does not reference the requested image".into());}
        let media=p.media(deckcraft_model::MediaId(id))
            .ok_or("Embedded image is not present")?;
        if media.link.is_some(){return Err("External images are not fetched".into());}
        let b=media.data.as_slice();
        if b.is_empty()||b.len()>8*1024*1024 {return Err("Image exceeds 8 MiB limit".into());}
        let valid=match media.content_type.as_str(){
            "image/png"=>b.starts_with(b"\x89PNG\r\n\x1a\n"),
            "image/jpeg"|"image/jpg"=>b.starts_with(&[0xff,0xd8,0xff]),
            "image/webp"=>b.len()>12&&b.starts_with(b"RIFF")&&&b[8..12]==b"WEBP",
            _=>false,
        };
        if !valid{return Err("Image format is not a supported embedded raster".into());}
        Ok(b.to_vec())
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
            "transform_shape" => {
                let id = value["shape"].as_u64().and_then(|n| u32::try_from(n).ok())
                    .ok_or("Missing shape identifier")?;
                let slide = value["slide"].as_u64().and_then(|n| usize::try_from(n).ok())
                    .and_then(|i| p.slides.get_mut(i)).ok_or("Slide index out of bounds")?;
                let shape = Arc::make_mut(slide).shapes.iter_mut().find(|shape| shape.id == ShapeId(id))
                    .filter(|shape| movable(shape)).ok_or("Shape cannot be moved or resized")?;
                let coordinate = |key| value[key].as_f64()
                    .filter(|n| n.is_finite() && n.abs() <= 1_000_000.0)
                    .ok_or("Invalid shape coordinates");
                let (x, y, w, h) = (coordinate("x")?, coordinate("y")?, coordinate("w")?, coordinate("h")?);
                if w < 1.0 || h < 1.0 { return Err("Shape size must be positive".into()); }
                let rect = shape.xfrm.as_mut().ok_or("Missing shape geometry")?;
                rect.x = x;
                rect.y = y;
                rect.w = w;
                rect.h = h;
            },
            "move_slide"=>{
                let source=value.get("slide").and_then(J::as_u64).and_then(|n|usize::try_from(n).ok()).ok_or("Missing slide index")?;
                let target=value.get("to").and_then(J::as_u64).and_then(|n|usize::try_from(n).ok()).ok_or("Missing target slide")?;
                if source>=p.slides.len() || target>=p.slides.len() {return Err("Slide index out of bounds".into())}
                let slide=p.slides.remove(source);p.slides.insert(target,slide);
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

    #[test]
    fn reordering_slides_preserves_content_and_geometry() {
        let mut p=Presentation::default();
        add_text(&mut p,0,"First 😀",true).unwrap();
        let initial=save(&p).unwrap();
        let two=edit(&initial,json!({"action":"add_slide","text":"Second"}));
        let three=edit(&two,json!({"action":"add_slide","text":"Third"}));
        let before=load(&three).unwrap();
        let moved=edit(&three,json!({"action":"move_slide","slide":0,"to":2}));
        let after=load(&moved).unwrap();
        // PPTX import allocates model identifiers anew; compare slide content,
        // rather than treating transient in-memory ids as file identities.
        for (new,old) in [(0,1),(1,2),(2,0)] {
            let a=&after.slides[new];let b=&before.slides[old];
            assert_eq!(a.shapes.len(),b.shapes.len());
            for (x,y) in a.shapes.iter().zip(&b.shapes) {
                assert_eq!(x.text.as_ref().map(|t|t.text()),y.text.as_ref().map(|t|t.text()));
                assert_eq!(x.xfrm,y.xfrm);
            }
            assert_eq!(a.notes_text(),b.notes_text());
        }
        assert!(after.validate().is_empty());
        let request=json!({"action":"move_slide","slide":0,"to":999}).to_string();
        let invalid=ac_pptx_edit(three.as_ptr(),three.len(),request.as_ptr(),request.len());
        assert_ne!(invalid.status,0);super::super::ac_result_free(invalid);
    }
}
