//! Worksheet AutoFilter through the pinned GridCraft command engine.
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;

use gridcraft_core::{CellRef, RangeRef, Value, letters_to_col};
use gridcraft_engine::display::cell_text;
use gridcraft_model::{FilterCriterion, Sheet, Workbook};
use serde_json::{Value as Json, json};

use super::grid::{command_session, write};

const MAX_VALUES: usize = 512;
const MAX_VALUE_BYTES: usize = 256 * 1024;

fn scope<'a>(wb: &'a Workbook, index: usize, req: &Json) -> Result<(&'a Sheet, RangeRef), String> {
    let sheet = wb.sheet(index).ok_or("Sheet index out of bounds")?;
    let range = req["range"]
        .as_str()
        .and_then(RangeRef::parse)
        .ok_or("Invalid filter range")?;
    if range.height() < 2 || range.height() > 4097 || range.width() > 128 {
        return Err("Select a header and up to 4096 data rows and 128 columns".into());
    }
    if wb.protected_structure || sheet.is_protected() {
        return Err("Protected sheet cannot be changed".into());
    }
    if sheet.row_height(range.start.row) == 0.0 {
        return Err("The filter header row must be visible".into());
    }
    if let Some(filter) = &sheet.autofilter {
        if filter.range != range {
            return Err("Use the existing AutoFilter range".into());
        }
        if filter.criteria.len() > range.width() as usize
            || filter.criteria.iter().any(|(col, rule)| {
                *col >= range.width()
                    || !matches!(rule, FilterCriterion::Values { values, .. }
                        if values.len() <= MAX_VALUES
                            && values.iter().map(String::len).sum::<usize>() <= MAX_VALUE_BYTES)
            })
        {
            return Err("This AutoFilter uses unsupported criteria".into());
        }
    }
    if sheet.merges.iter().any(|merge| merge.intersects(&range))
        || sheet.tables.iter().any(|table| {
            table.range.intersects(&range)
                || (!table.filter.is_empty()
                    && table.range.start.row <= range.end.row
                    && table.range.end.row > range.start.row)
        })
    {
        return Err("Select a range without merged cells or Excel tables".into());
    }
    Ok((sheet, range))
}

fn column(sheet: &Sheet, range: RangeRef, req: &Json) -> Result<u32, String> {
    req["column"]
        .as_str()
        .and_then(letters_to_col)
        .filter(|col| {
            (range.start.col..=range.end.col).contains(col) && sheet.col_width(*col) > 0.0
        })
        .ok_or_else(|| "Select a visible column inside the filter range".into())
}

// Match GridCraft's AutoFilter value semantics, including formatted numbers
// and the unformatted equivalents that Excel can write into imported criteria.
fn filter_cell(wb: &Workbook, sheet: &Sheet, at: CellRef) -> (Value, Option<String>) {
    let value = sheet.value(at);
    let blank = value.is_empty() || value.as_text().is_some_and(str::is_empty);
    let display = (!blank).then(|| cell_text(wb, sheet, at));
    (value, display)
}

fn selected(value: &Value, label: Option<&str>, rule: &FilterCriterion) -> bool {
    let FilterCriterion::Values { values, blanks } = rule else {
        return false;
    };
    let Some(label) = label else { return *blanks };
    let raw = value.display();
    values
        .iter()
        .any(|item| item.eq_ignore_ascii_case(label) || item.eq_ignore_ascii_case(&raw))
}

fn preserve_visibility(wb: &Workbook, sheet: &Sheet, range: RangeRef) -> Result<(), String> {
    for (&row, info) in sheet.rows.range(range.start.row + 1..=range.end.row) {
        if info.outline > 0 || info.collapsed || info.size == Some(0.0) {
            return Err("Filter range includes manually hidden or grouped rows".into());
        }
        if !info.hidden {
            continue;
        }
        let fails_filter = sheet.autofilter.as_ref().is_some_and(|filter| {
            filter.criteria.iter().any(|(off, rule)| {
                let (value, label) =
                    filter_cell(wb, sheet, CellRef::new(row, range.start.col + off));
                !selected(&value, label.as_deref(), rule)
            })
        });
        // Excel stores one hidden bit per row. Reject independently hidden
        // rows rather than letting GridCraft overwrite their visibility.
        if !fails_filter {
            return Err("Filter range includes manually hidden or grouped rows".into());
        }
    }
    Ok(())
}

