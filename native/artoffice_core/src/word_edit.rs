//! Bounded paragraph editing through the pinned WordCraft document model.
use std::sync::Arc;
use serde_json::{json, Value as J};
use wordcraft_doc::{Block, CharProps, Paragraph};
use wordcraft_doc::props::{Align, LineSpacing, TextColor, Underline};
use super::{AcResult, decode, protect, MAX_INPUT_BYTES, MAX_TEXT_BYTES};

fn offset(text: &str, units: u64) -> Result<usize,String> {
    let mut consumed=0u64;
    for (byte,c) in text.char_indices() {
        if consumed==units {return Ok(byte)}
        consumed+=c.len_utf16() as u64;
        if consumed>units {return Err("Selection splits a UTF-16 surrogate pair".into())}
    }
    if consumed==units {Ok(text.len())} else {Err("Selection outside paragraph".into())}
}
fn replace_text(p:&mut Paragraph,text:&str)->Result<(),String>{
    if text.contains('\0') || text.contains(wordcraft_doc::para::OBJ) {return Err("Unsupported control character".into())}
    if text.len()>65536 {return Err("Paragraph exceeds 64 KiB".into())}
    // Keep unchanged prefix/suffix runs and paragraph properties intact.
    let prefix=p.text.chars().zip(text.chars()).take_while(|(a,b)|a==b).map(|(a,_)|a.len_utf8()).sum::<usize>();
    let tail=p.text[prefix..].chars().rev().zip(text[prefix..].chars().rev())
        .take_while(|(a,b)|a==b).map(|(a,_)|a.len_utf8()).sum::<usize>();
    let end=p.text.len()-tail;
    let props=p.props_at(prefix).clone();
    p.delete(prefix,end).map_err(|e|e.to_string())?;
    p.insert_text(prefix,&text[prefix..text.len()-tail],&props).map_err(|e|e.to_string())?;
    Ok(())
}
fn number(j:&J,key:&str,min:f64,max:f64)->Result<Option<f32>,String>{
    let Some(value)=j.get(key) else {return Ok(None)};
    let n=value.as_f64().ok_or_else(||format!("Invalid {key}"))?;
    if !n.is_finite() || !(min..=max).contains(&n) {return Err(format!("{key} outside supported range"))}
    Ok(Some(n as f32))
}
fn bool_field(j:&J,key:&str)->Result<Option<bool>,String>{
    j.get(key).map(|v|v.as_bool().ok_or_else(||format!("Invalid {key}"))).transpose()
}
fn units(j:&J,key:&str,default:u64)->Result<u64,String>{
    match j.get(key) {None=>Ok(default),Some(v)=>v.as_u64().ok_or_else(||format!("Invalid {key} selection offset"))}
}
fn patch(p:&mut Paragraph,j:&J)->Result<(),String>{
    if let Some(text)=j.get("text") {replace_text(p,text.as_str().ok_or("Text must be a string")?)?;}
    if let Some(c)=j.get("char") {
        let object=c.as_object().ok_or("Invalid character properties")?;
        for key in object.keys() {if !["bold","italic","underline","size","color"].contains(&key.as_str()){return Err("Unsupported character property".into())}}
        let bold=bool_field(c,"bold")?;let italic=bool_field(c,"italic")?;let underline=bool_field(c,"underline")?;
        let size=number(c,"size",4.0,96.0)?;
        let color=c.get("color").map(|v|if v.is_null() {Ok(TextColor::Auto)} else {v.as_str().and_then(TextColor::parse).ok_or("Invalid color")}).transpose()?;
        let a=offset(&p.text,units(j,"start",0)?)?;
        let b=offset(&p.text,units(j,"end",p.text.encode_utf16().count() as u64)?)?;
        if a>b {return Err("Reversed selection".into())}
        let change=|r:&mut CharProps|{
            if let Some(v)=bold {r.bold=Some(v)}; if let Some(v)=italic {r.italic=Some(v)};
            if let Some(v)=underline {r.underline=Some(if v {Underline::Single}else{Underline::None})};
            if let Some(v)=size {r.size=Some(v)};if let Some(v)=color {r.color=Some(v)};
        };
        if p.text.is_empty(){change(&mut p.mark)}else{p.format(a,b,&change).map_err(|e|e.to_string())?;}
    }
    if let Some(v)=j.get("align") {p.props.align=Some(match v.as_str().ok_or("Invalid alignment")? {
        "left"=>Align::Left,"center"=>Align::Center,"right"=>Align::Right,"justify"=>Align::Justify,_=>return Err("Unknown alignment".into())});}
    if let Some(v)=number(j,"indentLeft",0.0,144.0)? {p.props.indent_left=Some(v)}
    if let Some(v)=number(j,"indentFirst",-72.0,144.0)? {p.props.indent_first=Some(v)}
    if let Some(v)=number(j,"spaceAfter",0.0,72.0)? {p.props.space_after=Some(v)}
    if let Some(v)=number(j,"lineSpacing",1.0,3.0)? {p.props.line_spacing=Some(LineSpacing::Multiple(v))}
    p.touch();Ok(())
}
fn editable(p:&Paragraph)->bool {
    p.objects.is_empty() && !p.runs.iter().any(|r|r.props.ins.is_some()||r.props.del.is_some()||r.props.fmt_change.is_some())
}
fn replace_matches(doc:&mut wordcraft_doc::Document,j:&J,all:bool)->Result<(),String> {
    let find=j.get("find").and_then(J::as_str).filter(|s|!s.is_empty() && s.len()<=1024).ok_or("Find text must contain 1..1024 bytes")?;
    let replacement=j.get("replacement").and_then(J::as_str).filter(|s|s.len()<=65536 && !s.contains('\0') && !s.contains(wordcraft_doc::para::OBJ)).ok_or("Invalid replacement text")?;
    let index=if all {None} else {Some(j.get("block").and_then(J::as_u64).and_then(|n|usize::try_from(n).ok()).ok_or("Invalid paragraph index")?)};
    if index.is_some_and(|n|n>=doc.body.len()) {return Err("Paragraph not found".into())}
    let mut count=0usize;
    for (i,block) in doc.body.iter_mut().enumerate() {
        if index.is_some_and(|n|n!=i) {continue}
        let Block::Para(p)=Arc::make_mut(block) else {
            if !all {return Err("Selected block is not a paragraph".into())} else {continue}
        };
        let ranges=if all {p.text.match_indices(find).take(10001).map(|(a,_)|(a,a+find.len())).collect::<Vec<_>>()} else {
            let a=offset(&p.text,units(j,"start",u64::MAX)?)?;
            let b=offset(&p.text,units(j,"end",u64::MAX)?)?;
            if p.text.get(a..b)!=Some(find) {return Err("The selected match has changed; find it again".into())}
            vec![(a,b)]
        };
        if ranges.is_empty() {continue}
        if !editable(p) {return Err("A matching paragraph contains protected revisions or inline objects".into())}
        count+=ranges.len();
        if count>10000 {return Err("Too many matches; narrow the search".into())}
        let removed=ranges.len().checked_mul(find.len()).ok_or("Replacement too large")?;
        let added=ranges.len().checked_mul(replacement.len()).ok_or("Replacement too large")?;
        if p.text.len()-removed+added>65536 {return Err("Replacement paragraph exceeds 64 KiB".into())}
        for (a,b) in ranges.into_iter().rev() {
            let props=p.props_of_char(a).clone();
            p.delete(a,b).map_err(|e|e.to_string())?;
            p.insert_text(a,replacement,&props).map_err(|e|e.to_string())?;
        }
        p.touch();
    }
    if count==0 {return Err("No matching text in editable paragraphs".into())}
    Ok(())
}
#[unsafe(no_mangle)]
pub extern "C" fn ac_docx_edit(data:*const u8,len:usize,req:*const u8,req_len:usize)->AcResult{
    protect(||{
        let j:J=serde_json::from_slice(decode(req,req_len,MAX_TEXT_BYTES)?).map_err(|e|format!("Invalid edit request: {e}"))?;
        let action=j.get("action").and_then(J::as_str).ok_or("Missing Word action")?;
        let mut doc=wordcraft_docx::read(decode(data,len,MAX_INPUT_BYTES)?).map_err(|e|e.to_string())?;
        if doc.settings.protection.is_some() || doc.settings.protect_formatting {return Err("Protected DOCX cannot be edited".into())}
        if doc.settings.track_changes {return Err("Track changes must be resolved in a full editor first".into())}
        if action=="replace_one" || action=="replace_all" {
            replace_matches(&mut doc,&j,action=="replace_all")?;
            return wordcraft_docx::write(&doc).map_err(|e|e.to_string())
        }
        if action!="paragraph" {return Err("Unsupported Word action".into())}
        let index=j.get("block").and_then(J::as_u64).and_then(|n|usize::try_from(n).ok()).ok_or("Invalid block index")?;
        let block=doc.body.get_mut(index).ok_or("Paragraph not found")?;
        let Block::Para(p)=Arc::make_mut(block) else {return Err("Selected block is not a paragraph".into())};
        if !p.objects.is_empty() || p.runs.iter().any(|r|r.props.ins.is_some()||r.props.del.is_some()||r.props.fmt_change.is_some()) {
            return Err("Paragraph has inline objects or tracked revisions; editing is unavailable".into())
        }
        patch(p,&j)?;
        wordcraft_docx::write(&doc).map_err(|e|e.to_string())
    })
}

