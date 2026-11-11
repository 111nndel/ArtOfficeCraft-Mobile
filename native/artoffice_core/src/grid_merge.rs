//! Bounded merge operations over the pinned GridCraft commands.
use gridcraft_core::{CellRef, RangeRef, Value};
use gridcraft_model::Workbook;
use serde_json::{Value as Json, json};
use super::grid::{checked_edit_range, command_session, put, write};

pub(super) fn edit(mut wb:Workbook, sheet:usize, address:&str, request:&Json)->Result<Vec<u8>,String> {
    let range=checked_edit_range(&wb,sheet,request)?;
    let active=CellRef::parse(address).ok_or("Invalid A1 reference")?;
    let mode=request["mode"].as_str().ok_or("Missing merge mode")?;
    if !matches!(mode,"merge"|"center"|"unmerge") {return Err("Unknown merge mode".into())}
    let sh=wb.sheet(sheet).unwrap();
    if sh.tables.iter().any(|table|table.range.intersects(&range)) {
        return Err("Merge/unmerge is not available inside Excel tables".into())
    }
    let affected=|r:&RangeRef| r.intersects(&range) ||
        request.get("value").is_some() && r.intersects(&RangeRef::cell(active));
    if sh.spill_ranges.values().any(affected) ||
        sh.cells.iter().any(|(at,c)|c.formula.as_ref().is_some_and(|f|
            f.array.is_some_and(|r|affected(&r)) || f.dynamic && affected(&RangeRef::cell(at)))) {
        return Err("Array and spilled formula ranges cannot be merged or unmerged in this preview".into())
    }
    if mode=="unmerge" {
        if !sh.merges.iter().any(|m|m.intersects(&range)) {return Err("No merged cells in the selected range".into())}
    } else if range.is_single() {return Err("Select at least two cells to merge".into())}
    let pending=request.get("value");
    if let Some(value)=pending {put(&mut wb,sheet,address,value.as_str().ok_or("Cell input must be text")?)?;}
    if mode!="unmerge" && request.get("allowContentLoss").and_then(Json::as_bool)!=Some(true) &&
        wb.sheet(sheet).unwrap().cells.iter_range(range).any(|(at,c)|at!=range.start &&
            (c.formula.is_some() || c.py.is_some() || c.value!=Value::Empty)) {
        return Err("Confirm clearing other populated cells before merging".into())
    }
    let mut session=command_session(wb,sheet,active)?;
    let params=json!({"sheet":sheet,"range":range.a1()});
    // mergeCenter is an upstream toggle. Explicit commands keep repeated Center
    // actions idempotent instead of accidentally unmerging an existing range.
    session.execute(if mode=="unmerge" {"home.unmergeCells"} else {"home.mergeCells"},params.clone()).map_err(|e|e.to_string())?;
    if mode=="center" {session.execute("home.alignCenter",params).map_err(|e|e.to_string())?;}
    let doc=session.doc_mut().map_err(|e|e.to_string())?;
    if pending.is_some() {gridcraft_calc::Calc::new().recalc_all(std::sync::Arc::make_mut(&mut doc.wb));}
    write(&doc.wb)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::grid::{workbook, ac_xlsx_set_cell, ac_xlsx_inspect_window};
    use gridcraft_model::{Cell, Formula, LineInfo};
    use gridcraft_model::style::{Style, Color, HAlign, PatternType};

    fn at(text:&str)->CellRef {CellRef::parse(text).unwrap()}
    fn invoke(bytes:&[u8], mut request:Json)->Result<Vec<u8>,String> {
        request["action"]=json!("merge_range");request["sheet"]=json!(0);
        if request.get("address").is_none() {request["address"]=json!("A1");}
        let text=request.to_string();
        let r=ac_xlsx_set_cell(bytes.as_ptr(),bytes.len(),text.as_ptr(),text.len());
        let out=unsafe{std::slice::from_raw_parts(r.ptr,r.len)}.to_vec();
        let status=r.status;crate::ac_result_free(r);
        if status==0 {Ok(out)} else {Err(String::from_utf8_lossy(&out).into_owned())}
    }
    fn source()->Workbook {
        let mut wb=Workbook::new();
        let mut style=Style::default();style.font.bold=true;
        style.fill.pattern=PatternType::Solid;style.fill.fg=Color::Rgb(0x225599);
        let style=wb.styles.intern(style);
        let sh=wb.sheet_mut(0).unwrap();
        sh.set_value(at("A1"),Value::number(12.0));sh.set_style(at("A1"),style);
        sh.set_value(at("B1"),Value::number(8.0));sh.set_style(at("B1"),style);
        sh.set_cell(at("F1"),Cell::formula(Formula::new("=SUM(A1:B1)")));
        sh.rows.insert(0,LineInfo{size:Some(45.0),custom:true,..Default::default()});
        sh.cols.insert(0,LineInfo{size:Some(120.0),custom:true,..Default::default()});
        gridcraft_calc::Calc::new().recalc_all(&mut wb);wb
    }

    #[test]
    fn centered_merge_and_unmerge_roundtrip_preserve_styles_layout_and_dependent_formulas() {
        let initial=write(&source()).unwrap();
        let merged=invoke(&initial,json!({"range":"A1:B2","mode":"center","allowContentLoss":true})).unwrap();
        let wb=workbook(&merged).unwrap();let sh=wb.sheet(0).unwrap();
        assert_eq!(sh.merges,[RangeRef::parse("A1:B2").unwrap()]);
        assert_eq!(sh.value(at("A1")),Value::number(12.0));
        assert_eq!(sh.value(at("B1")),Value::Empty);
        assert_eq!(sh.value(at("F1")),Value::number(12.0));
        assert_eq!(sh.input_text(at("F1")),"=SUM(A1:B1)");
        let style=wb.styles.get(sh.style_id(at("A1")));
        assert!(style.font.bold);assert_eq!(style.fill.fg,Color::Rgb(0x225599));
        assert_eq!(style.align.h,HAlign::Center);
        assert_eq!(sh.col_width(0),120.0);assert_eq!(sh.row_height(0),45.0);
        let again=invoke(&merged,json!({"range":"A1:B2","mode":"center"})).unwrap();
        assert_eq!(workbook(&again).unwrap().sheet(0).unwrap().merges,sh.merges);
        let unmerged=invoke(&again,json!({"range":"A1:B2","mode":"unmerge"})).unwrap();
        let wb=workbook(&unmerged).unwrap();let sh=wb.sheet(0).unwrap();
        assert!(sh.merges.is_empty());assert_eq!(sh.value(at("B1")),Value::Empty);
        assert!(wb.styles.get(sh.style_id(at("B1"))).font.bold);
        assert_eq!(workbook(&initial).unwrap().sheet(0).unwrap().value(at("B1")),Value::number(8.0));
    }

    #[test]
    fn hidden_empty_formula_requires_explicit_confirmation_and_has_content_metadata() {
        let mut wb=Workbook::new();
        wb.sheet_mut(0).unwrap().set_cell(at("B1"),Cell::formula(Formula::new("=\"\"")));
        gridcraft_calc::Calc::new().recalc_all(&mut wb);
        let initial=write(&wb).unwrap();
        let req=json!({"sheet":0,"row":0,"column":0,"rows":2,"columns":2,"selected":"A1"}).to_string();
        let r=ac_xlsx_inspect_window(initial.as_ptr(),initial.len(),req.as_ptr(),req.len());
        assert_eq!(r.status,0);
        let view:Json=serde_json::from_slice(unsafe{std::slice::from_raw_parts(r.ptr,r.len)}).unwrap();crate::ac_result_free(r);
        assert_eq!(view["sheets"][0]["cells"]["B1"]["hasContent"],true);
        assert_eq!(view["selection"]["hasContent"],false);
        for consent in [json!(false),json!(null),json!("true")] {
            assert!(invoke(&initial,json!({"range":"A1:B2","mode":"merge","allowContentLoss":consent,"value":"draft"})).is_err());
        }
        let merged=invoke(&initial,json!({"range":"A1:B2","mode":"merge","allowContentLoss":true})).unwrap();
        assert!(!workbook(&merged).unwrap().sheet(0).unwrap().cell(at("B1")).is_some_and(|c|c.formula.is_some()));
        assert!(workbook(&initial).unwrap().sheet(0).unwrap().cell(at("B1")).unwrap().formula.is_some());
    }

    #[test]
    fn pending_input_is_combined_with_merge_and_unmerge_without_changing_the_original() {
        let initial=write(&source()).unwrap();
        let merged=invoke(&initial,json!({"range":"A1:B2","mode":"merge","address":"B1","value":""})).unwrap();
        let unmerged=invoke(&merged,json!({"range":"A1:B2","mode":"unmerge","address":"B2","value":"15"})).unwrap();
        let wb=workbook(&unmerged).unwrap();let sh=wb.sheet(0).unwrap();
        assert!(sh.merges.is_empty());assert_eq!(sh.value(at("A1")),Value::number(15.0));
        assert_eq!(sh.value(at("B2")),Value::Empty);assert_eq!(sh.value(at("F1")),Value::number(15.0));
        assert!(wb.styles.get(sh.style_id(at("A1"))).font.bold);
        assert_eq!(workbook(&initial).unwrap().sheet(0).unwrap().value(at("A1")),Value::number(12.0));
    }

    #[test]
    fn invalid_partial_protected_and_array_ranges_are_rejected_before_publication() {
        let initial=write(&source()).unwrap();
        for (range,mode) in [("A1","merge"),("A1:B2","unknown"),("A1:XFD1048576","merge"),("XFE1:XFE2","merge"),("A0:B1","merge"),("A1:B2","unmerge")] {
            assert!(invoke(&initial,json!({"range":range,"mode":mode,"allowContentLoss":true})).is_err());
        }
        let merged=invoke(&initial,json!({"range":"A1:B2","mode":"merge","allowContentLoss":true})).unwrap();
        assert!(invoke(&merged,json!({"range":"B2:C3","mode":"unmerge"})).is_err());
        for workbook_lock in [false,true] {
            let mut wb=source();
            if workbook_lock {wb.protected_structure=true;} else {wb.sheet_mut(0).unwrap().protection=Some(Default::default());}
            for mode in ["merge","center","unmerge"] {
                assert!(invoke(&write(&wb).unwrap(),json!({"range":"A1:B2","mode":mode,"allowContentLoss":true})).is_err());
            }
        }
        let mut wb=source();
        let area=RangeRef::parse("J1:K2").unwrap();
        wb.sheet_mut(0).unwrap().spill_ranges.insert(at("J1"),area);
        assert!(edit(wb.clone(),0,"A1",&json!({"range":"J1:K2","mode":"merge","allowContentLoss":true})).is_err());
        assert!(edit(wb,0,"J1",&json!({"range":"A1:B2","mode":"center","value":"new","allowContentLoss":true})).is_err());
        let mut wb=source();let mut formula=Formula::new("=1");formula.array=Some(area);
        wb.sheet_mut(0).unwrap().set_cell(at("J1"),Cell::formula(formula));
        assert!(invoke(&write(&wb).unwrap(),json!({"range":"J1:K2","mode":"merge","allowContentLoss":true})).is_err());
        let mut wb=source();let mut formula=Formula::new("=SEQUENCE(2,2)");formula.dynamic=true;
        wb.sheet_mut(0).unwrap().set_cell(at("J1"),Cell::formula(formula));
        assert!(edit(wb,0,"A1",&json!({"range":"J1:K2","mode":"center","allowContentLoss":true})).is_err());
        let mut session=command_session(source(),0,at("A1")).unwrap();
        session.execute("insert.table",json!({"range":"A1:B3","header":true,"name":"Data"})).unwrap();
        let bytes=write(&session.doc().unwrap().wb).unwrap();
        for mode in ["merge","center","unmerge"] {
            assert!(invoke(&bytes,json!({"range":"A1:B2","mode":mode,"allowContentLoss":true})).unwrap_err().contains("Excel tables"));
        }
        let req=json!({"sheet":0,"row":0,"column":0,"rows":4,"columns":3,"selected":"A1"}).to_string();
        let r=ac_xlsx_inspect_window(bytes.as_ptr(),bytes.len(),req.as_ptr(),req.len());assert_eq!(r.status,0);
        let view:Json=serde_json::from_slice(unsafe{std::slice::from_raw_parts(r.ptr,r.len)}).unwrap();crate::ac_result_free(r);
        assert_eq!(view["layout"]["tables"],json!([[0,0,2,1]]));
    }
}
