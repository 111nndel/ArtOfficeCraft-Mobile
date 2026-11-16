//! Mobile bounds around GridCraft's existing directional fill commands.
use gridcraft_core::{CellRef, RangeRef};
use gridcraft_model::Workbook;
use serde_json::{Value as Json, json};
use super::grid::{checked_edit_range, command_session, put, write};

pub(super) fn edit(mut wb: Workbook, sheet: usize, address: &str, request: &Json) -> Result<Vec<u8>, String> {
    let range = checked_edit_range(&wb, sheet, request)?;
    let active = CellRef::parse(address).ok_or("Invalid A1 reference")?;
    let command = match request["direction"].as_str() {
        Some("down") if range.height() > 1 => "edit.fillDown",
        Some("right") if range.width() > 1 => "edit.fillRight",
        _ => return Err("Select the source and at least one destination row or column".into()),
    };
    let sh = wb.sheet(sheet).unwrap();
    if sh.merges.iter().any(|r| r.intersects(&range)) ||
        sh.tables.iter().any(|t| t.range.intersects(&range)) {
        return Err("Fill requires an unmerged range outside Excel tables".into());
    }
    if sh.spill_ranges.values().any(|r| r.intersects(&range)) ||
        sh.cells.iter().any(|(at, c)| c.formula.as_ref().is_some_and(|f|
            f.array.is_some_and(|r| r.intersects(&range)) ||
            f.dynamic && range.contains_range(&RangeRef::cell(at)))) {
        return Err("Array and spilled formula ranges cannot be filled in this preview".into());
    }
    let pending = request.get("value");
    if let Some(value) = pending {
        if !range.contains_range(&RangeRef::cell(active)) {
            return Err("Pending input must be inside the selected range".into());
        }
        put(&mut wb, sheet, address, value.as_str().ok_or("Cell input must be text")?)?;
    }
    let mut session = command_session(wb, sheet, active)?;
    session.execute(command, json!({"sheet": sheet, "range": range.a1()})).map_err(|e| e.to_string())?;
    let doc = session.doc_mut().map_err(|e| e.to_string())?;
    if pending.is_some() {
        gridcraft_calc::Calc::new().recalc_all(std::sync::Arc::make_mut(&mut doc.wb));
    }
    write(&doc.wb)
}

#[cfg(test)]
mod tests {
    use super::*;
    use gridcraft_core::Value;
    use gridcraft_model::{Cell, Formula};
    use gridcraft_model::style::Style;
    use crate::grid::{ac_xlsx_set_cell, workbook};

