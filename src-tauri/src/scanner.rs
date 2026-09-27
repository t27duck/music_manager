//! Keeping the index in sync with the files on disk.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::UNIX_EPOCH;

use anyhow::Result;
use rayon::prelude::*;
use serde::Serialize;
use walkdir::WalkDir;

use crate::db::{Db, ScannedFile};
use crate::tags;

/// Files are read in batches so progress can be reported and the DB lock isn't held long.
const BATCH: usize = 200;

#[derive(Debug, Clone, Default, Serialize)]
pub struct ScanSummary {
    pub total: usize,
    pub added_or_updated: usize,
    pub removed: usize,
}

#[derive(Debug, Clone, Serialize)]
pub struct ScanProgress {
    pub done: usize,
    pub total: usize,
}

pub fn is_mp3(path: &Path) -> bool {
    path.extension().and_then(|e| e.to_str()).is_some_and(|e| e.eq_ignore_ascii_case("mp3"))
}

pub fn file_stat(path: &Path) -> Option<(i64, i64)> {
    let meta = std::fs::metadata(path).ok()?;
    if !meta.is_file() {
        return None;
    }
    let mtime = meta.modified().ok()?.duration_since(UNIX_EPOCH).ok()?.as_nanos() as i64;
    Some((mtime, meta.len() as i64))
}

/// Path relative to the library root using forward slashes, or None if outside it.
pub fn rel_path(root: &Path, path: &Path) -> Option<String> {
    let rel = path.strip_prefix(root).ok()?;
    let s = rel.to_str()?.to_string();
    (!s.is_empty()).then_some(s)
}

fn hidden(entry: &walkdir::DirEntry) -> bool {
    entry.depth() > 0 && entry.file_name().to_str().is_some_and(|s| s.starts_with('.'))
}

/// Every MP3 under `dir`, with its stat.
fn walk_mp3s(root: &Path, dir: &Path) -> Vec<(String, i64, i64)> {
    WalkDir::new(dir)
        .follow_links(true)
        .into_iter()
        .filter_entry(|e| !hidden(e))
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file() && is_mp3(e.path()))
        .filter_map(|e| {
            let (mtime, size) = file_stat(e.path())?;
            Some((rel_path(root, e.path())?, mtime, size))
        })
        .collect()
}

fn read_file(root: &Path, rel: String, mtime: i64, size: i64) -> ScannedFile {
    let abs = root.join(&rel);
    ScannedFile {
        tags: tags::read_tags(&abs).map_err(|e| format!("{e:#}")),
        audio: tags::read_audio(&abs),
        rel_path: rel,
        mtime,
        size,
    }
}

fn read_and_store(
    db: &Mutex<Db>,
    root: &Path,
    todo: Vec<(String, i64, i64)>,
    mut progress: impl FnMut(usize, usize),
) -> Result<usize> {
    let total = todo.len();
    let mut done = 0;
    progress(0, total);
    for chunk in todo.chunks(BATCH) {
        let files: Vec<ScannedFile> = chunk.par_iter().map(|(p, m, s)| read_file(root, p.clone(), *m, *s)).collect();
        db.lock().unwrap().upsert_many(&files)?;
        done += chunk.len();
        progress(done, total);
    }
    Ok(total)
}

/// Bring the whole index up to date. Only new or modified files (by mtime and size) are read.
pub fn full_scan(db: &Mutex<Db>, root: &Path, progress: impl FnMut(usize, usize)) -> Result<ScanSummary> {
    let on_disk = walk_mp3s(root, root);
    let known = db.lock().unwrap().file_stats()?;

    let present: HashSet<&str> = on_disk.iter().map(|(p, _, _)| p.as_str()).collect();
    let gone: Vec<String> = known.keys().filter(|p| !present.contains(p.as_str())).cloned().collect();
    let total = on_disk.len();
    let todo: Vec<_> = on_disk.into_iter().filter(|(p, m, s)| known.get(p) != Some(&(*m, *s))).collect();

    let removed = db.lock().unwrap().delete_paths(&gone)?;
    let added_or_updated = read_and_store(db, root, todo, progress)?;
    Ok(ScanSummary { total, added_or_updated, removed })
}

