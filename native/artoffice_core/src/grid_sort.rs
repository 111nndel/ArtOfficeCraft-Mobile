//! Bound the worksheet selection before dispatching GridCraft's native sort.
use gridcraft_core::{CellRef, RangeRef, letters_to_col};
use gridcraft_model::Workbook;
use serde_json::{Value as Json, json};

use super::grid::{command_session, write};

pub(super) fn edit(
    mut workbook: Workbook,
    sheet: usize,
    address: &str,
    request: &Json,
) -> Result<Vec<u8>, String> {
    let range = request["range"]
        .as_str()
        .and_then(RangeRef::parse)
        .ok_or("Invalid sort range")?;
    if range.count() > 4096 || range.width() > 128 {
        return Err("Select at most 4096 cells and 128 columns to sort".into());
    }
    let column = request["column"].as_str().ok_or("Missing sort column")?;
    letters_to_col(column)
        .filter(|col| (range.start.col..=range.end.col).contains(col))
        .ok_or("Sort column must be inside the selected range")?;
    let order = request["order"]
        .as_str()
        .filter(|value| matches!(*value, "asc" | "desc"))
        .ok_or("Invalid sort order")?;
    let header = request["header"].as_bool().ok_or("Missing header choice")?;
    if range.height() < 2 + u32::from(header) {
        return Err("Select at least two data rows to sort".into());
    }
    let body = RangeRef::new(
        CellRef::new(range.start.row + u32::from(header), range.start.col),
        range.end,
    );
    let active = CellRef::parse(address).ok_or("Invalid A1 reference")?;
    let target = workbook.sheet(sheet).ok_or("Sheet index out of bounds")?;
    if workbook.protected_structure || target.is_protected() {
        return Err("Protected sheet cannot be changed".into());
    }
    if target.merges.iter().any(|merge| merge.intersects(&body))
        || target.cell_pictures.keys().any(|&cell| body.contains(cell))
        || target.pivots.iter().any(|pivot| {
            pivot
                .last_range
                .unwrap_or_else(|| RangeRef::cell(pivot.anchor))
                .intersects(&body)
        })
    {
        return Err("Cannot sort merged cells, cell pictures, or pivot results".into());
    }
    let overlaps_rows =
        |range: RangeRef| range.start.row <= body.end.row && range.end.row >= body.start.row;
    if target
        .autofilter
        .as_ref()
        .is_some_and(|filter| !filter.criteria.is_empty() && overlaps_rows(filter.range))
        || target
            .tables
            .iter()
            .any(|table| !table.filter.is_empty() && overlaps_rows(table.range))
    {
        return Err("Clear active filters in the selected rows before sorting".into());
    }
    if target.tables.iter().any(|table| {
        table.range.intersects(&body)
            && !table.data_range().is_some_and(|data| {
                data.contains_range(&body)
                    && data.start.col == body.start.col
                    && data.end.col == body.end.col
            })
    }) {
        return Err("Select all columns of the table and leave its header and totals fixed".into());
    }

    // Keys can be formulas. Recalculate before comparing their values, and guard
    // arrays whose anchors or results would be separated by the permutation.
    gridcraft_calc::Calc::new().recalc_all(&mut workbook);
    let target = workbook.sheet(sheet).ok_or("Sheet index out of bounds")?;
    if target
        .spill_ranges
        .values()
        .any(|range| range.intersects(&body))
        || target.cells.iter().any(|(at, cell)| {
            cell.formula.as_ref().is_some_and(|formula| {
                formula.array.is_some_and(|range| range.intersects(&body))
                    || (formula.dynamic && body.contains(at))
            })
        })
    {
        return Err("Cannot sort cells containing an array formula".into());
    }
    let mut session = command_session(workbook, sheet, active)?;
    session
        .execute(
            "data.sort",
            json!({
                "range": range.a1(),
                "header": header,
                "keys": [{"column": column, "order": order}],
            }),
        )
        .map_err(|error| error.to_string())?;
    write(&session.doc().map_err(|error| error.to_string())?.wb)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::grid::workbook;
    use gridcraft_core::Value;
    use gridcraft_model::{Cell, Formula};

    fn at(address: &str) -> CellRef {
        CellRef::parse(address).unwrap()
    }

    #[test]
    fn sorts_rows_by_calculated_key_and_keeps_header_styles_and_relative_formulas() {
        let mut input = Workbook::new();
        let mut style = gridcraft_model::style::Style::default();
        style.font.bold = true;
        let bold = input.styles.intern(style);
        let sheet = input.sheet_mut(0).unwrap();
        sheet.set_value(at("A1"), Value::text("Amount"));
        sheet.set_value(at("D2"), Value::text("outside"));
        for (row, value, name) in [(2, 30.0, "large"), (3, 10.0, "small"), (4, 20.0, "middle")] {
            sheet.set_value(at(&format!("A{row}")), Value::number(value));
            sheet.set_value(at(&format!("B{row}")), Value::text(name));
            sheet.set_cell(
                at(&format!("C{row}")),
                Cell::formula(Formula::new(&format!("=A{row}*2"))),
            );
        }
        sheet.set_style(at("B3"), bold);
        let request = json!({"range":"A1:C5", "column":"C", "order":"asc", "header":true});
        let result = workbook(&edit(input, 0, "A1", &request).unwrap()).unwrap();
        let sheet = result.sheet(0).unwrap();
        assert_eq!(sheet.value(at("A1")), Value::text("Amount"));
        assert_eq!(sheet.value(at("B2")), Value::text("small"));
        assert_eq!(sheet.value(at("B4")), Value::text("large"));
        assert_eq!(sheet.value(at("C5")), Value::Empty);
        assert_eq!(sheet.value(at("D2")), Value::text("outside"));
        assert_eq!(sheet.input_text(at("C2")), "=A2*2");
        assert_eq!(sheet.value(at("C2")), Value::number(20.0));
        assert!(result.styles.get(sheet.style_id(at("B2"))).font.bold);
    }

    #[test]
    fn refuses_invalid_keys_and_sorting_through_merged_cells() {
        let mut input = Workbook::new();
        let mut request = json!({"range":"A1:C3", "column":"D", "order":"desc", "header":false});
        assert!(edit(input.clone(), 0, "A1", &request).is_err());
        request["column"] = json!("A");
        input
            .sheet_mut(0)
            .unwrap()
            .merges
            .push(RangeRef::parse("B2:C2").unwrap());
        assert!(
            edit(input, 0, "A1", &request)
                .unwrap_err()
                .contains("merged cells")
        );
    }
}
