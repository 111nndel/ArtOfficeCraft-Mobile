//! GridCraft: real XLSX create/read/edit/write bridge.
//! Preview is bounded and does not pretend to render full Excel features.
use gridcraft_core::{CellRef, Value};
use gridcraft_model::{Cell, Formula, Workbook};
use gridcraft_model::style::{Color, Fill, HAlign, NumFmt, PatternType, Underline, Borders, BorderLine, VAlign};
use gridcraft_numfmt::{NumberFormat, format_value};
use std::collections::HashMap;
use serde_json::{json, Value as Json};
use super::{AcResult, decode, protect, MAX_INPUT_BYTES, MAX_TEXT_BYTES};

fn input<'a>(p: *const u8, n: usize) -> Result<&'a str, String> {
    std::str::from_utf8(decode(p, n, MAX_TEXT_BYTES)?).map_err(|_| "Invalid UTF-8 input".to_owned())
}
fn workbook(bytes: &[u8]) -> Result<Workbook,String> {
    gridcraft_xlsx::read_xlsx(bytes).map(|(w, _)| w).map_err(|e|format!("GridCraft XLSX read: {e}"))
}
fn write(w: &Workbook) -> Result<Vec<u8>,String> {
    gridcraft_xlsx::write_xlsx(w).map_err(|e|format!("GridCraft XLSX write: {e}"))
}
fn put(w: &mut Workbook, sheet_index: usize, a1: &str, value: &str) -> Result<(),String> {
    if w.protected_structure {return Err("Workbook structure is protected".into());}
    let reference=CellRef::parse(a1).ok_or("Invalid A1 reference")?;
    let reference=w.sheet(sheet_index).and_then(|s|s.merge_at(reference)).map_or(reference,|m|m.start);
    if value.len()>65535 {return Err("Cell input exceeds 65535 bytes".into());}
    let original=w.sheet(sheet_index).ok_or("Sheet index out of bounds")?;
    let text_format=w.styles.get(original.style_id(reference)).num_fmt.as_str()=="@";
    let sh=w.sheet_mut(sheet_index).ok_or("Sheet index out of bounds")?;
    if sh.protection.is_some() {return Err("Protected sheets cannot be edited in this preview".into());}
    let style=sh.style_id(reference);
    if value.is_empty() {
        sh.set_cell(reference,Cell {style,..Cell::default()});
    } else if text_format {
        sh.set_value(reference,Value::text(value.strip_prefix("'").unwrap_or(value)));
    } else if value.starts_with('=') {
        sh.set_cell(reference, Cell {style,..Cell::formula(Formula::new(value))});
    } else if let Some(text)=value.strip_prefix("'") {
        sh.set_value(reference,Value::text(text));
    } else if let Ok(number)=value.replace(',',".").parse::<f64>() {
        if number.is_finite() {sh.set_value(reference,Value::number(number));}
        else {return Err("Number must be finite".into());}
    } else {
        sh.set_value(reference,Value::text(value));
    }
    Ok(())
}

