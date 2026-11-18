//! Mobile sheet actions reuse GridCraft's reference-aware structural commands.
use gridcraft_core::CellRef;
use gridcraft_model::{Visibility, Workbook};
use serde_json::{Value as Json, json};
use std::sync::Arc;

use super::grid::{command_session, put, write};

pub(super) fn edit(mut wb: Workbook, sheet: usize, address: &str, req: &Json) -> Result<Vec<u8>, String> {
    let active = CellRef::parse(address).ok_or("Invalid A1 reference")?;
    wb.sheet(sheet).ok_or("Sheet index out of bounds")?;
    if wb.protected_structure { return Err("Workbook structure is protected".into()); }
    let legacy = req["action"] == "add_sheet";
    let op = if legacy { "add" } else { req["operation"].as_str().ok_or("Missing sheet operation")? };
    if legacy && req.get("value").is_some() { return Err("Add sheet does not accept a cell value".into()); }
    let index = |key: &str| req[key].as_u64().and_then(|v| usize::try_from(v).ok())
        .filter(|&i| i < wb.sheets.len()).ok_or_else(|| format!("Invalid sheet {key}"));
    let mut params = json!({"sheet":sheet});
    let command = match op {
        "add" => {
            if wb.sheets.len() >= 256 { return Err("Mobile editor supports at most 256 sheets".into()); }
            params["before"] = json!(wb.sheets.len());
            "home.insertSheet"
        }
        "rename" => "sheet.rename",
        "move" => { params["to"] = json!(index("to")?); params["copy"] = json!(false); "sheet.move" }
        "delete" => "home.deleteSheet",
        "hide" => "sheet.hide",
        "unhide" => { params["sheet"] = json!(index("target")?); "sheet.unhide" }
        _ => return Err("Unknown sheet operation".into()),
    };
    if matches!(op, "add" | "rename") {
        if let Some(value) = req.get("name") {
            let name = value.as_str().ok_or("Sheet name must be text")?;
            if name.chars().any(char::is_control) { return Err("Sheet name contains control characters".into()); }
            params["name"] = json!(name);
        } else if op == "rename" { return Err("Missing sheet name".into()); }
    }
    if let Some(value) = req.get("value") {
        put(&mut wb, sheet, address, value.as_str().ok_or("Cell input must be text")?)?;
    }
    let mut session = command_session(wb, sheet, active)?;
    session.execute(command, params).map_err(|e| e.to_string())?;
    let doc = session.doc_mut().map_err(|e| e.to_string())?;
    let wb = Arc::make_mut(&mut doc.wb);
    if op == "delete" {
        // A deleted tab can have a hidden neighbour; never activate that hidden tab.
        let start = sheet.min(wb.sheets.len().saturating_sub(1));
        let next = (start..wb.sheets.len()).chain((0..start).rev())
            .find(|&i| wb.sheets[i].visibility == Visibility::Visible)
            .ok_or("A workbook must contain a visible sheet")?;
        wb.set_active_sheet(next);
    }
    if req.get("value").is_some() { gridcraft_calc::Calc::new().recalc_all(wb); }
    write(wb)
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::grid::{ac_xlsx_set_cell, workbook};
    use gridcraft_core::{RangeRef, Value};
    use gridcraft_model::{DefinedName, Sheet};

    fn at(s: &str) -> CellRef { CellRef::parse(s).unwrap() }
    fn source() -> Workbook {
        let mut wb = Workbook::new();
        wb.sheet_mut(0).unwrap().name = "Source".into();
        put(&mut wb, 0, "A1", "12").unwrap();
        wb.sheet_mut(0).unwrap().rows.entry(0).or_default().size = Some(74.0);
        wb.sheet_mut(0).unwrap().merges.push(RangeRef::parse("C3:D4").unwrap());
        wb.sheets.push(Arc::new(Sheet::new("Summary")));
        put(&mut wb, 1, "A1", "=Source!A1*2").unwrap();
        wb.names.push(DefinedName { name:"Amount".into(), scope:Some(0), formula:"Source!$A$1".into(), comment:String::new(), hidden:false });
        wb
    }
    fn invoke(bytes: &[u8], patch: Json) -> Result<Vec<u8>, String> {
        let mut req = json!({"action":"sheet_structure","sheet":0,"address":"A1"});
        req.as_object_mut().unwrap().extend(patch.as_object().unwrap().clone());
        let req = req.to_string();
        let result = ac_xlsx_set_cell(bytes.as_ptr(), bytes.len(), req.as_ptr(), req.len());
        let data = unsafe { std::slice::from_raw_parts(result.ptr, result.len) }.to_vec();
        let status = result.status; super::super::super::ac_result_free(result);
        if status == 0 { Ok(data) } else { Err(String::from_utf8_lossy(&data).into_owned()) }
    }
    #[test]
    fn rename_move_and_pending_input_preserve_references_scopes_and_geometry() {
        let original = write(&source()).unwrap();
        let renamed = invoke(&original, json!({"operation":"rename","name":"Итог '26","value":"17"})).unwrap();
        let wb = workbook(&renamed).unwrap();
        assert_eq!(wb.sheet(0).unwrap().name, "Итог '26");
        assert!(wb.sheet(1).unwrap().input_text(at("A1")).contains("'Итог ''26'!A1"));
        assert_eq!(wb.sheet(1).unwrap().value(at("A1")), Value::number(34.0));
        assert!(wb.names[0].formula.contains("Итог ''26"));
        let moved = invoke(&renamed, json!({"operation":"move","to":1})).unwrap();
        let wb = workbook(&moved).unwrap();
        assert_eq!(wb.active_sheet(), 1);
        assert_eq!(wb.names[0].scope, Some(1));
        assert_eq!(wb.sheet(1).unwrap().row_height(0), 74.0);
        assert_eq!(wb.sheet(1).unwrap().merges, source().sheet(0).unwrap().merges);
        assert_eq!(wb.sheet(0).unwrap().value(at("A1")), Value::number(34.0));
        assert_eq!(workbook(&original).unwrap().sheet(0).unwrap().value(at("A1")), Value::number(12.0));
    }
    #[test]
    fn hide_unhide_and_delete_keep_visible_active_sheet_and_invalidate_references() {
        let mut wb = source();
        wb.sheets.insert(1, Arc::new(Sheet::new("Hidden")));
        wb.sheet_mut(1).unwrap().visibility = Visibility::Hidden;
        let original = write(&wb).unwrap();
        let hidden = invoke(&original, json!({"operation":"hide"})).unwrap();
        assert_eq!(workbook(&hidden).unwrap().active_sheet(), 2);
        assert!(invoke(&hidden, json!({"operation":"hide","sheet":2})).is_err());
        let visible = invoke(&hidden, json!({"operation":"unhide","sheet":2,"target":0})).unwrap();
        assert_eq!(workbook(&visible).unwrap().active_sheet(), 0);
        assert_eq!(workbook(&visible).unwrap().sheet(0).unwrap().value(at("A1")), Value::number(12.0));
        let deleted = invoke(&original, json!({"operation":"delete"})).unwrap();
        let wb = workbook(&deleted).unwrap();
        assert_eq!(wb.active_sheet(), 1);
        assert_eq!(wb.sheets.len(), 2);
        assert!(wb.sheet(1).unwrap().input_text(at("A1")).contains("#REF!"));
        assert!(wb.names.is_empty());
        assert!(invoke(&deleted, json!({"operation":"delete","sheet":1})).is_err());
    }
    #[test]
    fn invalid_or_protected_operations_do_not_change_original_bytes() {
        let original = write(&source()).unwrap();
        for patch in [json!({"operation":"rename","name":"Summary"}), json!({"operation":"rename","name":"bad/name"}),
            json!({"operation":"rename","name":""}), json!({"operation":"rename","name":"bad\nname"}),
            json!({"operation":"move","to":999}), json!({"operation":"move","to":-1}),
            json!({"operation":"unhide","target":999}), json!({"operation":"copy"}), json!({"operation":"add","name":""})] {
            let mut patch = patch; patch["value"] = json!("pending");
            assert!(invoke(&original, patch).is_err());
        }
        assert_eq!(workbook(&original).unwrap().sheet(0).unwrap().value(at("A1")), Value::number(12.0));
        let mut protected = source(); protected.protected_structure = true;
        let bytes = write(&protected).unwrap();
        for op in ["add", "rename", "move", "delete", "hide", "unhide"] {
            assert!(invoke(&bytes, json!({"operation":op,"name":"Changed","to":1,"target":1})).is_err());
        }
        let mut full = source();
        while full.sheets.len() < 256 { full.sheets.push(Arc::new(Sheet::new(format!("Tab{}", full.sheets.len())))); }
        assert!(edit(full, 0, "A1", &json!({"operation":"add"})).is_err());
        assert!(edit(Workbook::new(), 0, "A1", &json!({"operation":"delete"})).is_err());
        assert!(edit(Workbook::new(), 0, "A1", &json!({"operation":"hide"})).is_err());
    }
}
