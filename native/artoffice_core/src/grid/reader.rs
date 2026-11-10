//! Read-only workbook snapshots, owned by the document worker and explicitly closed.
//! IDs are process-wide (an isolate may move between OS threads), never pointers.
use std::{collections::BTreeMap, sync::{Mutex, OnceLock}};
use super::{Workbook, Json, json};

pub(super) struct Document {
    pub workbook: Workbook,
    pub warnings: Json,
}
impl Document {
    pub fn read(bytes: &[u8]) -> Result<Self, String> {
        let (workbook, report) = gridcraft_xlsx::read_xlsx(bytes)
            .map_err(|e| format!("GridCraft XLSX read: {e}"))?;
        Ok(Self { workbook, warnings: serde_json::to_value(report.warnings).map_err(|e|e.to_string())? })
    }
}
#[derive(Default)]
struct Readers { next: u64, documents: BTreeMap<u64, Document> }
static READERS: OnceLock<Mutex<Readers>> = OnceLock::new();

// Extends ac_xlsx_inspect_window without changing the existing stateless ABI.
// Open takes XLSX bytes; view/close take empty input. At most two models are
// retained; additional workers use the original stateless path, without eviction.
pub(super) fn command(bytes: &[u8], req: &Json) -> Result<Vec<u8>, String> {
    let mut readers = READERS.get_or_init(|| Mutex::new(Readers::default()))
        .lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    let output = match req["reader"].as_str() {
        Some("open") => {
            if readers.documents.len() >= 2 { json!({"session":null}) }
            else {
                let id = readers.next.checked_add(1).filter(|id| *id <= i64::MAX as u64)
                    .ok_or("Workbook reader IDs exhausted")?;
                let document = Document::read(bytes)?;
                readers.next = id;
                readers.documents.insert(id, document);
                json!({"session":id})
            }
        }
        Some(operation @ ("view" | "close")) => {
            if !bytes.is_empty() { return Err("Workbook reader view/close expects empty input".into()); }
            let id = req["session"].as_u64().filter(|id| *id > 0).ok_or("Invalid workbook reader ID")?;
            if operation == "close" { readers.documents.remove(&id); json!({}) }
            else {
                let document = readers.documents.get(&id).ok_or("Workbook reader is closed")?;
                return super::inspect_window(&document.workbook, &document.warnings, &req["view"]);
            }
        }
        _ => return Err("Unknown workbook reader operation".into()),
    };
    serde_json::to_vec(&output).map_err(|e|e.to_string())
}
