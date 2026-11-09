//! Test-only consumer of the pinned renderer API. No application ABI or code changes.
use std::error::Error;
use std::fs;
use std::io::{BufWriter, Write};
use std::path::Path;
use std::sync::Arc;
use std::time::{Duration, Instant};
use pdfcraft_render::{RenderConfig, RenderPool, RenderRequest, RequestKind};

fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 5 { return Err("usage: probe FILE OUT_DIR PAGE_COUNT SCALE".into()); }
    let pages: usize = args[3].parse()?;
    let scale: f32 = args[4].parse()?;
    if !(1..=16).contains(&pages) || !scale.is_finite() || !(0.25..=4.0).contains(&scale) {
        return Err("invalid bounded page count or scale".into());
    }
    if fs::metadata(&args[1])?.len() > 64 * 1024 * 1024 { return Err("fixture too large".into()); }
    let bytes = fs::read(&args[1])?;
    if !bytes.starts_with(b"%PDF-") { return Err("invalid PDF header".into()); }
    fs::create_dir_all(&args[2])?;
    let config = RenderConfig { reject_oversize: true, ..RenderConfig::default() };
    let pool = RenderPool::new(Arc::new(bytes), 1, config);
    pool.set_queue((0..pages).map(|page| RenderRequest {
        page, kind: RequestKind::Pixels, tile: None, scale,
        tag: page as u64 + 1, preview: false,
    }).collect());
    let start = Instant::now();
    let mut seen = vec![false; pages];
    let mut count = 0;
    while count < pages {
        if let Some(page) = pool.try_recv() {
            if let Some(error) = page.error { return Err(error.into()); }
            let index = page.request.page;
            if index >= pages || seen[index] { return Err("duplicate or invalid page response".into()); }
            let pixels = (page.width as usize).checked_mul(page.height as usize).ok_or("size overflow")?;
            if pixels == 0 || pixels > 8_000_000 || page.rgba.len() != pixels * 4 {
                return Err("invalid or oversized raster".into());
            }
            let path = Path::new(&args[2]).join(format!("page-{:02}.ppm", index + 1));
            let mut out = BufWriter::new(fs::File::create(path)?);
            write!(out, "P6\n{} {}\n255\n", page.width, page.height)?;
            for p in page.rgba.chunks_exact(4) {
                // The renderer returns premultiplied RGBA; composite on white.
                let white = 255 - p[3];
                out.write_all(&[p[0].saturating_add(white), p[1].saturating_add(white), p[2].saturating_add(white)])?;
            }
            out.flush()?;
            println!("page={} width={} height={} millis={} warnings={}",
                index + 1, page.width, page.height, page.millis, page.warnings.len());
            seen[index] = true;
            count += 1;
        } else if start.elapsed() > Duration::from_secs(120) {
            return Err("render timed out".into());
        } else { std::thread::sleep(Duration::from_millis(2)); }
    }
    Ok(())
}