fn collect_options(
    wb: &Workbook,
    sheet: &Sheet,
    range: RangeRef,
    col: u32,
) -> Result<Vec<(Option<String>, bool)>, String> {
    let rule = sheet.autofilter.as_ref().and_then(|filter| {
        filter
            .criteria
            .iter()
            .find(|(off, _)| range.start.col + off == col)
            .map(|(_, rule)| rule)
    });
    let mut options = BTreeMap::<String, (Option<String>, bool)>::new();
    let mut bytes = 0;
    let mut blank = None;
    for row in range.start.row + 1..=range.end.row {
        let (value, label) = filter_cell(wb, sheet, CellRef::new(row, col));
        let enabled = rule.is_none_or(|rule| selected(&value, label.as_deref(), rule));
        if let Some(label) = label {
            let entry = options.entry(label.to_ascii_lowercase());
            match entry {
                std::collections::btree_map::Entry::Vacant(entry) => {
                    bytes += label.len();
                    entry.insert((Some(label), enabled));
                }
                std::collections::btree_map::Entry::Occupied(entry) if entry.get().1 != enabled => {
                    return Err("This filter groups identical displayed values differently".into());
                }
                _ => {}
            }
        } else {
            blank = Some((None, enabled));
        }
        if options.len() + usize::from(blank.is_some()) > MAX_VALUES || bytes > MAX_VALUE_BYTES {
            return Err("This column has too many distinct filter values".into());
        }
    }
    Ok(options.into_values().chain(blank).collect())
}

pub(super) fn options(wb: &Workbook, index: usize, req: &Json) -> Result<Json, String> {
    let (sheet, range) = scope(wb, index, req)?;
    preserve_visibility(wb, sheet, range)?;
    let values = collect_options(wb, sheet, range, column(sheet, range, req)?)?;
    Ok(
        json!({"items":values.into_iter().map(|(value, checked)| json!({
        "value":value, "checked":checked,
    })).collect::<Vec<_>>()}),
    )
}