/// Insert a SUM only into a vacant, unmerged cell. Prefer the contiguous
/// numeric range above, then the one to the left; never replace user content.
fn autosum(w: &mut Workbook, idx: usize, address: &str) -> Result<(),String> {
    if w.protected_structure {return Err("Workbook is protected".into())}
    let loc=CellRef::parse(address).ok_or("Invalid A1 reference")?;
    let sh=w.sheet(idx).ok_or("Sheet index out of bounds")?;
    if sh.protection.is_some() {return Err("Protected sheet cannot be edited".into())}
    if sh.merge_at(loc).is_some() {return Err("AutoSum requires an unmerged cell".into())}
    if sh.cell(loc).is_some_and(|c|c.formula.is_some() || c.py.is_some() || c.value!=Value::Empty) {
        return Err("AutoSum requires an empty cell below or to the right of numbers".into())
    }
    let numeric=|r,c| sh.cell(CellRef::new(r,c)).is_some_and(|cell|matches!(cell.value,Value::Number(v) if v.is_finite()));
    let mut first=loc;
    while first.row>0 && numeric(first.row-1,loc.col) {first.row-=1;}
    let last=if first!=loc {CellRef::new(loc.row-1,loc.col)} else {
        while first.col>0 && numeric(loc.row,first.col-1) {first.col-=1;}
        if first==loc {return Err("No adjacent numeric range for AutoSum".into())}
        CellRef::new(loc.row,loc.col-1)
    };
    let formula=Formula::new(&format!("=SUM({}:{})",first.a1(),last.a1()));
    let style=sh.style_id(loc);
    w.sheet_mut(idx).unwrap().set_cell(loc,Cell {style,..Cell::formula(formula)});
    Ok(())
}
fn format_cell(w:&mut Workbook, idx:usize, a1:&str, patch:&Json)->Result<(),String> {
    if w.protected_structure {return Err("Workbook is protected".into())}
    let loc=CellRef::parse(a1).ok_or("Invalid A1 reference")?;
    let loc=w.sheet(idx).and_then(|s|s.merge_at(loc)).map_or(loc,|m|m.start);
    let sheet=w.sheet(idx).ok_or("Sheet index out of bounds")?;
    if sheet.protection.is_some() {return Err("Protected sheet cannot be formatted".into())}
    let mut style=w.styles.get(sheet.style_id(loc)).clone();
    let fields=patch.as_object().ok_or("Style must be an object")?;
    if fields.is_empty() {return Err("Empty style patch".into())}
    for (key,value) in fields {
        match key.as_str() {
            "bold"=>style.font.bold=value.as_bool().ok_or("bold must be boolean")?,
            "italic"=>style.font.italic=value.as_bool().ok_or("italic must be boolean")?,
            "underline"=>style.font.underline=if value.as_bool().ok_or("underline must be boolean")? {Underline::Single} else {Underline::None},
            "fontSize"=>{
                let size=value.as_f64().filter(|v|v.is_finite() && (6.0..=72.0).contains(v)).ok_or("Font size must be 6..72 pt")?;
                style.font.size=size as f32;
            },
            "color"|"fill"=>{
                let color=if value.is_null() {Color::Auto} else {
                    let h=value.as_str().ok_or("Color must be #RRGGBB or null")?;
                    if h.len()!=7 || !h.starts_with('#') {return Err("Color must be #RRGGBB".into())}
                    Color::from_hex(h).ok_or("Invalid RGB color")?
                };
                if key=="color" {style.font.color=color} else {
                    style.fill=if color==Color::Auto {Fill::default()} else {Fill::solid(color)};
                }
            },
            "align"=>style.align.h=match value.as_str().ok_or("align must be text")? {
                "general"=>HAlign::General,"left"=>HAlign::Left,"center"=>HAlign::Center,"right"=>HAlign::Right,
                _=>return Err("Unsupported alignment".into())
            },
            "verticalAlign"=>style.align.v=match value.as_str().ok_or("verticalAlign must be text")? {
                "top"=>VAlign::Top,"center"=>VAlign::Center,"bottom"=>VAlign::Bottom,
                _=>return Err("Unsupported vertical alignment".into())
            },
            "wrap"=>style.align.wrap=value.as_bool().ok_or("wrap must be boolean")?,
            "shrink"=>style.align.shrink=value.as_bool().ok_or("shrink must be boolean")?,
            "numFmt"=>{
                let code=value.as_str().filter(|v| !v.is_empty() && v.chars().count()<=255 && !v.contains('\0')).ok_or("Invalid number format")?;
                style.num_fmt=NumFmt::new(code);
            },
            "borders"=>style.borders=match value.as_str().ok_or("borders must be text")? {
                "none"=>Borders::default(),
                "all"=>Borders {left:BorderLine::thin(),right:BorderLine::thin(),top:BorderLine::thin(),bottom:BorderLine::thin(),..Borders::default()},
                _=>return Err("Unsupported border preset".into())
            },
            _=>return Err(format!("Unknown style property: {key}")),
        }
    }
    let id=w.styles.intern(style);
    w.sheet_mut(idx).ok_or("Sheet not found")?.set_style(loc,id);
    Ok(())
}
fn line_json(line:BorderLine,w:&Workbook)->Json {
    json!({"width":line.style.width(),"color":line.color.hex(&w.theme)})
}
fn style_json(w:&Workbook,id:gridcraft_model::style::StyleId)->Json {
    let s=w.styles.get(id);
    json!({"bold":s.font.bold,"italic":s.font.italic,"underline":s.font.underline!=Underline::None,
        "fontSize":s.font.size,"fontName":s.font.name,"strike":s.font.strike,"color":s.font.color.hex(&w.theme),
        "fill":if s.fill.pattern==PatternType::Solid {s.fill.fg.hex(&w.theme)} else {None},
        "align":match s.align.h {HAlign::Left=>"left",HAlign::Center=>"center",HAlign::Right=>"right",_=>"general"},
        "verticalAlign":match s.align.v {VAlign::Top=>"top",VAlign::Center=>"center",_=>"bottom"},
        "indent":s.align.indent,"shrink":s.align.shrink,"rotation":s.align.rotation,
        "wrap":s.align.wrap,"numFmt":s.num_fmt.as_str(),
        "borders":{"left":line_json(s.borders.left,w),"right":line_json(s.borders.right,w),"top":line_json(s.borders.top,w),"bottom":line_json(s.borders.bottom,w)}})
}
#[unsafe(no_mangle)]
pub extern "C" fn ac_xlsx_create(_: *const u8, _: usize) -> AcResult {
    protect(||write(&Workbook::new()))
}
#[unsafe(no_mangle)]
pub extern "C" fn ac_xlsx_inspect(data:*const u8, n:usize) -> AcResult {
    protect(||{
        let bytes=decode(data,n,MAX_INPUT_BYTES)?;
        let (wb,report)=gridcraft_xlsx::read_xlsx(bytes).map_err(|e|format!("GridCraft XLSX read: {e}"))?;
        let mut total=0usize;
        let mut formats=HashMap::new();
        let mut sheets=Vec::new();
        for (index, sh) in wb.sheets.iter().enumerate() {
            let mut cells=serde_json::Map::new();
            for (loc,c) in sh.cells.iter() {
                total+=1;
                if cells.len() >= 1600 {continue;}
                let fmt=formats.entry(c.style).or_insert_with(||NumberFormat::parse(wb.styles.get(c.style).num_fmt.as_str()));
                let displayed=format_value(&c.value,fmt,wb.date_system);
                cells.insert(loc.a1(),json!({"input":c.input_text(),"display":displayed.text,"numeric":displayed.numeric,
                    "formula":c.formula.is_some(),"style":style_json(&wb,c.style)}));
            }
            sheets.push(json!({"index":index,"name":sh.name,"cells":cells,"truncated":sh.cells.len()>1600}));
        }
        serde_json::to_vec(&json!({
            "type":"xlsx", "engine":"gridcraft", "sheets":sheets,
            "totalCells":total,"warnings":report.warnings,
            "note":"Only first 1600 populated cells per sheet appear in preview. Formula results may be stale if the source workbook has not been recalculated."
        })).map_err(|e|e.to_string())
    })
}
#[unsafe(no_mangle)]
pub extern "C" fn ac_xlsx_set_cell(data:*const u8,n:usize, request:*const u8,req_len:usize)->AcResult {
    protect(||{
        let bytes=decode(data,n,MAX_INPUT_BYTES)?;
        let req:Json=serde_json::from_str(input(request,req_len)?).map_err(|e|format!("Invalid cell edit JSON: {e}"))?;
        let idx=req.get("sheet").and_then(Json::as_u64).ok_or("Missing sheet index")? as usize;
        let address=req.get("address").and_then(Json::as_str).ok_or("Missing A1 address")?;
        let mut wb=workbook(bytes)?;
        let action=req.get("action").and_then(Json::as_str).unwrap_or("value");
        if !matches!(action,"value"|"format"|"rowHeight"|"columnWidth"|"autosum"|"recalculate") {return Err("Unknown cell action".into())}
        if matches!(action,"autosum"|"recalculate") && req.get("value").is_some() {
            return Err("Calculation actions do not accept a cell value".into())
        }
        if action=="autosum" {autosum(&mut wb,idx,address)?;}
        if action=="recalculate" {
            CellRef::parse(address).ok_or("Invalid A1 reference")?;
            if wb.protected_structure || wb.sheets.iter().any(|s|s.protection.is_some()) {
                return Err("Protected workbook cannot be recalculated in this preview".into())
            }
            wb.sheet(idx).ok_or("Sheet index out of bounds")?;
        }
        if action=="rowHeight" || action=="columnWidth" {
            let line=req.get("index").and_then(Json::as_u64).ok_or("Missing line index")?;
            let limit=if action=="rowHeight" {gridcraft_core::MAX_ROWS} else {gridcraft_core::MAX_COLS};
            if line>=limit as u64 {return Err("Line index out of bounds".into())}
            let size=req.get("size").and_then(Json::as_f64).filter(|s|s.is_finite() && (4.0..=4096.0).contains(s)).ok_or("Size must be 4..4096 pixels")?;
            if wb.protected_structure {return Err("Workbook is protected".into())}
            let sh=wb.sheet_mut(idx).ok_or("Sheet index out of bounds")?;
            if sh.protection.is_some() {return Err("Protected sheet cannot be resized".into())}
            let info=if action=="rowHeight" {sh.rows.entry(line as u32).or_default()} else {sh.cols.entry(line as u32).or_default()};
            info.size=Some(size as f32); info.hidden=false; info.custom=true;
        }
        if action=="format" {format_cell(&mut wb,idx,address,req.get("style").ok_or("Missing style")?)?;}
        if action=="value" || req.get("value").is_some() {
            let value=req.get("value").and_then(Json::as_str).ok_or("Missing cell value")?;
            put(&mut wb,idx,address,value)?;
        }
        if action=="value" || req.get("value").is_some() || matches!(action,"autosum"|"recalculate") {
            gridcraft_calc::Calc::new().recalc_all(&mut wb);
        }
        write(&wb)
    })
}

