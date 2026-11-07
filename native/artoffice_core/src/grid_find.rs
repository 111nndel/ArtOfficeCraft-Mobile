//! Bounded, read-only search over GridCraft's sparse cells and display formatting.
use gridcraft_core::{CellRef, RangeRef, MAX_COLS, MAX_ROWS};
use gridcraft_engine::display::{formula_hidden, value_text};
use gridcraft_model::Workbook;
use serde_json::{Value as Json, json};

pub(super) fn find(wb: &Workbook, req: &Json) -> Result<Json, String> {
    let query = req["query"].as_str()
        .filter(|text| !text.trim().is_empty() && text.len() <= 1024)
        .ok_or("Enter up to 256 characters to find")?.to_lowercase();
    let values = match req["lookIn"].as_str() {
        Some("values") => true,
        Some("formulas") => false,
        _ => return Err("Invalid Excel search mode".into()),
    };
    let all = req["workbook"].as_bool().ok_or("Invalid Excel search scope")?;
    let sheet = req["sheet"].as_u64().and_then(|n| usize::try_from(n).ok())
        .filter(|n| *n < wb.sheets.len()).ok_or("Invalid Excel search sheet")?;
    let limit = req["limit"].as_u64().filter(|n| (1..=512).contains(n))
        .ok_or("Invalid Excel search limit")? as usize;
    let cursor = &req["cursor"];
    let (start, after) = if cursor.is_null() {
        (if all { 0 } else { sheet }, None)
    } else {
        let index = cursor["sheet"].as_u64().and_then(|n| usize::try_from(n).ok())
            .filter(|n| *n < wb.sheets.len() && (all || *n == sheet))
            .ok_or("Invalid Excel search cursor")?;
        let after = match &cursor["after"] {
            Json::Null => None,
            Json::String(address) => Some(CellRef::parse(address).ok_or("Invalid Excel search cell")?),
            _ => return Err("Invalid Excel search cell".into()),
        };
        (index, after)
    };
    let end = if all { wb.sheets.len() } else { sheet + 1 };
    let timer = std::time::Instant::now();
    let mut hits = Vec::new();
    let mut scanned = 0usize;
    let mut next = None;
    for index in start..end {
        let sh = wb.sheet(index).ok_or("Sheet not found")?;
        let after = if index == start { after } else { None };
        let range = RangeRef {
            start: CellRef::new(after.map_or(0, |c| c.row), 0),
            end: CellRef::new(MAX_ROWS - 1, MAX_COLS - 1),
        };
        for (at, cell) in sh.cells.iter_range(range) {
            if after.is_some_and(|previous| (at.row, at.col) <= (previous.row, previous.col)) {
                continue;
            }
            scanned += 1;
            let text = if values || cell.formula.is_none() || formula_hidden(wb, sh, at) {
                value_text(wb, sh, at)
            } else {
                cell.input_text()
            };
            if text.to_lowercase().contains(&query)
                && !sh.merge_at(at).is_some_and(|merge| merge.start != at) {
                hits.push(json!({
                    "sheet":index, "address":at.a1(),
                    "hidden":sh.row_height(at.row) == 0.0 || sh.col_width(at.col) == 0.0,
                }));
            }
            next = Some(json!({"sheet":index,"after":at.a1()}));
            if hits.len() == limit || scanned == 4096 || timer.elapsed().as_millis() >= 150 {
                return Ok(json!({"hits":hits,"next":next,"scanned":scanned}));
            }
        }
        next = (index + 1 < end).then(|| json!({"sheet":index + 1,"after":null}));
        if index - start >= 23 || timer.elapsed().as_millis() >= 150 { break; }
    }
    Ok(json!({"hits":hits,"next":next,"scanned":scanned}))
}

#[cfg(test)]
mod tests {
    use super::*;
    use gridcraft_core::Value;
    use gridcraft_model::{Cell, Formula, Sheet};
    use std::sync::Arc;

    fn request(query: &str) -> Json {
        json!({"query":query,"sheet":0,"lookIn":"values","workbook":true,"limit":512})
    }