pub fn preview(doc:&wordcraft_doc::Document)->Vec<J>{
    doc.body.iter().enumerate().filter_map(|(index,b)|{
        let Block::Para(p)=b.as_ref() else {return None};
        let mut off=0usize;
        let runs:Vec<J>=p.runs.iter().map(|r|{let start=off;off=off.saturating_add(r.len).min(p.text.len());
            json!({"text":p.text.get(start..off).unwrap_or(""),"bold":r.props.bold,"italic":r.props.italic,
                "underline":r.props.underline.is_some_and(|v|v!=Underline::None),"size":r.props.size,
                "color":match r.props.color {Some(TextColor::Rgb(rgb))=>Some(format!("#{}",rgb.hex())),_=>None}})}).collect();
        let editable=p.objects.is_empty() && !doc.settings.track_changes && doc.settings.protection.is_none() && !doc.settings.protect_formatting
            && !p.runs.iter().any(|r|r.props.ins.is_some()||r.props.del.is_some()||r.props.fmt_change.is_some());
        Some(json!({"block":index,"text":p.plain_text(),"editable":editable,"runs":runs,
            "align":p.props.align.unwrap_or(Align::Left),"indentLeft":p.props.indent_left.unwrap_or(0.0),
            "indentFirst":p.props.indent_first.unwrap_or(0.0),"spaceAfter":p.props.space_after.unwrap_or(12.0),
            "lineSpacing":match p.props.line_spacing {Some(LineSpacing::Multiple(v))=>Some(v),_=>None}}))
    }).collect()
}