fn valid_extent(size:f32,fallback:f32)->f32 {
    if size.is_finite() && size>0.0 {size.min(1_000_000.0)} else {fallback}
}
fn axis_runs(lines:&std::collections::BTreeMap<u32,gridcraft_model::features::LineInfo>,default:f32)->Vec<(u32,u32,f32)> {
    let default=valid_extent(default,20.0);
    let mut runs:Vec<(u32,u32,f32)>=Vec::new();
    for (&i,info) in lines {
        let size=if info.hidden || info.size==Some(0.0) {0.0} else {valid_extent(info.size.unwrap_or(default),default)};
        if size==default {continue}
        if let Some(last)=runs.last_mut() {
            if last.1+1==i && last.2==size {last.1=i;continue}
        }
        runs.push((i,i,size));
    }
    runs
}

fn overview_cell(mut cell:Json)->Json {
    let obj=cell.as_object_mut().unwrap();
    obj.remove("input");
    if let Some(text)=obj.get("display").and_then(Json::as_str).map(|s|s.chars().take(512).collect::<String>()) {
        obj.insert("display".into(),Json::String(text));
    }
    cell
}

/// Bounded rectangle plus an independent selected-cell value. Sparse cells are
/// looked up by address, never selected by a global populated-cell cutoff.
#[unsafe(no_mangle)]
pub extern "C" fn ac_xlsx_inspect_window(data:*const u8,n:usize,request:*const u8,req_len:usize)->AcResult {
    protect(|| {
        let req:Json=serde_json::from_str(input(request,req_len)?).map_err(|e|e.to_string())?;
        let field=|name:&str| req.get(name).and_then(Json::as_u64).ok_or_else(||format!("Missing integer {name}"));
        let idx=field("sheet")?;
        let row=field("row")?; let col=field("column")?;
        let rows=field("rows")?; let cols=field("columns")?;
        let overview=match req.get("overview") {
            None=>false,Some(v)=>v.as_bool().ok_or("overview must be boolean")?,
        };
        if overview && (req.get("rowIndices").is_some() || req.get("columnIndices").is_some()) {
            return Err("Overview accepts a rectangle, not index lists".into())
        }
        let indices=|name:&str,start:u64,count:u64,max:u32,cap:usize| -> Result<Vec<u32>,String> {
            if let Some(array)=req.get(name) {
                let values=array.as_array().ok_or("Indices must be an array")?;
                if values.is_empty() || values.len()>cap {return Err("Oversized index list".into())}
                let mut result=Vec::with_capacity(values.len());
                for v in values {
                    let i=v.as_u64().filter(|i|*i<max as u64).ok_or("Invalid visible index")? as u32;
                    if result.last().is_some_and(|previous|*previous>=i) {return Err("Indices must be sorted and unique".into())}
                    result.push(i);
                }
                Ok(result)
            } else {
                if count==0 || count>cap as u64 || start>=max as u64 || count>max as u64-start {return Err("Invalid window bounds".into())}
                Ok((start as u32..(start+count) as u32).collect())
            }
        };
        let row_indices=if overview {Vec::new()} else {indices("rowIndices",row,rows,gridcraft_core::MAX_ROWS,128)?};
        let col_indices=if overview {Vec::new()} else {indices("columnIndices",col,cols,gridcraft_core::MAX_COLS,32)?};
        if rows==0 || cols==0 || row_indices.len()*col_indices.len()>4096 ||
            row>=gridcraft_core::MAX_ROWS as u64 || col>=gridcraft_core::MAX_COLS as u64 ||
            rows>gridcraft_core::MAX_ROWS as u64-row || cols>gridcraft_core::MAX_COLS as u64-col {
            return Err("Invalid or oversized sheet window".into())
        }
        let mut selected=CellRef::parse(req.get("selected").and_then(Json::as_str).ok_or("Missing selected cell")?)
            .ok_or("Invalid selected cell")?;
        let bytes=decode(data,n,MAX_INPUT_BYTES)?;
        let (wb,report)=gridcraft_xlsx::read_xlsx(bytes).map_err(|e|format!("GridCraft XLSX read: {e}"))?;
        let sh=wb.sheets.get(usize::try_from(idx).map_err(|_|"Invalid sheet index")?).ok_or("Sheet index out of bounds")?;
        selected=sh.merge_at(selected).map_or(selected,|m|m.start);
        let mut formats=HashMap::new();
        let mut inspect=|loc:CellRef| {
            let style=sh.style_id(loc);
            let fmt=formats.entry(style).or_insert_with(||NumberFormat::parse(wb.styles.get(style).num_fmt.as_str()));
            let displayed=format_value(&sh.value(loc),fmt,wb.date_system);
            json!({"address":loc.a1(),"input":sh.input_text(loc),"display":displayed.text,"numeric":displayed.numeric,
                "formula":sh.cell(loc).is_some_and(|c|c.formula.is_some()),"style":style_json(&wb,style)})
        };
        let mut cells=serde_json::Map::new();
        let in_region=|loc:CellRef| (loc.row as u64)>=row && (loc.row as u64)<row+rows &&
            (loc.col as u64)>=col && (loc.col as u64)<col+cols;
        let overview_total=if overview {sh.cells.iter().filter(|(loc,_)|in_region(*loc)).count()} else {0};
        const OVERVIEW_CAP:usize=8192;
        if overview {
            // Sample across the entire used range for huge sheets, never allocate
            // a row×column matrix or silently return only the first rows.
            let stride=if overview_total>OVERVIEW_CAP {overview_total.div_ceil(OVERVIEW_CAP-1)} else {1};
            for (i,(loc,_)) in sh.cells.iter().filter(|(loc,_)|in_region(*loc)).enumerate() {
                if i%stride==0 || i+1==overview_total {cells.insert(loc.a1(),overview_cell(inspect(loc)));}
            }
        }
        for &r in &row_indices {
            for &c in &col_indices {
                let loc=CellRef::new(r,c);
                if sh.cell(loc).is_some() || sh.spill.contains_key(&loc) || sh.style_id(loc)!=Default::default() {
                    cells.insert(loc.a1(),inspect(loc));
                }
            }
        }
        // Include anchors even when the visible portion starts inside a merge.
        for merge in &sh.merges {
            let intersects=if overview {in_region(merge.start) && cells.len()<OVERVIEW_CAP} else {
                row_indices.iter().any(|r|*r>=merge.start.row && *r<=merge.end.row) &&
                col_indices.iter().any(|c|*c>=merge.start.col && *c<=merge.end.col)
            };
            if intersects {
                let cell=inspect(merge.start);
                cells.insert(merge.start.a1(),if overview {overview_cell(cell)} else {cell});
            }
        }
        let selection=inspect(selected);
        let mut used=sh.used_range().map(|r|[r.start.row,r.start.col,r.end.row,r.end.col]).unwrap_or([0,0,0,0]);
        for m in &sh.merges {
            used[0]=used[0].min(m.start.row);used[1]=used[1].min(m.start.col);
            used[2]=used[2].max(m.end.row);used[3]=used[3].max(m.end.col);
        }
        let sheets:Vec<_>=wb.sheets.iter().enumerate().map(|(i,s)|json!({"index":i,"name":s.name,
            "cells":if i as u64==idx {Json::Object(cells.clone())} else {json!({})},
            "protected":s.protection.is_some() || wb.protected_structure})).collect();
        let layout=json!({"defaultRowHeight":valid_extent(sh.default_row_height,20.0),
            "defaultColumnWidth":valid_extent(sh.default_col_width,64.0),
            "rows":axis_runs(&sh.rows,sh.default_row_height),"columns":axis_runs(&sh.cols,sh.default_col_width),
            "merges":sh.merges.iter().map(|m|[m.start.row,m.start.col,m.end.row,m.end.col]).collect::<Vec<_>>(),
            "showGridlines":sh.show_gridlines,"usedRange":used});
        serde_json::to_vec(&json!({"type":"xlsx","engine":"gridcraft","sheets":sheets,
            "selection":selection,"window":req,"layout":layout,"warnings":report.warnings,
            "overviewTruncated":overview && overview_total>OVERVIEW_CAP,"overviewTotalCells":overview_total,
            "note":"Windowed cell view; imported layout is approximate and cached formula values may be stale."})).map_err(|e|e.to_string())
    })
}