/// Re-sync specific paths reported by the file watcher. Returns true if anything changed.
pub fn sync_paths(db: &Mutex<Db>, root: &Path, paths: &[PathBuf]) -> Result<bool> {
    let mut todo: Vec<(String, i64, i64)> = Vec::new();
    let mut changed = false;
    let mut seen = HashSet::new();

    for path in paths {
        let Some(rel) = rel_path(root, path) else { continue };
        if !seen.insert(rel.clone()) || rel.split('/').any(|seg| seg.starts_with('.')) {
            continue;
        }
        if path.is_dir() {
            let found = walk_mp3s(root, path);
            let db = db.lock().unwrap();
            for (p, m, s) in found {
                if db.file_stat(&p)? != Some((m, s)) {
                    todo.push((p, m, s));
                }
            }
        } else if let Some((m, s)) = file_stat(path) {
            if is_mp3(path) && db.lock().unwrap().file_stat(&rel)? != Some((m, s)) {
                todo.push((rel, m, s));
            }
        } else {
            // Gone: either a file or a whole directory that was deleted or moved away.
            changed |= db.lock().unwrap().delete_under(&rel)? > 0;
        }
    }

    changed |= !todo.is_empty();
    read_and_store(db, root, todo, |_, _| {})?;
    Ok(changed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tags::tests::fake_mp3;
    use crate::tags::{FieldEdit, TagEdits};

    #[test]
    fn scan_then_incremental() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::create_dir_all(root.join("A/B")).unwrap();
        std::fs::create_dir_all(root.join(".hidden")).unwrap();
        let a = fake_mp3(&root.join("A"), "one.mp3");
        fake_mp3(&root.join("A/B"), "two.MP3");
        fake_mp3(&root.join(".hidden"), "x.mp3");
        std::fs::write(root.join("A/cover.png"), b"x").unwrap();
        // macOS metadata: AppleDouble sidecars on non-APFS volumes, and Finder state.
        std::fs::write(root.join("A/._one.mp3"), b"x").unwrap();
        std::fs::write(root.join("A/.DS_Store"), b"x").unwrap();

        let db = Mutex::new(Db::open_in_memory().unwrap());
        let s = full_scan(&db, root, |_, _| {}).unwrap();
        assert_eq!((s.total, s.added_or_updated, s.removed), (2, 2, 0));

        let s = full_scan(&db, root, |_, _| {}).unwrap();
        assert_eq!(s.added_or_updated, 0);

        let edits = TagEdits { title: Some(FieldEdit::Set("Hello".into())), ..Default::default() };
        tags::write_tags(&a, &edits, None).unwrap();
        std::fs::remove_file(root.join("A/B/two.MP3")).unwrap();
        let s = full_scan(&db, root, |_, _| {}).unwrap();
        assert_eq!((s.total, s.added_or_updated, s.removed), (1, 1, 1));
        let rows = db.lock().unwrap().query(&Default::default()).unwrap();
        assert_eq!(rows[0].title.as_deref(), Some("Hello"));
        assert_eq!((rows[0].dir.as_str(), rows[0].filename.as_str()), ("A", "one.mp3"));
    }

    #[test]
    fn sync_handles_moved_directories() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::create_dir_all(root.join("Old")).unwrap();
        fake_mp3(&root.join("Old"), "one.mp3");
        let db = Mutex::new(Db::open_in_memory().unwrap());
        full_scan(&db, root, |_, _| {}).unwrap();

        std::fs::rename(root.join("Old"), root.join("New")).unwrap();
        assert!(sync_paths(&db, root, &[root.join("Old"), root.join("New")]).unwrap());
        let rows = db.lock().unwrap().query(&Default::default()).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].path, "New/one.mp3");
        assert!(!sync_paths(&db, root, &[root.join("New/one.mp3")]).unwrap());
    }
}