pub(super) fn edit(wb: Workbook, index: usize, req: &Json) -> Result<Vec<u8>, String> {
    let (sheet, range) = scope(&wb, index, req)?;
    preserve_visibility(&wb, sheet, range)?;
    let existing = sheet.autofilter.is_some();
    if req["remove"].as_bool() == Some(true) {
        if !existing {
            return Err("No worksheet filter to remove".into());
        }
        let mut session = command_session(wb, index, range.start)?;
        session
            .execute("data.clearFilter", json!({}))
            .map_err(|err| err.to_string())?;
        let doc = session.doc_mut().map_err(|err| err.to_string())?;
        // clearFilter updates only this range. The toggle can also reveal rows
        // from filtered Excel tables elsewhere on the worksheet.
        Arc::make_mut(&mut doc.wb)
            .sheet_mut(index)
            .ok_or("Sheet index out of bounds")?
            .autofilter = None;
        return write(&doc.wb);
    }
    let col = column(sheet, range, req)?;
    let choices = collect_options(&wb, sheet, range, col)?;
    let values = req["values"]
        .as_array()
        .filter(|items| !items.is_empty() && items.len() <= MAX_VALUES)
        .ok_or("Select at least one filter value")?;
    let allowed: BTreeSet<_> = choices.iter().map(|(value, _)| value.as_deref()).collect();
    let mut picked = BTreeSet::new();
    for item in values {
        let value = if item.is_null() {
            None
        } else {
            Some(item.as_str().ok_or("Invalid filter value")?)
        };
        if !allowed.contains(&value) || !picked.insert(value) {
            return Err("Filter values changed; refresh the list".into());
        }
    }
    let all = picked == allowed;
    let values: Vec<String> = picked
        .iter()
        .flatten()
        .map(|value| (*value).to_owned())
        .collect();
    let blanks = picked.contains(&None);
    if !all {
        let labels: BTreeSet<_> = values
            .iter()
            .map(|label| label.to_ascii_lowercase())
            .collect();
        let rule = FilterCriterion::Values {
            values: values.clone(),
            blanks,
        };
        for row in range.start.row + 1..=range.end.row {
            let (value, label) = filter_cell(&wb, sheet, CellRef::new(row, col));
            let checked = label
                .as_ref()
                .map_or(blanks, |label| labels.contains(&label.to_ascii_lowercase()));
            if checked != selected(&value, label.as_deref(), &rule) {
                return Err("Some filter values overlap because of number formatting".into());
            }
        }
    }
    let params = json!({
        "column":col - range.start.col,
        "clear":all,
        "values":values,
        "blanks":blanks,
    });
    let mut session = command_session(wb, index, range.start)?;
    if !existing {
        session
            .execute("data.filter", json!({"range":range.a1()}))
            .map_err(|err| err.to_string())?;
    }
    session
        .execute("data.filterBy", params)
        .map_err(|err| err.to_string())?;
    write(&session.doc().map_err(|err| err.to_string())?.wb)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::grid::workbook;
    use gridcraft_model::{Cell, Formula, LineInfo};

    fn at(address: &str) -> CellRef {
        CellRef::parse(address).unwrap()
    }

    fn fixture() -> Workbook {
        let mut wb = Workbook::new();
        let mut style = gridcraft_model::style::Style::default();
        style.num_fmt = gridcraft_model::style::NumFmt::new("0%");
        let percent = wb.styles.intern(style);
        let sheet = wb.sheet_mut(0).unwrap();
        for (address, value) in [
            ("A1", "Item"),
            ("B1", "Rate"),
            ("A2", "Tea"),
            ("A3", "Coffee"),
        ] {
            sheet.set_value(at(address), Value::text(value));
        }
        sheet.set_cell(at("A4"), Cell::formula(Formula::new("=\"\"")));
        sheet.set_cell(at("A5"), Cell::formula(Formula::new("=A2")));
        for (address, value) in [("B2", 0.5), ("B3", 0.25), ("B4", 0.5), ("B5", 0.25)] {
            sheet.set_cell(at(address), Cell::styled(Value::number(value), percent));
        }
        sheet.rows.insert(
            6,
            LineInfo {
                hidden: true,
                outline: 1,
                ..LineInfo::default()
            },
        );
        gridcraft_calc::Calc::new().recalc_all(&mut wb);
        wb
    }

    #[test]
    fn filters_by_displayed_values_and_blanks_across_columns_and_roundtrips() {
        let wb = fixture();
        let req = json!({"range":"A1:B5", "column":"A", "values":["Tea", null]});
        assert_eq!(
            options(&wb, 0, &req).unwrap()["items"],
            json!([
                {"value":"Coffee","checked":true}, {"value":"Tea","checked":true}, {"value":null,"checked":true}
            ])
        );
        let filtered = workbook(&edit(wb, 0, &req).unwrap()).unwrap();
        let sheet = filtered.sheet(0).unwrap();
        assert!(!sheet.is_row_hidden(0));
        assert!(sheet.is_row_hidden(2));
        assert!(!sheet.is_row_hidden(3));
        assert_eq!(sheet.input_text(at("A4")), "=\"\"");
        assert_eq!(sheet.input_text(at("A5")), "=A2");
        assert_eq!(
            options(&filtered, 0, &req).unwrap()["items"][0]["checked"],
            false
        );

        let both = workbook(
            &edit(
                filtered,
                0,
                &json!({"range":"A1:B5", "column":"B", "values":["50%"]}),
            )
            .unwrap(),
        )
        .unwrap();
        assert_eq!(
            both.sheet(0)
                .unwrap()
                .autofilter
                .as_ref()
                .unwrap()
                .criteria
                .len(),
            2
        );
        assert!(both.sheet(0).unwrap().is_row_hidden(4));
        let cleared =
            workbook(&edit(both, 0, &json!({"range":"A1:B5", "remove":true})).unwrap()).unwrap();
        let sheet = cleared.sheet(0).unwrap();
        assert!(sheet.autofilter.is_none());
        assert!((0..5).all(|row| !sheet.is_row_hidden(row)));
        assert!(sheet.is_row_hidden(6));
        assert_eq!(sheet.value(at("A3")), Value::text("Coffee"));
    }

    #[test]
    fn refuses_conflicting_ranges_stale_values_and_hidden_rows() {
        let mut wb = fixture();
        let mut req = json!({"range":"A1:B5", "column":"A", "values":["Missing"]});
        assert!(
            edit(wb.clone(), 0, &req)
                .unwrap_err()
                .contains("values changed")
        );
        req["values"] = json!(["Tea"]);
        let filtered = workbook(&edit(wb.clone(), 0, &req).unwrap()).unwrap();
        req["range"] = json!("A1:B6");
        assert!(
            edit(filtered, 0, &req)
                .unwrap_err()
                .contains("existing AutoFilter")
        );
        req["range"] = json!("A1:B5");
        wb.sheet_mut(0).unwrap().rows.entry(1).or_default().hidden = true;
        assert!(edit(wb, 0, &req).unwrap_err().contains("manually hidden"));
    }
}
