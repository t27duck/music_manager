//! Scan a library into a throwaway index and report timing, e.g.:
//! `cargo run --release --example scan -- /path/to/library`
use std::sync::Mutex;
use std::time::Instant;

use music_manager_lib::db::{Db, Filter, Query};
use music_manager_lib::scanner;

fn main() -> anyhow::Result<()> {
    let root = std::env::args().nth(1).expect("usage: scan <library>");
    let root = std::fs::canonicalize(root)?;
    let db = Mutex::new(Db::open_in_memory()?);
    let start = Instant::now();
    let summary = scanner::full_scan(&db, &root, |_, _| {})?;
    println!("scanned {} files in {:.1?}", summary.total, start.elapsed());

    let db = db.lock().unwrap();
    let count = |field: &str, op: &str| {
        let q = Query { filters: vec![Filter { field: field.into(), op: op.into(), value: String::new() }], ..Default::default() };
        db.query(&q).map(|r| r.len()).unwrap_or(0)
    };
    let start = Instant::now();
    let all = db.query(&Query::default())?;
    println!("query all: {} rows in {:.1?}", all.len(), start.elapsed());
    for field in ["title", "artist", "album", "album_artist", "year", "track", "genre"] {
        println!("  empty {field}: {}", count(field, "empty"));
    }
    let errors: Vec<_> = all.iter().filter(|t| t.error.is_some()).collect();
    println!("tag read errors: {}", errors.len());
    for t in errors.iter().take(10) {
        println!("  {}: {}", t.path, t.error.as_deref().unwrap_or_default());
    }
    println!("no duration: {}", all.iter().filter(|t| t.duration_ms.is_none()).count());
    println!("with art: {}", all.iter().filter(|t| t.has_art).count());
    Ok(())
}
