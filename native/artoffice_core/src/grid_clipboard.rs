//! Bounded mobile clipboard adapter over the pinned GridCraft command engine.
//! Only selected text leaves the app. Rich source bytes stay in app memory.
use std::sync::Arc;
use serde_json::{json, Value as J};
use gridcraft_core::{CellRef, RangeRef};
use gridcraft_engine::{Clipboard, Trust};
use gridcraft_model::Workbook;
use super::{AcResult, decode, protect, MAX_INPUT_BYTES, MAX_TEXT_BYTES};
use super::grid::{command_session, workbook, write};

pub(super) const MAX_CLIP_BYTES: usize = 24 * 1024 * 1024;
const MAX_TEXT: usize = 256 * 1024;
const MAX_CELLS: u64 = 4096;
fn sheet(req:&J, key:&str)->Result<usize,String> {
    req.get(key).and_then(J::as_u64).and_then(|v|usize::try_from(v).ok()).ok_or_else(||format!("Invalid {key}"))
}
fn range(req:&J, key:&str)->Result<RangeRef,String> {
    let r=req.get(key).and_then(J::as_str).and_then(RangeRef::parse).ok_or("Invalid cell range")?;
    if u64::from(r.height())*u64::from(r.width())>MAX_CELLS {return Err("Select at most 4096 cells per operation".into())}
    Ok(r)
}
fn check_area(wb:&Workbook, idx:usize, area:RangeRef, edit:bool, anchor_only:bool)->Result<(),String> {
    let sh=wb.sheet(idx).ok_or("Sheet index out of bounds")?;
    if edit && (wb.protected_structure || sh.protection.is_some()) {return Err("Protected sheet cannot be pasted into".into())}
    for m in &sh.merges {
        if m.intersects(&area) && !area.contains_range(m) && !(anchor_only && area.is_single() && area.start==m.start) {
            return Err("Select complete merged cells".into())
        }
    }
    if sh.spill_ranges.values().any(|r|r.intersects(&area)) || sh.cells.iter().any(|(_,c)|c.formula.as_ref().and_then(|f|f.array).is_some_and(|r|r.intersects(&area))) {
        return Err("Array and spilled formula ranges are not supported by the mobile clipboard yet".into())
    }
    Ok(())
}
fn footprint(at:CellRef, rows:u32, cols:u32)->Result<RangeRef,String> {
    if rows==0 || cols==0 || u64::from(rows)*u64::from(cols)>MAX_CELLS {return Err("Select at most 4096 cells per operation".into())}
    Ok(RangeRef::new(at,at.offset(i64::from(rows)-1,i64::from(cols)-1).ok_or("Pasted range does not fit in the sheet")?))
}

fn bounded_text(wb:&Workbook,idx:usize,area:RangeRef)->Result<String,String> {
    let sh=wb.sheet(idx).ok_or("Sheet index out of bounds")?;let mut out=String::new();
    for row in area.start.row..=area.end.row {
        if sh.is_row_hidden(row) {continue}
        for col in area.start.col..=area.end.col {
            let at=CellRef::new(row,col);
            if matches!(sh.value(at),gridcraft_core::Value::Text(ref text) if text.len()>MAX_TEXT) {return Err("Copied text exceeds 256 KiB".into())}
            let cell=gridcraft_engine::display::range_text(wb,idx,RangeRef::cell(at));
            let cell=cell.strip_suffix('\n').unwrap_or(&cell);
            if out.len()+cell.len()+2>MAX_TEXT {return Err("Copied text exceeds 256 KiB".into())}
            if col!=area.start.col {out.push('\t');}out.push_str(cell);
        }
        out.push('\n');
    }
    Ok(out)
}