#[cfg(test)]
mod window_tests {
    use super::*;
    fn view(bytes:&[u8], req:Json)->Result<Json,String> {
        let request=req.to_string();
        let r=ac_xlsx_inspect_window(bytes.as_ptr(),bytes.len(),request.as_ptr(),request.len());
        let data=unsafe{std::slice::from_raw_parts(r.ptr,r.len)}.to_vec();
        let status=r.status; super::super::ac_result_free(r);
        if status==0 {Ok(serde_json::from_slice(&data).unwrap())} else {Err(String::from_utf8_lossy(&data).into_owned())}
    }
    #[test]
    fn whole_book_overview_reads_last_row_without_rectangle_limit_or_mutation() {
        let mut wb=Workbook::new();
        for row in 0..232 {for col in 0..11 {
            wb.sheet_mut(0).unwrap().set_value(CellRef::new(row,col),Value::number((row*11+col) as f64));
        }}
        let original=write(&wb).unwrap();
        let mut req=json!({"sheet":0,"row":0,"column":0,"rows":232,"columns":11,"selected":"K232"});
        assert!(view(&original,req.clone()).is_err());
        req["overview"]=json!(true);
        let overview=view(&original,req).unwrap();
        assert_eq!(overview["layout"]["usedRange"],json!([0,0,231,10]));
        assert_eq!(overview["overviewTruncated"],false);
        assert_eq!(overview["sheets"][0]["cells"].as_object().unwrap().len(),2552);
        assert_eq!(overview["sheets"][0]["cells"]["K232"]["display"],"2551");
        assert_eq!(overview["selection"]["input"],"2551");
        assert_eq!(workbook(&original).unwrap().sheet(0).unwrap().cells.len(),2552);
    }
    #[test]
    fn overview_caps_sparse_cells_and_text_across_the_entire_excel_range() {
        let mut wb=Workbook::new();
        for row in 0..20000 {
            wb.sheet_mut(0).unwrap().set_value(CellRef::new(row*25,0),Value::number(row as f64));
        }
        put(&mut wb,0,"A1",&"x".repeat(1000)).unwrap();
        let bytes=write(&wb).unwrap();
        let overview=view(&bytes,json!({"overview":true,"sheet":0,"row":0,"column":0,"rows":1048576,"columns":16384,"selected":"A1"})).unwrap();
        let cells=overview["sheets"][0]["cells"].as_object().unwrap();
        assert!(cells.len()<=8192);
        assert!(cells.contains_key("A499976"));
        assert_eq!(cells["A1"]["display"].as_str().unwrap().len(),512);
        assert!(cells["A1"].get("input").is_none());
        assert_eq!(overview["selection"]["input"].as_str().unwrap().len(),1000);
        assert_eq!(overview["overviewTruncated"],true);
        assert_eq!(overview["overviewTotalCells"],20000);
    }
    #[test]
    fn overview_rejects_ambiguous_and_invalid_requests() {
        let bytes=write(&Workbook::new()).unwrap();
        for patch in [json!({"overview":"yes"}),json!({"rowIndices":[0]}),json!({"rows":0}),json!({"columns":16385}),json!({"row":1048576})] {
            let mut request=json!({"overview":true,"sheet":0,"row":0,"column":0,"rows":1048576,"columns":16384,"selected":"A1"});
            request.as_object_mut().unwrap().extend(patch.as_object().unwrap().clone());
            assert!(view(&bytes,request).is_err());
        }
    }
    #[test]
    fn window_finds_dense_and_far_cells_without_global_cutoff() {
        let mut wb=Workbook::new();
        for r in 0..100 {for c in 0..25 {
            wb.sheet_mut(0).unwrap().set_value(CellRef::new(r,c),Value::number((r*25+c) as f64));
        }}
        let far=CellRef::parse("XFD1048576").unwrap();
        wb.sheet_mut(0).unwrap().set_value(far,Value::text("last cell"));
        let bytes=write(&wb).unwrap();
        let middle=view(&bytes,json!({"sheet":0,"row":70,"column":20,"rows":20,"columns":12,"selected":"A1"})).unwrap();
        assert_eq!(middle["sheets"][0]["cells"]["Y90"]["display"],"2249");
        assert_eq!(middle["selection"]["input"],"0");
        assert!(middle["sheets"][0]["cells"].get("A1").is_none());
        let end=view(&bytes,json!({"sheet":0,"row":1048575,"column":16383,"rows":1,"columns":1,"selected":"XFD1048576"})).unwrap();
        assert_eq!(end["selection"]["input"],"last cell");
        assert_eq!(end["sheets"][0]["cells"]["XFD1048576"]["display"],"last cell");
    }
    #[test]
    fn independent_import_geometry_merges_and_finger_resize_roundtrip() {
        let original=include_bytes!("../../../test/fixtures/formatted-grid.xlsx").as_slice();
        let req=json!({"sheet":0,"row":1,"column":1,"rows":4,"columns":4,"rowIndices":[1,3,4],"columnIndices":[1,2,4],"selected":"B2"});
        let imported=view(original,req.clone()).unwrap();
        assert_eq!(imported["selection"]["address"],"A1");
        assert_eq!(imported["selection"]["input"],"Imported merged title");
        assert_eq!(imported["sheets"][0]["cells"]["A1"]["style"]["fill"],"#225599");
        assert_eq!(imported["selection"]["style"]["verticalAlign"],"center");
        assert_eq!(imported["layout"]["merges"],json!([[0,0,1,2]]));
        assert_eq!(imported["layout"]["showGridlines"],false);
        assert!((imported["layout"]["rows"][0][2].as_f64().unwrap()-40.0*4.0/3.0).abs()<0.01);
        let mut edited=original.to_vec();
        for edit in [json!({"action":"columnWidth","sheet":0,"address":"A1","index":0,"size":231}),
            json!({"action":"rowHeight","sheet":0,"address":"A1","index":3,"size":96}),
            json!({"sheet":0,"address":"B2","value":"Changed merged title"})] {
            let text=edit.to_string();
            let r=ac_xlsx_set_cell(edited.as_ptr(),edited.len(),text.as_ptr(),text.len());
            assert_eq!(r.status,0); edited=unsafe{std::slice::from_raw_parts(r.ptr,r.len)}.to_vec();super::super::ac_result_free(r);
        }
        let reread=view(&edited,req).unwrap();
        assert_eq!(reread["selection"]["input"],"Changed merged title");
        assert_eq!(reread["layout"]["merges"],imported["layout"]["merges"]);
        let book=workbook(&edited).unwrap();let sh=book.sheet(0).unwrap();
        assert_eq!(sh.col_width(0),231.0);assert_eq!(sh.row_height(3),96.0);
        assert_eq!(sh.row_height(2),0.0);assert_eq!(sh.col_width(3),0.0);
        assert_eq!(sh.input_text(CellRef::parse("B5").unwrap()),"=A5+22");
        assert_eq!(view(original,json!({"sheet":0,"row":0,"column":0,"rows":1,"columns":1,"selected":"A1"})).unwrap()["selection"]["input"],"Imported merged title");
    }
    #[test]
    fn sparse_window_spans_hidden_rows_without_unbounded_cell_work() {
        let bytes=write(&Workbook::new()).unwrap();
        let req=json!({"sheet":0,"row":0,"column":0,"rows":1048576,"columns":16384,
            "rowIndices":[0,1048575],"columnIndices":[0,16383],"selected":"XFD1048576"});
        assert!(view(&bytes,req.clone()).is_ok());
        for patch in [json!({"rowIndices":[0,0]}),json!({"columnIndices":[16384]}),json!({"rowIndices":[]}),json!({"rowIndices":[4,2]})] {
            let mut bad=req.clone();bad.as_object_mut().unwrap().extend(patch.as_object().unwrap().clone());
            assert!(view(&bytes,bad).is_err());
        }
    }
    #[test]
    fn window_rejects_invalid_bounds_and_selection_without_panicking() {
        let bytes=write(&Workbook::new()).unwrap();
        for patch in [json!({"row":-1}),json!({"rows":0}),json!({"rows":129}),json!({"column":16383,"columns":2}),json!({"selected":"XFE1"}),json!({"sheet":999})] {
            let mut req=json!({"sheet":0,"row":0,"column":0,"rows":32,"columns":16,"selected":"A1"});
            req.as_object_mut().unwrap().extend(patch.as_object().unwrap().clone());
            assert!(view(&bytes,req).is_err());
        }
    }
}
#[cfg(test)]
mod tests{
    use super::*;
    fn decode_result(r:AcResult)->Vec<u8>{
        let bytes=if r.len==0{Vec::new()} else {unsafe{std::slice::from_raw_parts(r.ptr,r.len).to_vec()}};
        let status=r.status;super::super::ac_result_free(r);
        if status !=0 {panic!("GridCraft error: {}",String::from_utf8_lossy(&bytes));}
        bytes
    }
    #[test]
    fn create_edit_formula_roundtrip(){
        let initial=decode_result(ac_xlsx_create(std::ptr::null(),0));
        assert!(initial.starts_with(b"PK"));
        let edit=|bytes:&Vec<u8>, address:&str, value:&str| {
            let req=json!({"sheet":0,"address":address,"value":value}).to_string();
            decode_result(ac_xlsx_set_cell(bytes.as_ptr(),bytes.len(),req.as_ptr(),req.len()))
        };
        let a=edit(&initial,"A1","12");
        let b=edit(&a,"B1","8");
        let c=edit(&b,"C1","=SUM(A1:B1)");
        let wb=workbook(&c).unwrap();
        let sh=wb.sheet(0).unwrap();
        assert_eq!(sh.cell(CellRef::parse("A1").unwrap()).unwrap().value,Value::number(12.0));
        assert_eq!(sh.cell(CellRef::parse("B1").unwrap()).unwrap().value,Value::number(8.0));
        let cell=sh.cell(CellRef::parse("C1").unwrap()).unwrap();
        assert!(cell.formula.is_some());
        let report=decode_result(ac_xlsx_inspect(c.as_ptr(),c.len()));
        let inspected:Json=serde_json::from_slice(&report).unwrap();
        assert_eq!(inspected["sheets"][0]["cells"]["C1"]["input"],"=SUM(A1:B1)");
    }
    #[test]
    fn invalid_file_fails_without_panicking(){
        let r=ac_xlsx_inspect(b"invalid".as_ptr(),7);
        assert_ne!(r.status,0);
        super::super::ac_result_free(r);
    }
}