#[cfg(test)]
mod tests{
 use super::*;
 fn bytes(r:AcResult)->Result<Vec<u8>,String>{let status=r.status;let v=if r.len==0{vec![]}else{unsafe{std::slice::from_raw_parts(r.ptr,r.len).to_vec()}};super::super::ac_result_free(r);if status==0{Ok(v)}else{Err(String::from_utf8_lossy(&v).into())}}
 fn edit(input:&[u8],request:J)->Result<Vec<u8>,String>{let request=request.to_string();bytes(ac_docx_edit(input.as_ptr(),input.len(),request.as_ptr(),request.len()))}
 #[test]fn unicode_text_and_selected_format_roundtrip(){
  let t="Привет 😀 мир";let input=bytes(super::super::ac_docx_create(t.as_ptr(),t.len())).unwrap();
  let out=edit(&input,json!({"action":"paragraph","block":0,"text":"Привет 😀 мир!","start":0,"end":6,"char":{"bold":true,"size":18},"align":"justify","indentLeft":18,"lineSpacing":1.5})).unwrap();
  let doc=wordcraft_docx::read(&out).unwrap();let Block::Para(p)=doc.body[0].as_ref()else{panic!()};
  assert_eq!(p.text,"Привет 😀 мир!");assert_eq!(p.props.align,Some(Align::Justify));assert_eq!(p.props.indent_left,Some(18.0));
  assert_eq!(p.props_at(1).bold,Some(true));assert_ne!(p.props_of_char("Привет ".len()).bold,Some(true));
 }
 #[test]fn unaffected_runs_survive_replace(){
  let mut p=Paragraph::with_text("До ",CharProps{bold:Some(true),..Default::default()});
  p.insert_text(p.len(),"после",&CharProps{italic:Some(true),..Default::default()}).unwrap();
  replace_text(&mut p,"До слова после").unwrap();assert_eq!(p.props_at(1).bold,Some(true));assert_eq!(p.props_of_char(p.len()-1).italic,Some(true));
 }
 #[test]fn invalid_selection_and_protected_file_fail(){
  let t="A😀B";let input=bytes(super::super::ac_docx_create(t.as_ptr(),t.len())).unwrap();
  assert!(edit(&input,json!({"action":"paragraph","block":0,"start":2,"end":3,"char":{"bold":true}})).is_err());
  assert!(edit(&input,json!({"action":"paragraph","block":999,"text":"x"})).is_err());
  let mut doc=wordcraft_docx::read(&input).unwrap();doc.settings.protection=Some("readOnly".into());let protected=wordcraft_docx::write(&doc).unwrap();
  assert!(edit(&protected,json!({"action":"paragraph","block":0,"text":"x"})).is_err());
 }

 #[test]fn find_replace_preserves_unicode_and_unaffected_runs(){
  let text="До cat / cat 😀";
  let input=bytes(super::super::ac_docx_create(text.as_ptr(),text.len())).unwrap();
  let bold=edit(&input,json!({"action":"paragraph","block":0,"start":0,"end":3,"char":{"bold":true}})).unwrap();
  let units=text.encode_utf16().count();
  let styled=edit(&bold,json!({"action":"paragraph","block":0,"start":units-2,"end":units,"char":{"italic":true}})).unwrap();
  let out=edit(&styled,json!({"action":"replace_all","find":"cat","replacement":"кот"})).unwrap();
  let doc=wordcraft_docx::read(&out).unwrap();let Block::Para(p)=doc.body[0].as_ref()else{panic!()};
  assert_eq!(p.text,"До кот / кот 😀");assert_eq!(p.props_at(1).bold,Some(true));
  assert_eq!(p.props_of_char(p.text.len()-4).italic,Some(true));
  let one=edit(&styled,json!({"action":"replace_one","block":0,"start":3,"end":6,"find":"cat","replacement":"X"})).unwrap();
  assert_eq!(preview(&wordcraft_docx::read(&one).unwrap())[0]["text"],"До X / cat 😀");
  assert_eq!(preview(&wordcraft_docx::read(&styled).unwrap())[0]["text"],text);
  assert!(edit(&styled,json!({"action":"replace_one","block":0,"start":3,"end":6,"find":"dog","replacement":"X"})).is_err());
 }
 #[test]fn replacement_limits_and_document_protection_are_atomic(){
  let text="a".repeat(10001);let original=bytes(super::super::ac_docx_create(text.as_ptr(),text.len())).unwrap();
  for request in [json!({"action":"replace_all","find":"a","replacement":"b"}),json!({"action":"replace_all","find":"","replacement":"b"})] {
   assert!(edit(&original,request).is_err());
  }
  let mut doc=wordcraft_docx::read(&original).unwrap();doc.settings.protection=Some("readOnly".into());
  let protected=wordcraft_docx::write(&doc).unwrap();
  assert!(edit(&protected,json!({"action":"replace_all","find":"a","replacement":"b"})).is_err());
  assert_eq!(preview(&wordcraft_docx::read(&original).unwrap())[0]["text"],text);
 }

 #[test]fn selected_color_indent_and_line_spacing_reopen_and_preview_consistently(){
  let text="До 😀 после";let original=bytes(super::super::ac_docx_create(text.as_ptr(),text.len())).unwrap();
  let out=edit(&original,json!({"action":"paragraph","block":0,"start":3,"end":5,"char":{"color":"#3565CA"},"indentLeft":24,"lineSpacing":2.0})).unwrap();
  let view=preview(&wordcraft_docx::read(&out).unwrap());
  assert_eq!(view[0]["indentLeft"],24.0);assert_eq!(view[0]["lineSpacing"],2.0);
  assert!(view[0]["runs"].as_array().unwrap().iter().any(|r|r["text"]=="😀" && r["color"]=="#3565CA"));
  let cleared=edit(&out,json!({"action":"paragraph","block":0,"start":3,"end":5,"char":{"color":null}})).unwrap();
  let view=preview(&wordcraft_docx::read(&cleared).unwrap());
  assert!(view[0]["runs"].as_array().unwrap().iter().all(|r|r["color"].is_null()));
 }
}
