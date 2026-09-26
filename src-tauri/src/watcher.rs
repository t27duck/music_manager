//! Live updates: watch the library with inotify and re-sync whatever changed.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use notify_debouncer_mini::notify::{RecommendedWatcher, RecursiveMode};
use notify_debouncer_mini::{new_debouncer, DebounceEventResult, Debouncer};
use tauri::{AppHandle, Emitter};

use crate::{scanner, AppState};

pub struct LibraryWatcher {
    _debouncer: Debouncer<RecommendedWatcher>,
}

impl LibraryWatcher {
    pub fn start(app: AppHandle, state: Arc<AppState>, root: PathBuf) -> Result<Self> {
        let sync_root = root.clone();
        let mut debouncer = new_debouncer(Duration::from_millis(800), move |res: DebounceEventResult| {
            let Ok(events) = res else { return };
            let paths: Vec<PathBuf> = events.into_iter().map(|e| e.path).collect();
            // Waits for any in-flight edit/reorganize, whose own changes are then no-ops.
            let _guard = state.op_lock.lock().unwrap();
            match scanner::sync_paths(&state.db, &sync_root, &paths) {
                Ok(true) => {
                    let _ = app.emit("library-changed", ());
                }
                Ok(false) => {}
                Err(e) => eprintln!("watcher sync failed: {e:#}"),
            }
        })?;
        debouncer.watcher().watch(&root, RecursiveMode::Recursive)?;
        Ok(Self { _debouncer: debouncer })
    }
}
