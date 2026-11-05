//! Whole rows and columns, dispatched to the pinned GridCraft command engine.
use gridcraft_core::{CellRef, RangeRef, MAX_COLS, MAX_ROWS};
use gridcraft_model::Workbook;
use serde_json::{Value as Json, json};

use super::grid::{command_session, write};

const MAX_LINES: u64 = 256;

pub(super) fn edit(
    workbook: Workbook,
    sheet: usize,
    address: &str,
    request: &Json,
) -> Result<Vec<u8>, String> {
    if request.get("value").is_some() {
        return Err("Row and column operations do not accept cell input".into());
    }
    let rows = match request["axis"].as_str() {
        Some("rows") => true,
        Some("columns") => false,
        _ => return Err("Expected rows or columns".into()),
    };
    let insert = match request["operation"].as_str() {
        Some("insert") => true,
        Some("delete") => false,
        _ => return Err("Expected insert or delete".into()),
    };
    let limit = if rows { MAX_ROWS } else { MAX_COLS };
    let start = request["start"]
        .as_u64()
        .filter(|start| *start < u64::from(limit))
        .ok_or("Line index out of bounds")? as u32;
    let count = request["count"]
        .as_u64()
        .filter(|count| (1..=MAX_LINES).contains(count))
        .ok_or("Select 1 to 256 lines per operation")? as u32;
    let end = start + count;
    if end > limit {
        return Err("Selected lines extend past the sheet boundary".into());
    }
    let active = CellRef::parse(address).ok_or("Invalid A1 reference")?;
    let target = workbook.sheet(sheet).ok_or("Sheet index out of bounds")?;
    if workbook.protected_structure || target.is_protected() {
        return Err("Protected sheet cannot be changed".into());
    }
    if insert {
        // The engine guards populated cells. Also protect imported line sizes
        // and merged regions with empty tails at the edge of the worksheet.
        let first_lost = start.max(limit - count);
        let lines = if rows { &target.rows } else { &target.cols };
        let loses_merge = target.merges.iter().any(|range| {
            let last = if rows { range.end.row } else { range.end.col };
            last >= first_lost
        });
        if lines.range(first_lost..).next().is_some() || loses_merge {
            return Err("Insertion would shift sheet formatting past the boundary".into());
        }
    }
    let (command, params) = match (rows, insert) {
        (true, true) => ("home.insertRows", json!({"rows": RangeRef::rows(start, end - 1).a1()})),
        (true, false) => ("home.deleteRows", json!({"rows": RangeRef::rows(start, end - 1).a1()})),
        (false, true) => ("home.insertColumns", json!({"cols": RangeRef::cols(start, end - 1).a1()})),
        (false, false) => ("home.deleteColumns", json!({"cols": RangeRef::cols(start, end - 1).a1()})),
    };
    let mut session = command_session(workbook, sheet, active)?;
    session.execute(command, params).map_err(|error| error.to_string())?;
    write(&session.doc().map_err(|error| error.to_string())?.wb)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::grid::workbook;
    use gridcraft_core::Value;
    use gridcraft_model::{Cell, DefinedName, Formula, LineInfo, Sheet};
    use std::sync::Arc;

    fn address(text: &str) -> CellRef {
        CellRef::parse(text).unwrap()
    }

    fn change(
        before: &Workbook,
        axis: &str,
        operation: &str,
        start: u32,
        count: u32,
    ) -> Result<Workbook, String> {
        let request = json!({"axis": axis, "operation": operation, "start": start, "count": count});
        let bytes = edit(workbook(&write(before)?)?, 0, "A1", &request)?;
        workbook(&bytes)
    }

    #[test]
    fn rows_rewrite_other_sheets_and_names_and_preserve_layout_on_xlsx_reopen() {
        let mut before = Workbook::new();
        let mut style = gridcraft_model::style::Style::default();
        style.font.bold = true;
        let bold = before.styles.intern(style);
        let source = before.sheet_mut(0).unwrap();
        source.name = "Source".into();
        for (cell, number) in [("A2", 10.0), ("A3", 20.0), ("A4", 30.0)] {
            source.set_value(address(cell), Value::number(number));
        }
        source.set_cell(address("F1"), Cell::formula(Formula::new("=SUM(A2:A4)")));
        source.set_style(address("A4"), bold);
        source.rows.insert(2, LineInfo { hidden: true, ..LineInfo::default() });
        source.rows.insert(3, LineInfo { size: Some(45.0), ..LineInfo::default() });
        source.merges.push(RangeRef::parse("D4:E5").unwrap());
        source.set_value(address("D4"), Value::text("merged"));
        let mut summary = Sheet::new("Summary");
        summary.set_cell(address("A1"), Cell::formula(Formula::new("=Source!$A$4*2")));
        before.sheets.push(Arc::new(summary));
        before.names.push(DefinedName {
            name: "Amount".into(), scope: None, formula: "Source!$A$4".into(),
            comment: String::new(), hidden: false,
        });
        gridcraft_calc::Calc::new().recalc_all(&mut before);

        let inserted = change(&before, "rows", "insert", 2, 2).unwrap();
        let source = inserted.sheet(0).unwrap();
        assert_eq!(source.value(address("A3")), Value::Empty);
        assert_eq!(source.value(address("A5")), Value::number(20.0));
        assert_eq!(source.value(address("A6")), Value::number(30.0));
        assert_eq!(source.input_text(address("F1")), "=SUM(A2:A6)");
        assert_eq!(source.value(address("F1")), Value::number(60.0));
        assert!(inserted.styles.get(source.style_id(address("A6"))).font.bold);
        assert!(source.is_row_hidden(4));
        assert_eq!(source.rows[&5].size, Some(45.0));
        assert_eq!(source.merges, [RangeRef::parse("D6:E7").unwrap()]);
        assert_eq!(source.value(address("D6")), Value::text("merged"));
        assert_eq!(inserted.names[0].formula, "Source!$A$6");
        let summary = inserted.sheet(1).unwrap();
        assert_eq!(summary.input_text(address("A1")), "=Source!$A$6*2");
        assert_eq!(summary.value(address("A1")), Value::number(60.0));

        let deleted = change(&inserted, "rows", "delete", 4, 1).unwrap();
        let source = deleted.sheet(0).unwrap();
        assert_eq!(source.input_text(address("F1")), "=SUM(A2:A5)");
        assert_eq!(source.value(address("F1")), Value::number(40.0));
        assert_eq!(source.value(address("A5")), Value::number(30.0));
        assert_eq!(deleted.sheet(1).unwrap().input_text(address("A1")), "=Source!$A$5*2");
        assert_eq!(before.sheet(0).unwrap().value(address("A4")), Value::number(30.0));
    }

    #[test]
    fn columns_move_sizes_and_formulas_and_mark_deleted_references() {
        let mut before = Workbook::new();
        let source = before.sheet_mut(0).unwrap();
        source.set_value(address("B1"), Value::number(11.0));
        source.set_value(address("C1"), Value::number(12.0));
        source.set_cell(address("D1"), Cell::formula(Formula::new("=B1+C1")));
        source.cols.insert(1, LineInfo { size: Some(123.0), ..LineInfo::default() });
        let inserted = change(&before, "columns", "insert", 1, 2).unwrap();
        let shifted = inserted.sheet(0).unwrap();
        assert_eq!(shifted.cols[&3].size, Some(123.0));
        assert_eq!(shifted.input_text(address("F1")), "=D1+E1");
        assert_eq!(shifted.value(address("F1")), Value::number(23.0));
        let deleted = change(&inserted, "columns", "delete", 3, 1).unwrap();
        let shifted = deleted.sheet(0).unwrap();
        assert_eq!(shifted.input_text(address("E1")), "=#REF!+D1");
        assert_eq!(shifted.value(address("D1")), Value::number(12.0));
        assert_eq!(before.sheet(0).unwrap().input_text(address("D1")), "=B1+C1");
    }

    #[test]
    fn refuses_protection_invalid_spans_and_push_off_of_cells_or_geometry() {
        let mut source = Workbook::new();
        assert!(change(&source, "rows", "delete", MAX_ROWS - 1, 2).is_err());
        assert!(change(&source, "columns", "delete", 0, 257).is_err());
        source.protected_structure = true;
        assert!(change(&source, "rows", "insert", 0, 1).is_err());
        source.protected_structure = false;
        source.sheet_mut(0).unwrap().protection = Some(Default::default());
        assert!(change(&source, "rows", "delete", 0, 1).is_err());
        source.sheet_mut(0).unwrap().protection = None;
        source.sheet_mut(0).unwrap().set_value(address("XFD1"), Value::number(9.0));
        assert!(change(&source, "columns", "insert", 0, 1).is_err());
        assert_eq!(source.sheet(0).unwrap().value(address("XFD1")), Value::number(9.0));
        let mut geometry = Workbook::new();
        geometry.sheet_mut(0).unwrap().cols.insert(MAX_COLS - 1, LineInfo { hidden: true, ..LineInfo::default() });
        assert!(change(&geometry, "columns", "insert", 0, 1).is_err());
        geometry.sheet_mut(0).unwrap().cols.clear();
        geometry.sheet_mut(0).unwrap().merges.push(RangeRef::parse("XFC2:XFD2").unwrap());
        assert!(change(&geometry, "columns", "insert", 0, 1).is_err());
    }
}