    #[test]
    fn finds_formatted_unicode_values_and_formulas_beyond_the_preview() {
        let mut wb = Workbook::new();
        let sh = wb.sheet_mut(0).unwrap();
        sh.set_value(CellRef::new(6000, 50), Value::text("Проверка K İ"));
        sh.set_cell(CellRef::new(5, 2), Cell {
            value: Value::number(42.0), ..Cell::formula(Formula::new("=SUM(A1:A2)"))
        });
        let mut style = wb.styles.get(Default::default()).clone();
        style.num_fmt = gridcraft_model::style::NumFmt::new("0.00%");
        let id = wb.styles.intern(style);
        wb.sheet_mut(0).unwrap().set_cell(CellRef::new(7, 3), Cell {
            style:id, ..Cell::value(Value::number(0.125))
        });
        wb.sheets.push(Arc::new(Sheet::new("Second")));
        wb.sheet_mut(1).unwrap().set_value(CellRef::new(1, 1), Value::text("ПРОВЕРКА"));
        let before = super::super::grid::write(&wb).unwrap();
        let hits = find(&wb, &request("проверка")).unwrap();
        assert_eq!(hits["hits"].as_array().unwrap().len(), 2);
        assert_eq!(hits["hits"][0]["address"], "AY6001");
        assert_eq!(hits["hits"][1]["sheet"], 1);
        assert_eq!(find(&wb, &request("12.50%")).unwrap()["hits"][0]["address"], "D8");
        assert!(find(&wb, &request("SUM")).unwrap()["hits"].as_array().unwrap().is_empty());
        let mut formulas = request("sum");
        formulas["lookIn"] = json!("formulas");
        assert_eq!(find(&wb, &formulas).unwrap()["hits"][0]["address"], "C6");
        let mut one = request("проверка");
        one["workbook"] = json!(false);
        assert_eq!(find(&wb, &one).unwrap()["hits"].as_array().unwrap().len(), 1);
        assert_eq!(super::super::grid::write(&wb).unwrap(), before);
        assert!(find(&wb, &request("missing")).unwrap()["hits"].as_array().unwrap().is_empty());
        assert!(find(&wb, &request(" ")).is_err());
    }

    #[test]
    fn protected_hidden_formulas_stay_hidden_and_hidden_cells_are_marked() {
        let mut wb = Workbook::new();
        let mut style = wb.styles.get(Default::default()).clone();
        style.protection.hidden = true;
        let id = wb.styles.intern(style);
        let sh = wb.sheet_mut(0).unwrap();
        sh.protection = Some(Default::default());
        sh.rows.entry(0).or_default().hidden = true;
        sh.set_cell(CellRef::new(0, 0), Cell {
            style:id, value:Value::number(42.0),
            ..Cell::formula(Formula::new("=SUM(B1:B2)"))
        });
        let mut req = request("SUM");
        req["lookIn"] = json!("formulas");
        assert!(find(&wb, &req).unwrap()["hits"].as_array().unwrap().is_empty());
        req["query"] = json!("42");
        let batch = find(&wb, &req).unwrap();
        assert_eq!(batch["hits"][0]["hidden"], true);
        assert_eq!(batch["hits"][0]["address"], "A1");
    }

    #[test]
    fn sparse_cursor_resumes_without_duplicates_and_includes_the_last_cell() {
        let mut wb = Workbook::new();
        for row in 0..4100 {
            wb.sheet_mut(0).unwrap().set_value(CellRef::new(row, 3), Value::text("hit"));
        }
        wb.sheet_mut(0).unwrap().set_value(CellRef::new(MAX_ROWS-1,MAX_COLS-1), Value::text("hit"));
        let mut req = request("hit");
        req["limit"] = json!(17);
        let mut addresses = Vec::new();
        loop {
            let batch = find(&wb, &req).unwrap();
            assert!(batch["hits"].as_array().unwrap().len() <= 17);
            addresses.extend(batch["hits"].as_array().unwrap().iter().map(|h| h["address"].as_str().unwrap().to_owned()));
            if batch["next"].is_null() { break; }
            assert_ne!(batch["next"], req["cursor"]);
            req["cursor"] = batch["next"].clone();
        }
        assert_eq!(addresses.len(), 4101);
        assert_eq!(addresses.iter().collect::<std::collections::BTreeSet<_>>().len(), 4101);
        assert_eq!(addresses.last().unwrap(), "XFD1048576");
    }
}