#[unsafe(no_mangle)]
pub extern "C" fn ac_xlsx_copy_range(data:*const u8,n:usize,request:*const u8,rn:usize)->AcResult {
    protect(||{
        let req:J=serde_json::from_slice(decode(request,rn,MAX_TEXT_BYTES)?).map_err(|e|e.to_string())?;
        let idx=sheet(&req,"sheet")?;let area=range(&req,"range")?;
        let wb=workbook(decode(data,n,MAX_CLIP_BYTES)?)?;
        check_area(&wb,idx,area,false,false)?;
        let text=bounded_text(&wb,idx,area)?;
        if text.len()>MAX_TEXT {return Err("Copied text exceeds 256 KiB".into())}
        serde_json::to_vec(&json!({"range":area.a1(),"rows":area.height(),"columns":area.width(),"text":text})).map_err(|e|e.to_string())
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn ac_xlsx_paste_range(data:*const u8,n:usize,source:*const u8,sn:usize,request:*const u8,rn:usize)->AcResult {
    protect(||{
        let req:J=serde_json::from_slice(decode(request,rn,MAX_TEXT_BYTES)?).map_err(|e|e.to_string())?;
        let idx=sheet(&req,"sheet")?;let src_idx=sheet(&req,"sourceSheet")?;
        let area=range(&req,"sourceRange")?;
        let at=req.get("address").and_then(J::as_str).and_then(CellRef::parse).ok_or("Invalid destination cell")?;
        let mode=req.get("mode").and_then(J::as_str).unwrap_or("all");
        if !matches!(mode,"all"|"values"|"formats"|"formulas") {return Err("Unsupported paste mode".into())}
        let src=workbook(decode(source,sn,MAX_CLIP_BYTES)?)?;
        check_area(&src,src_idx,area,false,false)?;
        if mode=="formats" && src.sheet(src_idx).unwrap().merges.iter().any(|m|m.intersects(&area)) {
            return Err("For merged source cells use Paste all or Paste values".into())
        }
        let wb=workbook(decode(data,n,MAX_INPUT_BYTES)?)?;
        let dest=footprint(at,area.height(),area.width())?;
        check_area(&wb,idx,dest,true,matches!(mode,"values"|"formulas"))?;
        if matches!(mode,"values"|"formulas") && !dest.is_single() && wb.sheet(idx).unwrap().merges.iter().any(|m|m.intersects(&dest)) {
            return Err("Paste values into an unmerged range or a single merged-cell anchor".into())
        }
        let mut s=command_session(wb,idx,at)?;
        s.clipboard=Some(Clipboard {wb:Arc::new(src),sheet:src_idx,range:area,selected:area,cut:false,doc_uid:0,text:String::new(),areas:Vec::new(),trust:Trust::FromFile});
        s.execute("edit.pasteSpecial",json!({"sheet":idx,"at":at.a1(),"what":mode})).map_err(|e|e.to_string())?;
        write(&s.doc().map_err(|e|e.to_string())?.wb)
    })
}

// Shape-only scan mirrors GridCraft engine cmd/edit/clipboard.rs::parse_tsv.
// It enforces mobile bounds before the engine allocates and applies the cells.
fn tsv_shape(text:&str)->Result<(u32,u32),String> {
    if text.len()>MAX_TEXT {return Err("Clipboard text exceeds 256 KiB".into())}
    let (mut rows,mut max_cols,mut tabs)=(0u32,0u32,0u32);
    let (mut quoted,mut start,mut content)=(false,true,false);
    let mut chars=text.chars().peekable();
    while let Some(c)=chars.next() {
        if quoted {
            if c=='"' {if chars.peek()==Some(&'"') {chars.next();content=true;} else {quoted=false;}} else {content=true;}
        } else {match c {
            '"' if start=>{quoted=true;start=false;},
            '\t'=>{tabs+=1;content=false;start=true;},
            '\r'=>{},
            '\n'=>{rows+=1;max_cols=max_cols.max(tabs+1);tabs=0;content=false;start=true;},
            _=>{content=true;start=false;},
        }}
        if rows>4096 || tabs>=4096 {return Err("Select at most 4096 cells per operation".into())}
    }
    if content || tabs>0 {rows+=1;max_cols=max_cols.max(tabs+1);}
    if rows==0 || max_cols==0 {return Err("Clipboard contains no cells".into())}
    if u64::from(rows)*u64::from(max_cols)>MAX_CELLS {return Err("Select at most 4096 cells per operation".into())}
    Ok((rows,max_cols))
}
pub(super) fn paste_text(wb:Workbook, req:&J)->Result<Vec<u8>,String> {
    let idx=sheet(req,"sheet")?;
    let at=req.get("address").and_then(J::as_str).and_then(CellRef::parse).ok_or("Invalid destination cell")?;
    let text=req.get("text").and_then(J::as_str).ok_or("Missing clipboard text")?;
    let (rows,cols)=tsv_shape(text)?;let dest=footprint(at,rows,cols)?;
    check_area(&wb,idx,dest,true,true)?;
    if !dest.is_single() && wb.sheet(idx).unwrap().merges.iter().any(|m|m.intersects(&dest)) {return Err("Paste text into an unmerged range or a single merged-cell anchor".into())}
    let mut s=command_session(wb,idx,at)?;
    s.execute("edit.paste",json!({"sheet":idx,"at":at.a1(),"text":text})).map_err(|e|e.to_string())?;
    write(&s.doc().map_err(|e|e.to_string())?.wb)
}

#[cfg(test)]
mod tests {
    use super::*;
    use gridcraft_core::Value;
    use gridcraft_model::{Cell,Formula};
    use gridcraft_model::style::{Style,Color,NumFmt};
    fn bytes(r:AcResult)->Result<Vec<u8>,String>{
        let out=if r.len==0 {Vec::new()}else{unsafe{std::slice::from_raw_parts(r.ptr,r.len)}.to_vec()};
        let status=r.status;super::super::ac_result_free(r);
        if status==0 {Ok(out)}else{Err(String::from_utf8_lossy(&out).into_owned())}
    }
    fn edit(input:&[u8],req:J)->Vec<u8>{
        let q=req.to_string();bytes(super::super::grid::ac_xlsx_set_cell(input.as_ptr(),input.len(),q.as_ptr(),q.len())).unwrap()
    }
    fn copy(input:&[u8],area:&str)->Result<J,String>{
        let q=json!({"sheet":0,"range":area}).to_string();let out=bytes(ac_xlsx_copy_range(input.as_ptr(),input.len(),q.as_ptr(),q.len()))?;
        serde_json::from_slice(&out).map_err(|e|e.to_string())
    }
    fn paste(target:&[u8],source:&[u8],area:&str,at:&str,mode:&str)->Result<Vec<u8>,String>{
        let q=json!({"sheet":0,"sourceSheet":0,"sourceRange":area,"address":at,"mode":mode}).to_string();
        bytes(ac_xlsx_paste_range(target.as_ptr(),target.len(),source.as_ptr(),source.len(),q.as_ptr(),q.len()))
    }
    fn sample()->Vec<u8>{
        let mut wb=Workbook::new();let mut style=Style::default();
        style.font.bold=true;style.font.color=Color::Rgb(0x225599);style.num_fmt=NumFmt::new("0.00");
        let id=wb.styles.intern(style);let sh=wb.sheet_mut(0).unwrap();
        sh.set_cell(CellRef::new(0,0),Cell::styled(Value::number(10.0),id));
        sh.set_cell(CellRef::new(0,1),Cell::formula(Formula::new("=A1*2")));
        gridcraft_calc::Calc::new().recalc_all(&mut wb);write(&wb).unwrap()
    }
    #[test] fn rich_paste_rebases_formulas_imports_styles_and_recalculates_dependents(){
        let source=sample();let copied=copy(&source,"A1:B1").unwrap();
        assert_eq!(copied["text"],"10.00\t20\n");assert_eq!(copied["rows"],1);assert_eq!(copied["columns"],2);
        let mut wb=Workbook::new();let mut different=Style::default();different.font.italic=true;different.font.color=Color::Rgb(0xFF0000);wb.styles.intern(different);
        let target=edit(&write(&wb).unwrap(),json!({"sheet":0,"address":"F1","value":"=SUM(D3:E3)"}));
        let out=paste(&target,&source,"A1:B1","D3","all").unwrap();
        let wb=workbook(&out).unwrap();let sh=wb.sheet(0).unwrap();
        assert_eq!(sh.input_text(CellRef::new(2,4)),"=D3*2");assert_eq!(sh.value(CellRef::new(0,5)),Value::number(30.0));
        let style=wb.styles.get(sh.style_id(CellRef::new(2,3)));
        assert!(style.font.bold);assert_eq!(style.font.color,Color::Rgb(0x225599));assert_eq!(style.num_fmt.as_str(),"0.00");
        assert_eq!(workbook(&source).unwrap().sheet(0).unwrap().input_text(CellRef::new(0,1)),"=A1*2");
        assert_eq!(workbook(&target).unwrap().sheet(0).unwrap().value(CellRef::new(0,5)),Value::number(0.0));
    }
    #[test] fn special_modes_keep_destination_values_or_format_as_requested(){
        let source=sample();let mut wb=Workbook::new();let mut green=Style::default();green.font.color=Color::Rgb(0x008800);let id=wb.styles.intern(green);
        wb.sheet_mut(0).unwrap().set_cell(CellRef::new(4,4),Cell::styled(Value::number(99.0),id));
        wb.sheet_mut(0).unwrap().set_value(CellRef::new(4,3),Value::number(7.0));let target=write(&wb).unwrap();
        let values=paste(&target,&source,"B1:B1","E5","values").unwrap();let wb=workbook(&values).unwrap();let sh=wb.sheet(0).unwrap();
        assert_eq!(sh.input_text(CellRef::new(4,4)),"20");assert_eq!(wb.styles.get(sh.style_id(CellRef::new(4,4))).font.color,Color::Rgb(0x008800));
        let formats=paste(&target,&source,"A1:A1","E5","formats").unwrap();let wb=workbook(&formats).unwrap();let sh=wb.sheet(0).unwrap();
        assert_eq!(sh.value(CellRef::new(4,4)),Value::number(99.0));assert!(wb.styles.get(sh.style_id(CellRef::new(4,4))).font.bold);
        let formulas=paste(&target,&source,"B1:B1","E5","formulas").unwrap();let wb=workbook(&formulas).unwrap();let sh=wb.sheet(0).unwrap();
        assert_eq!(sh.input_text(CellRef::new(4,4)),"=D5*2");assert_eq!(sh.value(CellRef::new(4,4)),Value::number(14.0));
        assert_eq!(wb.styles.get(sh.style_id(CellRef::new(4,4))).font.color,Color::Rgb(0x008800));
    }
    #[test] fn overlapping_snapshot_and_absolute_references_are_preserved(){
        let source=sample();let target=paste(&source,&source,"A1:B1","B1","all").unwrap();let wb=workbook(&target).unwrap();let sh=wb.sheet(0).unwrap();
        assert_eq!(sh.input_text(CellRef::new(0,2)),"=B1*2");assert_eq!(sh.value(CellRef::new(0,2)),Value::number(20.0));
        let source=edit(&source,json!({"sheet":0,"address":"B1","value":"=A1+$A1+A$1+$A$1"}));
        let out=paste(&source,&source,"B1:B1","C3","all").unwrap();
        assert_eq!(workbook(&out).unwrap().sheet(0).unwrap().input_text(CellRef::new(2,2)),"=B3+$A3+B$1+$A$1");
        let out=paste(&source,&source,"B1:B1","A1","all").unwrap();
        assert!(workbook(&out).unwrap().sheet(0).unwrap().input_text(CellRef::new(0,0)).contains("#REF!"));
    }
    #[test] fn external_tsv_handles_quotes_unicode_empty_fields_and_existing_text_formats(){
        let text="\"лево\tправо\"\t12\r\n\"строка1\nстрока2 😀\"\t=1+2\n";
        assert_eq!(tsv_shape(text).unwrap(),(2,2));
        let initial=write(&Workbook::new()).unwrap();
        let out=edit(&initial,json!({"action":"paste_text","sheet":0,"address":"A1","text":text}));
        let wb=workbook(&out).unwrap();let sh=wb.sheet(0).unwrap();
        assert_eq!(sh.input_text(CellRef::new(0,0)),"лево\tправо");assert_eq!(sh.value(CellRef::new(0,1)),Value::number(12.0));
        assert_eq!(sh.input_text(CellRef::new(1,0)),"строка1\nстрока2 😀");assert_eq!(sh.value(CellRef::new(1,1)),Value::number(3.0));
        let formatted=edit(&initial,json!({"action":"format","sheet":0,"address":"A1","style":{"numFmt":"@","bold":true}}));
        let out=edit(&formatted,json!({"action":"paste_text","sheet":0,"address":"A1","text":"=1+2\t\n"}));
        let wb=workbook(&out).unwrap();let sh=wb.sheet(0).unwrap();
        assert!(sh.cell(CellRef::new(0,0)).unwrap().formula.is_none());assert_eq!(sh.value(CellRef::new(0,0)),Value::text("=1+2"));
        assert!(wb.styles.get(sh.style_id(CellRef::new(0,0))).font.bold);
    }
    #[test] fn copied_text_is_bounded_before_assembling_a_large_selection(){
        let mut wb=Workbook::new();
        for row in 0..100 {wb.sheet_mut(0).unwrap().set_value(CellRef::new(row,0),Value::text("x".repeat(4000)));}
        let data=write(&wb).unwrap();
        assert!(copy(&data,"A1:A100").unwrap_err().contains("256 KiB"));
        assert_eq!(copy(&data,"A1:A2").unwrap()["rows"],2);
    }
    #[test] fn merged_cells_copy_whole_and_partial_or_oversized_pastes_fail_atomically(){
        let source=include_bytes!("../../../test/fixtures/formatted-grid.xlsx").as_slice();
        assert!(copy(source,"B2:C3").is_err());
        let target=write(&Workbook::new()).unwrap();let out=paste(&target,source,"A1:C2","D4","all").unwrap();
        let wb=workbook(&out).unwrap();assert!(wb.sheet(0).unwrap().merges.contains(&RangeRef::parse("D4:F5").unwrap()));
        assert!(paste(&target,source,"A1:C2","D4","formats").is_err());
        assert!(paste(source,&sample(),"A1:B1","B2","all").is_err());
        assert!(paste(&target,&sample(),"A1:B1","XFD1048576","all").is_err());
        assert!(copy(&sample(),"A1:Z300").is_err());
        let mut locked=Workbook::new();locked.protected_structure=true;
        assert!(paste(&write(&locked).unwrap(),&sample(),"A1:B1","A1","all").is_err());
        assert!(tsv_shape(&"x\t".repeat(4096)).is_err());assert!(tsv_shape(&"\n".repeat(4097)).is_err());
        assert!(tsv_shape(&"x".repeat(MAX_TEXT+1)).is_err());
    }
}