    fn at(s: &str) -> CellRef { CellRef::parse(s).unwrap() }
    fn invoke(bytes: &[u8], mut req: Json) -> Result<Vec<u8>, String> {
        req["action"] = json!("fill_range"); req["sheet"] = json!(0);
        if req.get("address").is_none() { req["address"] = json!("B1"); }
        let text = req.to_string();
        let r = ac_xlsx_set_cell(bytes.as_ptr(), bytes.len(), text.as_ptr(), text.len());
        let out = unsafe { std::slice::from_raw_parts(r.ptr, r.len) }.to_vec();
        let status = r.status; crate::ac_result_free(r);
        if status == 0 { Ok(out) } else { Err(String::from_utf8_lossy(&out).into_owned()) }
    }
    fn source() -> Workbook {
        let mut wb = Workbook::new();
        let mut style = Style::default(); style.font.bold = true;
        let id = wb.styles.intern(style);
        let sh = wb.sheet_mut(0).unwrap();
        for (address, value) in [("A1", 10.0), ("A2", 20.0), ("A3", 30.0), ("C2", 123.0)] {
            sh.set_value(at(address), Value::number(value));
        }
        sh.set_cell(at("B1"), Cell::styled(Value::text("original"), id));
        wb
    }
    #[test]
    fn down_and_right_rebase_mixed_references_and_keep_format_on_saved_xlsx() {
        let mut wb = source();
        wb.sheet_mut(0).unwrap().set_cell(at("D1"), Cell::formula(Formula::new("=SUM(B1:B3)")));
        let original = write(&wb).unwrap();
        let out = invoke(&original, json!({"range":"B1:B3", "direction":"down", "value":"=A1+$A$1+A$1+$A1"})).unwrap();
        let saved = workbook(&out).unwrap(); let sh = saved.sheet(0).unwrap();
        assert_eq!(sh.input_text(at("B2")), "=A2+$A$1+A$1+$A2");
        assert_eq!(sh.input_text(at("B3")), "=A3+$A$1+A$1+$A3");
        assert_eq!(sh.value(at("B3")), Value::number(80.0));
        assert_eq!(sh.value(at("D1")), Value::number(180.0));
        assert!(saved.styles.get(sh.style_id(at("B3"))).font.bold);
        assert_eq!(sh.value(at("C2")), Value::number(123.0));
        assert_eq!(workbook(&original).unwrap().sheet(0).unwrap().input_text(at("B1")), "original");
        let out = invoke(&write(&source()).unwrap(), json!({"range":"B1:D1", "direction":"right", "value":"=A1+$A$1+A$1+$A1"})).unwrap();
        let saved = workbook(&out).unwrap(); let sh = saved.sheet(0).unwrap();
        assert_eq!(sh.input_text(at("C1")), "=B1+$A$1+B$1+$A1");
        assert_eq!(sh.value(at("D1")), Value::number(220.0));
        assert!(saved.styles.get(sh.style_id(at("D1"))).font.bold);
    }
    #[test]
    fn fill_keeps_filtered_rows_and_the_saved_filter() {
        let mut wb = source(); let sh = wb.sheet_mut(0).unwrap();
        for (address, text) in [("A1","Name"), ("B1","Value"), ("A2","keep"), ("A3","hide"), ("A4","keep")] {
            sh.set_value(at(address), Value::text(text));
        }
        sh.set_value(at("B2"), Value::number(7.0));
        sh.set_value(at("B3"), Value::number(99.0));
        let filtered = crate::grid_filter::edit(wb, 0, &json!({"range":"A1:B4","column":"A","values":["keep"]})).unwrap();
        let out = invoke(&filtered, json!({"address":"B2","range":"B2:B4","direction":"down"})).unwrap();
        let saved = workbook(&out).unwrap(); let sh = saved.sheet(0).unwrap();
        assert_eq!(sh.value(at("B3")), Value::number(99.0));
        assert_eq!(sh.value(at("B4")), Value::number(7.0));
        assert!(sh.is_row_filtered(2)); assert!(sh.autofilter.is_some());
    }
    #[test]
    fn invalid_protected_merged_array_and_table_ranges_are_refused() {
        let original = write(&source()).unwrap();
        for req in [json!({"range":"A1:A4097","direction":"down"}),
                    json!({"range":"A1","direction":"down"}),
                    json!({"range":"A1:A3","direction":"right"}),
                    json!({"range":"A1:A3","direction":"left"}),
                    json!({"range":"A1:A3","direction":"down","value":"outside"})] {
            assert!(invoke(&original, req).is_err());
        }
        for workbook_lock in [true, false] {
            let mut wb = source();
            if workbook_lock { wb.protected_structure = true; }
            else { wb.sheet_mut(0).unwrap().protection = Some(Default::default()); }
            assert!(invoke(&write(&wb).unwrap(), json!({"range":"B1:B3","direction":"down"})).is_err());
        }
        let area = RangeRef::parse("B1:B3").unwrap();
        let mut wb = source(); wb.sheet_mut(0).unwrap().merges.push(area);
        assert!(invoke(&write(&wb).unwrap(), json!({"range":"B1:B3","direction":"down"})).is_err());
        for dynamic in [true, false] {
            let mut wb = source(); let mut f = Formula::new("=1");
            f.dynamic = dynamic; if !dynamic { f.array = Some(area); }
            wb.sheet_mut(0).unwrap().set_cell(at("B1"), Cell::formula(f));
            assert!(edit(wb, 0, "B1", &json!({"range":"B1:B3","direction":"down"})).is_err());
        }
        let mut session = command_session(source(), 0, at("A1")).unwrap();
        session.execute("insert.table", json!({"range":"A1:B3","header":true,"name":"Data"})).unwrap();
        assert!(invoke(&write(&session.doc().unwrap().wb).unwrap(), json!({"range":"B1:B3","direction":"down"})).is_err());
    }
}
