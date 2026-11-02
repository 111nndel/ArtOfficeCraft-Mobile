//! GridCraft 0.15.0: real XLSX create/read/edit/write bridge.
//! Preview is bounded and does not pretend to render full Excel features.
use gridcraft_core::{CellRef, Value};
use gridcraft_model::{Cell, Formula, Workbook};
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
    if value.len()>65535 {return Err("Cell input exceeds 65535 bytes".into());}
    let sh=w.sheet_mut(sheet_index).ok_or("Sheet index out of bounds")?;
    if sh.protection.is_some() {return Err("Protected sheets cannot be edited in this preview".into());}
    if value.is_empty() {
        sh.remove_cell(reference);
    } else if value.starts_with('=') {
        sh.set_cell(reference, Cell::formula(Formula::new(value)));
    } else if let Ok(number)=value.parse::<f64>() {
        if number.is_finite() {sh.set_value(reference,Value::number(number));}
        else {return Err("Number must be finite".into());}
    } else {
        sh.set_value(reference,Value::text(value));
    }
    Ok(())
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
        let mut sheets=Vec::new();
        for (index, sh) in wb.sheets.iter().enumerate() {
            let mut cells=serde_json::Map::new();
            for (loc,c) in sh.cells.iter() {
                total+=1;
                if cells.len() >= 1600 {continue;}
                cells.insert(loc.a1(),json!({"input":c.input_text(),"display":c.value.display(),"formula":c.formula.is_some()}));
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
        let value=req.get("value").and_then(Json::as_str).ok_or("Missing cell value")?;
        let mut wb=workbook(bytes)?;
        put(&mut wb,idx,address,value)?;
        gridcraft_calc::Calc::new().recalc_all(&mut wb);
        write(&wb)
    })
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
