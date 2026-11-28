//! Image readers keep only referenced raster bytes from the bounded slide preview.
use std::{
    collections::{HashMap, HashSet, hash_map::Entry},
    sync::{Arc, Mutex, MutexGuard, OnceLock},
};

use deckcraft_model::{MediaId, MediaItem, Presentation, Shape, ShapeKind, style::Fill};
use serde_json::json;

use super::{
    AcResult, J, MAX_INPUT_BYTES, MAX_PREVIEW_SHAPES, decode, decode_request, load, preview,
    protect,
};

const MAX_IMAGE_BYTES: usize = 8 * 1024 * 1024;
const MAX_READER_BYTES: usize = 16 * 1024 * 1024;
const MAX_READER_REFS: usize = 4096;
const MAX_READERS: usize = 2;
const MAX_PREVIEW_RESPONSE_BYTES: usize = 128 * 1024 * 1024;

pub(super) fn picture_id(shape: &Shape) -> Option<MediaId> {
    match (&shape.kind, &shape.fill) {
        (ShapeKind::Picture { fill }, _) | (_, Some(Fill::Picture(fill))) => Some(fill.media),
        _ => None,
    }
}

pub(super) fn previewable(media: &MediaItem) -> bool {
    media.link.is_none()
        && (1..=MAX_IMAGE_BYTES).contains(&media.data.len())
        && matches!(
            media.content_type.as_str(),
            "image/png" | "image/jpeg" | "image/jpg" | "image/webp"
        )
}

fn raster(media: &MediaItem) -> Result<&[u8], String> {
    if media.link.is_some() {
        return Err("External images are not fetched".into());
    }
    let bytes = media.data.as_slice();
    if !(1..=MAX_IMAGE_BYTES).contains(&bytes.len()) {
        return Err("Image exceeds 8 MiB limit".into());
    }
    let valid = match media.content_type.as_str() {
        "image/png" => bytes.starts_with(b"\x89PNG\r\n\x1a\n"),
        "image/jpeg" | "image/jpg" => bytes.starts_with(&[0xff, 0xd8, 0xff]),
        "image/webp" => bytes.len() > 12 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WEBP",
        _ => false,
    };
    if !valid {
        return Err("Image format is not a supported embedded raster".into());
    }
    Ok(bytes)
}

fn picture_reference(request: &J) -> Result<(usize, MediaId), String> {
    let slide = request["slide"]
        .as_u64()
        .and_then(|id| usize::try_from(id).ok())
        .ok_or("Missing slide index")?;
    let media = request["media"]
        .as_u64()
        .and_then(|id| u32::try_from(id).ok())
        .ok_or("Missing media identifier")?;
    Ok((slide, MediaId(media)))
}

/// Original stateless path, also used if an image does not fit in the reader.
#[unsafe(no_mangle)]
pub extern "C" fn ac_pptx_image(
    data: *const u8,
    len: usize,
    request: *const u8,
    request_len: usize,
) -> AcResult {
    protect(|| {
        let bytes = decode(data, len, MAX_INPUT_BYTES)?;
        let request: J = serde_json::from_str(decode_request(request, request_len)?)
            .map_err(|e| format!("Invalid PPTX image request: {e}"))?;
        let (index, id) = picture_reference(&request)?;
        let presentation = load(bytes)?;
        let slide = presentation
            .slides
            .get(index)
            .ok_or("PPTX slide out of range")?;
        if !slide
            .shapes
            .iter()
            .any(|shape| picture_id(shape) == Some(id))
        {
            return Err("Slide does not reference the requested image".into());
        }
        let media = presentation
            .media(id)
            .ok_or("Embedded image is not present")?;
        Ok(raster(media)?.to_vec())
    })
}

#[derive(Default)]
struct Pictures {
    media: HashMap<MediaId, Arc<Vec<u8>>>,
    references: HashSet<(usize, MediaId)>,
}

impl Pictures {
    fn collect(presentation: &Presentation) -> Self {
        let mut pictures = Self::default();
        let mut budget = MAX_READER_BYTES;
        // Index the source media once, since presentation.media scans a vector.
        let media_by_id: HashMap<_, _> = presentation
            .media
            .iter()
            .map(|media| (media.id, media))
            .collect();
        for (index, slide) in presentation.slides.iter().enumerate() {
            for id in slide
                .shapes
                .iter()
                .take(MAX_PREVIEW_SHAPES)
                .filter_map(picture_id)
            {
                if pictures.references.len() == MAX_READER_REFS {
                    return pictures;
                }
                if let Entry::Vacant(entry) = pictures.media.entry(id) {
                    let Some(media) = media_by_id.get(&id) else {
                        continue;
                    };
                    let capacity = media.data.capacity();
                    if capacity > budget || raster(media).is_err() {
                        continue;
                    }
                    budget -= capacity;
                    entry.insert(Arc::clone(&media.data));
                }
                pictures.references.insert((index, id));
            }
        }
        pictures
    }
}

#[derive(Default)]
struct Readers {
    next: u64,
    open: HashMap<u64, Pictures>,
}

fn readers() -> MutexGuard<'static, Readers> {
    static READERS: OnceLock<Mutex<Readers>> = OnceLock::new();
    READERS
        .get_or_init(Mutex::default)
        .lock()
        .unwrap_or_else(|error| error.into_inner())
}

