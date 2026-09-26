//! Renaming and moving files according to a path template.

use std::collections::{BTreeSet, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use anyhow::{Context, Result};
use serde::Serialize;

use crate::db::{Db, Track};
use crate::scanner::file_stat;
use crate::template;

/// Files that don't keep a folder alive on their own. When every MP3 has moved out of a
/// folder, these follow them if they all went to the same place, otherwise they're deleted.
const LEFTOVER_EXTS: [&str; 7] = ["jpg", "jpeg", "png", "gif", "bmp", "webp", "ini"];
const LEFTOVER_NAMES: [&str; 3] = ["thumbs.db", ".ds_store", ".directory"];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Move,
    Unchanged,
    Conflict,
    Error,
}

#[derive(Debug, Clone, Serialize)]
pub struct PlanItem {
    pub id: i64,
    pub from: String,
    pub to: String,
    pub status: Status,
    pub message: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct ApplyResult {
    pub moved: usize,
    pub skipped: usize,
    pub failed: Vec<(String, String)>,
    pub removed_dirs: usize,
}

pub fn plan(root: &Path, tracks: &[Track], template: &str) -> Vec<PlanItem> {
    let mut claimed: HashSet<String> = HashSet::new();
    let sources: HashSet<&str> = tracks.iter().map(|t| t.path.as_str()).collect();
    let mut items: Vec<PlanItem> = tracks
        .iter()
        .map(|t| match template::render(template, t) {
            Err(e) => {
                PlanItem { id: t.id, from: t.path.clone(), to: String::new(), status: Status::Error, message: Some(e) }
            }
            Ok(to) => PlanItem {
                id: t.id,
                status: if to == t.path { Status::Unchanged } else { Status::Move },
                from: t.path.clone(),
                to,
                message: None,
            },
        })
        .collect();

    // Files that stay put own their path outright.
    for item in items.iter().filter(|i| i.status == Status::Unchanged) {
        claimed.insert(item.to.to_lowercase());
    }
    for item in items.iter_mut().filter(|i| i.status == Status::Move) {
        let key = item.to.to_lowercase();
        let case_only = item.to.eq_ignore_ascii_case(&item.from);
        let message = if claimed.contains(&key) {
            Some("another selected file would get this path")
        } else if sources.contains(item.to.as_str()) {
            // Would only work if that file moved first; skipped to keep things predictable.
            Some("path is occupied by another selected file")
        } else if !case_only && root.join(&item.to).exists() {
            Some("a file already exists at this path")
        } else {
            None
        };
        match message {
            Some(m) => {
                item.status = Status::Conflict;
                item.message = Some(m.into());
            }
            None => {
                claimed.insert(key);
            }
        }
    }
    items
}

fn is_leftover(path: &Path) -> bool {
    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or_default().to_lowercase();
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or_default().to_lowercase();
    LEFTOVER_NAMES.contains(&name.as_str()) || LEFTOVER_EXTS.contains(&ext.as_str())
}

fn move_file(from: &Path, to: &Path) -> Result<()> {
    if let Some(parent) = to.parent() {
        std::fs::create_dir_all(parent).with_context(|| format!("creating {}", parent.display()))?;
    }
    match std::fs::rename(from, to) {
        Ok(()) => Ok(()),
        // Across filesystems (e.g. a library spanning mounts) fall back to copy + delete.
        Err(e) if e.raw_os_error() == Some(18) => {
            std::fs::copy(from, to).with_context(|| format!("copying to {}", to.display()))?;
            std::fs::remove_file(from).with_context(|| format!("removing {}", from.display()))
        }
        Err(e) => Err(e).with_context(|| format!("moving to {}", to.display())),
    }
}

/// If `dir` holds nothing but leftovers (cover images and the like), move those to
/// `follow` (when all its music went to one place) or delete them, then remove `dir`.
/// Walks up through parents that become empty as a result. Never removes `root`.
fn prune(root: &Path, dir: &Path, follow: Option<&Path>) -> usize {
    let mut removed = 0;
    let mut current = Some(dir.to_path_buf());
    let mut first = true;
    while let Some(d) = current {
        if d == root || !d.starts_with(root) {
            break;
        }
        let Ok(entries) = std::fs::read_dir(&d) else { break };
        let entries: Vec<PathBuf> = entries.filter_map(|e| e.ok().map(|e| e.path())).collect();
        if entries.iter().any(|p| p.is_dir() || !is_leftover(p)) {
            break;
        }
        for p in &entries {
            let target = follow.filter(|_| first).map(|f| f.join(p.file_name().unwrap_or_default()));
            match target {
                Some(t) if !t.exists() => {
                    if move_file(p, &t).is_err() {
                        let _ = std::fs::remove_file(p);
                    }
                }
                _ => {
                    let _ = std::fs::remove_file(p);
                }
            }
        }
        if std::fs::remove_dir(&d).is_err() {
            break;
        }
        removed += 1;
        first = false;
        current = d.parent().map(Path::to_path_buf);
    }
    removed
}

/// Execute the `Move` items of a plan, updating the index as files move.
pub fn apply(root: &Path, db: &Mutex<Db>, items: &[PlanItem], mut progress: impl FnMut(usize, usize)) -> ApplyResult {
    let mut result = ApplyResult::default();
    // old dir -> set of new dirs its files went to
    let mut dir_moves: HashMap<PathBuf, BTreeSet<PathBuf>> = HashMap::new();
    let total = items.len();

    for (i, item) in items.iter().enumerate() {
        progress(i, total);
        if item.status != Status::Move {
            result.skipped += 1;
            continue;
        }
        let from = root.join(&item.from);
        let to = root.join(&item.to);
        let case_only = item.to.eq_ignore_ascii_case(&item.from);
        if to.exists() && !case_only {
            result.skipped += 1;
            result.failed.push((item.from.clone(), "target appeared since the preview".into()));
            continue;
        }
        let outcome = move_file(&from, &to).and_then(|_| {
            let mtime = file_stat(&to).map(|(m, _)| m).unwrap_or_default();
            db.lock().unwrap().update_path(item.id, &item.to, mtime)
        });
        match outcome {
            Ok(()) => {
                result.moved += 1;
                if let (Some(old), Some(new)) = (from.parent(), to.parent()) {
                    dir_moves.entry(old.to_path_buf()).or_default().insert(new.to_path_buf());
                }
            }
            Err(e) => result.failed.push((item.from.clone(), format!("{e:#}"))),
        }
    }
    progress(total, total);

    // Deepest first so nested folders are handled before their parents.
    let mut dirs: Vec<_> = dir_moves.into_iter().collect();
    dirs.sort_by_key(|(d, _)| std::cmp::Reverse(d.components().count()));
    for (old, news) in dirs {
        if news.contains(&old) {
            continue;
        }
        let follow = (news.len() == 1).then(|| news.iter().next().unwrap().as_path());
        result.removed_dirs += prune(root, &old, follow);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scanner::full_scan;
    use crate::tags::tests::fake_mp3;
    use crate::tags::{write_tags, FieldEdit, TagEdits};

    fn tag(path: &Path, artist: &str, album: &str, title: &str, track: u32) {
        let e = TagEdits {
            artist: Some(FieldEdit::Set(artist.into())),
            album: Some(FieldEdit::Set(album.into())),
            title: Some(FieldEdit::Set(title.into())),
            track: Some(FieldEdit::Set(track)),
            ..Default::default()
        };
        write_tags(path, &e, None).unwrap();
    }

    fn setup() -> (tempfile::TempDir, Mutex<Db>) {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::create_dir_all(root.join("messy/sub")).unwrap();
        tag(&fake_mp3(&root.join("messy/sub"), "a.mp3"), "Queen", "Jazz", "Mustapha", 1);
        tag(&fake_mp3(&root.join("messy/sub"), "b.mp3"), "Queen", "Jazz", "Fat Bottomed Girls", 2);
        tag(&fake_mp3(&root.join("messy"), "c.mp3"), "Queen", "Jazz", "Mustapha", 1);
        std::fs::write(root.join("messy/sub/cover.png"), b"img").unwrap();
        let db = Mutex::new(Db::open_in_memory().unwrap());
        full_scan(&db, root, |_, _| {}).unwrap();
        (dir, db)
    }

    #[test]
    fn plan_flags_conflicts() {
        let (dir, db) = setup();
        let tracks = db.lock().unwrap().query(&Default::default()).unwrap();
        let items = plan(dir.path(), &tracks, "<Artist>/<Album>/<Track:2> <Title>");
        let by_from: HashMap<_, _> = items.iter().map(|i| (i.from.as_str(), i)).collect();
        assert_eq!(by_from["messy/sub/b.mp3"].status, Status::Move);
        assert_eq!(by_from["messy/sub/b.mp3"].to, "Queen/Jazz/02 Fat Bottomed Girls.mp3");
        let dupes: Vec<_> = ["messy/sub/a.mp3", "messy/c.mp3"].iter().map(|p| by_from[p].status).collect();
        assert!(dupes.contains(&Status::Move) && dupes.contains(&Status::Conflict));
        assert_eq!(plan(dir.path(), &tracks, "<Bogus>")[0].status, Status::Error);
    }

    #[test]
    fn apply_moves_and_prunes() {
        let (dir, db) = setup();
        let root = dir.path();
        let tracks = db.lock().unwrap().query(&Default::default()).unwrap();
        let sub: Vec<_> = tracks.into_iter().filter(|t| t.dir == "messy/sub").collect();
        let items = plan(root, &sub, "<Artist>/<Album>/<Track:2> <Title>");
        let r = apply(root, &db, &items, |_, _| {});
        assert_eq!((r.moved, r.failed.len(), r.removed_dirs), (2, 0, 1));
        assert!(root.join("Queen/Jazz/01 Mustapha.mp3").exists());
        assert!(root.join("Queen/Jazz/cover.png").exists(), "cover follows the album");
        assert!(!root.join("messy/sub").exists());
        assert!(root.join("messy/c.mp3").exists(), "folder with remaining music is kept");

        let paths: Vec<_> =
            db.lock().unwrap().query(&Default::default()).unwrap().into_iter().map(|t| t.path).collect();
        assert!(paths.contains(&"Queen/Jazz/02 Fat Bottomed Girls.mp3".to_string()));
        // Index and disk agree: a rescan finds nothing to do.
        let s = full_scan(&db, root, |_, _| {}).unwrap();
        assert_eq!((s.added_or_updated, s.removed), (0, 0));
    }
}