#[cfg(test)]
mod formatting_tests {
    use super::*;
    fn edit(bytes:&[u8],request:Json)->Vec<u8> {
        let req=request.to_string();
        let r=ac_xlsx_set_cell(bytes.as_ptr(),bytes.len(),req.as_ptr(),req.len());
        let result=unsafe {std::slice::from_raw_parts(r.ptr,r.len).to_vec()};
        let status=r.status;super::super::ac_result_free(r);
        assert_eq!(status,0,"{}",String::from_utf8_lossy(&result));result
    }
    #[test]
    fn autosum_chooses_vertical_then_horizontal_and_preserves_style() {
        let mut wb=Workbook::new();
        for (address,value) in [("A1",12.0),("A2",8.0),("B3",4.0),("C3",6.0)] {
            wb.sheet_mut(0).unwrap().set_value(CellRef::parse(address).unwrap(),Value::number(value));
        }
        let bytes=write(&wb).unwrap();
        let styled=edit(&bytes,json!({"action":"format","sheet":0,"address":"A3","style":{"numFmt":"0.00","fill":"#E2F0D9"}}));
        let vertical=edit(&styled,json!({"action":"autosum","sheet":0,"address":"A3"}));
        let horizontal=edit(&vertical,json!({"action":"autosum","sheet":0,"address":"D3"}));
        let result=workbook(&horizontal).unwrap();let sh=result.sheet(0).unwrap();
        assert_eq!(sh.input_text(CellRef::parse("A3").unwrap()),"=SUM(A1:A2)");
        assert_eq!(sh.cell(CellRef::parse("A3").unwrap()).unwrap().value,Value::number(20.0));
        assert_eq!(sh.input_text(CellRef::parse("D3").unwrap()),"=SUM(A3:C3)");
        assert_eq!(sh.cell(CellRef::parse("D3").unwrap()).unwrap().value,Value::number(30.0));
        let style=result.styles.get(sh.style_id(CellRef::parse("A3").unwrap()));
        assert_eq!(style.num_fmt.as_str(),"0.00");assert_eq!(style.fill.fg,Color::Rgb(0xE2F0D9));
        assert!(workbook(&styled).unwrap().sheet(0).unwrap().input_text(CellRef::parse("A3").unwrap()).is_empty());
    }
    #[test]
    fn calculation_actions_reject_nonempty_missing_range_and_protection_without_mutation() {
        let mut wb=Workbook::new();put(&mut wb,0,"A1","12").unwrap();put(&mut wb,0,"B1","=0").unwrap();
        let bytes=write(&wb).unwrap();
        for request in [json!({"action":"autosum","sheet":0,"address":"A1"}),
            json!({"action":"autosum","sheet":0,"address":"B1"}),
            json!({"action":"autosum","sheet":0,"address":"Z99"}),
            json!({"action":"recalculate","sheet":0,"address":"XFE1"}),
            json!({"action":"autosum","sheet":0,"address":"A2","value":"erase"})] {
            let req=request.to_string();let r=ac_xlsx_set_cell(bytes.as_ptr(),bytes.len(),req.as_ptr(),req.len());
            assert_ne!(r.status,0);super::super::ac_result_free(r);
        }
        wb.protected_structure=true;
        for action in ["autosum","recalculate"] {
            let protected=write(&wb).unwrap();let req=json!({"action":action,"sheet":0,"address":"A2"}).to_string();
            let r=ac_xlsx_set_cell(protected.as_ptr(),protected.len(),req.as_ptr(),req.len());
            assert_ne!(r.status,0);super::super::ac_result_free(r);
        }
        assert_eq!(workbook(&bytes).unwrap().sheet(0).unwrap().input_text(CellRef::parse("A1").unwrap()),"12");
    }
    #[test]
    fn recalculate_refreshes_imported_stale_formula_and_keeps_geometry() {
        let mut wb=Workbook::new();put(&mut wb,0,"A1","12").unwrap();put(&mut wb,0,"B1","8").unwrap();
        let mut stale=Cell::formula(Formula::new("=A1+B1"));stale.value=Value::number(999.0);
        wb.sheet_mut(0).unwrap().set_cell(CellRef::parse("C1").unwrap(),stale);
        wb.sheet_mut(0).unwrap().cols.entry(0).or_default().size=Some(193.0);
        let original=write(&wb).unwrap();
        let result=edit(&original,json!({"action":"recalculate","sheet":0,"address":"A1"}));
        let reopened=workbook(&result).unwrap();let sh=reopened.sheet(0).unwrap();
        assert_eq!(sh.cell(CellRef::parse("C1").unwrap()).unwrap().value,Value::number(20.0));
        assert_eq!(sh.input_text(CellRef::parse("C1").unwrap()),"=A1+B1");assert_eq!(sh.col_width(0),193.0);
        assert_eq!(workbook(&original).unwrap().sheet(0).unwrap().cell(CellRef::parse("C1").unwrap()).unwrap().value,Value::number(999.0));
    }
    #[test]
    fn styles_survive_values_formulas_clear_and_xlsx_reopen() {
        let initial=write(&Workbook::new()).unwrap();
        let styled=edit(&initial,json!({"action":"format","sheet":0,"address":"B2","value":"12,5",
            "style":{"bold":true,"italic":true,"underline":true,"fontSize":18,"fill":"#E8F5E9","color":"#123456","align":"center","wrap":true,"borders":"all","numFmt":"0.00%"}}));
        for bytes in [styled.clone(),edit(&styled,json!({"sheet":0,"address":"B2","value":"=1/2"})),edit(&styled,json!({"sheet":0,"address":"B2","value":""}))] {
            let wb=workbook(&bytes).unwrap();let sh=wb.sheet(0).unwrap();let c=sh.cell(CellRef::parse("B2").unwrap()).unwrap();let style=wb.styles.get(c.style);
            assert!(style.font.bold && style.font.italic && style.align.wrap);
            assert_eq!(style.font.size,18.0);assert_eq!(style.fill.fg,Color::Rgb(0xE8F5E9));assert_eq!(style.font.color,Color::Rgb(0x123456));
            assert_eq!(style.align.h,HAlign::Center);assert_eq!(style.num_fmt.as_str(),"0.00%");assert!(!style.borders.left.is_none());
        }
        let changed=edit(&styled,json!({"sheet":0,"address":"B2","value":"=1/2"}));
        let r=ac_xlsx_inspect(changed.as_ptr(),changed.len());
        assert_eq!(r.status,0);let json:Json=serde_json::from_slice(unsafe {std::slice::from_raw_parts(r.ptr,r.len)}).unwrap();super::super::ac_result_free(r);
        assert_eq!(json["sheets"][0]["cells"]["B2"]["display"],"50.00%");
        assert_eq!(json["sheets"][0]["cells"]["B2"]["input"],"=1/2");
    }
    #[test]
    fn text_format_preserves_leading_zeroes_and_literal_formulas() {
        let initial=write(&Workbook::new()).unwrap();
        let text=edit(&initial,json!({"action":"format","sheet":0,"address":"A1","value":"00123","style":{"numFmt":"@"}}));
        let wb=workbook(&text).unwrap();assert_eq!(wb.sheet(0).unwrap().cell(CellRef::parse("A1").unwrap()).unwrap().value,Value::text("00123"));
        let text=edit(&text,json!({"sheet":0,"address":"A1","value":"=1+1"}));
        let wb=workbook(&text).unwrap();let cell=wb.sheet(0).unwrap().cell(CellRef::parse("A1").unwrap()).unwrap();
        assert_eq!(cell.value,Value::text("=1+1"));assert!(cell.formula.is_none());
    }
    #[test]
    fn style_rejects_invalid_patches_without_changing_input() {
        let initial=write(&Workbook::new()).unwrap();
        for style in [json!({"fontSize":1000}),json!({"fill":"bad"}),json!({"bold":"yes"}),json!({"unknown":true})] {
            let req=json!({"action":"format","sheet":0,"address":"A1","style":style}).to_string();
            let r=ac_xlsx_set_cell(initial.as_ptr(),initial.len(),req.as_ptr(),req.len());assert_ne!(r.status,0);super::super::ac_result_free(r);
        }
        assert!(workbook(&initial).unwrap().sheet(0).unwrap().cells.is_empty());
    }
    #[test]
    fn formatting_does_not_change_formula_or_numeric_value() {
        let initial=write(&Workbook::new()).unwrap();
        let entered=edit(&initial,json!({"sheet":0,"address":"A1","value":"12,5"}));
        let output=edit(&entered,json!({"sheet":0,"address":"A1","action":"format","style":{"numFmt":"#,##0.00 \"₽\""}}));
        let wb=workbook(&output).unwrap();assert_eq!(wb.sheet(0).unwrap().cell(CellRef::parse("A1").unwrap()).unwrap().value,Value::number(12.5));
    }
}