/// Opening takes PPTX bytes and optionally returns its JSON preview.
/// Read and close take the session ID and empty input. A read miss returns zero
/// bytes so callers can fall back to the original lookup on the same snapshot.
#[unsafe(no_mangle)]
pub extern "C" fn ac_pptx_image_reader(
    data: *const u8,
    len: usize,
    request: *const u8,
    request_len: usize,
) -> AcResult {
    protect(|| {
        let request: J = serde_json::from_str(decode_request(request, request_len)?)
            .map_err(|e| format!("Invalid PPTX reader request: {e}"))?;
        let operation = request["reader"].as_str();
        if operation == Some("open") {
            let want_preview = request["preview"] == true;
            let available = readers().open.len() < MAX_READERS;
            if !available && !want_preview {
                return Ok(b"{\"session\":null}".to_vec());
            }
            let presentation = load(decode(data, len, MAX_INPUT_BYTES)?)?;
            let report = want_preview.then(|| preview(&presentation));
            let pictures = available.then(|| Pictures::collect(&presentation));
            let id = pictures
                .filter(|pictures| !pictures.references.is_empty())
                .and_then(|pictures| {
                    let mut registry = readers();
                    let id = registry
                        .next
                        .checked_add(1)
                        .filter(|id| *id <= i64::MAX as u64 && registry.open.len() < MAX_READERS)?;
                    registry.next = id;
                    registry.open.insert(id, pictures);
                    Some(id)
                });
            let mut response = json!({"session":id});
            if let Some(report) = report {
                response["preview"] = report;
            }
            let response = serde_json::to_vec(&response)
                .map_err(|error| error.to_string())
                .and_then(|bytes| {
                    if bytes.len() > MAX_PREVIEW_RESPONSE_BYTES {
                        Err("PPTX preview exceeds 128 MiB limit".into())
                    } else {
                        Ok(bytes)
                    }
                });
            if response.is_err()
                && let Some(id) = id
            {
                readers().open.remove(&id);
            }
            return response;
        }
        if len != 0 {
            return Err("PPTX reader read/close expects empty input".into());
        }
        let id = request["session"]
            .as_u64()
            .filter(|id| *id > 0)
            .ok_or("Invalid PPTX reader ID")?;
        match operation {
            Some("read") => {
                let reference = picture_reference(&request)?;
                let data = readers()
                    .open
                    .get(&id)
                    .filter(|pictures| pictures.references.contains(&reference))
                    .and_then(|pictures| pictures.media.get(&reference.1))
                    .cloned();
                Ok(data.map_or_else(Vec::new, |bytes| bytes.as_slice().to_vec()))
            }
            Some("close") => {
                readers().open.remove(&id);
                Ok(Vec::new())
            }
            _ => Err("Unknown PPTX reader operation".into()),
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::deck::{save, tests::bytes};
    use deckcraft_model::{LayoutType, ShapeId, Xfrm, defaults, style::PictureFill};

    fn call(deck: &[u8], request: J) -> Vec<u8> {
        let request = request.to_string();
        bytes(ac_pptx_image_reader(
            deck.as_ptr(),
            deck.len(),
            request.as_ptr(),
            request.len(),
        ))
    }

    #[test]
    fn preview_reuses_images_under_the_correct_slide_and_releases_reader_slots() {
        let mut deck = Presentation::default();
        let layout = defaults::layout_of_kind(&deck, LayoutType::Blank).unwrap();
        let mut slide = defaults::new_slide(&mut deck, layout).unwrap();
        let mut png = Vec::new();
        {
            let mut writer = png::Encoder::new(&mut png, 1, 1).write_header().unwrap();
            writer.write_image_data(&[220]).unwrap();
        }
        let media = deck
            .add_media("raster.png", "image/png", png.clone())
            .unwrap();
        slide.shapes.push(Shape {
            id: ShapeId(deck.alloc_id().unwrap()),
            kind: ShapeKind::Picture {
                fill: PictureFill {
                    media,
                    ..Default::default()
                },
            },
            xfrm: Some(Xfrm::new(20.0, 20.0, 50.0, 50.0)),
            ..Default::default()
        });
        deck.slides.push(Arc::new(slide));
        let deck = save(&deck).unwrap();

        let open = json!({"reader":"open","preview":true});
        let first: J = serde_json::from_slice(&call(&deck, open.clone())).unwrap();
        let second: J = serde_json::from_slice(&call(&deck, open.clone())).unwrap();
        let full: J = serde_json::from_slice(&call(&deck, open)).unwrap();
        let id = first["session"].as_u64().unwrap();
        let other = second["session"].as_u64().unwrap();
        assert_ne!(id, other);
        assert!(full["session"].is_null());
        assert_eq!(full["preview"], first["preview"]);

        let media = first["preview"]["slides"][1]["shapes"]
            .as_array()
            .unwrap()
            .iter()
            .find_map(|shape| shape["imageId"].as_u64())
            .unwrap();
        let read = json!({"reader":"read","session":id,"slide":1,"media":media});
        assert_eq!(call(&[], read.clone()), png);
        assert_eq!(call(&[], read.clone()), png);
        assert!(
            call(
                &[],
                json!({"reader":"read","session":id,"slide":0,"media":media})
            )
            .is_empty()
        );

        assert!(call(&[], json!({"reader":"close","session":id})).is_empty());
        assert!(call(&[], read).is_empty());
        let reopened: J = serde_json::from_slice(&call(&deck, json!({"reader":"open"}))).unwrap();
        let new_id = reopened["session"].as_u64().unwrap();
        assert_ne!(new_id, id);
        call(&[], json!({"reader":"close","session":other}));
        call(&[], json!({"reader":"close","session":new_id}));
    }
}
